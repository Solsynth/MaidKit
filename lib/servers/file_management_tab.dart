import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive_io.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:super_context_menu/super_context_menu.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/shared/presentation/maidkit_alert.dart';
import 'package:maid_kit/shared/presentation/task_progress.dart';
import 'package:maid_kit/theme.dart';
import 'file_editor_tab.dart';
import 'server_connection_actions.dart';
import 'server_models.dart';
import 'server_providers.dart';
import 'terminal_tabs_provider.dart';

enum _FileSide { local, remote }

enum _ClipboardMode { copy, cut }

enum _ArchiveFormat { zip, tarGzip }

/// Fixed row height of the file lists (matches `_FileRow`'s intrinsic
/// height) so keyboard navigation can scroll items into view precisely.
const double _kFileRowExtent = 44.0;

class _TransferCancelled implements Exception {
  const _TransferCancelled();
}

class _TransferController {
  var _isPaused = false;
  var _isCancelled = false;
  Completer<void>? _resumeCompleter;

  bool get isCancelled => _isCancelled;

  void pause() {
    if (_isCancelled || _isPaused) return;
    _isPaused = true;
    _resumeCompleter = Completer<void>();
  }

  void resume() {
    if (!_isPaused) return;
    _isPaused = false;
    final completer = _resumeCompleter;
    _resumeCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    resume();
  }

  Future<void> waitIfPaused() async {
    throwIfCancelled();
    final completer = _resumeCompleter;
    if (_isPaused && completer != null) {
      await completer.future;
    }
    throwIfCancelled();
  }

  void throwIfCancelled() {
    if (_isCancelled) throw const _TransferCancelled();
  }
}

class _QueuedTransfer {
  const _QueuedTransfer({
    required this.id,
    required this.title,
    required this.totalBytes,
    required this.controller,
    required this.notify,
    required this.action,
    this.onSuccess,
    this.onFinish,
  });

  final String id;
  final String title;
  final int? totalBytes;
  final _TransferController controller;
  final bool notify;
  final Future<void> Function(_TransferController, void Function(int)) action;
  final Future<void> Function()? onSuccess;
  final Future<void> Function()? onFinish;
}

class _ClipboardEntry {
  const _ClipboardEntry({
    required this.side,
    required this.path,
    required this.name,
    required this.isDirectory,
    this.serverId,
  });

  final _FileSide side;
  final String path;
  final String name;
  final bool isDirectory;

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
  late Directory _localDirectory;
  var _remotePath = '.';
  List<FileSystemEntity> _localEntries = const [];
  List<SftpName> _remoteEntries = const [];
  var _loadingLocal = true;
  var _loadingRemote = true;
  String? _localError;
  String? _remoteError;
  String? _workingPath;
  final Queue<_QueuedTransfer> _transferQueue = Queue<_QueuedTransfer>();
  var _processingTransferQueue = false;
  var _draggingFiles = false;
  _FileSide? _dropTargetSide;
  Future<SftpClient>? _sftpClient;
  Future<SftpClient>? _leftSftpClient;
  int? _leftServerId;
  var _leftRemotePath = '.';
  List<SftpName> _leftRemoteEntries = const [];
  var _loadingLeftRemote = false;
  String? _leftRemoteError;
  late final TextEditingController _leftRemotePathController;
  late final FocusNode _leftRemotePathFocusNode;
  late final TextEditingController _remotePathController;
  late final FocusNode _remotePathFocusNode;
  late final FocusNode _shortcutFocusNode;
  final ScrollController _localListController = ScrollController();
  final ScrollController _leftRemoteListController = ScrollController();
  final ScrollController _rightRemoteListController = ScrollController();

  Set<String> _selectedLocalPaths = {};
  Set<String> _selectedRemotePaths = {};
  int? _localAnchorIndex;
  int? _remoteAnchorIndex;
  _FileSide? _focusedSide;
  _FileClipboard? _clipboard;
  var _localCollapsed = false;
  var _leftSearchOpen = false;
  var _rightSearchOpen = false;
  late final TextEditingController _leftSearchController;
  late final TextEditingController _rightSearchController;
  late final FocusNode _leftSearchFocusNode;
  late final FocusNode _rightSearchFocusNode;

  /// Phone-width layouts always keep the local pane visible (no collapse).
  static const _mobileLocalBreakpoint = 900.0;

  bool get _isMobileLayout {
    final width = MediaQuery.sizeOf(context).width;
    return width < _mobileLocalBreakpoint;
  }

  List<FileSystemEntity> get _displayedLocalEntries {
    final query = _leftSearchController.text.trim().toLowerCase();
    if (query.isEmpty) return _localEntries;
    return [
      for (final entry in _localEntries)
        if (_entityName(entry).toLowerCase().contains(query)) entry,
    ];
  }

  List<SftpName> get _displayedLeftRemoteEntries {
    final query = _leftSearchController.text.trim().toLowerCase();
    if (query.isEmpty) return _leftRemoteEntries;
    return [
      for (final entry in _leftRemoteEntries)
        if (entry.filename.toLowerCase().contains(query)) entry,
    ];
  }

  List<SftpName> get _displayedRemoteEntries {
    final query = _rightSearchController.text.trim().toLowerCase();
    if (query.isEmpty) return _remoteEntries;
    return [
      for (final entry in _remoteEntries)
        if (entry.filename.toLowerCase().contains(query)) entry,
    ];
  }

  @override
  void initState() {
    super.initState();
    _localDirectory = Directory.current;
    _remotePath = widget.tab.initialPath ?? '.';
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
    _refreshLocal();
    _refreshRemote();
  }

  bool get _leftIsRemote => _leftServerId != null;

  /// Whether this tab manages the machine MaidKit runs on. The local machine
  /// has no SFTP side, so the right pane is informational and the local pane
  /// is the only filesystem browser.
  bool get _isLocalMachine {
    final servers = ref.read(serversProvider).asData?.value ?? const [];
    final server = servers
        .where((item) => item.id == widget.tab.serverId)
        .firstOrNull;
    return server?.connectionType == ServerConnectionType.local.name;
  }

  Future<SftpClient> _leftSftp() {
    final serverId = _leftServerId;
    if (serverId == null) {
      throw StateError('Choose a server for the left pane.');
    }
    return _leftSftpClient ??= ref
        .read(connectionManagerProvider)
        .withClient(serverId, (client) => client.sftp());
  }

  Future<void> _refreshLeftRemote() async {
    if (!_leftIsRemote) return;
    setState(() {
      _loadingLeftRemote = true;
      _leftRemoteError = null;
    });
    try {
      final sftp = await _leftSftp();
      final absolutePath = await sftp.absolute(_leftRemotePath);
      final entries = await sftp.listdir(absolutePath);
      entries.removeWhere(
        (entry) => entry.filename == '.' || entry.filename == '..',
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
          _selectedLocalPaths = _selectedLocalPaths
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
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, -1),
            child: Text('fileManagerUseLocalFiles'.tr()),
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
      final previous = _leftSftpClient;
      setState(() {
        _leftServerId = null;
        _leftSftpClient = null;
        _selectedLocalPaths = {};
      });
      _closeSftp(previous);
      await _refreshLocal();
      return;
    }
    final server = servers.firstWhere((item) => item.id == selectedServerId);
    final connected = await connectForStatistics(context, ref, server);
    if (!connected || !mounted) return;
    final previous = _leftSftpClient;
    setState(() {
      _leftServerId = server.id;
      _leftSftpClient = null;
      _leftRemotePath = '.';
      _leftRemotePathController.text = _leftRemotePath;
      _leftRemoteEntries = const [];
      _selectedLocalPaths = {};
      _localAnchorIndex = null;
    });
    _closeSftp(previous);
    await _refreshLeftRemote();
  }

  @override
  void dispose() {
    for (final transfer in _transferQueue) {
      transfer.controller.cancel();
    }
    _transferQueue.clear();
    // Close the SFTP channels so opening/closing many file-management tabs does
    // not leak one SSH channel per tab (and per left-pane server) until the
    // whole session disconnects.
    _closeSftp(_sftpClient);
    _closeSftp(_leftSftpClient);
    _sftpClient = null;
    _leftSftpClient = null;
    _leftRemotePathController.dispose();
    _leftRemotePathFocusNode.dispose();
    _remotePathController.dispose();
    _remotePathFocusNode.dispose();
    _shortcutFocusNode.dispose();
    _localListController.dispose();
    _leftRemoteListController.dispose();
    _rightRemoteListController.dispose();
    _leftSearchController.dispose();
    _rightSearchController.dispose();
    _leftSearchFocusNode.dispose();
    _rightSearchFocusNode.dispose();
    super.dispose();
  }

  /// Closes a cached SFTP channel once its [Future] resolves, ignoring the
  /// close races that happen when the underlying session is already gone.
  void _closeSftp(Future<SftpClient>? pending) {
    if (pending == null) return;
    unawaited(
      pending.then((client) {
        try {
          client.close();
        } catch (_) {}
      }),
    );
  }

  Future<void> _refreshLocal() async {
    setState(() {
      _loadingLocal = true;
      _localError = null;
    });
    try {
      final entries = await _localDirectory.list().toList();
      entries.sort((a, b) {
        final directoryOrder =
            ((b is Directory) ? 1 : 0) - ((a is Directory) ? 1 : 0);
        return directoryOrder != 0
            ? directoryOrder
            : _entityName(
                a,
              ).toLowerCase().compareTo(_entityName(b).toLowerCase());
      });
      if (mounted) {
        final paths = entries.map((entry) => entry.path).toSet();
        setState(() {
          _localEntries = entries;
          _selectedLocalPaths = _selectedLocalPaths
              .where(paths.contains)
              .toSet();
        });
      }
    } catch (error) {
      if (mounted) setState(() => _localError = error.toString());
    } finally {
      if (mounted) setState(() => _loadingLocal = false);
    }
  }

  Future<void> _refreshRemote() async {
    // The local machine has no SFTP side; keep the right pane idle instead
    // of surfacing a connection error.
    if (_isLocalMachine) {
      setState(() {
        _loadingRemote = false;
        _remoteError = null;
      });
      return;
    }
    setState(() {
      _loadingRemote = true;
      _remoteError = null;
    });
    try {
      final sftp = await _sftp();
      final absolutePath = await sftp.absolute(_remotePath);
      final entries = await sftp.listdir(absolutePath);
      entries.removeWhere(
        (entry) => entry.filename == '.' || entry.filename == '..',
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

  Future<void> _chooseLocalDirectory() async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose local folder',
      initialDirectory: _localDirectory.path,
    );
    if (path == null || !mounted) return;
    setState(() {
      _localDirectory = Directory(path);
      _selectedLocalPaths = {};
      _localAnchorIndex = null;
      _focusedSide = _FileSide.local;
    });
    await _refreshLocal();
  }

  Future<void> _openLocal(FileSystemEntity entry) async {
    if (entry is! Directory) return;
    setState(() {
      _localDirectory = entry;
      _selectedLocalPaths = {};
      _localAnchorIndex = null;
      _focusedSide = _FileSide.local;
    });
    await _refreshLocal();
  }

  Future<void> _openRemote(SftpName entry) async {
    if (!entry.attr.isDirectory) return;
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
    setState(() {
      _leftRemotePath = destination;
      _selectedLocalPaths = {};
      _localAnchorIndex = null;
      _focusedSide = _FileSide.local;
    });
    _leftRemotePathFocusNode.unfocus();
    await _refreshLeftRemote();
  }

  Future<void> _goUpLocal() async {
    final parent = _localDirectory.parent;
    if (parent.path == _localDirectory.path) return;
    setState(() {
      _localDirectory = parent;
      _selectedLocalPaths = {};
      _localAnchorIndex = null;
      _focusedSide = _FileSide.local;
    });
    await _refreshLocal();
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
    if (server.connectionType == ServerConnectionType.local.name) {
      await openLocalTerminalSession(
        context,
        ref,
        server,
        initialDirectory: _localDirectory.path,
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

  void _selectLocal(
    FileSystemEntity entry, {
    required int index,
    bool toggle = false,
    bool range = false,
  }) {
    _requestShortcutFocus();
    setState(() {
      _focusedSide = _FileSide.local;
      _selectedRemotePaths = {};
      _remoteAnchorIndex = null;
      if (range && _localAnchorIndex != null) {
        final start = math.min(_localAnchorIndex!, index);
        final end = math.max(_localAnchorIndex!, index);
        if (_leftIsRemote) {
          final displayed = _displayedLeftRemoteEntries;
          _selectedLocalPaths = {
            for (var i = start; i <= end && i < displayed.length; i++)
              _joinRemotePath(_leftRemotePath, displayed[i].filename),
          };
        } else {
          final displayed = _displayedLocalEntries;
          _selectedLocalPaths = {
            for (var i = start; i <= end && i < displayed.length; i++)
              displayed[i].path,
          };
        }
      } else if (toggle) {
        final next = {..._selectedLocalPaths};
        if (!next.add(entry.path)) next.remove(entry.path);
        _selectedLocalPaths = next;
        _localAnchorIndex = index;
      } else {
        _selectedLocalPaths = {entry.path};
        _localAnchorIndex = index;
      }
    });
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
      _selectedLocalPaths = {};
      _localAnchorIndex = null;
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

  void _selectLeftRemote(
    SftpName entry, {
    required int index,
    bool toggle = false,
    bool range = false,
  }) {
    _requestShortcutFocus();
    final path = _joinRemotePath(_leftRemotePath, entry.filename);
    setState(() {
      _focusedSide = _FileSide.local;
      _selectedRemotePaths = {};
      _remoteAnchorIndex = null;
      if (range && _localAnchorIndex != null) {
        final start = math.min(_localAnchorIndex!, index);
        final end = math.max(_localAnchorIndex!, index);
        final displayed = _displayedLeftRemoteEntries;
        _selectedLocalPaths = {
          for (var i = start; i <= end && i < displayed.length; i++)
            _joinRemotePath(_leftRemotePath, displayed[i].filename),
        };
      } else if (toggle) {
        final next = {..._selectedLocalPaths};
        if (!next.add(path)) next.remove(path);
        _selectedLocalPaths = next;
        _localAnchorIndex = index;
      } else {
        _selectedLocalPaths = {path};
        _localAnchorIndex = index;
      }
    });
  }

  void _ensureLeftRemoteContextSelection(SftpName entry, int index) {
    final path = _joinRemotePath(_leftRemotePath, entry.filename);
    if (_selectedLocalPaths.contains(path)) {
      setState(() {
        _focusedSide = _FileSide.local;
        _selectedRemotePaths = {};
      });
      return;
    }
    _selectLeftRemote(entry, index: index);
  }

  void _ensureLocalContextSelection(FileSystemEntity entry, int index) {
    if (_selectedLocalPaths.contains(entry.path)) {
      setState(() {
        _focusedSide = _FileSide.local;
        _selectedRemotePaths = {};
      });
      return;
    }
    _selectLocal(entry, index: index);
  }

  void _ensureRemoteContextSelection(SftpName entry, int index) {
    final path = _joinRemotePath(_remotePath, entry.filename);
    if (_selectedRemotePaths.contains(path)) {
      setState(() {
        _focusedSide = _FileSide.remote;
        _selectedLocalPaths = {};
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
    final isLocal = side == _FileSide.local;
    final opening = !(isLocal ? _leftSearchOpen : _rightSearchOpen);
    setState(() {
      if (isLocal) {
        _leftSearchOpen = opening;
        if (!opening) _leftSearchController.clear();
        _localAnchorIndex = null;
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
    final isLocal = side == _FileSide.local;
    setState(() {
      if (isLocal) {
        _leftSearchOpen = true;
        _localAnchorIndex = null;
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
    final isLocal = side == _FileSide.local;
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
              _localAnchorIndex = null;
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
    final isLocal = side == _FileSide.local;
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
      if (side == _FileSide.local) {
        if (_leftIsRemote) {
          final displayed = _displayedLeftRemoteEntries;
          _selectedLocalPaths = {
            for (final entry in displayed)
              _joinRemotePath(_leftRemotePath, entry.filename),
          };
          _localAnchorIndex = displayed.isEmpty ? null : 0;
        } else {
          final displayed = _displayedLocalEntries;
          _selectedLocalPaths = {for (final entry in displayed) entry.path};
          _localAnchorIndex = displayed.isEmpty ? null : 0;
        }
        _selectedRemotePaths = {};
      } else {
        final displayed = _displayedRemoteEntries;
        _selectedRemotePaths = {
          for (final entry in displayed)
            _joinRemotePath(_remotePath, entry.filename),
        };
        _selectedLocalPaths = {};
        _remoteAnchorIndex = displayed.isEmpty ? null : 0;
      }
    });
  }

  List<_ClipboardEntry> _entriesForSelection(_FileSide side) {
    if (side == _FileSide.local) {
      if (_leftIsRemote) {
        return [
          for (final entry in _leftRemoteEntries)
            if (_selectedLocalPaths.contains(
              _joinRemotePath(_leftRemotePath, entry.filename),
            ))
              _ClipboardEntry(
                side: _FileSide.local,
                serverId: _leftServerId,
                path: _joinRemotePath(_leftRemotePath, entry.filename),
                name: entry.filename,
                isDirectory: entry.attr.isDirectory,
              ),
        ];
      }
      return [
        for (final entity in _localEntries)
          if (_selectedLocalPaths.contains(entity.path))
            _ClipboardEntry(
              side: _FileSide.local,
              path: entity.path,
              name: _entityName(entity),
              isDirectory: entity is Directory,
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
          ),
    ];
  }

  _ClipboardEntry _clipboardEntryForLocal(FileSystemEntity entity) =>
      _ClipboardEntry(
        side: _FileSide.local,
        path: entity.path,
        name: _entityName(entity),
        isDirectory: entity is Directory,
      );

  _ClipboardEntry _clipboardEntryForLeftRemote(SftpName entry) =>
      _ClipboardEntry(
        side: _FileSide.local,
        serverId: _leftServerId,
        path: _joinRemotePath(_leftRemotePath, entry.filename),
        name: entry.filename,
        isDirectory: entry.attr.isDirectory,
      );

  _ClipboardEntry _clipboardEntryForRemote(SftpName entry) => _ClipboardEntry(
    side: _FileSide.remote,
    path: _joinRemotePath(_remotePath, entry.filename),
    name: entry.filename,
    isDirectory: entry.attr.isDirectory,
  );

  _FileDragData _dragDataForLocal(FileSystemEntity entry) {
    final selected = _selectedLocalPaths.contains(entry.path)
        ? _entriesForSelection(_FileSide.local)
        : [_clipboardEntryForLocal(entry)];
    return _FileDragData(side: _FileSide.local, entries: selected);
  }

  _FileDragData _dragDataForLeftRemote(SftpName entry) {
    final path = _joinRemotePath(_leftRemotePath, entry.filename);
    final selected = _selectedLocalPaths.contains(path)
        ? _entriesForSelection(_FileSide.local)
        : [_clipboardEntryForLeftRemote(entry)];
    return _FileDragData(side: _FileSide.local, entries: selected);
  }

  _FileDragData _dragDataForRemote(SftpName entry) {
    final path = _joinRemotePath(_remotePath, entry.filename);
    final selected = _selectedRemotePaths.contains(path)
        ? _entriesForSelection(_FileSide.remote)
        : [_clipboardEntryForRemote(entry)];
    return _FileDragData(side: _FileSide.remote, entries: selected);
  }

  Future<void> _renameEntry(_ClipboardEntry entry) async {
    if (_workingPath != null) return;
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
      if (entry.side == _FileSide.local && entry.serverId == null) {
        final destination =
            '${File(entry.path).parent.path}${Platform.pathSeparator}$name';
        if (entry.isDirectory) {
          await Directory(entry.path).rename(destination);
        } else {
          await File(entry.path).rename(destination);
        }
        await _refreshLocal();
      } else {
        final sftp = entry.serverId == null ? await _sftp() : await _leftSftp();
        final destination = _joinRemotePath(
          _parentRemotePath(entry.path),
          name,
        );
        await sftp.rename(entry.path, destination);
        if (entry.serverId == null) {
          await _refreshRemote();
        } else {
          await _refreshLeftRemote();
        }
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
    if (_workingPath != null) return;
    final name = await _showFileNameSheet(
      context,
      title: 'fileManagerCreateFolder'.tr(),
      label: 'fileManagerFolderName'.tr(),
      actionLabel: 'fileManagerCreate'.tr(),
    );
    if (name == null || !mounted) return;

    setState(() => _workingPath = name);
    try {
      if (side == _FileSide.local && !_leftIsRemote) {
        await Directory(
          '${_localDirectory.path}${Platform.pathSeparator}$name',
        ).create();
        await _refreshLocal();
      } else {
        final isLeftRemote = side == _FileSide.local;
        final sftp = isLeftRemote ? await _leftSftp() : await _sftp();
        final directory = isLeftRemote ? _leftRemotePath : _remotePath;
        await sftp.mkdir(_joinRemotePath(directory, name));
        if (isLeftRemote) {
          await _refreshLeftRemote();
        } else {
          await _refreshRemote();
        }
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
        if (_leftIsRemote) {
          await _transferBetweenServers(
            entry,
            sourceServerId: entry.serverId ?? widget.tab.serverId,
            targetServerId: targetSide == _FileSide.local
                ? _leftServerId!
                : widget.tab.serverId,
            targetDirectory: targetSide == _FileSide.local
                ? _leftRemotePath
                : _remotePath,
            notify: false,
          );
          continue;
        }
        if (entry.side == _FileSide.local && targetSide == _FileSide.remote) {
          await _transferLocalToRemote(entry, notify: false);
        } else if (entry.side == _FileSide.remote &&
            targetSide == _FileSide.local) {
          await _transferRemoteToLocal(entry, notify: false);
        }
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
    final isLeftRemoteEntry =
        entry.side == _FileSide.local && entry.serverId != null;
    final isLeftRemoteTarget = _leftIsRemote && targetSide == _FileSide.local;

    // Same-side copy/cut on the left remote pane (SFTP rename/copy).
    if (isLeftRemoteEntry &&
        isLeftRemoteTarget &&
        entry.serverId == leftServerId) {
      if (mode == _ClipboardMode.cut) {
        await _moveSameSide(entry, _FileSide.local);
      } else {
        await _copySameSide(entry, _FileSide.local);
      }
      return;
    }

    // Left remote <-> right remote transfers.
    if (_leftIsRemote &&
        (isLeftRemoteEntry ||
            entry.side == _FileSide.remote ||
            isLeftRemoteTarget)) {
      final targetServerId = targetSide == _FileSide.local
          ? leftServerId!
          : widget.tab.serverId;
      await _transferBetweenServers(
        entry,
        sourceServerId: entry.serverId ?? widget.tab.serverId,
        targetServerId: targetServerId,
        targetDirectory: targetSide == _FileSide.local
            ? _leftRemotePath
            : _remotePath,
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
    if (entry.side == targetSide && mode == _ClipboardMode.cut) {
      await _moveSameSide(entry, targetSide);
      return;
    }
    if (entry.side == targetSide && mode == _ClipboardMode.copy) {
      await _copySameSide(entry, targetSide);
      return;
    }
    if (entry.side == _FileSide.local && targetSide == _FileSide.remote) {
      if (mode == _ClipboardMode.cut) {
        await _transferLocalToRemote(
          entry,
          notify: false,
          onSuccess: () => _deleteEntry(entry, confirm: false, notify: false),
        );
      } else {
        await _transferLocalToRemote(entry, notify: false);
      }
      return;
    }
    if (entry.side == _FileSide.remote && targetSide == _FileSide.local) {
      if (mode == _ClipboardMode.cut) {
        await _transferRemoteToLocal(
          entry,
          notify: false,
          onSuccess: () => _deleteEntry(entry, confirm: false, notify: false),
        );
      } else {
        await _transferRemoteToLocal(entry, notify: false);
      }
    }
  }

  bool _canPasteInto(_FileSide targetSide) {
    final clipboard = _clipboard;
    if (clipboard == null || clipboard.isEmpty) return false;
    final transferPaste = clipboard.entries.any(
      (entry) => entry.side != targetSide,
    );
    return transferPaste || _workingPath == null;
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
    final source = await _sftpForServer(sourceServerId);
    final size = entry.isDirectory
        ? null
        : (await source.stat(entry.path)).size;
    await _runTransfer(
      title: 'fileManagerTransferring'.tr(args: [entry.name]),
      totalBytes: size,
      notify: notify,
      action: (controller, reportProgress) async {
        final destination = await _sftpForServer(targetServerId);
        final target = await _uniqueRemotePath(
          destination,
          targetDirectory,
          entry.name,
        );
        try {
          if (entry.isDirectory) {
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

  Future<SftpClient> _sftpForServer(int serverId) =>
      serverId == widget.tab.serverId
      ? _sftp()
      : serverId == _leftServerId
      ? _leftSftp()
      : ref
            .read(connectionManagerProvider)
            .withClient(serverId, (client) => client.sftp());

  Future<void> _streamRemoteFile(
    SftpClient source,
    SftpClient destination,
    String sourcePath,
    String targetPath,
    _TransferController controller,
    void Function(int) reportProgress, {
    int transferredBytes = 0,
  }) async {
    final input = await source.open(sourcePath, mode: SftpFileOpenMode.read);
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
      await input.close();
      await output.close();
    }
  }

  Future<int> _streamRemoteDirectory(
    SftpClient source,
    SftpClient destination,
    String sourcePath,
    String targetPath,
    _TransferController controller,
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
    final sftp = await _sftpForServer(serverId);
    if (entry.isDirectory) {
      await _deleteRemoteDirectory(sftp, entry.path);
    } else {
      await sftp.remove(entry.path);
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
    final sftp = await _sftpForServer(serverId);
    final extension = format == _ArchiveFormat.zip ? '.zip' : '.tar.gz';
    final archivePath = await _uniqueRemotePath(
      sftp,
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

  Future<void> _runRemoteUtility({
    required int serverId,
    required String title,
    required String command,
  }) async {
    if (_workingPath != null) return;
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
    if (side == _FileSide.local) {
      // Left pane can be either the local filesystem or another remote.
      if (_leftIsRemote && entry.serverId != null) {
        final destinationDir = _leftRemotePath;
        if (_parentRemotePath(entry.path) == destinationDir) return;
        final sftp = await _leftSftp();
        final destination = await _uniqueRemotePath(
          sftp,
          destinationDir,
          entry.name,
        );
        await sftp.rename(entry.path, destination);
        await _refreshLeftRemote();
        return;
      }
      final destinationDir = _localDirectory.path;
      if (File(entry.path).parent.path == destinationDir ||
          Directory(entry.path).parent.path == destinationDir) {
        return;
      }
      final destination = await _uniqueLocalPath(destinationDir, entry.name);
      if (entry.isDirectory) {
        await Directory(entry.path).rename(destination);
      } else {
        await File(entry.path).rename(destination);
      }
      await _refreshLocal();
      return;
    }

    final destinationDir = _remotePath;
    if (_parentRemotePath(entry.path) == destinationDir) return;
    final sftp = await _sftp();
    final destination = await _uniqueRemotePath(
      sftp,
      destinationDir,
      entry.name,
    );
    await sftp.rename(entry.path, destination);
    await _refreshRemote();
  }

  Future<void> _copySameSide(_ClipboardEntry entry, _FileSide side) async {
    if (side == _FileSide.local) {
      if (_leftIsRemote && entry.serverId != null) {
        final sftp = await _leftSftp();
        final destination = await _uniqueRemotePath(
          sftp,
          _leftRemotePath,
          entry.name,
        );
        if (entry.isDirectory) {
          await _copyRemoteDirectory(sftp, entry.path, destination);
        } else {
          await _copyRemoteFile(sftp, entry.path, destination);
        }
        await _refreshLeftRemote();
        return;
      }
      final destination = await _uniqueLocalPath(
        _localDirectory.path,
        entry.name,
      );
      if (entry.isDirectory) {
        await _copyLocalDirectory(
          Directory(entry.path),
          Directory(destination),
        );
      } else {
        await File(entry.path).copy(destination);
      }
      await _refreshLocal();
      return;
    }

    final sftp = await _sftp();
    final destination = await _uniqueRemotePath(sftp, _remotePath, entry.name);
    if (entry.isDirectory) {
      await _copyRemoteDirectory(sftp, entry.path, destination);
    } else {
      await _copyRemoteFile(sftp, entry.path, destination);
    }
    await _refreshRemote();
  }

  Future<void> _transferLocalToRemote(
    _ClipboardEntry entry, {
    bool notify = true,
    Future<void> Function()? onSuccess,
  }) async {
    if (entry.isDirectory) {
      await _uploadDirectory(
        Directory(entry.path),
        entry.name,
        notify: notify,
        onSuccess: onSuccess,
      );
    } else {
      await _upload(File(entry.path), notify: notify, onSuccess: onSuccess);
    }
  }

  Future<void> _transferRemoteToLocal(
    _ClipboardEntry entry, {
    bool notify = true,
    Future<void> Function()? onSuccess,
  }) async {
    if (_isMobileLayout) {
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
      return;
    }
    if (entry.isDirectory) {
      await _downloadDirectory(
        entry.path,
        entry.name,
        notify: notify,
        onSuccess: onSuccess,
      );
    } else {
      final sftpName = _remoteEntries
          .where((item) => item.filename == entry.name)
          .firstOrNull;
      if (sftpName != null) {
        await _download(sftpName, notify: notify, onSuccess: onSuccess);
      } else {
        await _downloadPath(
          entry.path,
          entry.name,
          null,
          notify: notify,
          onSuccess: onSuccess,
        );
      }
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
      final deletedLocal = <String>{};
      final deletedRemote = <String>{};
      final deletedLeftRemote = <String>{};
      for (final entry in entries) {
        if (entry.side == _FileSide.local) {
          if (entry.serverId != null) {
            final sftp = await _sftpForServer(entry.serverId!);
            if (entry.isDirectory) {
              await _deleteRemoteDirectory(sftp, entry.path);
            } else {
              await sftp.remove(entry.path);
            }
            deletedLeftRemote.add(entry.path);
          } else {
            if (entry.isDirectory) {
              await Directory(entry.path).delete(recursive: true);
            } else {
              await File(entry.path).delete();
            }
            deletedLocal.add(entry.path);
          }
        } else {
          final sftp = await _sftp();
          if (entry.isDirectory) {
            await _deleteRemoteDirectory(sftp, entry.path);
          } else {
            await sftp.remove(entry.path);
          }
          deletedRemote.add(entry.path);
        }
      }
      if (deletedLocal.isNotEmpty) {
        setState(() {
          _selectedLocalPaths = _selectedLocalPaths
              .difference(deletedLocal)
              .toSet();
        });
        await _refreshLocal();
      }
      if (deletedRemote.isNotEmpty) {
        setState(() {
          _selectedRemotePaths = _selectedRemotePaths
              .difference(deletedRemote)
              .toSet();
        });
        await _refreshRemote();
      }
      if (deletedLeftRemote.isNotEmpty) {
        setState(() {
          _selectedLocalPaths = _selectedLocalPaths
              .difference(deletedLeftRemote)
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

  Future<void> _deleteEntry(
    _ClipboardEntry entry, {
    required bool confirm,
    bool notify = true,
  }) => _deleteEntries([entry], confirm: confirm, notify: notify);

  Future<void> _upload(
    FileSystemEntity entry, {
    bool notify = true,
    Future<void> Function()? onSuccess,
    Future<void> Function()? onFinish,
  }) async {
    if (entry is! File) return;
    final totalBytes = await entry.length();
    await _runTransfer(
      title: 'fileManagerUploading'.tr(args: [_entityName(entry)]),
      totalBytes: totalBytes,
      notify: notify,
      action: (controller, reportProgress) async {
        final sftp = await _sftp();
        final remotePath = await _uniqueRemotePath(
          sftp,
          _remotePath,
          _entityName(entry),
        );
        final remoteFile = await sftp.open(
          remotePath,
          mode:
              SftpFileOpenMode.write |
              SftpFileOpenMode.create |
              SftpFileOpenMode.truncate,
        );
        try {
          var transferredBytes = 0;
          await for (final chunk in entry.openRead().map(Uint8List.fromList)) {
            await controller.waitIfPaused();
            await remoteFile.writeBytes(chunk, offset: transferredBytes);
            transferredBytes += chunk.length;
            reportProgress(transferredBytes);
          }
        } finally {
          await remoteFile.close();
          if (controller.isCancelled) {
            try {
              await sftp.remove(remotePath);
            } catch (_) {}
          }
        }
        await _refreshRemote();
      },
      onSuccess: onSuccess,
      onFinish: onFinish,
    );
  }

  Future<void> _uploadDirectory(
    Directory directory,
    String name, {
    bool notify = true,
    Future<void> Function()? onSuccess,
    Future<void> Function()? onFinish,
  }) async {
    await _runTransfer(
      title: 'fileManagerUploading'.tr(args: [name]),
      totalBytes: null,
      notify: notify,
      action: (controller, reportProgress) async {
        final sftp = await _sftp();
        final remoteRoot = await _uniqueRemotePath(sftp, _remotePath, name);
        try {
          await _uploadLocalDirectory(
            sftp,
            directory,
            remoteRoot,
            controller: controller,
            reportProgress: reportProgress,
          );
        } finally {
          if (controller.isCancelled) {
            try {
              await _deleteRemoteDirectory(sftp, remoteRoot);
            } catch (_) {}
          }
        }
        await _refreshRemote();
      },
      onSuccess: onSuccess,
      onFinish: onFinish,
    );
  }

  Future<int> _uploadLocalDirectory(
    SftpClient sftp,
    Directory local,
    String remotePath, {
    _TransferController? controller,
    void Function(int)? reportProgress,
    int transferredBytes = 0,
  }) async {
    await controller?.waitIfPaused();
    await sftp.mkdir(remotePath);
    await for (final entity in local.list(followLinks: false)) {
      await controller?.waitIfPaused();
      final name = _entityName(entity);
      final childRemote = _joinRemotePath(remotePath, name);
      if (entity is Directory) {
        transferredBytes = await _uploadLocalDirectory(
          sftp,
          entity,
          childRemote,
          controller: controller,
          reportProgress: reportProgress,
          transferredBytes: transferredBytes,
        );
      } else if (entity is File) {
        final remoteFile = await sftp.open(
          childRemote,
          mode:
              SftpFileOpenMode.write |
              SftpFileOpenMode.create |
              SftpFileOpenMode.truncate,
        );
        try {
          var fileOffset = 0;
          await for (final chunk in entity.openRead().map(Uint8List.fromList)) {
            await controller?.waitIfPaused();
            await remoteFile.writeBytes(chunk, offset: fileOffset);
            fileOffset += chunk.length;
            transferredBytes += chunk.length;
            reportProgress?.call(transferredBytes);
          }
        } finally {
          await remoteFile.close();
        }
      }
    }
    return transferredBytes;
  }

  Future<void> _uploadDroppedFiles(List<DropItem> items) async {
    for (final item in items.whereType<DropItemFile>()) {
      final bookmark = item.extraAppleBookmark;
      final hasSecurityScopedAccess =
          bookmark != null &&
          await DesktopDrop.instance.startAccessingSecurityScopedResource(
            bookmark: bookmark,
          );
      await _upload(
        File(item.path),
        onFinish: hasSecurityScopedAccess
            ? () => DesktopDrop.instance.stopAccessingSecurityScopedResource(
                bookmark: bookmark,
              )
            : null,
      );
    }
  }

  Future<void> _download(
    SftpName entry, {
    bool notify = true,
    Future<void> Function()? onSuccess,
    Future<void> Function()? onFinish,
  }) async {
    if (!entry.attr.isFile) return;
    await _downloadPath(
      _joinRemotePath(_remotePath, entry.filename),
      entry.filename,
      entry.attr.size,
      notify: notify,
      onSuccess: onSuccess,
      onFinish: onFinish,
    );
  }

  Future<void> _downloadPath(
    String remotePath,
    String filename,
    int? totalBytes, {
    bool notify = true,
    Future<void> Function()? onSuccess,
    Future<void> Function()? onFinish,
  }) async {
    await _runTransfer(
      title: 'fileManagerDownloading'.tr(args: [filename]),
      totalBytes: totalBytes,
      notify: notify,
      action: (controller, reportProgress) async {
        final sftp = await _sftp();
        final destinationPath = await _uniqueLocalPath(
          _localDirectory.path,
          filename,
        );
        final destination = File(destinationPath);
        final remoteFile = await sftp.open(
          remotePath,
          mode: SftpFileOpenMode.read,
        );
        final sink = destination.openWrite();
        var transferredBytes = 0;
        try {
          await for (final chunk in remoteFile.read(
            length: totalBytes,
            chunkSize: 64 * 1024,
            maxPendingRequests: 4,
          )) {
            await controller.waitIfPaused();
            sink.add(chunk);
            transferredBytes += chunk.length;
            reportProgress(transferredBytes);
            if (transferredBytes % (1024 * 1024) < chunk.length) {
              await sink.flush();
            }
          }
        } finally {
          await sink.close();
          await remoteFile.close();
          if (controller.isCancelled) {
            try {
              await destination.delete();
            } catch (_) {}
          }
        }
        await _refreshLocal();
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
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'maidkit-download-',
    );
    final temporaryFile = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}$filename',
    );
    await _runTransfer(
      title: 'fileManagerDownloading'.tr(args: [filename]),
      totalBytes: null,
      notify: notify,
      action: (controller, reportProgress) async {
        final sftp = await _sftp();
        final remoteFile = await sftp.open(
          remotePath,
          mode: SftpFileOpenMode.read,
        );
        final sink = temporaryFile.openWrite();
        var transferredBytes = 0;
        try {
          await for (final chunk in remoteFile.read(
            chunkSize: 64 * 1024,
            maxPendingRequests: 4,
          )) {
            await controller.waitIfPaused();
            sink.add(chunk);
            transferredBytes += chunk.length;
            reportProgress(transferredBytes);
            if (transferredBytes % (1024 * 1024) < chunk.length) {
              await sink.flush();
            }
          }
        } finally {
          await sink.close();
          await remoteFile.close();
        }
        controller.throwIfCancelled();
        await FileSaver.instance.saveAs(
          name: filename,
          filePath: temporaryFile.path,
          includeExtension: false,
          mimeType: MimeType.other,
        );
      },
      onSuccess: onSuccess,
      onFinish: () async {
        try {
          await temporaryDirectory.delete(recursive: true);
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
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'maidkit-download-',
    );
    final stagedDirectory = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}$name',
    );
    final archiveFile = File('${temporaryDirectory.path}/$name.zip');
    await _runTransfer(
      title: 'fileManagerDownloading'.tr(args: [name]),
      totalBytes: null,
      notify: notify,
      action: (controller, reportProgress) async {
        final sftp = await _sftp();
        await _downloadRemoteDirectory(
          sftp,
          remotePath,
          stagedDirectory,
          controller: controller,
          reportProgress: reportProgress,
        );
        controller.throwIfCancelled();
        await ZipFileEncoder().zipDirectory(
          stagedDirectory,
          filename: archiveFile.path,
        );
        controller.throwIfCancelled();
        await FileSaver.instance.saveAs(
          name: '$name.zip',
          filePath: archiveFile.path,
          includeExtension: false,
          mimeType: MimeType.zip,
        );
      },
      onSuccess: onSuccess,
      onFinish: () async {
        try {
          await temporaryDirectory.delete(recursive: true);
        } catch (_) {}
      },
    );
  }

  Future<void> _downloadDirectory(
    String remotePath,
    String name, {
    bool notify = true,
    Future<void> Function()? onSuccess,
    Future<void> Function()? onFinish,
  }) async {
    await _runTransfer(
      title: 'fileManagerDownloading'.tr(args: [name]),
      totalBytes: null,
      notify: notify,
      action: (controller, reportProgress) async {
        final sftp = await _sftp();
        final localRoot = await _uniqueLocalPath(_localDirectory.path, name);
        final localDirectory = Directory(localRoot);
        try {
          await _downloadRemoteDirectory(
            sftp,
            remotePath,
            localDirectory,
            controller: controller,
            reportProgress: reportProgress,
          );
        } finally {
          if (controller.isCancelled) {
            try {
              await localDirectory.delete(recursive: true);
            } catch (_) {}
          }
        }
        await _refreshLocal();
      },
      onSuccess: onSuccess,
      onFinish: onFinish,
    );
  }

  Future<int> _downloadRemoteDirectory(
    SftpClient sftp,
    String remotePath,
    Directory local, {
    _TransferController? controller,
    void Function(int)? reportProgress,
    int transferredBytes = 0,
  }) async {
    await controller?.waitIfPaused();
    await local.create(recursive: true);
    final entries = await sftp.listdir(remotePath);
    for (final entry in entries) {
      if (entry.filename == '.' || entry.filename == '..') continue;
      await controller?.waitIfPaused();
      final childRemote = _joinRemotePath(remotePath, entry.filename);
      final childLocal = local.uri.resolve(entry.filename).toFilePath();
      if (entry.attr.isDirectory) {
        transferredBytes = await _downloadRemoteDirectory(
          sftp,
          childRemote,
          Directory(childLocal),
          controller: controller,
          reportProgress: reportProgress,
          transferredBytes: transferredBytes,
        );
      } else if (entry.attr.isFile) {
        final remoteFile = await sftp.open(
          childRemote,
          mode: SftpFileOpenMode.read,
        );
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
          await remoteFile.close();
        }
      }
    }
    return transferredBytes;
  }

  Future<void> _copyLocalDirectory(
    Directory source,
    Directory destination,
  ) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final name = _entityName(entity);
      final child = destination.uri.resolve(name).toFilePath();
      if (entity is Directory) {
        await _copyLocalDirectory(entity, Directory(child));
      } else if (entity is File) {
        await entity.copy(child);
      }
    }
  }

  Future<void> _copyRemoteFile(
    SftpClient sftp,
    String source,
    String destination,
  ) async {
    final remoteFile = await sftp.open(
      destination,
      mode:
          SftpFileOpenMode.write |
          SftpFileOpenMode.create |
          SftpFileOpenMode.truncate,
    );
    try {
      final sourceFile = await sftp.open(source, mode: SftpFileOpenMode.read);
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
    SftpClient sftp,
    String source,
    String destination,
  ) async {
    await sftp.mkdir(destination);
    final entries = await sftp.listdir(source);
    for (final entry in entries) {
      if (entry.filename == '.' || entry.filename == '..') continue;
      final childSource = _joinRemotePath(source, entry.filename);
      final childDestination = _joinRemotePath(destination, entry.filename);
      if (entry.attr.isDirectory) {
        await _copyRemoteDirectory(sftp, childSource, childDestination);
      } else if (entry.attr.isFile) {
        await _copyRemoteFile(sftp, childSource, childDestination);
      }
    }
  }

  Future<void> _deleteRemoteDirectory(SftpClient sftp, String path) async {
    final entries = await sftp.listdir(path);
    for (final entry in entries) {
      if (entry.filename == '.' || entry.filename == '..') continue;
      final child = _joinRemotePath(path, entry.filename);
      if (entry.attr.isDirectory) {
        await _deleteRemoteDirectory(sftp, child);
      } else {
        await sftp.remove(child);
      }
    }
    await sftp.rmdir(path);
  }

  Future<String> _uniqueLocalPath(String directory, String name) async {
    var candidate = '$directory${Platform.pathSeparator}$name';
    if (!await FileSystemEntity.type(
      candidate,
    ).then((type) => type != FileSystemEntityType.notFound)) {
      return candidate;
    }
    final dot = name.lastIndexOf('.');
    final hasExtension = dot > 0 && !name.startsWith('.');
    final stem = hasExtension ? name.substring(0, dot) : name;
    final extension = hasExtension ? name.substring(dot) : '';
    var index = 1;
    while (true) {
      candidate = '$directory${Platform.pathSeparator}$stem ($index)$extension';
      final exists = await FileSystemEntity.type(
        candidate,
      ).then((type) => type != FileSystemEntityType.notFound);
      if (!exists) return candidate;
      index += 1;
    }
  }

  Future<String> _uniqueRemotePath(
    SftpClient sftp,
    String directory,
    String name,
  ) async {
    var candidate = _joinRemotePath(directory, name);
    if (!await _remoteExists(sftp, candidate)) return candidate;
    final dot = name.lastIndexOf('.');
    final hasExtension = dot > 0 && !name.startsWith('.');
    final stem = hasExtension ? name.substring(0, dot) : name;
    final extension = hasExtension ? name.substring(dot) : '';
    var index = 1;
    while (true) {
      candidate = _joinRemotePath(directory, '$stem ($index)$extension');
      if (!await _remoteExists(sftp, candidate)) return candidate;
      index += 1;
    }
  }

  Future<bool> _remoteExists(SftpClient sftp, String path) async {
    try {
      await sftp.stat(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _runTransfer({
    required String title,
    required int? totalBytes,
    required Future<void> Function(_TransferController, void Function(int))
    action,
    bool notify = true,
    Future<void> Function()? onSuccess,
    Future<void> Function()? onFinish,
  }) async {
    final controller = _TransferController();
    final taskId = ref
        .read(taskProgressProvider.notifier)
        .start(
          title: title,
          totalBytes: totalBytes,
          status: TaskProgressStatus.queued,
          onCancel: controller.cancel,
        );
    _transferQueue.add(
      _QueuedTransfer(
        id: taskId,
        title: title,
        totalBytes: totalBytes,
        controller: controller,
        notify: notify,
        action: action,
        onSuccess: onSuccess,
        onFinish: onFinish,
      ),
    );
    _processTransferQueue();
  }

  void _processTransferQueue() {
    if (_processingTransferQueue) return;
    _processingTransferQueue = true;
    unawaited(_drainTransferQueue());
  }

  Future<void> _drainTransferQueue() async {
    try {
      while (_transferQueue.isNotEmpty) {
        final transfer = _transferQueue.removeFirst();
        if (transfer.controller.isCancelled) continue;
        await _executeQueuedTransfer(transfer);
      }
    } finally {
      _processingTransferQueue = false;
      if (_transferQueue.isNotEmpty) _processTransferQueue();
    }
  }

  Future<void> _executeQueuedTransfer(_QueuedTransfer transfer) async {
    final controller = transfer.controller;
    ref
        .read(taskProgressProvider.notifier)
        .startRunning(
          transfer.id,
          onPause: controller.pause,
          onResume: controller.resume,
          onCancel: controller.cancel,
        );
    Timer? progressTimer;
    var pendingBytes = 0;
    var hasPendingProgress = false;
    var lastProgressAt = DateTime.fromMillisecondsSinceEpoch(0);

    void flushProgress() {
      progressTimer?.cancel();
      progressTimer = null;
      if (!hasPendingProgress) return;
      hasPendingProgress = false;
      lastProgressAt = DateTime.now();
      ref.read(taskProgressProvider.notifier).update(transfer.id, pendingBytes);
    }

    void reportProgress(int transferredBytes) {
      pendingBytes = transferredBytes;
      hasPendingProgress = true;
      final elapsed = DateTime.now().difference(lastProgressAt);
      if (elapsed >= const Duration(milliseconds: 250)) {
        flushProgress();
        return;
      }
      progressTimer ??= Timer(
        const Duration(milliseconds: 250) - elapsed,
        flushProgress,
      );
    }

    if (mounted) setState(() => _workingPath = transfer.title);
    try {
      await transfer.action(controller, reportProgress);
      controller.throwIfCancelled();
      flushProgress();
      if (transfer.onSuccess != null) {
        await transfer.onSuccess!();
      }
      ref.read(taskProgressProvider.notifier).complete(transfer.id);
      if (transfer.notify && mounted) {
        showStyledSnackBar(
          message: transfer.title,
          title: 'fileManagerTransferComplete'.tr(),
          icon: Symbols.check_circle,
          accentColor: Theme.of(context).colorScheme.primary,
        );
      }
    } on _TransferCancelled {
      flushProgress();
      await ref.read(taskProgressProvider.notifier).cancel(transfer.id);
    } catch (error) {
      flushProgress();
      ref.read(taskProgressProvider.notifier).fail(transfer.id);
      if (transfer.notify && mounted) {
        showStyledSnackBar(
          message: error.toString(),
          title: 'fileManagerTransferFailed'.tr(),
          icon: Symbols.error,
          accentColor: Theme.of(context).colorScheme.error,
        );
      }
      // Re-throw for compound ops (paste) that silence notifications and
      // handle failures themselves. Direct upload/download already notified.
    } finally {
      progressTimer?.cancel();
      if (transfer.onFinish != null) {
        await transfer.onFinish!();
      }
      if (mounted) setState(() => _workingPath = null);
    }
  }

  Future<SftpClient> _sftp() => _sftpClient ??= ref
      .read(connectionManagerProvider)
      .withClient(widget.tab.serverId, (client) => client.sftp());

  Future<void> _editLocal(File file) async {
    final server = _serverForTab();
    if (server == null) return;
    try {
      final length = await file.length();
      validateEditableText(length, file.path);
    } catch (error) {
      if (!mounted) return;
      showMaidKitErrorAlert(
        error,
        title: 'fileManagerCouldNotOpen'.tr(args: [_entityName(file)]),
      );
      return;
    }
    ref
        .read(terminalTabsProvider.notifier)
        .openFileEditor(
          server: server,
          path: file.path,
          fileName: _entityName(file),
          isRemote: false,
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

  Menu _localEntryMenu(FileSystemEntity entry, int index) {
    final selected = _entriesForSelection(_FileSide.local);
    final entries = selected.isEmpty
        ? [_clipboardEntryForLocal(entry)]
        : selected;
    final onlyThis = entries.length == 1 && entries.first.path == entry.path;
    final isDirectory = entry is Directory;
    final busy = _workingPath != null;
    final canPaste = _canPasteInto(_FileSide.local);
    final transferLabel = entries.length == 1
        ? 'Upload to remote'
        : 'Upload ${entries.length} items';
    return Menu(
      children: [
        if (onlyThis && isDirectory)
          MenuAction(
            title: 'fileManagerOpen'.tr(),
            callback: () => _openLocal(entry),
          ),
        if (onlyThis && entry is File)
          MenuAction(
            title: 'fileManagerEdit'.tr(),
            callback: () => _editLocal(entry),
          ),
        MenuAction(
          title: transferLabel,
          callback: () async {
            _ensureLocalContextSelection(entry, index);
            for (final item in _entriesForSelection(_FileSide.local)) {
              await _transferLocalToRemote(item);
            }
          },
        ),
        MenuAction(
          title: 'commonCopy'.tr(),
          activator: const SingleActivator(LogicalKeyboardKey.keyC, meta: true),
          callback: () {
            _ensureLocalContextSelection(entry, index);
            _setClipboard(_ClipboardMode.copy);
          },
        ),
        MenuAction(
          title: 'fileManagerCut'.tr(),
          activator: const SingleActivator(LogicalKeyboardKey.keyX, meta: true),
          callback: () {
            _ensureLocalContextSelection(entry, index);
            _setClipboard(_ClipboardMode.cut);
          },
        ),
        MenuAction(
          title: 'fileManagerPaste'.tr(),
          attributes: MenuActionAttributes(disabled: !canPaste),
          activator: const SingleActivator(LogicalKeyboardKey.keyV, meta: true),
          callback: () => _pasteInto(_FileSide.local),
        ),
        if (onlyThis)
          MenuAction(
            title: 'fileManagerRename'.tr(),
            attributes: MenuActionAttributes(disabled: busy),
            callback: () {
              _ensureLocalContextSelection(entry, index);
              _renameEntry(_clipboardEntryForLocal(entry));
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
            _ensureLocalContextSelection(entry, index);
            _deleteSelection();
          },
        ),
      ],
    );
  }

  Menu _remoteEntryMenu(SftpName entry, int index) {
    final selected = _entriesForSelection(_FileSide.remote);
    final path = _joinRemotePath(_remotePath, entry.filename);
    final entries = selected.isEmpty
        ? [_clipboardEntryForRemote(entry)]
        : selected;
    final onlyThis = entries.length == 1 && entries.first.path == path;
    final isDirectory = entry.attr.isDirectory;
    final busy = _workingPath != null;
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
              await _transferRemoteToLocal(item);
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

  Menu _leftRemoteEntryMenu(SftpName entry, int index) {
    final selected = _entriesForSelection(_FileSide.local);
    final path = _joinRemotePath(_leftRemotePath, entry.filename);
    final entries = selected.isEmpty
        ? [_clipboardEntryForLeftRemote(entry)]
        : selected;
    final onlyThis = entries.length == 1 && entries.first.path == path;
    final busy = _workingPath != null;
    return Menu(
      children: [
        if (onlyThis && entry.attr.isDirectory)
          MenuAction(
            title: 'fileManagerOpen'.tr(),
            callback: () async {
              _ensureLeftRemoteContextSelection(entry, index);
              setState(() {
                _leftRemotePath = path;
                _selectedLocalPaths = {};
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
            _ensureLeftRemoteContextSelection(entry, index);
            for (final item in _entriesForSelection(_FileSide.local)) {
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
            _ensureLeftRemoteContextSelection(entry, index);
            _setClipboard(_ClipboardMode.copy);
          },
        ),
        MenuAction(
          title: 'fileManagerCut'.tr(),
          activator: const SingleActivator(LogicalKeyboardKey.keyX, meta: true),
          callback: () {
            _ensureLeftRemoteContextSelection(entry, index);
            _setClipboard(_ClipboardMode.cut);
          },
        ),
        MenuAction(
          title: 'fileManagerPaste'.tr(),
          attributes: MenuActionAttributes(
            disabled: !_canPasteInto(_FileSide.local),
          ),
          activator: const SingleActivator(LogicalKeyboardKey.keyV, meta: true),
          callback: () => _pasteInto(_FileSide.local),
        ),
        if (onlyThis)
          MenuAction(
            title: 'fileManagerRename'.tr(),
            attributes: MenuActionAttributes(disabled: busy),
            callback: () {
              _ensureLeftRemoteContextSelection(entry, index);
              _renameEntry(_clipboardEntryForLeftRemote(entry));
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
            _ensureLeftRemoteContextSelection(entry, index);
            _deleteSelection();
          },
        ),
      ],
    );
  }

  Menu _paneBackgroundMenu(_FileSide side) {
    final canPaste = _canPasteInto(side);
    final leftRemote = side == _FileSide.local && _leftIsRemote;
    final canGoUp = side == _FileSide.local
        ? leftRemote
              ? _leftRemotePath != '/'
              : _localDirectory.parent.path != _localDirectory.path
        : _remotePath != '/';
    return Menu(
      children: [
        MenuAction(
          title: 'fileManagerCreateFolder'.tr(),
          attributes: MenuActionAttributes(disabled: _workingPath != null),
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
            if (side == _FileSide.remote) {
              _goUpRemote();
            } else if (leftRemote) {
              setState(() {
                _leftRemotePath = _parentRemotePath(_leftRemotePath);
                _selectedLocalPaths = {};
                _localAnchorIndex = null;
              });
              unawaited(_refreshLeftRemote());
            } else {
              _goUpLocal();
            }
          },
        ),
        if (side == _FileSide.local && !_leftIsRemote)
          MenuAction(title: 'Choose folder…', callback: _chooseLocalDirectory),
        MenuAction(
          title: 'commonRefresh'.tr(),
          callback: () {
            if (side == _FileSide.remote) {
              _refreshRemote();
            } else if (leftRemote) {
              _refreshLeftRemote();
            } else {
              _refreshLocal();
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

  /// True when the local pane is rendered and can receive focus.
  bool get _canFocusLocalPane => !_isMobileLayout && !_localCollapsed;

  int _displayedLength(_FileSide side) {
    if (side == _FileSide.local) {
      return _leftIsRemote
          ? _displayedLeftRemoteEntries.length
          : _displayedLocalEntries.length;
    }
    return _displayedRemoteEntries.length;
  }

  /// Index of the selection anchor (or first selected entry) within the
  /// displayed entries of [side], or null when nothing is selected.
  int? _selectionIndex(_FileSide side) {
    if (side == _FileSide.local) {
      final anchor = _localAnchorIndex;
      if (anchor != null && anchor >= 0 && anchor < _displayedLength(side)) {
        return anchor;
      }
      if (_leftIsRemote) {
        for (var i = 0; i < _displayedLeftRemoteEntries.length; i++) {
          final path = _joinRemotePath(
            _leftRemotePath,
            _displayedLeftRemoteEntries[i].filename,
          );
          if (_selectedLocalPaths.contains(path)) return i;
        }
      } else {
        for (var i = 0; i < _displayedLocalEntries.length; i++) {
          if (_selectedLocalPaths.contains(_displayedLocalEntries[i].path)) {
            return i;
          }
        }
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
    if (side == _FileSide.local) {
      if (_leftIsRemote) {
        final displayed = _displayedLeftRemoteEntries;
        if (index < 0 || index >= displayed.length) return;
        _selectLeftRemote(displayed[index], index: index, range: range);
      } else {
        final displayed = _displayedLocalEntries;
        if (index < 0 || index >= displayed.length) return;
        _selectLocal(displayed[index], index: index, range: range);
      }
      return;
    }
    final displayed = _displayedRemoteEntries;
    if (index < 0 || index >= displayed.length) return;
    _selectRemote(displayed[index], index: index, range: range);
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
    final controller = side == _FileSide.local
        ? (_leftIsRemote ? _leftRemoteListController : _localListController)
        : _rightRemoteListController;
    if (!controller.hasClients) return;
    final position = controller.position;
    final top = index * _kFileRowExtent;
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
    if (_focusedSide == _FileSide.local) {
      if (_leftIsRemote) {
        if (_leftRemotePath == '/') return;
        setState(() {
          _leftRemotePath = _parentRemotePath(_leftRemotePath);
          _selectedLocalPaths = {};
          _localAnchorIndex = null;
          _focusedSide = _FileSide.local;
        });
        unawaited(_refreshLeftRemote());
      } else {
        unawaited(_goUpLocal());
      }
      return;
    }
    unawaited(_goUpRemote());
  }

  void _openLeftRemotePath(String path) {
    setState(() {
      _leftRemotePath = path;
      _selectedLocalPaths = {};
      _localAnchorIndex = null;
      _focusedSide = _FileSide.local;
    });
    unawaited(_refreshLeftRemote());
  }

  void _openFocusedSelection() {
    _requestShortcutFocus();
    final side = _focusedSide;
    if (side == null) return;
    final entries = _entriesForSelection(side);
    if (entries.length != 1) return;
    final entry = entries.first;
    if (entry.isDirectory) {
      if (side == _FileSide.local) {
        if (entry.serverId != null) {
          _openLeftRemotePath(entry.path);
        } else {
          unawaited(_openLocal(Directory(entry.path)));
        }
      } else {
        unawaited(_navigateRemote(entry.path));
      }
      return;
    }
    if (side == _FileSide.local && entry.serverId == null) {
      final entity = _localEntries
          .where((item) => item.path == entry.path)
          .firstOrNull;
      if (entity is File) unawaited(_editLocal(entity));
    } else if (side == _FileSide.remote) {
      final sftpName = _remoteEntries
          .where(
            (item) => _joinRemotePath(_remotePath, item.filename) == entry.path,
          )
          .firstOrNull;
      if (sftpName != null && sftpName.attr.isFile) {
        unawaited(_editRemote(sftpName));
      }
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
    if (side == _FileSide.local) {
      if (_leftIsRemote) {
        unawaited(_refreshLeftRemote());
      } else {
        unawaited(_refreshLocal());
      }
    } else {
      unawaited(_refreshRemote());
    }
  }

  void _focusPathBar() {
    final focusLeft = _focusedSide == _FileSide.local && _leftIsRemote;
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
        if (_canFocusLocalPane) _focusSide(_FileSide.local);
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
        if (_leftSearchOpen) _toggleSearch(_FileSide.local);
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
    final localPane = _leftIsRemote
        ? _buildLeftRemotePane(pathTextStyle)
        : _FilePane(
            title: 'fileManagerLocal'.tr(),
            path: _localDirectory.path,
            pathTextStyle: pathTextStyle,
            searchInput: _leftSearchOpen ? _searchInput(_FileSide.local) : null,
            focused: _focusedSide == _FileSide.local,
            dropHighlighted: _dropTargetSide == _FileSide.local,
            canGoUp: _localDirectory.parent.path != _localDirectory.path,
            onGoUp: _goUpLocal,
            onPathTap: _chooseLocalDirectory,
            onRefresh: _refreshLocal,
            onFocus: () => _focusSide(_FileSide.local),
            loading: _loadingLocal,
            error: _localError,
            clipboardHint: _clipboardHint(_FileSide.local),
            backgroundMenu: () => _paneBackgroundMenu(_FileSide.local),
            canAcceptDrop: (data) => data.side == _FileSide.remote,
            onDragEntered: () =>
                setState(() => _dropTargetSide = _FileSide.local),
            onDragExited: () {
              if (_dropTargetSide == _FileSide.local) {
                setState(() => _dropTargetSide = null);
              }
            },
            onAcceptDrop: (data) => _handleInternalDrop(data, _FileSide.local),
            headerActions: [
              _searchToggle(_FileSide.local),
              IconButton(
                tooltip: 'fileManagerCreateFolder'.tr(),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: _workingPath == null
                    ? () => _createFolder(_FileSide.local)
                    : null,
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
              // Keep local visible on mobile; collapse is desktop/wide only.
              if (!_isMobileLayout)
                IconButton(
                  tooltip: 'fileManagerHideLocal'.tr(),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  onPressed: () => setState(() {
                    _localCollapsed = true;
                    if (_focusedSide == _FileSide.local) {
                      _focusedSide = _FileSide.remote;
                    }
                    if (_dropTargetSide == _FileSide.local) {
                      _dropTargetSide = null;
                    }
                  }),
                  icon: const Icon(Symbols.left_panel_close, size: 18),
                ),
            ],
            child: _LocalFileList(
              entries: _displayedLocalEntries,
              scrollController: _localListController,
              emptyMessage: _leftSearchController.text.trim().isEmpty
                  ? null
                  : 'fileManagerNoMatches'.tr(),
              selectedPaths: _selectedLocalPaths,
              cutPaths: _cutPathsFor(_FileSide.local),
              onTapEntry: (entry, index) {
                _selectLocal(
                  entry,
                  index: index,
                  toggle: _isMultiModifierPressed,
                  range: _isRangeModifierPressed,
                );
              },
              onOpen: _openLocal,
              onEdit: (entry) {
                if (entry is File) unawaited(_editLocal(entry));
              },
              dragDataFor: _dragDataForLocal,
              onContextPrepare: _ensureLocalContextSelection,
              menuProvider: _localEntryMenu,
            ),
          );
    final remotePane = _FilePane(
      title: _isLocalMachine
          ? 'fileManagerLocalMachine'.tr()
          : 'fileManagerRemote'.tr(),
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
      backgroundMenu: () => _paneBackgroundMenu(_FileSide.remote),
      canAcceptDrop: (data) => data.side == _FileSide.local,
      onDragEntered: () => setState(() => _dropTargetSide = _FileSide.remote),
      onDragExited: () {
        if (_dropTargetSide == _FileSide.remote) {
          setState(() => _dropTargetSide = null);
        }
      },
      onAcceptDrop: (data) => _handleInternalDrop(data, _FileSide.remote),
      headerActions: [
        _searchToggle(_FileSide.remote),
        IconButton(
          tooltip: 'fileManagerCreateFolder'.tr(),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          onPressed: _workingPath == null
              ? () => _createFolder(_FileSide.remote)
              : null,
          icon: const Icon(Symbols.create_new_folder, size: 18),
        ),
        if (_localCollapsed && !_isMobileLayout)
          IconButton(
            tooltip: 'fileManagerShowLocal'.tr(),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => setState(() => _localCollapsed = false),
            icon: const Icon(Symbols.left_panel_open, size: 18),
          ),
      ],
      child: _RemoteFileList(
        entries: _displayedRemoteEntries,
        scrollController: _rightRemoteListController,
        emptyMessage: _isLocalMachine
            ? 'fileManagerLocalMachineHint'.tr()
            : _rightSearchController.text.trim().isEmpty
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
        final wide = constraints.maxWidth >= _mobileLocalBreakpoint;
        // Mobile always shows the local pane; collapse is wide-layout only.
        final forceLocal = !wide;
        final showExpanded = forceLocal || !_localCollapsed;
        return TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOutCubic,
          tween: Tween<double>(end: showExpanded ? 1.0 : 0.0),
          builder: (context, localFactor, _) {
            final factor = forceLocal ? 1.0 : localFactor.clamp(0.0, 1.0);
            final showLocal = forceLocal || factor > 0.001;
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showLocal) ...[
                    ClipRect(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: factor,
                        child: SizedBox(
                          width: constraints.maxWidth / 2,
                          child: Opacity(opacity: factor, child: localPane),
                        ),
                      ),
                    ),
                    Opacity(
                      opacity: factor,
                      child: const VerticalDivider(width: 1),
                    ),
                  ],
                  Expanded(child: remotePane),
                ],
              );
            }
            return remotePane;
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
      searchInput: _leftSearchOpen ? _searchInput(_FileSide.local) : null,
      focused: _focusedSide == _FileSide.local,
      dropHighlighted: _dropTargetSide == _FileSide.local,
      canGoUp: _leftRemotePath != '/',
      onGoUp: () async {
        setState(() {
          _leftRemotePath = _parentRemotePath(_leftRemotePath);
          _selectedLocalPaths = {};
          _localAnchorIndex = null;
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
          _focusSide(_FileSide.local);
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
      onFocus: () => _focusSide(_FileSide.local),
      loading: _loadingLeftRemote,
      error: _leftRemoteError,
      clipboardHint: _clipboardHint(_FileSide.local),
      backgroundMenu: () => _paneBackgroundMenu(_FileSide.local),
      canAcceptDrop: (data) => data.side == _FileSide.remote,
      onDragEntered: () => setState(() => _dropTargetSide = _FileSide.local),
      onDragExited: () {
        if (_dropTargetSide == _FileSide.local) {
          setState(() => _dropTargetSide = null);
        }
      },
      onAcceptDrop: (data) => _handleInternalDrop(data, _FileSide.local),
      headerActions: [
        _searchToggle(_FileSide.local),
        IconButton(
          tooltip: 'fileManagerCreateFolder'.tr(),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          onPressed: _workingPath == null
              ? () => _createFolder(_FileSide.local)
              : null,
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
        if (!_isMobileLayout)
          IconButton(
            tooltip: 'fileManagerHideLeftPane'.tr(),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => setState(() => _localCollapsed = true),
            icon: const Icon(Symbols.left_panel_close, size: 18),
          ),
      ],
      child: _RemoteFileList(
        entries: _displayedLeftRemoteEntries,
        scrollController: _leftRemoteListController,
        emptyMessage: _leftSearchController.text.trim().isEmpty
            ? null
            : 'fileManagerNoMatches'.tr(),
        currentPath: _leftRemotePath,
        selectedPaths: _selectedLocalPaths,
        cutPaths: _cutPathsFor(_FileSide.local),
        onTapEntry: (entry, index) => _selectLeftRemote(
          entry,
          index: index,
          toggle: _isMultiModifierPressed,
          range: _isRangeModifierPressed,
        ),
        onOpen: (entry) async {
          if (!entry.attr.isDirectory) return;
          setState(() {
            _leftRemotePath = _joinRemotePath(_leftRemotePath, entry.filename);
            _selectedLocalPaths = {};
            _localAnchorIndex = null;
          });
          await _refreshLeftRemote();
        },
        onEdit: (_) {},
        dragDataFor: _dragDataForLeftRemote,
        onContextPrepare: _ensureLeftRemoteContextSelection,
        menuProvider: _leftRemoteEntryMenu,
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
    final first = clipboard.entries.first;
    final source = first.serverId != null || first.side == _FileSide.remote
        ? 'remote'
        : 'local';
    return '$verb $count from $source · paste here';
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
    this.onPathTap,
    this.pathInput,
    this.searchInput,
    this.onCopyPath,
    this.onOpenTerminal,
    this.clipboardHint,
    this.headerActions = const [],
  });

  final String title;
  final String path;
  final TextStyle? pathTextStyle;
  final bool focused;
  final bool dropHighlighted;
  final bool canGoUp;
  final VoidCallback onGoUp;
  final VoidCallback? onPathTap;
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
  final String? clipboardHint;
  final List<Widget> headerActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ContextMenuWidget(
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
                                TextButton(
                                  onPressed: onPathTap,
                                  style: TextButton.styleFrom(
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 0,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  child: Text(
                                    path,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: pathTextStyle,
                                  ),
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
                              icon: const Icon(Symbols.content_copy, size: 18),
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
    );
  }
}

class _LocalFileList extends StatelessWidget {
  const _LocalFileList({
    required this.entries,
    required this.selectedPaths,
    required this.cutPaths,
    required this.onTapEntry,
    required this.onOpen,
    required this.onEdit,
    required this.dragDataFor,
    required this.onContextPrepare,
    required this.menuProvider,
    this.scrollController,
    this.emptyMessage,
  });

  final List<FileSystemEntity> entries;
  final Set<String> selectedPaths;
  final Set<String> cutPaths;
  final String? emptyMessage;
  final ScrollController? scrollController;
  final void Function(FileSystemEntity entry, int index) onTapEntry;
  final ValueChanged<FileSystemEntity> onOpen;
  final ValueChanged<FileSystemEntity> onEdit;
  final _FileDragData Function(FileSystemEntity entry) dragDataFor;
  final void Function(FileSystemEntity entry, int index) onContextPrepare;
  final Menu Function(FileSystemEntity entry, int index) menuProvider;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return _EmptyPane(message: emptyMessage ?? 'This folder is empty.');
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemExtent: _kFileRowExtent,
      controller: scrollController,
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final isDirectory = entry is Directory;
        final name = _entityName(entry);
        final selected = selectedPaths.contains(entry.path);
        final dimmed = cutPaths.contains(entry.path);
        final dragData = dragDataFor(entry);
        return ContextMenuWidget(
          menuProvider: (_) {
            onContextPrepare(entry, index);
            return menuProvider(entry, index);
          },
          child: _DraggableFileRow(
            dragData: dragData,
            icon: isDirectory ? Symbols.folder : Symbols.description,
            name: name,
            detail: isDirectory ? 'fileManagerFolder'.tr() : null,
            selected: selected,
            dimmed: dimmed,
            onTap: () => onTapEntry(entry, index),
            onDoubleTap: isDirectory
                ? () => onOpen(entry)
                : () => onEdit(entry),
          ),
        );
      },
    );
  }
}

class _RemoteFileList extends StatelessWidget {
  const _RemoteFileList({
    required this.entries,
    required this.currentPath,
    required this.selectedPaths,
    required this.cutPaths,
    required this.onTapEntry,
    required this.onOpen,
    required this.onEdit,
    required this.dragDataFor,
    required this.onContextPrepare,
    required this.menuProvider,
    this.scrollController,
    this.emptyMessage,
  });

  final List<SftpName> entries;
  final String currentPath;
  final Set<String> selectedPaths;
  final Set<String> cutPaths;
  final String? emptyMessage;
  final ScrollController? scrollController;
  final void Function(SftpName entry, int index) onTapEntry;
  final ValueChanged<SftpName> onOpen;
  final ValueChanged<SftpName> onEdit;
  final _FileDragData Function(SftpName entry) dragDataFor;
  final void Function(SftpName entry, int index) onContextPrepare;
  final Menu Function(SftpName entry, int index) menuProvider;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return _EmptyPane(message: emptyMessage ?? 'This folder is empty.');
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemExtent: _kFileRowExtent,
      controller: scrollController,
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final isDirectory = entry.attr.isDirectory;
        final path = _joinRemotePath(currentPath, entry.filename);
        final selected = selectedPaths.contains(path);
        final dimmed = cutPaths.contains(path);
        final dragData = dragDataFor(entry);
        return ContextMenuWidget(
          menuProvider: (_) {
            onContextPrepare(entry, index);
            return menuProvider(entry, index);
          },
          child: _DraggableFileRow(
            dragData: dragData,
            icon: isDirectory ? Symbols.folder : Symbols.description,
            name: entry.filename,
            detail: isDirectory
                ? 'fileManagerFolder'.tr()
                : _formatBytes(entry.attr.size),
            selected: selected,
            dimmed: dimmed,
            onTap: () => onTapEntry(entry, index),
            onDoubleTap: isDirectory
                ? () => onOpen(entry)
                : () => onEdit(entry),
          ),
        );
      },
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
        borderRadius: BorderRadius.circular(8),
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

String _entityName(FileSystemEntity entry) =>
    entry.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty);

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
