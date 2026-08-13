import 'package:dartssh2/dartssh2.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/theme.dart';

/// What the picker should allow the user to choose.
enum CloudFilePickerSelection {
  /// Only files can be confirmed.
  file,

  /// Only the current directory (or a selected directory) can be confirmed.
  folder,

  /// Files and directories can be confirmed.
  fileOrFolder,
}

/// A path chosen from a remote SFTP server.
class CloudPickedPath {
  const CloudPickedPath({
    required this.path,
    required this.name,
    required this.isDirectory,
  });

  /// Absolute remote path.
  final String path;

  /// Final path segment.
  final String name;

  final bool isDirectory;
}

/// Opens a bottom sheet for browsing and selecting remote paths over SFTP.
///
/// Provide [sftp] as a factory that returns an authenticated [SftpClient]. The
/// picker reuses that client for listing and navigation only.
///
/// Returns `null` if dismissed, otherwise one or more [CloudPickedPath] values
/// depending on [allowMultiple].
Future<List<CloudPickedPath>?> showCloudFilePicker(
  BuildContext context, {
  required Future<SftpClient> Function() sftp,
  String? title,
  String? subtitle,
  String initialPath = '.',
  CloudFilePickerSelection selection = CloudFilePickerSelection.file,
  bool allowMultiple = false,
  double heightFactor = 0.85,
}) {
  return showModalBottomSheet<List<CloudPickedPath>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    builder: (_) => _CloudFilePickerSheet(
      sftp: sftp,
      title: title,
      subtitle: subtitle,
      initialPath: initialPath,
      selection: selection,
      allowMultiple: allowMultiple,
      heightFactor: heightFactor,
    ),
  );
}

class _CloudFilePickerSheet extends StatefulWidget {
  const _CloudFilePickerSheet({
    required this.sftp,
    required this.initialPath,
    required this.selection,
    required this.allowMultiple,
    required this.heightFactor,
    this.title,
    this.subtitle,
  });

  final Future<SftpClient> Function() sftp;
  final String initialPath;
  final CloudFilePickerSelection selection;
  final bool allowMultiple;
  final double heightFactor;
  final String? title;
  final String? subtitle;

  @override
  State<_CloudFilePickerSheet> createState() => _CloudFilePickerSheetState();
}

class _CloudFilePickerSheetState extends State<_CloudFilePickerSheet> {
  late final TextEditingController _pathController;
  late final FocusNode _pathFocusNode;
  Future<SftpClient>? _client;
  var _path = '.';
  List<SftpName> _entries = const [];
  final _selectedPaths = <String>{};
  var _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _path = widget.initialPath.trim().isEmpty ? '.' : widget.initialPath.trim();
    _pathController = TextEditingController(text: _path);
    _pathFocusNode = FocusNode();
    _refresh();
  }

  @override
  void dispose() {
    _pathController.dispose();
    _pathFocusNode.dispose();
    super.dispose();
  }

  String get _title {
    if (widget.title != null) return widget.title!;
    return switch (widget.selection) {
      CloudFilePickerSelection.file =>
        widget.allowMultiple
            ? 'filePickerChooseFiles'.tr()
            : 'filePickerChooseFile'.tr(),
      CloudFilePickerSelection.folder => 'filePickerChooseFolders'.tr(),
      CloudFilePickerSelection.fileOrFolder =>
        widget.allowMultiple
            ? 'filePickerChooseItems'.tr()
            : 'filePickerChooseItem'.tr(),
    };
  }

  Future<SftpClient> _sftp() => _client ??= widget.sftp();

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sftp = await _sftp();
      final absolute = await sftp.absolute(_path);
      final entries = await sftp.listdir(absolute);
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
      if (!mounted) return;
      setState(() {
        _path = absolute;
        _entries = entries;
        _selectedPaths.removeWhere(
          (path) => !entries.any(
            (entry) => _joinRemotePath(absolute, entry.filename) == path,
          ),
        );
        if (!_pathFocusNode.hasFocus) {
          _pathController.text = absolute;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _navigate(String path) async {
    final destination = path.trim();
    if (destination.isEmpty) return;
    setState(() {
      _path = destination;
      _selectedPaths.clear();
    });
    _pathFocusNode.unfocus();
    await _refresh();
  }

  Future<void> _openDirectory(SftpName entry) async {
    if (!entry.attr.isDirectory) return;
    await _navigate(_joinRemotePath(_path, entry.filename));
  }

  Future<void> _goUp() async {
    if (_path == '/') return;
    await _navigate(_parentRemotePath(_path));
  }

  bool _isSelectable(SftpName entry) {
    return switch (widget.selection) {
      CloudFilePickerSelection.file => entry.attr.isFile,
      CloudFilePickerSelection.folder => entry.attr.isDirectory,
      CloudFilePickerSelection.fileOrFolder => true,
    };
  }

  void _toggleSelection(SftpName entry) {
    if (!_isSelectable(entry)) return;
    final path = _joinRemotePath(_path, entry.filename);
    setState(() {
      if (widget.allowMultiple) {
        if (!_selectedPaths.add(path)) _selectedPaths.remove(path);
      } else {
        _selectedPaths
          ..clear()
          ..add(path);
      }
    });
  }

  CloudPickedPath _pickedForEntry(SftpName entry) {
    final path = _joinRemotePath(_path, entry.filename);
    return CloudPickedPath(
      path: path,
      name: entry.filename,
      isDirectory: entry.attr.isDirectory,
    );
  }

  List<CloudPickedPath> _resultFromSelection() {
    if (widget.selection == CloudFilePickerSelection.folder &&
        _selectedPaths.isEmpty) {
      final name = _path == '/'
          ? '/'
          : _path
                .split('/')
                .lastWhere((part) => part.isNotEmpty, orElse: () => _path);
      return [CloudPickedPath(path: _path, name: name, isDirectory: true)];
    }

    final byPath = <String, SftpName>{
      for (final entry in _entries)
        _joinRemotePath(_path, entry.filename): entry,
    };
    return [
      for (final path in _selectedPaths)
        if (byPath[path] != null) _pickedForEntry(byPath[path]!),
    ];
  }

  bool get _canConfirm {
    if (widget.selection == CloudFilePickerSelection.folder &&
        _selectedPaths.isEmpty) {
      return !_loading && _error == null;
    }
    return _selectedPaths.isNotEmpty;
  }

  String get _confirmLabel {
    if (widget.selection == CloudFilePickerSelection.folder &&
        _selectedPaths.isEmpty) {
      return 'Select this folder';
    }
    if (_selectedPaths.length > 1) {
      return 'Select ${_selectedPaths.length}';
    }
    return 'Select';
  }

  void _confirm() {
    if (!_canConfirm) return;
    final result = _resultFromSelection();
    if (result.isEmpty) return;
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pathStyle = theme.textTheme.bodyMedium?.copyWith(
      fontFamily: MaidKitFonts.mono,
      color: scheme.onSurfaceVariant,
    );

    return SheetScaffold(
      titleText: _title,
      heightFactor: widget.heightFactor,
      actions: [
        if (widget.subtitle != null)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: Text(
                widget.subtitle!,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Go up',
                  onPressed: _loading || _path == '/' ? null : _goUp,
                  icon: const Icon(Symbols.arrow_upward),
                ),
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    focusNode: _pathFocusNode,
                    style: pathStyle,
                    maxLines: 1,
                    textInputAction: TextInputAction.go,
                    onTap: () => _pathController.selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: _pathController.text.length,
                    ),
                    onSubmitted: _navigate,
                    decoration: const InputDecoration(
                      hintText: 'Remote path',
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy path',
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: _path)),
                  icon: const Icon(Symbols.content_copy),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _loading ? null : _refresh,
                  icon: const Icon(Symbols.refresh),
                ),
              ],
            ),
          ),
          if (widget.selection == CloudFilePickerSelection.folder)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Open folders to navigate. Select this folder, or pick a '
                'folder in the list.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else if (widget.allowMultiple)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Tap items to multi-select. Open folders with the chevron.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          const Divider(height: 1),
          Expanded(child: _buildBody(theme, scheme)),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                if (_selectedPaths.isNotEmpty)
                  Expanded(
                    child: Text(
                      '${_selectedPaths.length} selected',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('filePickerCancel'.tr()),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _canConfirm ? _confirm : null,
                  child: Text(_confirmLabel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme scheme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Symbols.error, color: scheme.error),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.error,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: _refresh,
                child: Text('filePickerRetry'.tr()),
              ),
            ],
          ),
        ),
      );
    }
    if (_entries.isEmpty) {
      return Center(
        child: Text(
          'This folder is empty.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _entries.length,
      itemBuilder: (context, index) {
        final entry = _entries[index];
        final isDirectory = entry.attr.isDirectory;
        final path = _joinRemotePath(_path, entry.filename);
        final selected = _selectedPaths.contains(path);
        final selectable = _isSelectable(entry);
        final detail = isDirectory ? 'Folder' : _formatBytes(entry.attr.size);

        return Material(
          color: selected
              ? scheme.secondaryContainer.withValues(alpha: 0.55)
              : Colors.transparent,
          child: InkWell(
            onTap: () {
              if (isDirectory &&
                  widget.selection == CloudFilePickerSelection.file) {
                _openDirectory(entry);
                return;
              }
              if (isDirectory &&
                  widget.selection == CloudFilePickerSelection.folder &&
                  !widget.allowMultiple) {
                // Single folder pick: first tap selects, open via chevron.
                _toggleSelection(entry);
                return;
              }
              if (selectable) {
                _toggleSelection(entry);
                return;
              }
              if (isDirectory) _openDirectory(entry);
            },
            onDoubleTap: isDirectory
                ? () => _openDirectory(entry)
                : selectable && !widget.allowMultiple
                ? () {
                    _toggleSelection(entry);
                    _confirm();
                  }
                : null,
            child: SizedBox(
              height: 48,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(
                      isDirectory ? Symbols.folder : Symbols.description,
                      size: 20,
                      color: selected
                          ? scheme.onSecondaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        entry.filename,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: selected ? scheme.onSecondaryContainer : null,
                        ),
                      ),
                    ),
                    Text(
                      detail,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: selected
                            ? scheme.onSecondaryContainer.withValues(alpha: 0.8)
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: isDirectory
                          ? IconButton(
                              tooltip: 'Open folder',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              onPressed: () => _openDirectory(entry),
                              icon: const Icon(Symbols.chevron_right),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

String _joinRemotePath(String directory, String name) =>
    directory == '/' ? '/$name' : '$directory/$name';

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
