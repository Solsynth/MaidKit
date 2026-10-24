import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive_io.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:super_context_menu/super_context_menu.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/platform/platform_support.dart'
    show platformPathSeparator;
import 'package:maid_kit/shared/presentation/app_context_menu.dart';
import 'package:maid_kit/shared/presentation/maidkit_alert.dart';
import 'package:maid_kit/shared/presentation/task_progress.dart';
import 'package:maid_kit/theme.dart';
import 'file_editor_tab.dart';
import 'remote_file_client_resolver.dart';
import 'remote_file_system.dart';
import 'server_connection_actions.dart';
import 'server_models.dart';
import 'server_providers.dart';
import 'terminal_tabs_provider.dart';
import 'transfer_conflict_preferences.dart';

enum _FileSide { left, remote }

enum _ClipboardMode { copy, cut }

enum _ArchiveFormat { zip, tarGzip }

/// Fixed row height of the file lists (matches `_FileRow`'s intrinsic
/// height) so keyboard navigation can scroll items into view precisely.
const double _kFileRowExtent = 44.0;

/// Per-conflict choice when the transfer conflict mode is [ask].
enum _TransferConflictChoice { overwrite, keepBoth, skip }

/// Conflict mode used by drag-and-drop uploads. A drop is an explicit,
/// one-off action, so it always offers the overwrite choice instead of
/// silently renaming or overwriting the way the saved transfer mode would.
const TransferConflictMode _kDropConflictMode = TransferConflictMode.ask;

class _ClipboardEntry {
  const _ClipboardEntry({
    required this.side,
    required this.path,
    required this.name,
    required this.isDirectory,
    this.serverId,
    this.isSymbolicLink = false,
  });

  final _FileSide side;
  final String path;
  final String name;
  final bool isDirectory;
  final bool isSymbolicLink;

  /// Set when this entry belongs to the optional second remote pane.
  final int? serverId;
}

class _FileClipboard {
  const _FileClipboard({required this.mode, required this.entries});

  final _ClipboardMode mode;
  final List<_ClipboardEntry> entries;

  bool get isEmpty => entries.isEmpty;
  bool get isNotEmpty => entries.isNotEmpty;
}

class _FileDragData {
  const _FileDragData({required this.side, required this.entries});

  final _FileSide side;
  final List<_ClipboardEntry> entries;
}

class FileManagementTabView extends ConsumerStatefulWidget {
  const FileManagementTabView({required this.tab, super.key});

  final FileManagementTab tab;

  @override
  ConsumerState<FileManagementTabView> createState() =>
      _FileManagementTabViewState();
}

class _FileManagementTabViewState extends ConsumerState<FileManagementTabView> {
  var _remotePath = '.';
  List<String> _favoritePaths = [];
  List<SftpName> _remoteEntries = const [];
  var _loadingRemote = true;
  String? _remoteError;

  /// The app-wide task queue this tab submits transfers to.
  ///
  /// Captured in `initState` because `ref` cannot be read in `dispose`, and
  /// closing a tab always cancels the transfers it still owns. The queue
  /// outlives the tab, but the work it runs — SSH file handles, this tab's
  /// directory state — belongs to the tab.
  late final TaskProgressNotifier _tasks;

  /// Ids of the transfers this tab has queued.
  final _transferIds = <String>{};
  String? _workingPath;
  var _draggingFiles = false;
  _FileSide? _dropTargetSide;
  Future<RemoteFileClient>? _fileClient;
  SSHClient? _fileClientOwner;
  Future<RemoteFileClient>? _leftFileClient;
  SSHClient? _leftFileClientOwner;
  final _otherFileClients = <int, Future<RemoteFileClient>>{};
  final _otherFileClientOwners = <int, SSHClient?>{};
  int? _leftServerId;
  var _leftRemotePath = '.';
  List<SftpName> _leftRemoteEntries = const [];
  final _leftRemoteSymlinkPaths = <String>{};
  var _loadingLeftRemote = false;
  String? _leftRemoteError;
  final _remoteSymlinkPaths = <String>{};
  late final TextEditingController _leftRemotePathController;
  late final FocusNode _leftRemotePathFocusNode;
  late final TextEditingController _remotePathController;
  late final FocusNode _remotePathFocusNode;
  late final FocusNode _shortcutFocusNode;
  final ScrollController _leftRemoteListController = ScrollController();
  final ScrollController _rightRemoteListController = ScrollController();

  Set<String> _selectedLeftPaths = {};
  Set<String> _selectedRemotePaths = {};
  int? _leftAnchorIndex;
  int? _remoteAnchorIndex;
  _FileSide? _focusedSide;
  _FileClipboard? _clipboard;

  /// Folder navigation history for the mouse side buttons, one stack per pane.
  final List<String> _leftBackHistory = [];
  final List<String> _leftForwardHistory = [];
  final List<String> _remoteBackHistory = [];
  final List<String> _remoteForwardHistory = [];
  var _leftCollapsed = false;
  var _remoteCollapsed = false;
  var _paneSplitRatio = 0.5;
  double? _paneDragRatio;
  var _leftSearchOpen = false;
  var _rightSearchOpen = false;
  late final TextEditingController _leftSearchController;
  late final TextEditingController _rightSearchController;
  late final FocusNode _leftSearchFocusNode;
  late final FocusNode _rightSearchFocusNode;

  /// Below this width the tab shows only the selected server.
  static const _narrowLayoutBreakpoint = 900.0;
  static const _paneDividerWidth = 1.0;
  static const _paneDividerHitTargetWidth = 32.0;
  static const _minimumPaneWidth = 280.0;
  static const _paneCollapseThreshold = 0.08;

  bool get _isNarrowLayout {
    final width = MediaQuery.sizeOf(context).width;
    return width < _narrowLayoutBreakpoint;
  }

  List<T> _displayFileEntries<T>({
    required Iterable<T> entries,
    required String Function(T) nameOf,
    required String query,
  }) {
    final visible = <T>[];
    final hidden = <T>[];
    for (final entry in entries) {
      final name = nameOf(entry);
      final lowerName = name.toLowerCase();
      final isHidden = _isHiddenFileName(name);
      if (query.isNotEmpty && !lowerName.contains(query)) continue;
      (isHidden ? hidden : visible).add(entry);
    }
    return [...visible, ...hidden];
  }

  List<SftpName> get _displayedLeftRemoteEntries => _displayFileEntries(
    entries: _leftRemoteEntries,
    nameOf: (entry) => entry.filename,
    query: _leftSearchController.text.trim().toLowerCase(),
  );

  List<SftpName> get _displayedRemoteEntries => _displayFileEntries(
    entries: _remoteEntries,
    nameOf: (entry) => entry.filename,
    query: _rightSearchController.text.trim().toLowerCase(),
  );

  @override
  void initState() {
    super.initState();
    _tasks = ref.read(taskProgressProvider.notifier);
    // The starting path and favorite folders come from the server row, which a
    // browser reads over HTTP too.
    final server = _serverRecord();
    _remotePath =
        widget.tab.initialPath ?? server?.fileManagementInitialPath ?? '.';
    _favoritePaths = decodeStringList(server?.fileManagementFavorites);
    _leftRemotePathController = TextEditingController(text: _leftRemotePath);
    _leftRemotePathFocusNode = FocusNode();
    _remotePathController = TextEditingController(text: _remotePath);
    _remotePathFocusNode = FocusNode();
    _shortcutFocusNode = FocusNode(debugLabel: 'file-management-shortcuts');
    _leftSearchController = TextEditingController();
    _rightSearchController = TextEditingController();
    _leftSearchFocusNode = FocusNode(debugLabel: 'file-management-left-search');
    _rightSearchFocusNode = FocusNode(
      debugLabel: 'file-management-right-search',
    );
    _refreshRemote();
  }

  bool get _leftIsRemote => _leftServerId != null;

  /// How transfers resolve destination entries that already exist. Read at
  /// transfer time so setting changes apply to queued work immediately.
  TransferConflictMode get _conflictMode =>
      ref.read(transferConflictModeProvider);

  Future<void> _closeFileClient(Future<RemoteFileClient>? future) async {
    if (future == null) return;
    try {
      final files = await future;
      await files.close();
    } catch (_) {}
  }

  void _releaseLeftFileClient() {
    final previous = _leftFileClient;
    _leftFileClient = null;
    _leftFileClientOwner = null;
    if (previous != null) unawaited(_closeFileClient(previous));
  }

  Future<void> _closeFileSessions() async {
    final sessions = <Future<RemoteFileClient>>[];
    final main = _fileClient;
    final left = _leftFileClient;
    if (main != null) sessions.add(main);
    if (left != null) sessions.add(left);
    sessions.addAll(_otherFileClients.values);
    _fileClient = null;
    _fileClientOwner = null;
    _leftFileClient = null;
    _leftFileClientOwner = null;
    _otherFileClients.clear();
    _otherFileClientOwners.clear();
    await Future.wait(sessions.map(_closeFileClient));
  }

  Future<RemoteFileClient> _leftFiles() {
    final serverId = _leftServerId;
    if (serverId == null) {
      throw StateError('Choose a server for the left pane.');
    }
    final owner = ref.read(connectionManagerProvider).clientFor(serverId);
    final cached = _leftFileClient;
    if (cached != null && identical(_leftFileClientOwner, owner)) {
      return cached;
    }
    if (cached != null) unawaited(_closeFileClient(cached));
    final next = _openFileClient(serverId, owner);
    _leftFileClient = next;
    _leftFileClientOwner = owner;
    return next;
  }

  Future<List<SftpName>> _resolveRemoteEntries(
    RemoteFileClient files,
    String directory,
    List<SftpName> entries,
    Set<String> symlinkPaths,
  ) async {
    return Future.wait(
      entries.map((entry) async {
        if (!entry.attr.isSymbolicLink) return entry;
        final path = _joinRemotePath(directory, entry.filename);
        symlinkPaths.add(path);
        try {
          final targetAttrs = await files.stat(path);
          if (!isRemoteDirectoryEntry(entry.attr, followed: targetAttrs) &&
              !isRemoteFileEntry(entry.attr, followed: targetAttrs)) {
            return entry;
          }
          return SftpName(
            filename: entry.filename,
            longname: entry.longname,
            attr: targetAttrs,
          );
        } catch (_) {
          return entry;
        }
      }),
    );
  }

  Future<void> _refreshLeftRemote() async {
    if (!_leftIsRemote) return;
    setState(() {
      _loadingLeftRemote = true;
      _leftRemoteError = null;
    });
    try {
      final files = await _leftFiles();
      final absolutePath = await files.absolute(_leftRemotePath);
      final listedEntries = await files.listdir(absolutePath);
      listedEntries.removeWhere(
        (entry) => entry.filename == '.' || entry.filename == '..',
      );
      final symlinkPaths = <String>{};
      final entries = await _resolveRemoteEntries(
        files,
        absolutePath,
        listedEntries,
        symlinkPaths,
      );
      entries.sort((a, b) {
        final directoryOrder =
            (b.attr.isDirectory ? 1 : 0) - (a.attr.isDirectory ? 1 : 0);
        return directoryOrder != 0
            ? directoryOrder
            : a.filename.toLowerCase().compareTo(b.filename.toLowerCase());
      });
      if (mounted) {
        setState(() {
          _leftRemotePath = absolutePath;
          _leftRemoteEntries = entries;
          _leftRemoteSymlinkPaths
            ..clear()
            ..addAll(symlinkPaths);
          _selectedLeftPaths = _selectedLeftPaths
              .where(
                (path) => entries.any(
                  (entry) =>
                      _joinRemotePath(absolutePath, entry.filename) == path,
                ),
              )
              .toSet();
        });
        if (!_leftRemotePathFocusNode.hasFocus) {
          _leftRemotePathController.text = absolutePath;
        }
      }
    } catch (error) {
      if (mounted) setState(() => _leftRemoteError = error.toString());
    } finally {
      if (mounted) setState(() => _loadingLeftRemote = false);
    }
  }

  Future<void> _chooseLeftServer() async {
    final servers = ref.read(serversProvider).asData?.value ?? const <Server>[];
    final choices = servers
        .where((server) => server.id != widget.tab.serverId)
        .toList();
    final selectedServerId = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('fileManagerUseAnotherServer'.tr()),
        children: [
          if (_leftIsRemote)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, -1),
              child: Text('fileManagerUseOnlyThisServer'.tr()),
            ),
          for (final item in choices)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, item.id),
              child: Text(item.name),
            ),
        ],
      ),
    );
    if (!mounted || selectedServerId == null) return;
    if (selectedServerId == -1) {
      _releaseLeftFileClient();
      setState(() {
        _leftServerId = null;
        _leftRemoteEntries = const [];
        _leftRemoteSymlinkPaths.clear();
        _selectedLeftPaths = {};
        _leftAnchorIndex = null;
        _leftCollapsed = false;
        if (_focusedSide == _FileSide.left) _focusedSide = _FileSide.remote;
        if (_dropTargetSide == _FileSide.left) _dropTargetSide = null;
      });
      _leftBackHistory.clear();
      _leftForwardHistory.clear();
      return;
    }
    final server = servers.firstWhere((item) => item.id == selectedServerId);
    final connected = await connectForStatistics(context, ref, server);
    if (!connected || !mounted) return;
    _releaseLeftFileClient();
    _leftBackHistory.clear();
    _leftForwardHistory.clear();
    setState(() {
      _leftServerId = server.id;
      _leftRemotePath = '.';
      _leftRemotePathController.text = _leftRemotePath;
      _leftRemoteEntries = const [];
      _leftRemoteSymlinkPaths.clear();
      _selectedLeftPaths = {};
      _leftAnchorIndex = null;
    });
    await _refreshLeftRemote();
  }

  /// Whether this tab has a transfer queued or running.
  ///
  /// A queued transfer already holds its destination directory, so renaming or
  /// creating an entry there would race it.
  bool get _busy => _workingPath != null || _transferIds.isNotEmpty;

  @override
  void dispose() {
    // Read in initState: `ref` is unsafe to touch once the element is being
    // unmounted, and closing a tab always cancels its transfers.
    final tasks = _tasks;
    for (final id in _transferIds) {
      unawaited(tasks.cancel(id));
    }
    _transferIds.clear();
    unawaited(_closeFileSessions());
    _leftRemotePathController.dispose();
    _leftRemotePathFocusNode.dispose();
    _remotePathController.dispose();
    _remotePathFocusNode.dispose();
    _shortcutFocusNode.dispose();
    _leftRemoteListController.dispose();
    _rightRemoteListController.dispose();
    _leftSearchController.dispose();
    _rightSearchController.dispose();
    _leftSearchFocusNode.dispose();
    _rightSearchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _refreshRemote() async {
    setState(() {
      _loadingRemote = true;
      _remoteError = null;
    });
    try {
      final files = await _files();
      final absolutePath = await files.absolute(_remotePath);
      final listedEntries = await files.listdir(absolutePath);
      listedEntries.removeWhere(
        (entry) => entry.filename == '.' || entry.filename == '..',
      );
      final symlinkPaths = <String>{};
      final entries = await _resolveRemoteEntries(
        files,
        absolutePath,
        listedEntries,
        symlinkPaths,
      );
      entries.sort((a, b) {
        final directoryOrder =
            (b.attr.isDirectory ? 1 : 0) - (a.attr.isDirectory ? 1 : 0);
        return directoryOrder != 0
            ? directoryOrder
            : a.filename.toLowerCase().compareTo(b.filename.toLowerCase());
      });
      if (mounted) {
        final paths = {
          for (final entry in entries)
            _joinRemotePath(absolutePath, entry.filename),
        };
        setState(() {
          _remotePath = absolutePath;
          _remoteEntries = entries;
          _remoteSymlinkPaths
            ..clear()
            ..addAll(symlinkPaths);
          _selectedRemotePaths = _selectedRemotePaths
              .where(paths.contains)
              .toSet();
        });
        if (!_remotePathFocusNode.hasFocus) {
          _remotePathController.text = absolutePath;
        }
      }
    } catch (error) {
      if (mounted) setState(() => _remoteError = error.toString());
    } finally {
      if (mounted) setState(() => _loadingRemote = false);
    }
  }

  Future<void> _openRemote(SftpName entry) async {
    if (!entry.attr.isDirectory) return;
    _pushRemoteHistory();
    setState(() {
      _remotePath = _joinRemotePath(_remotePath, entry.filename);
      _selectedRemotePaths = {};
      _remoteAnchorIndex = null;
      _focusedSide = _FileSide.remote;
    });
    await _refreshRemote();
  }

  Future<void> _navigateRemote(String path) async {
    final destination = path.trim();
    if (destination.isEmpty) return;
    _pushRemoteHistory();
    setState(() {
      _remotePath = destination;
      _selectedRemotePaths = {};
      _remoteAnchorIndex = null;
      _focusedSide = _FileSide.remote;
    });
    _remotePathFocusNode.unfocus();
    await _refreshRemote();
  }

  Future<void> _navigateLeftRemote(String path) async {
    final destination = path.trim();
    if (destination.isEmpty) return;
    _pushLeftHistory();
    setState(() {
      _leftRemotePath = destination;
      _selectedLeftPaths = {};
      _leftAnchorIndex = null;
      _focusedSide = _FileSide.left;
    });
    _leftRemotePathFocusNode.unfocus();
    await _refreshLeftRemote();
  }

  Future<void> _goUpRemote() async {
    if (_remotePath == '/') return;
    final parent = _parentRemotePath(_remotePath);
    setState(() {
      _remotePath = parent;
      _selectedRemotePaths = {};
      _remoteAnchorIndex = null;
      _focusedSide = _FileSide.remote;
    });
    await _refreshRemote();
  }

  /// Records the left pane's current folder as a back-history entry before a
  /// user navigation and clears the forward stack (standard browser
  /// semantics: a fresh navigation invalidates any forward history).
  void _pushLeftHistory() {
    if (_leftBackHistory.isNotEmpty &&
        _leftBackHistory.last == _leftRemotePath) {
      return;
    }
    _leftBackHistory.add(_leftRemotePath);
    _leftForwardHistory.clear();
  }

  void _pushRemoteHistory() {
    if (_remoteBackHistory.isNotEmpty &&
        _remoteBackHistory.last == _remotePath) {
      return;
    }
    _remoteBackHistory.add(_remotePath);
    _remoteForwardHistory.clear();
  }

  void _navigateLeftHistory(String path) {
    setState(() {
      _focusedSide = _FileSide.left;
      _leftRemotePath = path;
      _selectedLeftPaths = {};
      _leftAnchorIndex = null;
    });
    unawaited(_refreshLeftRemote());
  }

  void _navigateRemoteHistory(String path) {
    setState(() {
      _focusedSide = _FileSide.remote;
      _remotePath = path;
      _selectedRemotePaths = {};
      _remoteAnchorIndex = null;
    });
    unawaited(_refreshRemote());
  }

  void _goBackInHistory(_FileSide side) {
    _requestShortcutFocus();
    if (side == _FileSide.left) {
      if (_leftBackHistory.isEmpty) return;
      final target = _leftBackHistory.removeLast();
      _leftForwardHistory.add(_leftRemotePath);
      _navigateLeftHistory(target);
    } else {
      if (_remoteBackHistory.isEmpty) return;
      final target = _remoteBackHistory.removeLast();
      _remoteForwardHistory.add(_remotePath);
      _navigateRemoteHistory(target);
    }
  }

  void _goForwardInHistory(_FileSide side) {
    _requestShortcutFocus();
    if (side == _FileSide.left) {
      if (_leftForwardHistory.isEmpty) return;
      final target = _leftForwardHistory.removeLast();
      _leftBackHistory.add(_leftRemotePath);
      _navigateLeftHistory(target);
    } else {
      if (_remoteForwardHistory.isEmpty) return;
      final target = _remoteForwardHistory.removeLast();
      _remoteBackHistory.add(_remotePath);
      _navigateRemoteHistory(target);
    }
  }

  /// Mouse side-button support (issue #93): back/forward buttons navigate
  /// the pane the pointer is over.
  void _handlePanePointerDown(PointerDownEvent event, _FileSide side) {
    if (event.buttons == kBackMouseButton) {
      _goBackInHistory(side);
    } else if (event.buttons == kForwardMouseButton) {
      _goForwardInHistory(side);
    }
  }

  Future<void> _copyRemotePath() =>
      Clipboard.setData(ClipboardData(text: _remotePath));

  Future<void> _openTerminalHere() async {
    final servers = ref.read(serversProvider).asData?.value ?? const [];
    final server = servers
        .where((item) => item.id == widget.tab.serverId)
        .firstOrNull;
    if (server == null) {
      if (!mounted) return;
      showStyledSnackBar(
        message: 'The server for this file session is no longer available.',
        title: 'Could not open terminal',
        icon: Symbols.error,
        accentColor: Theme.of(context).colorScheme.error,
      );
      return;
    }
    await openTerminalSession(
      context,
      ref,
      server,
      initialDirectory: _remotePath,
    );
  }

  bool get _isMultiModifierPressed =>
      HardwareKeyboard.instance.isMetaPressed ||
      HardwareKeyboard.instance.isControlPressed;

  bool get _isRangeModifierPressed => HardwareKeyboard.instance.isShiftPressed;

  void _requestShortcutFocus() {
    if (!_shortcutFocusNode.hasFocus) {
      _shortcutFocusNode.requestFocus();
    }
  }

  void _selectRemote(
    SftpName entry, {
    required int index,
    bool toggle = false,
    bool range = false,
  }) {
    _requestShortcutFocus();
    final path = _joinRemotePath(_remotePath, entry.filename);
    setState(() {
      _focusedSide = _FileSide.remote;
      _selectedLeftPaths = {};
      _leftAnchorIndex = null;
      if (range && _remoteAnchorIndex != null) {
        final start = math.min(_remoteAnchorIndex!, index);
        final end = math.max(_remoteAnchorIndex!, index);
        final displayed = _displayedRemoteEntries;
        _selectedRemotePaths = {
          for (var i = start; i <= end && i < displayed.length; i++)
            _joinRemotePath(_remotePath, displayed[i].filename),
        };
      } else if (toggle) {
        final next = {..._selectedRemotePaths};
        if (!next.add(path)) next.remove(path);
        _selectedRemotePaths = next;
        _remoteAnchorIndex = index;
      } else {
        _selectedRemotePaths = {path};
        _remoteAnchorIndex = index;
      }
    });
  }

  void _selectLeft(
    SftpName entry, {
    required int index,
    bool toggle = false,
    bool range = false,
  }) {
    _requestShortcutFocus();
    final path = _joinRemotePath(_leftRemotePath, entry.filename);
    setState(() {
      _focusedSide = _FileSide.left;
      _selectedRemotePaths = {};
      _remoteAnchorIndex = null;
      if (range && _leftAnchorIndex != null) {
        final start = math.min(_leftAnchorIndex!, index);
        final end = math.max(_leftAnchorIndex!, index);
        final displayed = _displayedLeftRemoteEntries;
        _selectedLeftPaths = {
          for (var i = start; i <= end && i < displayed.length; i++)
            _joinRemotePath(_leftRemotePath, displayed[i].filename),
        };
      } else if (toggle) {
        final next = {..._selectedLeftPaths};
        if (!next.add(path)) next.remove(path);
        _selectedLeftPaths = next;
        _leftAnchorIndex = index;
      } else {
        _selectedLeftPaths = {path};
        _leftAnchorIndex = index;
      }
    });
  }

  void _ensureLeftContextSelection(SftpName entry, int index) {
    final path = _joinRemotePath(_leftRemotePath, entry.filename);
    if (_selectedLeftPaths.contains(path)) {
      setState(() {
        _focusedSide = _FileSide.left;
        _selectedRemotePaths = {};
      });
      return;
    }
    _selectLeft(entry, index: index);
  }

  void _ensureRemoteContextSelection(SftpName entry, int index) {
    final path = _joinRemotePath(_remotePath, entry.filename);
    if (_selectedRemotePaths.contains(path)) {
      setState(() {
        _focusedSide = _FileSide.remote;
        _selectedLeftPaths = {};
      });
      return;
    }
    _selectRemote(entry, index: index);
  }

  void _focusSide(_FileSide side) {
    _requestShortcutFocus();
    if (_focusedSide == side) return;
    setState(() => _focusedSide = side);
  }

  void _toggleSearch(_FileSide side) {
    final isLocal = side == _FileSide.left;
    final opening = !(isLocal ? _leftSearchOpen : _rightSearchOpen);
    setState(() {
      if (isLocal) {
        _leftSearchOpen = opening;
        if (!opening) _leftSearchController.clear();
        _leftAnchorIndex = null;
      } else {
        _rightSearchOpen = opening;
        if (!opening) _rightSearchController.clear();
        _remoteAnchorIndex = null;
      }
    });
    if (opening) {
      final node = isLocal ? _leftSearchFocusNode : _rightSearchFocusNode;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) node.requestFocus();
      });
    }
  }

  /// Opens the pane search and focuses it, ready to replace any query
  /// (used by the backslash shortcut).
  void _wakeSearch(_FileSide side) {
    final isLocal = side == _FileSide.left;
    setState(() {
      if (isLocal) {
        _leftSearchOpen = true;
        _leftAnchorIndex = null;
      } else {
        _rightSearchOpen = true;
        _remoteAnchorIndex = null;
      }
    });
    final controller = isLocal ? _leftSearchController : _rightSearchController;
    final node = isLocal ? _leftSearchFocusNode : _rightSearchFocusNode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      node.requestFocus();
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
    });
  }

  Widget _searchInput(_FileSide side) {
    final isLocal = side == _FileSide.left;
    final controller = isLocal ? _leftSearchController : _rightSearchController;
    final focusNode = isLocal ? _leftSearchFocusNode : _rightSearchFocusNode;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _toggleSearch(side);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          style: Theme.of(context).textTheme.bodySmall,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {
            if (isLocal) {
              _leftAnchorIndex = null;
            } else {
              _remoteAnchorIndex = null;
            }
          }),
          decoration: InputDecoration(
            hintText: 'fileManagerSearch'.tr(),
            isDense: true,
            prefixIcon: const Icon(Symbols.search, size: 16),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'fileManagerClearSearch'.tr(),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    icon: const Icon(Symbols.close, size: 16),
                    onPressed: () => setState(() => controller.clear()),
                  ),
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 6,
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchToggle(_FileSide side) {
    final isLocal = side == _FileSide.left;
    final open = isLocal ? _leftSearchOpen : _rightSearchOpen;
    return IconButton(
      tooltip: open ? 'fileManagerCloseSearch'.tr() : 'fileManagerSearch'.tr(),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      onPressed: () => _toggleSearch(side),
      icon: Icon(open ? Symbols.close : Symbols.search, size: 18),
    );
  }

  void _selectAllOnFocusedSide() {
    final side = _focusedSide;
    if (side == null) return;
    setState(() {
      if (side == _FileSide.left) {
        final displayed = _displayedLeftRemoteEntries;
        _selectedLeftPaths = {
          for (final entry in displayed)
            _joinRemotePath(_leftRemotePath, entry.filename),
        };
        _leftAnchorIndex = displayed.isEmpty ? null : 0;
        _selectedRemotePaths = {};
      } else {
        final displayed = _displayedRemoteEntries;
        _selectedRemotePaths = {
          for (final entry in displayed)
            _joinRemotePath(_remotePath, entry.filename),
        };
        _leftAnchorIndex = null;
        _selectedLeftPaths = {};
        _remoteAnchorIndex = displayed.isEmpty ? null : 0;
      }
    });
  }

  List<_ClipboardEntry> _entriesForSelection(_FileSide side) {
    if (side == _FileSide.left) {
      return [
        for (final entry in _leftRemoteEntries)
          if (_selectedLeftPaths.contains(
            _joinRemotePath(_leftRemotePath, entry.filename),
          ))
            _ClipboardEntry(
              side: _FileSide.left,
              serverId: _leftServerId,
              path: _joinRemotePath(_leftRemotePath, entry.filename),
              name: entry.filename,
              isDirectory: entry.attr.isDirectory,
              isSymbolicLink: _leftRemoteSymlinkPaths.contains(
                _joinRemotePath(_leftRemotePath, entry.filename),
              ),
            ),
      ];
    }
    return [
      for (final entry in _remoteEntries)
        if (_selectedRemotePaths.contains(
          _joinRemotePath(_remotePath, entry.filename),
        ))
          _ClipboardEntry(
            side: _FileSide.remote,
            path: _joinRemotePath(_remotePath, entry.filename),
            name: entry.filename,
            isDirectory: entry.attr.isDirectory,
            isSymbolicLink: _remoteSymlinkPaths.contains(
              _joinRemotePath(_remotePath, entry.filename),
            ),
          ),
    ];
  }

  _ClipboardEntry _clipboardEntryForLeft(SftpName entry) => _ClipboardEntry(
    side: _FileSide.left,
    serverId: _leftServerId,
    path: _joinRemotePath(_leftRemotePath, entry.filename),
    name: entry.filename,
    isDirectory: entry.attr.isDirectory,
    isSymbolicLink: _leftRemoteSymlinkPaths.contains(
      _joinRemotePath(_leftRemotePath, entry.filename),
    ),
  );

  _FileDragData _dragDataForLeft(SftpName entry) {
    final path = _joinRemotePath(_leftRemotePath, entry.filename);
    final selected = _selectedLeftPaths.contains(path)
        ? _entriesForSelection(_FileSide.left)
        : [_clipboardEntryForLeft(entry)];
    return _FileDragData(side: _FileSide.left, entries: selected);
  }

  _ClipboardEntry _clipboardEntryForRemote(SftpName entry) => _ClipboardEntry(
    side: _FileSide.remote,
    path: _joinRemotePath(_remotePath, entry.filename),
    name: entry.filename,
    isDirectory: entry.attr.isDirectory,
    isSymbolicLink: _remoteSymlinkPaths.contains(
      _joinRemotePath(_remotePath, entry.filename),
    ),
  );

  _FileDragData _dragDataForRemote(SftpName entry) {
    final path = _joinRemotePath(_remotePath, entry.filename);
    final selected = _selectedRemotePaths.contains(path)
        ? _entriesForSelection(_FileSide.remote)
        : [_clipboardEntryForRemote(entry)];
    return _FileDragData(side: _FileSide.remote, entries: selected);
  }

  Future<void> _renameEntry(_ClipboardEntry entry) async {
    if (_busy) return;
    final name = await _showFileNameSheet(
      context,
      title: 'fileManagerRename'.tr(),
      label: 'fileManagerName'.tr(),
      initialName: entry.name,
      actionLabel: 'fileManagerRename'.tr(),
    );
    if (name == null || name == entry.name || !mounted) return;

    setState(() => _workingPath = entry.path);
    try {
      final files = entry.serverId == null
          ? await _files()
          : await _leftFiles();
      final destination = _joinRemotePath(_parentRemotePath(entry.path), name);
      await files.rename(entry.path, destination);
      if (entry.serverId == null) {
        await _refreshRemote();
      } else {
        await _refreshLeftRemote();
      }

      if (mounted) {
        showStyledSnackBar(
          message: name,
          title: 'fileManagerRenamed'.tr(),
          icon: Symbols.check_circle,
          accentColor: Theme.of(context).colorScheme.primary,
        );
      }
    } catch (error) {
      if (mounted) {
        showStyledSnackBar(
          message: error.toString(),
          title: 'fileManagerRenameFailed'.tr(),
          icon: Symbols.error,
          accentColor: Theme.of(context).colorScheme.error,
        );
      }
    } finally {
      if (mounted) setState(() => _workingPath = null);
    }
  }

  Future<void> _createFolder(_FileSide side) async {
    if (_busy) return;
    final name = await _showFileNameSheet(
      context,
      title: 'fileManagerCreateFolder'.tr(),
      label: 'fileManagerFolderName'.tr(),
      actionLabel: 'fileManagerCreate'.tr(),
    );
    if (name == null || !mounted) return;

    setState(() => _workingPath = name);
    try {
      final files = side == _FileSide.left
          ? await _leftFiles()
          : await _files();
      final directory = side == _FileSide.left ? _leftRemotePath : _remotePath;
      await files.mkdir(_joinRemotePath(directory, name));
      if (side == _FileSide.left) {
        await _refreshLeftRemote();
      } else {
        await _refreshRemote();
      }

      if (mounted) {
        showStyledSnackBar(
          message: name,
          title: 'fileManagerFolderCreated'.tr(),
          icon: Symbols.check_circle,
          accentColor: Theme.of(context).colorScheme.primary,
        );
      }
    } catch (error) {
      if (mounted) {
        showStyledSnackBar(
          message: error.toString(),
          title: 'fileManagerCreateFolderFailed'.tr(),
          icon: Symbols.error,
          accentColor: Theme.of(context).colorScheme.error,
        );
      }
    } finally {
      if (mounted) setState(() => _workingPath = null);
    }
  }

  void _setClipboard(_ClipboardMode mode) {
    final side = _focusedSide;
    if (side == null) return;
    final entries = _entriesForSelection(side);
    if (entries.isEmpty) return;
    setState(() {
      _clipboard = _FileClipboard(mode: mode, entries: entries);
    });
    if (!mounted) return;
    final label = entries.length == 1
        ? entries.first.name
        : '${entries.length} items';
    showStyledSnackBar(
      message: label,
      title: mode == _ClipboardMode.copy
          ? 'fileManagerCopied'.tr()
          : 'fileManagerCut'.tr(),
      icon: mode == _ClipboardMode.copy
          ? Symbols.content_copy
          : Symbols.content_cut,
      accentColor: Theme.of(context).colorScheme.primary,
    );
  }

  Future<void> _handleInternalDrop(
    _FileDragData data,
    _FileSide targetSide,
  ) async {
    if (data.side == targetSide || data.entries.isEmpty) {
      return;
    }
    setState(() {
      _focusedSide = targetSide;
      _dropTargetSide = null;
    });
    try {
      for (final entry in data.entries) {
        await _transferBetweenServers(
          entry,
          sourceServerId: entry.serverId ?? widget.tab.serverId,
          targetServerId: targetSide == _FileSide.left
              ? _leftServerId!
              : widget.tab.serverId,
          targetDirectory: targetSide == _FileSide.left
              ? _leftRemotePath
              : _remotePath,
          notify: false,
        );
      }
      if (mounted) {
        showStyledSnackBar(
          message: data.entries.length == 1
              ? data.entries.first.name
              : '${data.entries.length} items',
          title: 'fileManagerTransferQueued'.tr(),
          icon: Symbols.schedule,
          accentColor: Theme.of(context).colorScheme.primary,
        );
      }
    } catch (error) {
      if (mounted) {
        showStyledSnackBar(
          message: error.toString(),
          title: 'fileManagerDropFailed'.tr(),
          icon: Symbols.error,
          accentColor: Theme.of(context).colorScheme.error,
        );
      }
    }
  }

  Future<void> _pasteInto(_FileSide targetSide) async {
    final clipboard = _clipboard;
    if (clipboard == null || clipboard.isEmpty || !_canPasteInto(targetSide)) {
      return;
    }
    final transferPaste = clipboard.entries.any(
      (entry) => entry.side != targetSide,
    );

    setState(() => _focusedSide = targetSide);
    try {
      for (final entry in clipboard.entries) {
        await _pasteEntry(entry, clipboard.mode, targetSide);
      }
      if (clipboard.mode == _ClipboardMode.cut) {
        setState(() => _clipboard = null);
      }
      if (mounted) {
        showStyledSnackBar(
          message: transferPaste
              ? '${clipboard.entries.length} transfer task${clipboard.entries.length == 1 ? '' : 's'}'
              : clipboard.mode == _ClipboardMode.cut
              ? 'Items moved'
              : 'Items pasted',
          title: transferPaste
              ? 'fileManagerTransferQueued'.tr()
              : 'fileManagerDone'.tr(),
          icon: transferPaste ? Symbols.schedule : Symbols.check_circle,
          accentColor: Theme.of(context).colorScheme.primary,
        );
      }
    } catch (error) {
      if (mounted) {
        showStyledSnackBar(
          message: error.toString(),
          title: 'fileManagerPasteFailed'.tr(),
          icon: Symbols.error,
          accentColor: Theme.of(context).colorScheme.error,
        );
      }
    }
  }

  Future<void> _pasteEntry(
    _ClipboardEntry entry,
    _ClipboardMode mode,
    _FileSide targetSide,
  ) async {
    final leftServerId = _leftServerId;
    final isLeftEntry = entry.side == _FileSide.left;
    final isLeftTarget = targetSide == _FileSide.left;

    // Same-side copy/cut inside the left server pane (SFTP rename/copy).
    if (isLeftEntry && isLeftTarget && entry.serverId == leftServerId) {
      if (mode == _ClipboardMode.cut) {
        await _moveSameSide(entry, _FileSide.left);
      } else {
        await _copySameSide(entry, _FileSide.left);
      }
      return;
    }

    // Left server <-> right server transfers.
    if (_leftIsRemote && (isLeftEntry || isLeftTarget)) {
      final targetServerId = isLeftTarget ? leftServerId! : widget.tab.serverId;
      await _transferBetweenServers(
        entry,
        sourceServerId: entry.serverId ?? widget.tab.serverId,
        targetServerId: targetServerId,
        targetDirectory: isLeftTarget ? _leftRemotePath : _remotePath,
        notify: false,
        onSuccess: mode == _ClipboardMode.cut
            ? () => _deleteRemoteEntryOnServer(
                entry,
                serverId: entry.serverId ?? widget.tab.serverId,
              )
            : null,
      );
      return;
    }
    if (mode == _ClipboardMode.cut) {
      await _moveSameSide(entry, _FileSide.remote);
    } else {
      await _copySameSide(entry, _FileSide.remote);
    }
  }

  bool _canPasteInto(_FileSide targetSide) {
    final clipboard = _clipboard;
    if (clipboard == null || clipboard.isEmpty) return false;
    final transferPaste = clipboard.entries.any(
      (entry) => entry.side != targetSide,
    );
    return transferPaste || !_busy;
  }

  Future<void> _transferBetweenServers(
    _ClipboardEntry entry, {
    required int sourceServerId,
    required int targetServerId,
    required String targetDirectory,
    bool notify = true,
    Future<void> Function()? onSuccess,
  }) async {
    if (sourceServerId == targetServerId) return;
    final source = await _filesFor(sourceServerId);
    final size = entry.isDirectory
        ? null
        : (await source.stat(entry.path)).size;
    _runTransfer(
      title: 'fileManagerTransferring'.tr(args: [entry.name]),
      totalBytes: size,
      notify: notify,
      action: (controller, reportProgress) async {
        final destination = await _filesFor(targetServerId);
        final target = await _resolveRemoteDestination(
          destination,
          targetDirectory,
          entry.name,
        );
        if (target == null) throw const TaskSkipped();
        try {
          if (entry.isDirectory) {
            await _removeRemoteEntry(destination, target);
            await _streamRemoteDirectory(
              source,
              destination,
              entry.path,
              target,
              controller,
              reportProgress,
            );
          } else {
            await _streamRemoteFile(
              source,
              destination,
              entry.path,
              target,
              controller,
              reportProgress,
            );
          }
        } finally {
          if (controller.isCancelled) {
            try {
              if (entry.isDirectory) {
                await _deleteRemoteDirectory(destination, target);
              } else {
                await destination.remove(target);
              }
            } catch (_) {}
          }
        }
        await _refreshRemote();
        await _refreshLeftRemote();
      },
      onSuccess: onSuccess,
    );
  }

  Future<RemoteFileClient> _filesFor(int serverId) {
    if (serverId == widget.tab.serverId) return _files();
    if (serverId == _leftServerId) return _leftFiles();

    final owner = ref.read(connectionManagerProvider).clientFor(serverId);
    final cached = _otherFileClients[serverId];
    // The SSH client doubles as the cache key: when it changes the transport
    // changed too, and a null key means the daemon is serving this server.
    if (cached != null && identical(_otherFileClientOwners[serverId], owner)) {
      return cached;
    }
    if (cached != null) unawaited(_closeFileClient(cached));
    final next = _openFileClient(serverId, owner);
    _otherFileClients[serverId] = next;
    _otherFileClientOwners[serverId] = owner;
    return next;
  }

  /// Opens the transport that can serve [serverId]'s files.
  ///
  /// [owner] is the server's live SSH client, or null when there is none — in
  /// which case a browser falls back to the MaidCafe daemon and a native
  /// client keeps asking for a connection, which is the behavior the file
  /// surfaces have always had.
  Future<RemoteFileClient> _openFileClient(
    int serverId,
    SSHClient? owner,
  ) async {
    if (owner == null && !kIsWeb) {
      throw const ServerConnectionRequiredException();
    }
    final server = await _serverById(serverId);
    if (server == null) throw const ServerConnectionRequiredException();
    return resolveRemoteFileClient(
      manager: ref.read(connectionManagerProvider),
      registry: ref.read(maidCafeSessionRegistryProvider),
      server: server,
      daemonAllowed: kIsWeb,
    );
  }

  /// Looks a server row up by id, for the pane that browses a server other than
  /// the tab's own.
  Future<Server?> _serverById(int serverId) async {
    final servers = await ref.read(serverRepositoryProvider).all();
    return servers.where((server) => server.id == serverId).firstOrNull;
  }

  Future<void> _streamRemoteFile(
    RemoteFileClient source,
    RemoteFileClient destination,
    String sourcePath,
    String targetPath,
    TaskControl controller,
    void Function(int) reportProgress, {
    int transferredBytes = 0,
  }) async {
    final input = await source.open(sourcePath, mode: SftpFileOpenMode.read);
    try {
      final output = await destination.open(
        targetPath,
        mode:
            SftpFileOpenMode.write |
            SftpFileOpenMode.create |
            SftpFileOpenMode.truncate,
      );
      try {
        var fileOffset = 0;
        await for (final chunk in input.read(
          chunkSize: 64 * 1024,
          maxPendingRequests: 4,
        )) {
          await controller.waitIfPaused();
          await output.writeBytes(chunk, offset: fileOffset);
          fileOffset += chunk.length;
          reportProgress(transferredBytes + fileOffset);
        }
      } finally {
        await output.close();
      }
    } finally {
      await input.close();
    }
  }

  Future<int> _streamRemoteDirectory(
    RemoteFileClient source,
    RemoteFileClient destination,
    String sourcePath,
    String targetPath,
    TaskControl controller,
    void Function(int) reportProgress, {
    int transferredBytes = 0,
  }) async {
    await destination.mkdir(targetPath);
    final entries = await source.listdir(sourcePath);
    for (final entry in entries) {
      if (entry.filename == '.' || entry.filename == '..') continue;
      await controller.waitIfPaused();
      final childSource = _joinRemotePath(sourcePath, entry.filename);
      final childTarget = _joinRemotePath(targetPath, entry.filename);
      if (entry.attr.isDirectory) {
        transferredBytes = await _streamRemoteDirectory(
          source,
          destination,
          childSource,
          childTarget,
          controller,
          reportProgress,
          transferredBytes: transferredBytes,
        );
      } else if (entry.attr.isFile) {
        await _streamRemoteFile(
          source,
          destination,
          childSource,
          childTarget,
          controller,
          reportProgress,
          transferredBytes: transferredBytes,
        );
        transferredBytes += entry.attr.size ?? 0;
      }
    }
    return transferredBytes;
  }

  Future<void> _deleteRemoteEntryOnServer(
    _ClipboardEntry entry, {
    required int serverId,
  }) async {
    final files = await _filesFor(serverId);
    if (entry.isSymbolicLink) {
      await files.remove(entry.path);
    } else if (entry.isDirectory) {
      await _deleteRemoteDirectory(files, entry.path);
    } else {
      await files.remove(entry.path);
    }
    await _refreshLeftRemote();
    await _refreshRemote();
  }

  Future<void> _extractRemoteArchive(
    _ClipboardEntry entry, {
    required int serverId,
    required String directory,
  }) async {
    if (!_isSupportedArchive(entry.name)) return;
    final command = entry.name.toLowerCase().endsWith('.zip')
        ? 'unzip -o -- ${_shellQuote(entry.name)}'
        : 'tar -xzf ${_shellQuote(entry.name)}';
    await _runRemoteUtility(
      serverId: serverId,
      title: 'fileManagerUnarchiving'.tr(args: [entry.name]),
      command: 'cd ${_shellQuote(directory)} && $command',
    );
  }

  Future<void> _archiveRemoteEntries(
    List<_ClipboardEntry> entries, {
    required int serverId,
    required String directory,
    required _ArchiveFormat format,
  }) async {
    if (entries.isEmpty) return;
    final files = await _filesFor(serverId);
    final extension = format == _ArchiveFormat.zip ? '.zip' : '.tar.gz';
    final archivePath = await _uniqueRemotePath(
      files,
      directory,
      entries.length == 1
          ? '${entries.first.name}$extension'
          : 'archive$extension',
    );
    final archiveName = archivePath.substring(archivePath.lastIndexOf('/') + 1);
    final names = entries.map((entry) => _shellQuote(entry.name)).join(' ');
    final command = format == _ArchiveFormat.zip
        ? 'zip -r -- ${_shellQuote(archiveName)} $names'
        : 'tar -czf ${_shellQuote(archiveName)} -- $names';
    await _runRemoteUtility(
      serverId: serverId,
      title: 'fileManagerArchiving'.tr(args: [archiveName]),
      command: 'cd ${_shellQuote(directory)} && $command',
    );
  }

  /// Runs a shell command on the server for the archive/unarchive actions.
  ///
  /// These are the file manager's only shell features: they need `zip`, `tar`
  /// and a working directory on the host, which the daemon's file API does not
  /// offer (it deliberately serves named operations, not a shell). A browser
  /// build therefore reports them unavailable instead of silently doing
  /// nothing, and the menu entries that call this are hidden there.
  Future<void> _runRemoteUtility({
    required int serverId,
    required String title,
    required String command,
  }) async {
    if (_busy) return;
    final owner = ref.read(connectionManagerProvider).clientFor(serverId);
    if (owner == null) {
      showStyledSnackBar(
        message: 'fileManagerShellUnavailable'.tr(),
        title: 'fileManagerUtilityFailed'.tr(args: [title]),
        icon: Symbols.terminal,
        accentColor: Theme.of(context).colorScheme.error,
      );
      return;
    }
    setState(() => _workingPath = title);
    try {
      final result = await ref.read(connectionManagerProvider).withClient(
        serverId,
        (client) async {
          final session = await client.execute(command);
          final stdout = utf8.decoder.bind(session.stdout).join();
          final stderr = utf8.decoder.bind(session.stderr).join();
          await session.done;
          final error = (await stderr).trim();
          if (session.exitCode != 0) {
            throw StateError(
              error.isEmpty ? 'fileManagerRemoteCommandFailed'.tr() : error,
            );
          }
          return (await stdout).trim();
        },
      );
      await _refreshRemote();
      await _refreshLeftRemote();
      if (mounted) {
        showStyledSnackBar(
          message: result.isEmpty ? title : result,
          title: 'fileManagerUtilityCompleted'.tr(),
          icon: Symbols.check_circle,
          accentColor: Theme.of(context).colorScheme.primary,
        );
      }
    } catch (error) {
      if (mounted) {
        showStyledSnackBar(
          message: error.toString(),
          title: 'fileManagerUtilityFailed'.tr(args: [title]),
          icon: Symbols.error,
          accentColor: Theme.of(context).colorScheme.error,
        );
      }
    } finally {
      if (mounted) setState(() => _workingPath = null);
    }
  }

  Future<void> _moveSameSide(_ClipboardEntry entry, _FileSide side) async {
    final isLeft = side == _FileSide.left;
    final destinationDir = isLeft ? _leftRemotePath : _remotePath;
    if (_parentRemotePath(entry.path) == destinationDir) return;
    final files = isLeft ? await _leftFiles() : await _files();
    final destination = await _resolveRemoteDestination(
      files,
      destinationDir,
      entry.name,
    );
    if (destination == null) return;
    await _removeRemoteEntry(files, destination);
    await files.rename(entry.path, destination);
    if (isLeft) {
      await _refreshLeftRemote();
    } else {
      await _refreshRemote();
    }
  }

  Future<void> _copySameSide(_ClipboardEntry entry, _FileSide side) async {
    final isLeft = side == _FileSide.left;
    final files = isLeft ? await _leftFiles() : await _files();
    final destination = await _resolveRemoteDestination(
      files,
      isLeft ? _leftRemotePath : _remotePath,
      entry.name,
    );
    if (destination == null) return;
    if (entry.isDirectory) {
      await _removeRemoteEntry(files, destination);
      await _copyRemoteDirectory(files, entry.path, destination);
    } else {
      await _copyRemoteFile(files, entry.path, destination);
    }
    if (isLeft) {
      await _refreshLeftRemote();
    } else {
      await _refreshRemote();
    }
  }

  Future<void> _saveEntryToDevice(
    _ClipboardEntry entry, {
    bool notify = true,
    Future<void> Function()? onSuccess,
  }) async {
    // There is no local pane to download into: the entry is saved to the
    // device, which on the web hands the bytes to the browser itself.
    if (entry.isDirectory) {
      await _downloadDirectoryToDevice(
        entry.path,
        entry.name,
        notify: notify,
        onSuccess: onSuccess,
      );
    } else {
      await _downloadToDevice(
        entry.path,
        entry.name,
        notify: notify,
        onSuccess: onSuccess,
      );
    }
  }

  Future<void> _deleteSelection() async {
    final side = _focusedSide;
    if (side == null) return;
    final entries = _entriesForSelection(side);
    if (entries.isEmpty) return;
    await _deleteEntries(entries, confirm: true);
  }

  Future<void> _deleteEntries(
    List<_ClipboardEntry> entries, {
    required bool confirm,
    bool notify = true,
  }) async {
    if (entries.isEmpty) return;
    if (confirm) {
      final label = entries.length == 1
          ? entries.first.name
          : '${entries.length} items';
      final message = entries.length == 1 && entries.first.isDirectory
          ? 'This folder and its contents will be permanently removed.'
          : entries.length == 1
          ? 'This file will be permanently removed.'
          : 'Selected files and folders will be permanently removed.';
      final approved = await showMaidKitConfirmAlert(
        message,
        'Delete $label?',
        isDanger: true,
      );
      if (!approved || !mounted) return;
    }

    try {
      final deletedLeft = <String>{};
      final deletedRemote = <String>{};
      for (final entry in entries) {
        final isLeft = entry.side == _FileSide.left;
        final files = isLeft
            ? await _filesFor(entry.serverId ?? _leftServerId!)
            : await _filesFor(widget.tab.serverId);
        if (entry.isSymbolicLink) {
          await files.remove(entry.path);
        } else if (entry.isDirectory) {
          await _deleteRemoteDirectory(files, entry.path);
        } else {
          await files.remove(entry.path);
        }
        (isLeft ? deletedLeft : deletedRemote).add(entry.path);
      }

      if (deletedRemote.isNotEmpty) {
        setState(() {
          _selectedRemotePaths = _selectedRemotePaths
              .difference(deletedRemote)
              .toSet();
        });
        await _refreshRemote();
      }
      if (deletedLeft.isNotEmpty) {
        setState(() {
          _selectedLeftPaths = _selectedLeftPaths
              .difference(deletedLeft)
              .toSet();
        });
        await _refreshLeftRemote();
      }
      if (notify && mounted) {
        showStyledSnackBar(
          message: entries.length == 1
              ? entries.first.name
              : '${entries.length} items',
          title: 'fileManagerDeleted'.tr(),
          icon: Symbols.delete,
          accentColor: Theme.of(context).colorScheme.primary,
        );
      }
    } catch (error) {
      if (notify && mounted) {
        showStyledSnackBar(
          message: error.toString(),
          title: 'fileManagerDeleteFailed'.tr(),
          icon: Symbols.error,
          accentColor: Theme.of(context).colorScheme.error,
        );
      }
      rethrow;
    }
  }

  Future<void> _uploadDroppedFiles(List<DropItem> items) async {
    for (final item in items.whereType<DropItemFile>()) {
      // macOS hands a security-scoped bookmark alongside the path, which must
      // be held open until the streamed read finishes; a browser hands over
      // bytes and no usable path.
      final bookmark = item.extraAppleBookmark;
      final hasSecurityScopedAccess =
          bookmark != null &&
          await DesktopDrop.instance.startAccessingSecurityScopedResource(
            bookmark: bookmark,
          );
      if (kIsWeb) {
        await _uploadBytes(
          await item.readAsBytes(),
          item.name.isEmpty ? 'upload.bin' : item.name,
          conflictMode: _kDropConflictMode,
        );
        continue;
      }
      final name = item.name.isEmpty ? _fileNameOf(item.path) : item.name;
      await _uploadFile(
        File(item.path),
        name,
        conflictMode: _kDropConflictMode,
        onFinish: hasSecurityScopedAccess
            ? () => DesktopDrop.instance.stopAccessingSecurityScopedResource(
                bookmark: bookmark,
              )
            : null,
      );
    }
  }

  /// Uploads one local file, streaming it from disk so a large drop never has
  /// to fit in memory.
  Future<void> _uploadFile(
    File file,
    String name, {
    bool notify = true,
    TransferConflictMode? conflictMode,
    Future<void> Function()? onSuccess,
    Future<void> Function()? onFinish,
  }) async {
    final totalBytes = await file.length();
    _runTransfer(
      title: 'fileManagerUploading'.tr(args: [name]),
      totalBytes: totalBytes,
      notify: notify,
      action: (controller, reportProgress) async {
        final files = await _files();
        final remotePath = await _resolveRemoteDestination(
          files,
          _remotePath,
          name,
          conflictMode: conflictMode,
        );
        if (remotePath == null) throw const TaskSkipped();
        final remoteFile = await files.open(
          remotePath,
          mode:
              SftpFileOpenMode.write |
              SftpFileOpenMode.create |
              SftpFileOpenMode.truncate,
        );
        try {
          var transferredBytes = 0;
          await for (final chunk in file.openRead().map(Uint8List.fromList)) {
            await controller.waitIfPaused();
            await remoteFile.writeBytes(chunk, offset: transferredBytes);
            transferredBytes += chunk.length;
            reportProgress(transferredBytes);
          }
        } finally {
          await remoteFile.close();
          if (controller.isCancelled) {
            try {
              await files.remove(remotePath);
            } catch (_) {}
          }
        }
        await _refreshRemote();
      },
      onSuccess: onSuccess,
      onFinish: onFinish,
    );
  }

  /// Last path segment of a local path, without pulling in the filesystem
  /// entity types the rest of this file no longer uses.
  static String _fileNameOf(String path) => Uri.file(
    path,
  ).pathSegments.lastWhere((segment) => segment.isNotEmpty, orElse: () => '');

  /// Uploads bytes the caller already holds, which is what a browser drop
  /// produces: the chunks are written through the transport's write handle, so
  /// the daemon's whole-file semantics are handled in one place.
  Future<void> _uploadBytes(
    Uint8List bytes,
    String name, {
    bool notify = true,
    TransferConflictMode? conflictMode,
    Future<void> Function()? onSuccess,
    Future<void> Function()? onFinish,
  }) async {
    _runTransfer(
      title: 'fileManagerUploading'.tr(args: [name]),
      totalBytes: bytes.length,
      notify: notify,
      action: (controller, reportProgress) async {
        final files = await _files();
        final remotePath = await _resolveRemoteDestination(
          files,
          _remotePath,
          name,
          conflictMode: conflictMode,
        );
        if (remotePath == null) throw const TaskSkipped();
        final remoteFile = await files.open(
          remotePath,
          mode:
              SftpFileOpenMode.write |
              SftpFileOpenMode.create |
              SftpFileOpenMode.truncate,
        );
        try {
          const chunkSize = 256 * 1024;
          var offset = 0;
          while (offset < bytes.length) {
            await controller.waitIfPaused();
            final end = math.min(offset + chunkSize, bytes.length);
            await remoteFile.writeBytes(
              bytes.sublist(offset, end),
              offset: offset,
            );
            offset = end;
            reportProgress(offset);
          }
        } finally {
          await remoteFile.close();
          if (controller.isCancelled) {
            try {
              await files.remove(remotePath);
            } catch (_) {}
          }
        }
        await _refreshRemote();
      },
      onSuccess: onSuccess,
      onFinish: onFinish,
    );
  }

  Future<void> _downloadToDevice(
    String remotePath,
    String filename, {
    bool notify = true,
    Future<void> Function()? onSuccess,
  }) async {
    // A browser has no temporary directory to stage into and no path to hand a
    // save dialog: the bytes go straight to the browser's own download, which
    // is what file_saver does with `bytes` on the web. Off the web the file is
    // staged on disk so a large download never has to fit in memory.
    final staging = kIsWeb
        ? null
        : await Directory.systemTemp.createTemp('maidkit-download-');
    final temporaryFile = staging == null
        ? null
        : File('${staging.path}$platformPathSeparator$filename');
    _runTransfer(
      title: 'fileManagerDownloading'.tr(args: [filename]),
      totalBytes: null,
      notify: notify,
      action: (controller, reportProgress) async {
        final files = await _files();
        final remoteFile = await files.open(
          remotePath,
          mode: SftpFileOpenMode.read,
        );
        final buffer = kIsWeb ? BytesBuilder(copy: false) : null;
        try {
          final sink = temporaryFile?.openWrite();
          try {
            var transferredBytes = 0;
            await for (final chunk in remoteFile.read(
              chunkSize: 64 * 1024,
              maxPendingRequests: 4,
            )) {
              await controller.waitIfPaused();
              if (buffer != null) {
                buffer.add(chunk);
              } else {
                sink!.add(chunk);
              }
              transferredBytes += chunk.length;
              reportProgress(transferredBytes);
              if (sink != null &&
                  transferredBytes % (1024 * 1024) < chunk.length) {
                await sink.flush();
              }
            }
          } finally {
            await sink?.close();
          }
        } finally {
          await remoteFile.close();
        }
        controller.throwIfCancelled();
        await FileSaver.instance.saveAs(
          name: filename,
          bytes: buffer?.takeBytes(),
          filePath: temporaryFile?.path,
          includeExtension: false,
          mimeType: MimeType.other,
        );
      },
      onSuccess: onSuccess,
      onFinish: () async {
        try {
          await staging?.delete(recursive: true);
        } catch (_) {}
      },
    );
  }

  Future<void> _downloadDirectoryToDevice(
    String remotePath,
    String name, {
    bool notify = true,
    Future<void> Function()? onSuccess,
  }) async {
    // A browser builds the zip in memory and hands the bytes to its own
    // download; off the web the tree is staged on disk and zipped there, so a
    // large directory is never held in memory.
    final staging = kIsWeb
        ? null
        : await Directory.systemTemp.createTemp('maidkit-download-');
    final stagedDirectory = staging == null
        ? null
        : Directory('${staging.path}$platformPathSeparator$name');
    final archiveFile = staging == null
        ? null
        : File('${staging.path}/$name.zip');
    _runTransfer(
      title: 'fileManagerDownloading'.tr(args: [name]),
      totalBytes: null,
      notify: notify,
      action: (controller, reportProgress) async {
        final files = await _files();
        if (stagedDirectory != null) {
          await _downloadRemoteDirectory(
            files,
            remotePath,
            stagedDirectory,
            controller: controller,
            reportProgress: reportProgress,
          );
          controller.throwIfCancelled();
          await ZipFileEncoder().zipDirectory(
            stagedDirectory,
            filename: archiveFile!.path,
          );
          controller.throwIfCancelled();
          await FileSaver.instance.saveAs(
            name: '$name.zip',
            filePath: archiveFile.path,
            includeExtension: false,
            mimeType: MimeType.zip,
          );
          return;
        }
        final archive = Archive();
        await _archiveRemoteDirectory(
          files,
          remotePath,
          archive,
          prefix: '',
          controller: controller,
          reportProgress: reportProgress,
        );
        controller.throwIfCancelled();
        final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
        controller.throwIfCancelled();
        await FileSaver.instance.saveAs(
          name: '$name.zip',
          bytes: bytes,
          includeExtension: false,
          mimeType: MimeType.zip,
        );
      },
      onSuccess: onSuccess,
      onFinish: () async {
        try {
          await staging?.delete(recursive: true);
        } catch (_) {}
      },
    );
  }

  /// Fills [archive] with the remote tree under [remotePath], the in-memory
  /// counterpart of [_downloadRemoteDirectory] that a browser uses because it
  /// has nowhere to stage files.
  Future<void> _archiveRemoteDirectory(
    RemoteFileClient files,
    String remotePath,
    Archive archive, {
    required String prefix,
    TaskControl? controller,
    void Function(int)? reportProgress,
  }) async {
    await controller?.waitIfPaused();
    final entries = await files.listdir(remotePath);
    for (final entry in entries) {
      if (entry.filename == '.' || entry.filename == '..') continue;
      await controller?.waitIfPaused();
      final childRemote = _joinRemotePath(remotePath, entry.filename);
      final childName = prefix.isEmpty
          ? entry.filename
          : '$prefix/${entry.filename}';

      if (entry.attr.isDirectory) {
        await _archiveRemoteDirectory(
          files,
          childRemote,
          archive,
          prefix: childName,
          controller: controller,
          reportProgress: reportProgress,
        );
      } else if (entry.attr.isFile) {
        final remoteFile = await files.open(
          childRemote,
          mode: SftpFileOpenMode.read,
        );
        try {
          final bytes = await remoteFile.readBytes();
          archive.addFile(ArchiveFile(childName, bytes.length, bytes));
        } finally {
          await remoteFile.close();
        }
      }
    }
  }

  /// Downloads the remote tree under [remotePath] into a staging directory
  /// on disk, so a large directory download never has to fit in memory.
  Future<int> _downloadRemoteDirectory(
    RemoteFileClient files,
    String remotePath,
    Directory local, {
    TaskControl? controller,
    void Function(int)? reportProgress,
    int transferredBytes = 0,
  }) async {
    await controller?.waitIfPaused();
    await local.create(recursive: true);
    final entries = await files.listdir(remotePath);
    for (final entry in entries) {
      if (entry.filename == '.' || entry.filename == '..') continue;
      await controller?.waitIfPaused();
      final childRemote = _joinRemotePath(remotePath, entry.filename);
      final childLocal = local.uri.resolve(entry.filename).toFilePath();
      if (entry.attr.isDirectory) {
        transferredBytes = await _downloadRemoteDirectory(
          files,
          childRemote,
          Directory(childLocal),
          controller: controller,
          reportProgress: reportProgress,
          transferredBytes: transferredBytes,
        );
      } else if (entry.attr.isFile) {
        final remoteFile = await files.open(
          childRemote,
          mode: SftpFileOpenMode.read,
        );
        try {
          final sink = File(childLocal).openWrite();
          try {
            await for (final chunk in remoteFile.read(
              length: entry.attr.size,
              chunkSize: 64 * 1024,
              maxPendingRequests: 4,
            )) {
              await controller?.waitIfPaused();
              sink.add(chunk);
              transferredBytes += chunk.length;
              reportProgress?.call(transferredBytes);
            }
          } finally {
            await sink.close();
          }
        } finally {
          await remoteFile.close();
        }
      }
    }
    return transferredBytes;
  }

  Future<void> _copyRemoteFile(
    RemoteFileClient files,
    String source,
    String destination,
  ) async {
    final remoteFile = await files.open(
      destination,
      mode:
          SftpFileOpenMode.write |
          SftpFileOpenMode.create |
          SftpFileOpenMode.truncate,
    );
    try {
      final sourceFile = await files.open(source, mode: SftpFileOpenMode.read);
      try {
        final data = await sourceFile.readBytes();
        await remoteFile.writeBytes(data);
      } finally {
        await sourceFile.close();
      }
    } finally {
      await remoteFile.close();
    }
  }

  Future<void> _copyRemoteDirectory(
    RemoteFileClient files,
    String source,
    String destination,
  ) async {
    await files.mkdir(destination);
    final entries = await files.listdir(source);
    for (final entry in entries) {
      if (entry.filename == '.' || entry.filename == '..') continue;
      final childSource = _joinRemotePath(source, entry.filename);
      final childDestination = _joinRemotePath(destination, entry.filename);
      if (entry.attr.isDirectory) {
        await _copyRemoteDirectory(files, childSource, childDestination);
      } else if (entry.attr.isFile) {
        await _copyRemoteFile(files, childSource, childDestination);
      }
    }
  }

  Future<void> _deleteRemoteDirectory(
    RemoteFileClient files,
    String path,
  ) async {
    final entries = await files.listdir(path);
    for (final entry in entries) {
      if (entry.filename == '.' || entry.filename == '..') continue;
      final child = _joinRemotePath(path, entry.filename);
      if (entry.attr.isDirectory) {
        await _deleteRemoteDirectory(files, child);
      } else {
        await files.remove(child);
      }
    }
    await files.rmdir(path);
  }

  /// Asks the user how to resolve a name conflict during a transfer.
  Future<_TransferConflictChoice> _askConflict(String name) async {
    final choice = await showMaidKitOverlayDialog<_TransferConflictChoice>(
      barrierDismissible: false,
      builder: (context, close) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kMaidKitDialogMaxWidth),
        child: AlertDialog(
          title: Text('fileManagerOverwriteTitle'.tr()),
          content: Text('fileManagerOverwriteMessage'.tr(args: [name])),
          actions: [
            TextButton(
              onPressed: () => close(_TransferConflictChoice.skip),
              child: Text('fileManagerSkip'.tr()),
            ),
            TextButton(
              onPressed: () => close(_TransferConflictChoice.keepBoth),
              child: Text('fileManagerKeepBoth'.tr()),
            ),
            FilledButton(
              onPressed: () => close(_TransferConflictChoice.overwrite),
              child: Text('fileManagerOverwrite'.tr()),
            ),
          ],
        ),
      ),
    );
    return choice ?? _TransferConflictChoice.skip;
  }

  /// Resolves where [name] should land inside [directory] on the remote side,
  /// honoring [conflictMode] when given and the configured transfer mode
  /// otherwise.
  Future<String?> _resolveRemoteDestination(
    RemoteFileClient files,
    String directory,
    String name, {
    TransferConflictMode? conflictMode,
  }) async {
    final candidate = _joinRemotePath(directory, name);
    if (!await _remoteExists(files, candidate)) return candidate;
    switch (conflictMode ?? _conflictMode) {
      case TransferConflictMode.rename:
        return _uniqueRemotePath(files, directory, name);
      case TransferConflictMode.overwrite:
        return candidate;
      case TransferConflictMode.ask:
        switch (await _askConflict(name)) {
          case _TransferConflictChoice.overwrite:
            return candidate;
          case _TransferConflictChoice.keepBoth:
            return _uniqueRemotePath(files, directory, name);
          case _TransferConflictChoice.skip:
            return null;
        }
    }
  }

  /// Removes an existing remote entry so a move or directory transfer can
  /// replace it. No-op when nothing exists at [path].
  Future<void> _removeRemoteEntry(RemoteFileClient files, String path) async {
    try {
      final linkAttrs = await files.stat(path, followLink: false);
      if (linkAttrs.isSymbolicLink) {
        await files.remove(path);
        return;
      }
      if (linkAttrs.isDirectory) {
        await _deleteRemoteDirectory(files, path);
      } else {
        await files.remove(path);
      }
    } catch (_) {
      // Nothing to replace (or already gone); the transfer itself reports
      // real failures.
    }
  }

  Future<String> _uniqueRemotePath(
    RemoteFileClient files,
    String directory,
    String name,
  ) async {
    var candidate = _joinRemotePath(directory, name);
    if (!await _remoteExists(files, candidate)) return candidate;
    final dot = name.lastIndexOf('.');
    final hasExtension = dot > 0 && !name.startsWith('.');
    final stem = hasExtension ? name.substring(0, dot) : name;
    final extension = hasExtension ? name.substring(dot) : '';
    var index = 1;
    while (true) {
      candidate = _joinRemotePath(directory, '$stem ($index)$extension');
      if (!await _remoteExists(files, candidate)) return candidate;
      index += 1;
    }
  }

  Future<bool> _remoteExists(RemoteFileClient files, String path) async {
    try {
      await files.stat(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Hands a transfer to the app-wide task queue and returns immediately.
  ///
  /// The one-at-a-time drain, the 250 ms progress throttle, speed sampling and
  /// the pause/cancel control all live in [TaskProgressNotifier], so a file
  /// copy is just an [AppTaskRequest] there — the same machinery the window's
  /// progress bar and sheet already render.
  void _runTransfer({
    required String title,
    required int? totalBytes,
    required Future<void> Function(TaskControl, TaskProgressReport) action,
    bool notify = true,
    Future<void> Function()? onSuccess,
    Future<void> Function()? onFinish,
  }) {
    // The queue defers its drain, so `id` is assigned before any callback can
    // read it, and the tab is marked busy before the action starts.
    late final String id;
    id = ref
        .read(taskProgressProvider.notifier)
        .run(
          AppTaskRequest(title: title, totalBytes: totalBytes, action: action),
          onSuccess: onSuccess,
          onComplete: () {
            if (notify && mounted) {
              showStyledSnackBar(
                message: title,
                title: 'fileManagerTransferComplete'.tr(),
                icon: Symbols.check_circle,
                accentColor: Theme.of(context).colorScheme.primary,
              );
            }
          },
          onError: (error) {
            if (!notify || !mounted) return;
            showStyledSnackBar(
              message: error.toString(),
              title: 'fileManagerTransferFailed'.tr(),
              icon: Symbols.error,
              accentColor: Theme.of(context).colorScheme.error,
            );
          },
          onFinish: () async {
            if (mounted) setState(() => _transferIds.remove(id));
            await onFinish?.call();
          },
        );
    // Transfers signal busy through [_transferIds] — the queue is shared, so a
    // transfer still queued behind another one must already block a rename in
    // this tab's directory.
    setState(() => _transferIds.add(id));
  }

  Future<RemoteFileClient> _files() {
    final owner = ref
        .read(connectionManagerProvider)
        .clientFor(widget.tab.serverId);
    final cached = _fileClient;
    if (cached != null && identical(_fileClientOwner, owner)) return cached;
    if (cached != null) unawaited(_closeFileClient(cached));
    final next = _openFileClient(widget.tab.serverId, owner);
    _fileClient = next;
    _fileClientOwner = owner;
    return next;
  }

  Future<void> _editLeft(SftpName entry) async {
    final server = await _serverById(_leftServerId ?? widget.tab.serverId);
    if (server == null) return;
    final path = _joinRemotePath(_leftRemotePath, entry.filename);
    try {
      validateEditableText(entry.attr.size, path);
    } catch (error) {
      if (!mounted) return;
      showMaidKitErrorAlert(
        error,
        title: 'fileManagerCouldNotOpen'.tr(args: [entry.filename]),
      );
      return;
    }
    ref
        .read(terminalTabsProvider.notifier)
        .openFileEditor(
          server: server,
          path: path,
          fileName: entry.filename,
          isRemote: true,
        );
  }

  Future<void> _editRemote(SftpName entry) async {
    final server = _serverForTab();
    if (server == null) return;
    final path = _joinRemotePath(_remotePath, entry.filename);
    try {
      validateEditableText(entry.attr.size, path);
    } catch (error) {
      if (!mounted) return;
      showMaidKitErrorAlert(
        error,
        title: 'fileManagerCouldNotOpen'.tr(args: [entry.filename]),
      );
      return;
    }
    ref
        .read(terminalTabsProvider.notifier)
        .openFileEditor(
          server: server,
          path: path,
          fileName: entry.filename,
          isRemote: true,
        );
  }

  Server? _serverForTab() {
    final servers = ref.read(serversProvider).asData?.value ?? const [];
    final server = servers
        .where((item) => item.id == widget.tab.serverId)
        .firstOrNull;
    if (server == null && mounted) {
      showStyledSnackBar(
        message: 'The server for this file session is no longer available.',
        title: 'fileManagerCouldNotOpen'.tr(args: ['']),
        icon: Symbols.error,
        accentColor: Theme.of(context).colorScheme.error,
      );
    }
    return server;
  }

  Menu _remoteEntryMenu(SftpName entry, int index) {
    final selected = _entriesForSelection(_FileSide.remote);
    final path = _joinRemotePath(_remotePath, entry.filename);
    final entries = selected.isEmpty
        ? [_clipboardEntryForRemote(entry)]
        : selected;
    final onlyThis = entries.length == 1 && entries.first.path == path;
    final isDirectory = entry.attr.isDirectory;
    final busy = _busy;
    final canPaste = _canPasteInto(_FileSide.remote);
    final transferLabel = entries.length == 1
        ? 'Download to local'
        : 'Download ${entries.length} items';
    return Menu(
      children: [
        if (onlyThis && isDirectory)
          MenuAction(
            title: 'fileManagerOpen'.tr(),
            callback: () => _openRemote(entry),
          ),
        if (onlyThis && entry.attr.isFile)
          MenuAction(
            title: 'fileManagerEdit'.tr(),
            callback: () => _editRemote(entry),
          ),
        MenuAction(
          title: transferLabel,
          callback: () async {
            _ensureRemoteContextSelection(entry, index);
            for (final item in _entriesForSelection(_FileSide.remote)) {
              await _saveEntryToDevice(item);
            }
          },
        ),
        MenuSeparator(),
        if (onlyThis &&
            !entry.attr.isDirectory &&
            _isSupportedArchive(entry.filename))
          MenuAction(
            title: 'fileManagerUnarchiveHere'.tr(),
            attributes: MenuActionAttributes(disabled: busy),
            callback: () => _extractRemoteArchive(
              entries.first,
              serverId: widget.tab.serverId,
              directory: _remotePath,
            ),
          ),
        MenuAction(
          title: 'fileManagerArchiveAsZip'.tr(),
          attributes: MenuActionAttributes(disabled: busy),
          callback: () => _archiveRemoteEntries(
            entries,
            serverId: widget.tab.serverId,
            directory: _remotePath,
            format: _ArchiveFormat.zip,
          ),
        ),
        MenuAction(
          title: 'fileManagerArchiveAsTarGz'.tr(),
          attributes: MenuActionAttributes(disabled: busy),
          callback: () => _archiveRemoteEntries(
            entries,
            serverId: widget.tab.serverId,
            directory: _remotePath,
            format: _ArchiveFormat.tarGzip,
          ),
        ),
        MenuSeparator(),
        MenuAction(
          title: 'commonCopy'.tr(),
          activator: const SingleActivator(LogicalKeyboardKey.keyC, meta: true),
          callback: () {
            _ensureRemoteContextSelection(entry, index);
            _setClipboard(_ClipboardMode.copy);
          },
        ),
        MenuAction(
          title: 'fileManagerCut'.tr(),
          activator: const SingleActivator(LogicalKeyboardKey.keyX, meta: true),
          callback: () {
            _ensureRemoteContextSelection(entry, index);
            _setClipboard(_ClipboardMode.cut);
          },
        ),
        MenuAction(
          title: 'fileManagerPaste'.tr(),
          attributes: MenuActionAttributes(disabled: !canPaste),
          activator: const SingleActivator(LogicalKeyboardKey.keyV, meta: true),
          callback: () => _pasteInto(_FileSide.remote),
        ),
        if (onlyThis)
          MenuAction(
            title: 'fileManagerRename'.tr(),
            attributes: MenuActionAttributes(disabled: busy),
            callback: () {
              _ensureRemoteContextSelection(entry, index);
              _renameEntry(_clipboardEntryForRemote(entry));
            },
          ),
        MenuSeparator(),
        MenuAction(
          title: entries.length == 1
              ? 'commonDelete'.tr()
              : 'Delete ${entries.length}',
          attributes: MenuActionAttributes(destructive: true, disabled: busy),
          activator: const SingleActivator(LogicalKeyboardKey.backspace),
          callback: () {
            _ensureRemoteContextSelection(entry, index);
            _deleteSelection();
          },
        ),
      ],
    );
  }

  Menu _leftEntryMenu(SftpName entry, int index) {
    final selected = _entriesForSelection(_FileSide.left);
    final path = _joinRemotePath(_leftRemotePath, entry.filename);
    final entries = selected.isEmpty
        ? [_clipboardEntryForLeft(entry)]
        : selected;
    final onlyThis = entries.length == 1 && entries.first.path == path;
    final busy = _busy;
    return Menu(
      children: [
        if (onlyThis && entry.attr.isDirectory)
          MenuAction(
            title: 'fileManagerOpen'.tr(),
            callback: () async {
              _ensureLeftContextSelection(entry, index);
              setState(() {
                _leftRemotePath = path;
                _selectedLeftPaths = {};
              });
              await _refreshLeftRemote();
            },
          ),
        MenuAction(
          title: entries.length == 1
              ? 'fileManagerTransferToServer'.tr(args: [widget.tab.serverName])
              : 'fileManagerTransferItemsToServer'.tr(
                  args: ['${entries.length}', widget.tab.serverName],
                ),
          callback: () async {
            _ensureLeftContextSelection(entry, index);
            for (final item in _entriesForSelection(_FileSide.left)) {
              await _transferBetweenServers(
                item,
                sourceServerId: _leftServerId!,
                targetServerId: widget.tab.serverId,
                targetDirectory: _remotePath,
              );
            }
          },
        ),
        MenuSeparator(),
        if (onlyThis &&
            !entry.attr.isDirectory &&
            _isSupportedArchive(entry.filename))
          MenuAction(
            title: 'fileManagerUnarchiveHere'.tr(),
            attributes: MenuActionAttributes(disabled: busy),
            callback: () => _extractRemoteArchive(
              entries.first,
              serverId: _leftServerId!,
              directory: _leftRemotePath,
            ),
          ),
        MenuAction(
          title: 'fileManagerArchiveAsZip'.tr(),
          attributes: MenuActionAttributes(disabled: busy),
          callback: () => _archiveRemoteEntries(
            entries,
            serverId: _leftServerId!,
            directory: _leftRemotePath,
            format: _ArchiveFormat.zip,
          ),
        ),
        MenuAction(
          title: 'fileManagerArchiveAsTarGz'.tr(),
          attributes: MenuActionAttributes(disabled: busy),
          callback: () => _archiveRemoteEntries(
            entries,
            serverId: _leftServerId!,
            directory: _leftRemotePath,
            format: _ArchiveFormat.tarGzip,
          ),
        ),
        MenuSeparator(),
        MenuAction(
          title: 'commonCopy'.tr(),
          activator: const SingleActivator(LogicalKeyboardKey.keyC, meta: true),
          callback: () {
            _ensureLeftContextSelection(entry, index);
            _setClipboard(_ClipboardMode.copy);
          },
        ),
        MenuAction(
          title: 'fileManagerCut'.tr(),
          activator: const SingleActivator(LogicalKeyboardKey.keyX, meta: true),
          callback: () {
            _ensureLeftContextSelection(entry, index);
            _setClipboard(_ClipboardMode.cut);
          },
        ),
        MenuAction(
          title: 'fileManagerPaste'.tr(),
          attributes: MenuActionAttributes(
            disabled: !_canPasteInto(_FileSide.left),
          ),
          activator: const SingleActivator(LogicalKeyboardKey.keyV, meta: true),
          callback: () => _pasteInto(_FileSide.left),
        ),
        if (onlyThis)
          MenuAction(
            title: 'fileManagerRename'.tr(),
            attributes: MenuActionAttributes(disabled: busy),
            callback: () {
              _ensureLeftContextSelection(entry, index);
              _renameEntry(_clipboardEntryForLeft(entry));
            },
          ),
        MenuSeparator(),
        MenuAction(
          title: entries.length == 1
              ? 'commonDelete'.tr()
              : 'Delete ${entries.length}',
          attributes: MenuActionAttributes(destructive: true, disabled: busy),
          activator: const SingleActivator(LogicalKeyboardKey.backspace),
          callback: () {
            _ensureLeftContextSelection(entry, index);
            _deleteSelection();
          },
        ),
      ],
    );
  }

  Menu _paneBackgroundMenu(_FileSide side) {
    final canPaste = _canPasteInto(side);
    final isLeft = side == _FileSide.left;
    final canGoUp = isLeft ? _leftRemotePath != '/' : _remotePath != '/';
    return Menu(
      children: [
        MenuAction(
          title: 'fileManagerCreateFolder'.tr(),
          attributes: MenuActionAttributes(disabled: _busy),
          callback: () => _createFolder(side),
        ),
        MenuAction(
          title: 'fileManagerPaste'.tr(),
          attributes: MenuActionAttributes(disabled: !canPaste),
          activator: const SingleActivator(LogicalKeyboardKey.keyV, meta: true),
          callback: () => _pasteInto(side),
        ),
        MenuSeparator(),
        MenuAction(
          title: 'fileManagerGoUp'.tr(),
          attributes: MenuActionAttributes(disabled: !canGoUp),
          callback: () {
            if (isLeft) {
              _openLeftRemotePath(_parentRemotePath(_leftRemotePath));
            } else {
              _goUpRemote();
            }
          },
        ),
        MenuAction(
          title: 'commonRefresh'.tr(),
          callback: () {
            if (isLeft) {
              unawaited(_refreshLeftRemote());
            } else {
              unawaited(_refreshRemote());
            }
          },
        ),
      ],
    );
  }

  /// True when a text field (path bar, etc.) should own typing shortcuts.
  bool get _isTextInputFocused {
    if (_leftRemotePathFocusNode.hasFocus) return true;
    if (_remotePathFocusNode.hasFocus) return true;
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null || primary.context == null) return false;
    // TextField / EditableText own the primary focus while editing.
    return primary.context!.widget is EditableText ||
        primary.context!.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// Whether the left pane is shown and can receive focus.
  ///
  /// The left pane only exists once a second server is chosen, and a narrow
  /// layout shows the right pane alone.
  bool get _canFocusLeftPane =>
      _leftIsRemote && !_isNarrowLayout && !_leftCollapsed;

  double _clampPaneSplitRatio(double ratio, double availableWidth) {
    if (availableWidth <= 0) return 0.5;
    final minimumRatio = math.min(0.5, _minimumPaneWidth / availableWidth);
    return ratio.clamp(minimumRatio, 1.0 - minimumRatio).toDouble();
  }

  void _collapseLeftPane() {
    if (_isNarrowLayout) return;
    setState(() {
      _leftCollapsed = true;
      _remoteCollapsed = false;
      _paneSplitRatio = 0.5;
      if (_focusedSide == _FileSide.left) _focusedSide = _FileSide.remote;
      if (_dropTargetSide == _FileSide.left) _dropTargetSide = null;
    });
  }

  void _collapseRemotePane() {
    if (_isNarrowLayout) return;
    setState(() {
      _leftCollapsed = false;
      _remoteCollapsed = true;
      _paneSplitRatio = 0.5;
      if (_focusedSide == _FileSide.remote) _focusedSide = _FileSide.left;
      if (_dropTargetSide == _FileSide.remote) _dropTargetSide = null;
    });
  }

  void _expandLeftPane() {
    setState(() {
      _leftCollapsed = false;
      _paneSplitRatio = 0.5;
    });
  }

  void _expandRemotePane() {
    setState(() {
      _remoteCollapsed = false;
      _paneSplitRatio = 0.5;
    });
  }

  void _startPaneResize() {
    _paneDragRatio = _paneSplitRatio;
  }

  void _resizePanes(DragUpdateDetails details, double availableWidth) {
    if (availableWidth <= 0) return;
    final next =
        (_paneDragRatio ?? _paneSplitRatio) + details.delta.dx / availableWidth;
    _paneDragRatio = next;
    if (next <= _paneCollapseThreshold) {
      _paneDragRatio = null;
      _collapseLeftPane();
      return;
    }
    if (next >= 1.0 - _paneCollapseThreshold) {
      _paneDragRatio = null;
      _collapseRemotePane();
      return;
    }
    setState(() {
      _paneSplitRatio = _clampPaneSplitRatio(next, availableWidth);
    });
  }

  void _endPaneResize() {
    _paneDragRatio = null;
  }

  int _displayedLength(_FileSide side) => side == _FileSide.left
      ? _displayedLeftRemoteEntries.length
      : _displayedRemoteEntries.length;

  bool _canGoUpForSide(_FileSide side) =>
      side == _FileSide.left ? _leftRemotePath != '/' : _remotePath != '/';

  int? _selectionIndex(_FileSide side) {
    if (side == _FileSide.left) {
      final anchor = _leftAnchorIndex;
      if (anchor != null && anchor >= 0 && anchor < _displayedLength(side)) {
        return anchor;
      }
      for (var i = 0; i < _displayedLeftRemoteEntries.length; i++) {
        final path = _joinRemotePath(
          _leftRemotePath,
          _displayedLeftRemoteEntries[i].filename,
        );
        if (_selectedLeftPaths.contains(path)) return i;
      }
      return null;
    }
    final anchor = _remoteAnchorIndex;
    if (anchor != null &&
        anchor >= 0 &&
        anchor < _displayedRemoteEntries.length) {
      return anchor;
    }
    for (var i = 0; i < _displayedRemoteEntries.length; i++) {
      final path = _joinRemotePath(
        _remotePath,
        _displayedRemoteEntries[i].filename,
      );
      if (_selectedRemotePaths.contains(path)) return i;
    }
    return null;
  }

  void _selectIndex(_FileSide side, int index, {bool range = false}) {
    final displayed = side == _FileSide.left
        ? _displayedLeftRemoteEntries
        : _displayedRemoteEntries;
    if (index < 0 || index >= displayed.length) return;
    if (side == _FileSide.left) {
      _selectLeft(displayed[index], index: index, range: range);
    } else {
      _selectRemote(displayed[index], index: index, range: range);
    }
  }

  void _moveSelectionInSide(int delta, {required bool range}) {
    _requestShortcutFocus();
    final side = _focusedSide ?? _FileSide.remote;
    final length = _displayedLength(side);
    if (length == 0) return;
    final current = _selectionIndex(side);
    if (current == null) {
      final index = delta > 0 ? 0 : length - 1;
      _selectIndex(side, index);
      _scrollToIndex(side, index);
      return;
    }
    var index = current + delta;
    if (index < 0) index = 0;
    if (index >= length) index = length - 1;
    if (!range && index == current) return;
    _selectIndex(side, index, range: range);
    _scrollToIndex(side, index);
  }

  void _selectBoundary({required bool first}) {
    _requestShortcutFocus();
    final side = _focusedSide ?? _FileSide.remote;
    final length = _displayedLength(side);
    if (length == 0) return;
    final index = first ? 0 : length - 1;
    _selectIndex(side, index);
    _scrollToIndex(side, index);
  }

  void _scrollToIndex(_FileSide side, int index) {
    final controller = side == _FileSide.left
        ? _leftRemoteListController
        : _rightRemoteListController;
    if (!controller.hasClients) return;
    final position = controller.position;
    final rowOffset = _canGoUpForSide(side) ? 1 : 0;
    final top = (index + rowOffset) * _kFileRowExtent;
    final bottom = top + _kFileRowExtent;
    final viewport = position.viewportDimension;
    if (top < position.pixels) {
      position.jumpTo(top < 0 ? 0 : top);
    } else if (bottom > position.pixels + viewport) {
      position.jumpTo((bottom - viewport).clamp(0.0, position.maxScrollExtent));
    }
  }

  void _goUpFocusedSide() {
    _requestShortcutFocus();
    if (_focusedSide == _FileSide.left) {
      if (_leftRemotePath == '/') return;
      _openLeftRemotePath(_parentRemotePath(_leftRemotePath));
      return;
    }
    unawaited(_goUpRemote());
  }

  void _openLeftRemotePath(String path) {
    _pushLeftHistory();
    setState(() {
      _leftRemotePath = path;
      _selectedLeftPaths = {};
      _leftAnchorIndex = null;
      _focusedSide = _FileSide.left;
    });
    unawaited(_refreshLeftRemote());
  }

  void _openFocusedSelection() {
    _requestShortcutFocus();
    final side = _focusedSide;
    if (side == null) return;
    final entry = _entriesForSelection(side).firstOrNull;
    if (entry == null) return;
    if (entry.isDirectory) {
      if (side == _FileSide.left) {
        _openLeftRemotePath(entry.path);
      } else {
        unawaited(_navigateRemote(entry.path));
      }
      return;
    }
    if (side == _FileSide.left) {
      final match = _leftRemoteEntries
          .where(
            (item) =>
                _joinRemotePath(_leftRemotePath, item.filename) == entry.path,
          )
          .firstOrNull;
      if (match != null && match.attr.isFile) unawaited(_editLeft(match));
      return;
    }
    final remoteMatch = _remoteEntries
        .where(
          (item) => _joinRemotePath(_remotePath, item.filename) == entry.path,
        )
        .firstOrNull;
    if (remoteMatch != null && remoteMatch.attr.isFile) {
      unawaited(_editRemote(remoteMatch));
    }
  }

  void _renameFocusedSelection() {
    _requestShortcutFocus();
    final side = _focusedSide;
    if (side == null) return;
    final entries = _entriesForSelection(side);
    if (entries.length != 1) return;
    unawaited(_renameEntry(entries.first));
  }

  void _refreshFocusedPane() {
    final side = _focusedSide ?? _FileSide.remote;
    if (side == _FileSide.left) {
      unawaited(_refreshLeftRemote());
    } else {
      unawaited(_refreshRemote());
    }
  }

  void _focusPathBar() {
    final focusLeft = _focusedSide == _FileSide.left && _leftIsRemote;
    final node = focusLeft ? _leftRemotePathFocusNode : _remotePathFocusNode;
    final controller = focusLeft
        ? _leftRemotePathController
        : _remotePathController;
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // Let path bar and other text fields handle select-all, delete, paste, etc.
    if (_isTextInputFocused) return KeyEventResult.ignored;

    final isMeta =
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final logical = event.logicalKey;

    if (isMeta) {
      if (logical == LogicalKeyboardKey.keyA) {
        _selectAllOnFocusedSide();
        return KeyEventResult.handled;
      }
      if (logical == LogicalKeyboardKey.keyC) {
        _setClipboard(_ClipboardMode.copy);
        return KeyEventResult.handled;
      }
      if (logical == LogicalKeyboardKey.keyX) {
        _setClipboard(_ClipboardMode.cut);
        return KeyEventResult.handled;
      }
      if (logical == LogicalKeyboardKey.keyV) {
        final side = _focusedSide;
        if (side != null) _pasteInto(side);
        return KeyEventResult.handled;
      }
      if (logical == LogicalKeyboardKey.keyN) {
        unawaited(_createFolder(_focusedSide ?? _FileSide.remote));
        return KeyEventResult.handled;
      }
      if (logical == LogicalKeyboardKey.keyR) {
        _refreshFocusedPane();
        return KeyEventResult.handled;
      }
      if (logical == LogicalKeyboardKey.keyL) {
        _focusPathBar();
        return KeyEventResult.handled;
      }
      if (logical == LogicalKeyboardKey.arrowUp) {
        _goUpFocusedSide();
        return KeyEventResult.handled;
      }
      if (logical == LogicalKeyboardKey.arrowDown) {
        _openFocusedSelection();
        return KeyEventResult.handled;
      }
      if (logical == LogicalKeyboardKey.arrowLeft) {
        if (_canFocusLeftPane) _focusSide(_FileSide.left);
        return KeyEventResult.handled;
      }
      if (logical == LogicalKeyboardKey.arrowRight) {
        _focusSide(_FileSide.remote);
        return KeyEventResult.handled;
      }
    }
    if (logical == LogicalKeyboardKey.arrowUp ||
        logical == LogicalKeyboardKey.arrowDown) {
      _moveSelectionInSide(
        logical == LogicalKeyboardKey.arrowDown ? 1 : -1,
        range: isShift,
      );
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.home) {
      _selectBoundary(first: true);
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.end) {
      _selectBoundary(first: false);
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.enter ||
        logical == LogicalKeyboardKey.numpadEnter) {
      _openFocusedSelection();
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.f2) {
      _renameFocusedSelection();
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.f5) {
      _refreshFocusedPane();
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.backslash) {
      _wakeSearch(_focusedSide ?? _FileSide.remote);
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.escape) {
      if (_leftSearchOpen || _rightSearchOpen) {
        if (_leftSearchOpen) _toggleSearch(_FileSide.left);
        if (_rightSearchOpen) _toggleSearch(_FileSide.remote);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (logical == LogicalKeyboardKey.backspace ||
        logical == LogicalKeyboardKey.delete) {
      _deleteSelection();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pathTextStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontFamily: MaidKitFonts.mono,
      color: scheme.onSurfaceVariant,
    );
    // The left pane exists only once another server is chosen; with one server
    // this tab is a single-pane browser.
    final leftPane = _leftIsRemote ? _buildLeftRemotePane(pathTextStyle) : null;
    final remotePane = _FilePane(
      title: 'fileManagerRemote'.tr(),
      path: _remotePath,
      pathTextStyle: pathTextStyle,
      searchInput: _rightSearchOpen ? _searchInput(_FileSide.remote) : null,
      focused: _focusedSide == _FileSide.remote,
      dropHighlighted: _dropTargetSide == _FileSide.remote,
      canGoUp: _remotePath != '/',
      onGoUp: _goUpRemote,
      pathInput: TextField(
        controller: _remotePathController,
        focusNode: _remotePathFocusNode,
        style: pathTextStyle,
        maxLines: 1,
        textInputAction: TextInputAction.go,
        onTap: () {
          _focusSide(_FileSide.remote);
          _remotePathController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _remotePathController.text.length,
          );
        },
        onSubmitted: _navigateRemote,
        decoration: InputDecoration(
          hintText: 'fileManagerRemotePath'.tr(),
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        ),
      ),
      onCopyPath: _copyRemotePath,
      onOpenTerminal: _openTerminalHere,
      onRefresh: _refreshRemote,
      onFocus: () => _focusSide(_FileSide.remote),
      loading: _loadingRemote,
      error: _remoteError,
      clipboardHint: _clipboardHint(_FileSide.remote),
      aboveList: _favoritePaths.isEmpty
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [_favoritePathsPanel(), const Divider(height: 1)],
            ),
      backgroundMenu: () => _paneBackgroundMenu(_FileSide.remote),
      canAcceptDrop: (data) => data.side == _FileSide.left,
      onDragEntered: () => setState(() => _dropTargetSide = _FileSide.remote),
      onDragExited: () {
        if (_dropTargetSide == _FileSide.remote) {
          setState(() => _dropTargetSide = null);
        }
      },
      onAcceptDrop: (data) => _handleInternalDrop(data, _FileSide.remote),
      headerActions: [
        _searchToggle(_FileSide.remote),
        _favoriteToggleButton(),
        IconButton(
          tooltip: 'fileManagerCreateFolder'.tr(),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          onPressed: _busy ? null : () => _createFolder(_FileSide.remote),
          icon: const Icon(Symbols.create_new_folder, size: 18),
        ),
        IconButton(
          tooltip: 'fileManagerUseAnotherServer'.tr(),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          onPressed: _chooseLeftServer,
          icon: const Icon(Symbols.swap_horiz, size: 18),
        ),
      ],
      onPointerDown: (event) => _handlePanePointerDown(event, _FileSide.remote),
      child: _RemoteFileList(
        entries: _displayedRemoteEntries,
        expandHidden: _rightSearchController.text.trim().isNotEmpty,
        symbolicLinkPaths: _remoteSymlinkPaths,
        scrollController: _rightRemoteListController,
        canGoUp: _remotePath != '/',
        onGoUp: _goUpRemote,
        emptyMessage: _rightSearchController.text.trim().isEmpty
            ? null
            : 'fileManagerNoMatches'.tr(),
        currentPath: _remotePath,
        selectedPaths: _selectedRemotePaths,
        cutPaths: _cutPathsFor(_FileSide.remote),
        onTapEntry: (entry, index) {
          _selectRemote(
            entry,
            index: index,
            toggle: _isMultiModifierPressed,
            range: _isRangeModifierPressed,
          );
        },
        onOpen: _openRemote,
        onEdit: (entry) {
          if (entry.attr.isFile) unawaited(_editRemote(entry));
        },
        dragDataFor: _dragDataForRemote,
        onContextPrepare: _ensureRemoteContextSelection,
        menuProvider: _remoteEntryMenu,
      ),
    );
    final content = LayoutBuilder(
      builder: (context, constraints) {
        if (leftPane == null ||
            constraints.maxWidth < _narrowLayoutBreakpoint) {
          return remotePane;
        }
        final availableWidth = constraints.maxWidth - _paneDividerWidth;
        final paneRatio = _clampPaneSplitRatio(_paneSplitRatio, availableWidth);
        final baseLeftWidth = availableWidth * paneRatio;
        final baseRemoteWidth = availableWidth - baseLeftWidth;
        final showLeftTarget = !_leftCollapsed;
        final showRemoteTarget = !_remoteCollapsed;
        return TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOutCubic,
          tween: Tween<double>(end: showLeftTarget ? 1.0 : 0.0),
          builder: (context, leftFactor, _) {
            return TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOutCubic,
              tween: Tween<double>(end: showRemoteTarget ? 1.0 : 0.0),
              builder: (context, remoteFactor, _) {
                final leftWidth = showRemoteTarget
                    ? baseLeftWidth * leftFactor
                    : availableWidth - baseRemoteWidth * remoteFactor;
                final remoteWidth = availableWidth - leftWidth;
                final showLeft = leftWidth > 0.001;
                final showRemote = remoteWidth > 0.001;
                return Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showLeft)
                          ClipRect(
                            child: SizedBox(
                              width: leftWidth,
                              child: Opacity(
                                opacity: leftFactor,
                                child: leftPane,
                              ),
                            ),
                          ),
                        const SizedBox(width: _paneDividerWidth),
                        if (showRemote)
                          ClipRect(
                            child: SizedBox(
                              width: remoteWidth,
                              child: Opacity(
                                opacity: remoteFactor,
                                child: remotePane,
                              ),
                            ),
                          ),
                      ],
                    ),
                    Positioned(
                      left:
                          leftWidth +
                          (_paneDividerWidth - _paneDividerHitTargetWidth) / 2,
                      top: 0,
                      bottom: 0,
                      width: _paneDividerHitTargetWidth,
                      child: _FilePaneDivider(
                        dividerWidth: _paneDividerHitTargetWidth,
                        leftCollapsed: !showLeft,
                        remoteCollapsed: !showRemote,
                        onExpandLeft: _expandLeftPane,
                        onExpandRemote: _expandRemotePane,
                        onDragStart: _startPaneResize,
                        onDragUpdate: (details) =>
                            _resizePanes(details, availableWidth),
                        onDragEnd: _endPaneResize,
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );

    return Focus(
      focusNode: _shortcutFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: DropTarget(
        onDragEntered: (_) => setState(() => _draggingFiles = true),
        onDragExited: (_) => setState(() => _draggingFiles = false),
        onDragDone: (details) async {
          setState(() => _draggingFiles = false);
          await _uploadDroppedFiles(details.files);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            content,
            if (_draggingFiles)
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    border: Border.all(color: scheme.primary, width: 2),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Symbols.upload_file,
                          size: 32,
                          color: scheme.primary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Drop files to upload to $_remotePath',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftRemotePane(TextStyle? pathTextStyle) {
    final serverName =
        (ref.read(serversProvider).asData?.value ?? const <Server>[])
            .where((server) => server.id == _leftServerId)
            .firstOrNull
            ?.name ??
        'fileManagerAnotherServer'.tr();
    return _FilePane(
      title: serverName,
      path: _leftRemotePath,
      pathTextStyle: pathTextStyle,
      searchInput: _leftSearchOpen ? _searchInput(_FileSide.left) : null,
      focused: _focusedSide == _FileSide.left,
      dropHighlighted: _dropTargetSide == _FileSide.left,
      canGoUp: _leftRemotePath != '/',
      onGoUp: () async {
        _pushLeftHistory();
        setState(() {
          _leftRemotePath = _parentRemotePath(_leftRemotePath);
          _selectedLeftPaths = {};
          _leftAnchorIndex = null;
        });
        await _refreshLeftRemote();
      },
      pathInput: TextField(
        controller: _leftRemotePathController,
        focusNode: _leftRemotePathFocusNode,
        style: pathTextStyle,
        maxLines: 1,
        textInputAction: TextInputAction.go,
        onTap: () {
          _focusSide(_FileSide.left);
          _leftRemotePathController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _leftRemotePathController.text.length,
          );
        },
        onSubmitted: _navigateLeftRemote,
        decoration: InputDecoration(
          hintText: 'fileManagerRemotePath'.tr(),
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        ),
      ),
      onRefresh: _refreshLeftRemote,
      onFocus: () => _focusSide(_FileSide.left),
      loading: _loadingLeftRemote,
      error: _leftRemoteError,
      clipboardHint: _clipboardHint(_FileSide.left),
      backgroundMenu: () => _paneBackgroundMenu(_FileSide.left),
      canAcceptDrop: (data) => data.side == _FileSide.remote,
      onDragEntered: () => setState(() => _dropTargetSide = _FileSide.left),
      onDragExited: () {
        if (_dropTargetSide == _FileSide.left) {
          setState(() => _dropTargetSide = null);
        }
      },
      onAcceptDrop: (data) => _handleInternalDrop(data, _FileSide.left),
      headerActions: [
        _searchToggle(_FileSide.left),
        IconButton(
          tooltip: 'fileManagerCreateFolder'.tr(),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          onPressed: _busy ? null : () => _createFolder(_FileSide.left),
          icon: const Icon(Symbols.create_new_folder, size: 18),
        ),
        IconButton(
          tooltip: 'fileManagerChangeServer'.tr(),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          onPressed: _chooseLeftServer,
          icon: const Icon(Symbols.swap_horiz, size: 18),
        ),
      ],
      onPointerDown: (event) => _handlePanePointerDown(event, _FileSide.left),
      child: _RemoteFileList(
        entries: _displayedLeftRemoteEntries,
        expandHidden: _leftSearchController.text.trim().isNotEmpty,
        symbolicLinkPaths: _leftRemoteSymlinkPaths,
        scrollController: _leftRemoteListController,
        canGoUp: _leftRemotePath != '/',
        onGoUp: () async {
          _pushLeftHistory();
          setState(() {
            _leftRemotePath = _parentRemotePath(_leftRemotePath);
            _selectedLeftPaths = {};
            _leftAnchorIndex = null;
          });
          await _refreshLeftRemote();
        },
        emptyMessage: _leftSearchController.text.trim().isEmpty
            ? null
            : 'fileManagerNoMatches'.tr(),
        currentPath: _leftRemotePath,
        selectedPaths: _selectedLeftPaths,
        cutPaths: _cutPathsFor(_FileSide.left),
        onTapEntry: (entry, index) => _selectLeft(
          entry,
          index: index,
          toggle: _isMultiModifierPressed,
          range: _isRangeModifierPressed,
        ),
        onOpen: (entry) async {
          if (!entry.attr.isDirectory) return;
          _pushLeftHistory();
          setState(() {
            _leftRemotePath = _joinRemotePath(_leftRemotePath, entry.filename);
            _selectedLeftPaths = {};
            _leftAnchorIndex = null;
          });
          await _refreshLeftRemote();
        },
        onEdit: (_) {},
        dragDataFor: _dragDataForLeft,
        onContextPrepare: _ensureLeftContextSelection,
        menuProvider: _leftEntryMenu,
      ),
    );
  }

  Set<String> _cutPathsFor(_FileSide side) {
    final clipboard = _clipboard;
    if (clipboard == null || clipboard.mode != _ClipboardMode.cut) {
      return const {};
    }
    return clipboard.entries
        .where((entry) => entry.side == side)
        .map((entry) => entry.path)
        .toSet();
  }

  String? _clipboardHint(_FileSide side) {
    final clipboard = _clipboard;
    if (clipboard == null || clipboard.isEmpty) return null;
    final count = clipboard.entries.length;
    final verb = clipboard.mode == _ClipboardMode.cut
        ? 'fileManagerCut'.tr()
        : 'fileManagerCopied'.tr();
    final source = clipboard.entries.first.side == _FileSide.remote
        ? 'remote'
        : 'server';
    return '$verb $count from $source · paste here';
  }

  Server? _serverRecord() {
    final servers = ref.read(serversProvider).asData?.value ?? const <Server>[];
    return servers
        .where((server) => server.id == widget.tab.serverId)
        .firstOrNull;
  }

  Future<void> _toggleFavoritePath(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty) return;
    final previous = List<String>.of(_favoritePaths);
    final next = [...previous];
    if (!next.remove(normalized)) {
      next.add(normalized);
    }
    setState(() => _favoritePaths = next);
    try {
      await ref
          .read(serverRepositoryProvider)
          .updateFileManagementFavorites(widget.tab.serverId, next);
    } catch (error) {
      if (!mounted) return;
      setState(() => _favoritePaths = previous);
      showStyledSnackBar(
        message: error.toString(),
        title: 'fileManagerFavoriteSaveFailed'.tr(),
        icon: Symbols.error,
        accentColor: Theme.of(context).colorScheme.error,
      );
    }
  }

  Future<void> _navigateFavorite(String path) async {
    await _navigateRemote(path);
  }

  Widget _favoritePathsPanel() {
    return ExpansionTile(
      initiallyExpanded: true,
      dense: true,
      minTileHeight: _kFileRowExtent,
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: EdgeInsets.zero,
      shape: const Border(),
      collapsedShape: const Border(),
      title: Row(
        children: [
          Icon(
            Symbols.folder_special,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'fileManagerFavoritePaths'.tr(
                args: [_favoritePaths.length.toString()],
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
      children: [
        for (final path in _favoritePaths)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            title: Row(
              children: [
                Icon(
                  Symbols.star,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            onTap: () => _navigateFavorite(path),
            trailing: IconButton(
              tooltip: 'fileManagerRemoveFavorite'.tr(),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Symbols.delete, size: 18),
              onPressed: () => _toggleFavoritePath(path),
            ),
          ),
      ],
    );
  }

  Widget _favoriteToggleButton() {
    final favorite = _favoritePaths.contains(_remotePath);
    return IconButton(
      tooltip: favorite
          ? 'fileManagerRemoveFavorite'.tr()
          : 'fileManagerAddFavorite'.tr(),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      onPressed: () => _toggleFavoritePath(_remotePath),
      icon: Icon(favorite ? Symbols.star : Symbols.star_border, size: 18),
    );
  }
}

Future<String?> _showFileNameSheet(
  BuildContext context, {
  required String title,
  required String label,
  required String actionLabel,
  String initialName = '',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    builder: (_) => _FileNameSheet(
      title: title,
      label: label,
      actionLabel: actionLabel,
      initialName: initialName,
    ),
  );
}

class _FileNameSheet extends StatefulWidget {
  const _FileNameSheet({
    required this.title,
    required this.label,
    required this.actionLabel,
    required this.initialName,
  });

  final String title;
  final String label;
  final String actionLabel;
  final String initialName;

  @override
  State<_FileNameSheet> createState() => _FileNameSheetState();
}

class _FileNameSheetState extends State<_FileNameSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(context, _name.text.trim());
  }

  @override
  Widget build(BuildContext context) => SheetScaffold(
    titleText: widget.title,
    heightFactor: 0.36,
    child: Form(
      key: _formKey,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(labelText: widget.label),
              validator: _validateFileName,
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('commonCancel'.tr()),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _submit,
                  child: Text(widget.actionLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

String? _validateFileName(String? value) {
  final name = value?.trim() ?? '';
  if (name.isEmpty) return 'fileManagerNameRequired'.tr();
  if (name == '.' || name == '..' || name.contains('/')) {
    return 'fileManagerInvalidName'.tr();
  }
  return null;
}

class _FilePaneDivider extends StatelessWidget {
  const _FilePaneDivider({
    required this.dividerWidth,
    required this.leftCollapsed,
    required this.remoteCollapsed,
    required this.onExpandLeft,
    required this.onExpandRemote,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final double dividerWidth;
  final bool leftCollapsed;
  final bool remoteCollapsed;
  final VoidCallback onExpandLeft;
  final VoidCallback onExpandRemote;
  final VoidCallback onDragStart;
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => onDragStart(),
        onHorizontalDragUpdate: onDragUpdate,
        onHorizontalDragEnd: (_) => onDragEnd(),
        onHorizontalDragCancel: onDragEnd,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned(
              top: 0,
              bottom: 0,
              left: (dividerWidth - 1) / 2,
              width: 1,
              child: ColoredBox(
                color: scheme.outlineVariant.withValues(alpha: 0.8),
                child: const SizedBox.expand(),
              ),
            ),
            if (leftCollapsed)
              IconButton(
                tooltip: 'fileManagerShowLeftPane'.tr(),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: onExpandLeft,
                icon: const Icon(Symbols.left_panel_open, size: 18),
              )
            else if (remoteCollapsed)
              IconButton(
                tooltip: 'Show remote',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: onExpandRemote,
                icon: const Icon(Symbols.right_panel_open, size: 18),
              ),
          ],
        ),
      ),
    );
  }
}

class _FilePane extends StatelessWidget {
  const _FilePane({
    required this.title,
    required this.path,
    required this.pathTextStyle,
    required this.focused,
    required this.dropHighlighted,
    required this.canGoUp,
    required this.onGoUp,
    required this.onRefresh,
    required this.onFocus,
    required this.loading,
    required this.error,
    required this.backgroundMenu,
    required this.canAcceptDrop,
    required this.onDragEntered,
    required this.onDragExited,
    required this.onAcceptDrop,
    required this.child,
    this.pathInput,
    this.searchInput,
    this.onCopyPath,
    this.onOpenTerminal,
    this.aboveList,
    this.clipboardHint,
    this.onPointerDown,
    this.headerActions = const [],
  });

  final String title;
  final String path;
  final TextStyle? pathTextStyle;
  final bool focused;
  final bool dropHighlighted;
  final bool canGoUp;
  final VoidCallback onGoUp;
  final VoidCallback onRefresh;
  final VoidCallback onFocus;
  final bool loading;
  final String? error;
  final Menu Function() backgroundMenu;
  final bool Function(_FileDragData data) canAcceptDrop;
  final VoidCallback onDragEntered;
  final VoidCallback onDragExited;
  final Future<void> Function(_FileDragData data) onAcceptDrop;
  final Widget child;
  final Widget? pathInput;
  final Widget? searchInput;
  final Future<void> Function()? onCopyPath;
  final Future<void> Function()? onOpenTerminal;
  final Widget? aboveList;
  final String? clipboardHint;
  final void Function(PointerDownEvent event)? onPointerDown;
  final List<Widget> headerActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Listener(
      onPointerDown: onPointerDown,
      child: ContextMenuWidget(
        desktopMenuWidgetBuilder: maidKitDesktopMenuWidgetBuilder,
        menuProvider: (_) => backgroundMenu(),
        child: DragTarget<_FileDragData>(
          onWillAcceptWithDetails: (details) {
            if (!canAcceptDrop(details.data)) return false;
            onDragEntered();
            return true;
          },
          onLeave: (_) => onDragExited(),
          onAcceptWithDetails: (details) => onAcceptDrop(details.data),
          builder: (context, candidate, rejected) {
            final highlighted = dropHighlighted || candidate.isNotEmpty;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onFocus,
              child: ColoredBox(
                color: highlighted
                    ? scheme.primary.withValues(alpha: 0.08)
                    : Colors.transparent,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
                      child: SizedBox(
                        height: 32,
                        child: Row(
                          children: [
                            Text(
                              title,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: focused || highlighted
                                    ? scheme.primary
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child:
                                  pathInput ??
                                  Text(
                                    path,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: pathTextStyle,
                                  ),
                            ),
                            if (clipboardHint != null)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Text(
                                  clipboardHint!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.primary,
                                  ),
                                ),
                              ),
                            ...headerActions,
                            IconButton(
                              tooltip: 'fileManagerGoUp'.tr(),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              onPressed: canGoUp ? onGoUp : null,
                              icon: const Icon(Symbols.arrow_upward, size: 18),
                            ),
                            if (onCopyPath != null)
                              IconButton(
                                tooltip: 'Copy remote path',
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                onPressed: () => onCopyPath!(),
                                icon: const Icon(
                                  Symbols.content_copy,
                                  size: 18,
                                ),
                              ),
                            if (onOpenTerminal != null)
                              IconButton(
                                tooltip: 'Open terminal here',
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                onPressed: () => onOpenTerminal!(),
                                icon: const Icon(Symbols.terminal, size: 18),
                              ),
                            IconButton(
                              tooltip: 'commonRefresh'.tr(),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              onPressed: loading ? null : onRefresh,
                              icon: const Icon(Symbols.refresh, size: 18),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    ?searchInput,
                    ?aboveList,
                    Expanded(
                      child: loading
                          ? const Center(child: CircularProgressIndicator())
                          : error != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(error!),
                              ),
                            )
                          : child,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RemoteFileList extends StatelessWidget {
  const _RemoteFileList({
    required this.entries,
    required this.symbolicLinkPaths,
    required this.currentPath,
    required this.selectedPaths,
    required this.cutPaths,
    required this.onTapEntry,
    required this.onOpen,
    required this.onEdit,
    required this.dragDataFor,
    required this.onContextPrepare,
    required this.menuProvider,
    required this.expandHidden,
    required this.canGoUp,
    required this.onGoUp,
    this.scrollController,
    this.emptyMessage,
  });

  final List<SftpName> entries;
  final String currentPath;
  final Set<String> selectedPaths;
  final Set<String> cutPaths;
  final Set<String> symbolicLinkPaths;
  final String? emptyMessage;
  final ScrollController? scrollController;
  final bool canGoUp;
  final Future<void> Function() onGoUp;
  final void Function(SftpName entry, int index) onTapEntry;
  final ValueChanged<SftpName> onOpen;
  final ValueChanged<SftpName> onEdit;
  final _FileDragData Function(SftpName entry) dragDataFor;
  final void Function(SftpName entry, int index) onContextPrepare;
  final Menu Function(SftpName entry, int index) menuProvider;
  final bool expandHidden;

  @override
  Widget build(BuildContext context) {
    final goUpRow = canGoUp
        ? _ParentDirectoryRow(onGoUp: () => onGoUp())
        : null;
    if (entries.isEmpty) {
      return Column(
        children: [
          ?goUpRow,
          Expanded(
            child: _EmptyPane(message: emptyMessage ?? 'This folder is empty.'),
          ),
        ],
      );
    }

    final visibleIndices = <int>[];
    final hiddenIndices = <int>[];
    for (var index = 0; index < entries.length; index++) {
      (_isHiddenFileName(entries[index].filename)
              ? hiddenIndices
              : visibleIndices)
          .add(index);
    }

    Widget buildRow(int index) {
      final entry = entries[index];
      final isDirectory = entry.attr.isDirectory;
      final path = _joinRemotePath(currentPath, entry.filename);
      final selected = selectedPaths.contains(path);
      final dimmed = cutPaths.contains(path);
      final dragData = dragDataFor(entry);
      final isSymbolicLink = symbolicLinkPaths.contains(path);
      return ContextMenuWidget(
        desktopMenuWidgetBuilder: maidKitDesktopMenuWidgetBuilder,
        menuProvider: (_) {
          onContextPrepare(entry, index);
          return menuProvider(entry, index);
        },
        child: _DraggableFileRow(
          dragData: dragData,
          icon: _fileIcon(entry.filename, isDirectory: isDirectory),
          name: entry.filename,
          detail: _fileDetail(
            isDirectory: isDirectory,
            isSymbolicLink: isSymbolicLink,
            size: entry.attr.size,
          ),
          selected: selected,
          dimmed: dimmed,
          onTap: () => onTapEntry(entry, index),
          onDoubleTap: isDirectory ? () => onOpen(entry) : () => onEdit(entry),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      controller: scrollController,
      children: [
        ?goUpRow,
        for (final index in visibleIndices) buildRow(index),
        if (hiddenIndices.isNotEmpty)
          ExpansionTile(
            key: ValueKey('remote-hidden-$expandHidden'),
            initiallyExpanded: expandHidden,
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            dense: true,
            minTileHeight: _kFileRowExtent,
            shape: const Border(),
            collapsedShape: const Border(),
            childrenPadding: EdgeInsets.zero,
            title: Row(
              children: [
                Icon(
                  Symbols.visibility_off,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'fileManagerHiddenFiles'.tr(
                      args: [hiddenIndices.length.toString()],
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            children: [for (final index in hiddenIndices) buildRow(index)],
          ),
      ],
    );
  }
}

class _DraggableFileRow extends StatelessWidget {
  const _DraggableFileRow({
    required this.dragData,
    required this.icon,
    required this.name,
    required this.selected,
    required this.dimmed,
    required this.onTap,
    this.onDoubleTap,
    this.detail,
  });

  final _FileDragData dragData;
  final IconData icon;
  final String name;
  final String? detail;
  final bool selected;
  final bool dimmed;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 900;
    if (isMobile) {
      return _FileRow(
        icon: icon,
        name: name,
        detail: detail,
        selected: selected,
        dimmed: dimmed,
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        selectOnTapDown: false,
      );
    }
    final count = dragData.entries.length;
    final feedbackLabel = count == 1 ? name : '$count items';
    return Draggable<_FileDragData>(
      data: dragData,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(MaidKitRadius.sm),
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(feedbackLabel),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: _FileRow(
          icon: icon,
          name: name,
          detail: detail,
          selected: selected,
          dimmed: true,
          onTap: onTap,
          onDoubleTap: onDoubleTap,
        ),
      ),
      child: _FileRow(
        icon: icon,
        name: name,
        detail: detail,
        selected: selected,
        dimmed: dimmed,
        onTap: onTap,
        onDoubleTap: onDoubleTap,
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.icon,
    required this.name,
    required this.selected,
    required this.dimmed,
    required this.onTap,
    this.selectOnTapDown = true,
    this.onDoubleTap,
    this.detail,
  });

  final IconData icon;
  final String name;
  final String? detail;
  final bool selected;
  final bool dimmed;
  final VoidCallback onTap;
  final bool selectOnTapDown;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: selected
          ? scheme.secondaryContainer.withValues(alpha: 0.55)
          : Colors.transparent,
      child: InkWell(
        // Desktop file managers select on mouse-down. On narrow layouts that
        // would steal vertical drag gestures from the surrounding ListView.
        onTapDown: selectOnTapDown ? (_) => onTap() : null,
        onTap: selectOnTapDown ? null : onTap,
        onDoubleTap: onDoubleTap,
        child: Opacity(
          opacity: dimmed ? 0.45 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected
                      ? scheme.onSecondaryContainer
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: selected ? scheme.onSecondaryContainer : null,
                    ),
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    detail!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: selected
                          ? scheme.onSecondaryContainer.withValues(alpha: 0.8)
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ParentDirectoryRow extends StatelessWidget {
  const _ParentDirectoryRow({required this.onGoUp});

  final VoidCallback onGoUp;

  @override
  Widget build(BuildContext context) {
    // Uses selectOnTapDown: false so a double-click fires onDoubleTap
    // (and suppresses the single tap), navigating up exactly once instead of
    // on each mouse-down.
    return Tooltip(
      message: 'fileManagerGoUp'.tr(),
      child: _FileRow(
        icon: Symbols.folder,
        name: '..',
        selected: false,
        dimmed: false,
        selectOnTapDown: false,
        onTap: onGoUp,
        onDoubleTap: onGoUp,
      ),
    );
  }
}

class _EmptyPane extends StatelessWidget {
  const _EmptyPane({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

const _configFileExtensions = {
  '.conf',
  '.config',
  '.env',
  '.ini',
  '.json',
  '.lock',
  '.plist',
  '.properties',
  '.toml',
  '.xml',
  '.yaml',
  '.yml',
};

const _scriptFileExtensions = {
  '.app',
  '.appimage',
  '.bat',
  '.bin',
  '.c',
  '.cc',
  '.cmd',
  '.cpp',
  '.cs',
  '.dart',
  '.exe',
  '.fish',
  '.go',
  '.h',
  '.hpp',
  '.java',
  '.js',
  '.jsx',
  '.kt',
  '.mjs',
  '.php',
  '.pl',
  '.ps1',
  '.py',
  '.rb',
  '.rs',
  '.run',
  '.sh',
  '.swift',
  '.ts',
  '.tsx',
  '.zsh',
};

const _documentFileExtensions = {
  '.csv',
  '.doc',
  '.docx',
  '.log',
  '.md',
  '.odt',
  '.pdf',
  '.rtf',
  '.tex',
  '.text',
  '.txt',
  '.xls',
  '.xlsx',
};

const _archiveFileExtensions = {
  '.7z',
  '.bz2',
  '.gz',
  '.iso',
  '.rar',
  '.tar',
  '.tgz',
  '.xz',
  '.zip',
  '.zst',
};

const _imageFileExtensions = {
  '.avif',
  '.bmp',
  '.gif',
  '.heic',
  '.jpeg',
  '.jpg',
  '.png',
  '.svg',
  '.tif',
  '.tiff',
  '.webp',
};

const _videoFileExtensions = {
  '.avi',
  '.flv',
  '.m4v',
  '.mkv',
  '.mov',
  '.mp4',
  '.mpeg',
  '.webm',
  '.wmv',
};

const _audioFileExtensions = {'.aac', '.flac', '.m4a', '.mp3', '.ogg', '.wav'};

const _databaseFileExtensions = {'.db', '.sqlite', '.sqlite3', '.sql'};

String? _fileDetail({
  required bool isDirectory,
  required bool isSymbolicLink,
  int? size,
}) {
  final base = isDirectory
      ? 'fileManagerFolder'.tr()
      : size == null
      ? null
      : _formatBytes(size);
  if (!isSymbolicLink) return base;
  final linkHint = 'fileManagerSymbolicLink'.tr();
  return base == null ? linkHint : '$linkHint · $base';
}

IconData _fileIcon(String name, {required bool isDirectory}) {
  if (isDirectory) return Symbols.folder;

  final lowerName = name.toLowerCase();
  if (lowerName == 'dockerfile' || lowerName == 'makefile') {
    return Symbols.code;
  }
  if (_hasFileExtension(lowerName, _configFileExtensions)) {
    return Symbols.settings;
  }
  if (_hasFileExtension(lowerName, _scriptFileExtensions)) {
    return Symbols.code;
  }
  if (_hasFileExtension(lowerName, _databaseFileExtensions)) {
    return Symbols.database;
  }
  if (_hasFileExtension(lowerName, _archiveFileExtensions)) {
    return Symbols.archive;
  }
  if (_hasFileExtension(lowerName, _videoFileExtensions)) {
    return Symbols.video_file;
  }
  if (_hasFileExtension(lowerName, _imageFileExtensions)) {
    return Symbols.image;
  }
  if (_hasFileExtension(lowerName, _audioFileExtensions)) {
    return Symbols.audio_file;
  }
  if (_hasFileExtension(lowerName, _documentFileExtensions)) {
    return Symbols.article;
  }
  return Symbols.description;
}

bool _hasFileExtension(String name, Set<String> extensions) =>
    extensions.any(name.endsWith);

bool _isHiddenFileName(String name) => name.startsWith('.');

String _joinRemotePath(String directory, String name) =>
    directory == '/' ? '/$name' : '$directory/$name';

String _shellQuote(String value) => "'${value.replaceAll("'", "'\\\"'\\\"'")}'";

bool _isSupportedArchive(String filename) {
  final name = filename.toLowerCase();
  return name.endsWith('.zip') ||
      name.endsWith('.tar.gz') ||
      name.endsWith('.tgz');
}

String _parentRemotePath(String path) {
  if (path == '/' || path.isEmpty) return '/';
  final normalized = path.endsWith('/')
      ? path.substring(0, path.length - 1)
      : path;
  final index = normalized.lastIndexOf('/');
  if (index <= 0) return '/';
  return normalized.substring(0, index);
}

String _formatBytes(int? bytes) {
  if (bytes == null) return 'Unknown size';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
