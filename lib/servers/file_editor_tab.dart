import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartssh2/dartssh2.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/highlight_core.dart' show Mode;
import 'package:highlight/languages/bash.dart' as bash;
import 'package:highlight/languages/css.dart' as css;
import 'package:highlight/languages/dart.dart' as dart;
import 'package:highlight/languages/ini.dart' as ini;
import 'package:highlight/languages/javascript.dart' as javascript;
import 'package:highlight/languages/json.dart' as json_lang;
import 'package:highlight/languages/python.dart' as python;
import 'package:highlight/languages/typescript.dart' as typescript;
import 'package:highlight/languages/xml.dart' as xml;
import 'package:highlight/languages/yaml.dart' as yaml_lang;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/shared/presentation/maidkit_alert.dart';
import 'package:maid_kit/theme.dart';
import 'server_providers.dart';
import 'structured_document.dart';
import 'terminal_tabs_provider.dart';

const maximumEditableBytes = 1024 * 1024;

/// A stalled filesystem or SFTP write must not leave an editor tab locked.
const fileSaveTimeout = Duration(seconds: 30);

/// Offload parse/lint to a worker isolate above this size.
const _lintIsolateThresholdBytes = 12 * 1024;

void validateEditableText(int? size, String path) {
  if (size != null && size > maximumEditableBytes) {
    throw FileSystemException('fileManagerFileTooLarge'.tr(), path);
  }
}

class FileEditorTabView extends ConsumerStatefulWidget {
  const FileEditorTabView({required this.tab, super.key});

  final FileEditorTab tab;

  @override
  ConsumerState<FileEditorTabView> createState() => _FileEditorTabViewState();
}

class _FileEditorTabViewState extends ConsumerState<FileEditorTabView> {
  late final CodeController _controller;
  late final FocusNode _editorFocusNode;
  late final ValueNotifier<bool> _dirty;
  late final ValueNotifier<bool> _saving;
  late final ValueNotifier<String?> _status;
  late final ValueNotifier<List<StructuredDocumentIssue>> _issues;
  late final Listenable _chromeListenable;

  var _loading = true;
  String _savedText = '';
  Future<SftpClient>? _sftpClient;
  AnalysisResult? _lastSyncedAnalysis;
  var _listening = false;

  StructuredDocumentKind? get _kind =>
      structuredKindForFileName(widget.tab.fileName);

  bool get _canFormat => _kind != null && !_loading && !_saving.value;

  @override
  void initState() {
    super.initState();
    _dirty = ValueNotifier(false);
    _saving = ValueNotifier(false);
    _status = ValueNotifier<String?>(null);
    _issues = ValueNotifier<List<StructuredDocumentIssue>>(const []);
    _chromeListenable = Listenable.merge([_dirty, _saving, _status, _issues]);
    _editorFocusNode = FocusNode(debugLabel: 'file-editor-${widget.tab.id}');
    final language = languageForFileName(widget.tab.fileName);
    _controller = CodeController(
      language: language,
      analyzer: StructuredDocumentAnalyzer(kind: _kind),
    );
    fileEditorCloseGuards[widget.tab.id] = _requestClose;
    unawaited(_load());
  }

  @override
  void dispose() {
    fileEditorCloseGuards.remove(widget.tab.id);
    // Close the SFTP channel so opening/closing many editor tabs does not
    // leak one SSH channel per tab until the whole session disconnects.
    final pending = _sftpClient;
    if (pending != null) {
      unawaited(
        pending.then((client) {
          try {
            client.close();
          } catch (_) {
            // The remote channel may already be closed; ignore close races.
          }
        }),
      );
    }
    if (_listening) {
      _controller.removeListener(_onControllerChanged);
    }
    _controller.dispose();
    _editorFocusNode.dispose();
    _dirty.dispose();
    _saving.dispose();
    _status.dispose();
    _issues.dispose();
    super.dispose();
  }

  Future<bool> _requestClose() async {
    if (_saving.value) return false;
    if (!_dirty.value) return true;
    return showMaidKitConfirmAlert(
      'fileManagerDiscardChangesMessage'.tr(args: [widget.tab.fileName]),
      'fileManagerDiscardChangesTitle'.tr(),
      isDanger: true,
    );
  }

  Future<void> _load() async {
    try {
      final text = await _readFile();
      if (!mounted) return;
      _controller.text = text;
      _savedText = text;
      _dirty.value = false;
      _status.value = null;
      _issues.value = const [];
      _lastSyncedAnalysis = null;
      if (!_listening) {
        _controller.addListener(_onControllerChanged);
        _listening = true;
      }
      setState(() => _loading = false);
      // Let the editor paint before the first analysis pass.
      unawaited(_controller.analyzeCode());
    } catch (error) {
      if (!mounted) return;
      showMaidKitErrorAlert(
        error,
        title: 'fileManagerCouldNotOpen'.tr(args: [widget.tab.fileName]),
      );
      await ref.read(terminalTabsProvider.notifier).close(widget.tab.id);
    }
  }

  Future<String> _readFile() async {
    if (widget.tab.isRemote) {
      final sftp = await _sftp();
      final file = await sftp.open(
        widget.tab.path,
        mode: SftpFileOpenMode.read,
      );
      try {
        final bytes = await file.readBytes();
        validateEditableText(bytes.length, widget.tab.path);
        return utf8.decode(bytes);
      } finally {
        await file.close();
      }
    }

    final file = File(widget.tab.path);
    final bytes = await file.readAsBytes();
    validateEditableText(bytes.length, widget.tab.path);
    return utf8.decode(bytes);
  }

  Future<void> _writeFile(String text) async {
    final encoded = utf8.encode(text);
    if (widget.tab.isRemote) {
      final sftp = await _sftp();
      final file = await sftp.open(
        widget.tab.path,
        mode:
            SftpFileOpenMode.write |
            SftpFileOpenMode.create |
            SftpFileOpenMode.truncate,
      );
      try {
        await file.writeBytes(Uint8List.fromList(encoded));
      } finally {
        await file.close();
      }
      return;
    }
    await File(widget.tab.path).writeAsBytes(encoded, flush: true);
  }

  Future<SftpClient> _sftp() => _sftpClient ??= ref
      .read(connectionManagerProvider)
      .withClient(widget.tab.serverId, (client) => client.sftp());

  /// Cheap dirty/status updates only — never re-parses the document here.
  void _onControllerChanged() {
    if (_loading) return;

    final dirty = _computeDirty();
    if (_dirty.value != dirty) {
      _dirty.value = dirty;
    }

    final status = _status.value;
    if (status != null && _isTransientStatus(status)) {
      _status.value = null;
    }

    // Analysis already runs on CodeController's 500ms debounce; only mirror
    // results into the banner when they actually change.
    final analysis = _controller.analysisResult;
    if (!identical(analysis, _lastSyncedAnalysis)) {
      _lastSyncedAnalysis = analysis;
      _issues.value = [
        for (final issue in analysis.issues)
          if (issue.type == IssueType.error)
            StructuredDocumentIssue(line: issue.line, message: issue.message),
      ];
    }
  }

  bool _computeDirty() {
    final text = _controller.text;
    if (identical(text, _savedText)) return false;
    if (text.length != _savedText.length) return true;
    return text != _savedText;
  }

  bool _isTransientStatus(String status) =>
      status == 'fileManagerSaved'.tr() ||
      status == 'fileEditorFormatted'.tr() ||
      status == 'fileEditorAlreadyFormatted'.tr() ||
      status == 'fileEditorLintClean'.tr();

  Future<void> _save() async {
    if (_loading || _saving.value || !_dirty.value) return;
    _saving.value = true;
    try {
      final text = _controller.text;
      await _writeFile(text).timeout(fileSaveTimeout);
      if (!mounted) return;
      _savedText = text;
      _dirty.value = false;
      _status.value = 'fileManagerSaved'.tr();
      showStyledSnackBar(
        message: widget.tab.fileName,
        title: 'fileManagerSaved'.tr(),
        icon: Symbols.check_circle,
        accentColor: Theme.of(context).colorScheme.primary,
      );
    } catch (error) {
      if (!mounted) return;
      _saving.value = false;
      showMaidKitErrorAlert(
        error,
        title: 'fileManagerCouldNotSave'.tr(args: [widget.tab.fileName]),
      );
    } finally {
      // A timeout only stops waiting for the write. Always release the UI so
      // the user can close the tab or decide how to handle unsaved changes.
      if (mounted) _saving.value = false;
    }
  }

  void _format() {
    final kind = _kind;
    if (kind == null || _loading || _saving.value) return;
    try {
      final formatted = formatStructuredDocument(_controller.text, kind);
      if (formatted == _controller.text) {
        _issues.value = const [];
        _status.value = 'fileEditorAlreadyFormatted'.tr();
        return;
      }
      final selection = _controller.selection;
      _controller.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(
          offset: selection.baseOffset.clamp(0, formatted.length),
        ),
      );
      _dirty.value = _computeDirty();
      _issues.value = const [];
      _status.value = 'fileEditorFormatted'.tr();
    } catch (error) {
      _status.value = 'fileEditorFormatFailed'.tr();
      unawaited(_controller.analyzeCode());
      showMaidKitErrorAlert(error, title: 'fileEditorFormatFailed'.tr());
    }
  }

  Future<void> _lint() async {
    if (_loading) return;
    final kind = _kind;
    if (kind == null) {
      _issues.value = const [];
      _status.value = 'fileEditorLintUnsupported'.tr();
      return;
    }
    final issues = lintStructuredDocument(_controller.text, kind);
    await _controller.analyzeCode();
    if (!mounted) return;
    _issues.value = issues;
    _status.value = issues.isEmpty
        ? 'fileEditorLintClean'.tr()
        : 'fileEditorLintIssues'.tr(args: ['${issues.length}']);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final kind = _kind;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
          unawaited(_save());
        },
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          unawaited(_save());
        },
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true):
            _format,
        const SingleActivator(
          LogicalKeyboardKey.keyS,
          control: true,
          shift: true,
        ): _format,
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Chrome rebuilds without rebuilding the CodeField subtree.
            ListenableBuilder(
              listenable: _chromeListenable,
              builder: (context, _) => _EditorToolbar(
                path: widget.tab.path,
                isRemote: widget.tab.isRemote,
                kind: kind,
                loading: _loading,
                saving: _saving.value,
                dirty: _dirty.value,
                canFormat: _canFormat,
                onSave: () => unawaited(_save()),
                onFormat: _format,
                onLint: () => unawaited(_lint()),
                issueCount: _issues.value.length,
              ),
            ),
            ListenableBuilder(
              listenable: _issues,
              builder: (context, _) {
                final issues = _issues.value;
                if (issues.isEmpty) return const SizedBox.shrink();
                return _IssuesBanner(
                  issues: issues,
                  onDismiss: () => _issues.value = const [],
                );
              },
            ),
            Expanded(child: _buildEditor(context)),
            ListenableBuilder(
              listenable: _chromeListenable,
              builder: (context, _) => DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: scheme.outlineVariant)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _footerLabel(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (kind != null)
                        Text(
                          kind.name.toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontFamily: MaidKitFonts.mono,
                          ),
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

  String _footerLabel() {
    if (_saving.value) return 'fileManagerSaving'.tr();
    if (_status.value != null) return _status.value!;
    if (_dirty.value) return 'fileManagerUnsavedChanges'.tr();
    if (_loading) return '…';
    return 'fileManagerSaved'.tr();
  }

  Widget _buildEditor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    // Stable subtree: parent chrome updates must not rebuild this when only
    // dirty/status notifiers change (ListenableBuilder isolates those).
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        color: scheme.surfaceContainerLowest,
      ),
      child: CodeTheme(
        data: CodeThemeData(
          styles: {
            'root': TextStyle(
              color: scheme.onSurface,
              backgroundColor: scheme.surfaceContainerLowest,
              fontFamily: MaidKitFonts.mono,
            ),
            'comment': TextStyle(color: scheme.onSurfaceVariant),
            'keyword': TextStyle(color: scheme.primary),
            'string': TextStyle(color: scheme.tertiary),
            'number': TextStyle(color: scheme.secondary),
            'literal': TextStyle(color: scheme.secondary),
            'built_in': TextStyle(color: scheme.primary),
          },
        ),
        child: CodeField(
          controller: _controller,
          focusNode: _editorFocusNode,
          expands: true,
          wrap: false,
          padding: const EdgeInsets.all(12),
          textStyle: const TextStyle(
            fontFamily: MaidKitFonts.mono,
            fontSize: 13,
            height: 1.45,
          ),
          gutterStyle: GutterStyle(
            textStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            showErrors: true,
            // Folding parse/layout is relatively expensive while typing.
            showFoldingHandles: false,
            errorPopupTextStyle: TextStyle(
              color: scheme.onErrorContainer,
              backgroundColor: scheme.errorContainer,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({
    required this.path,
    required this.isRemote,
    required this.kind,
    required this.loading,
    required this.saving,
    required this.dirty,
    required this.canFormat,
    required this.onSave,
    required this.onFormat,
    required this.onLint,
    required this.issueCount,
  });

  final String path;
  final bool isRemote;
  final StructuredDocumentKind? kind;
  final bool loading;
  final bool saving;
  final bool dirty;
  final bool canFormat;
  final VoidCallback onSave;
  final VoidCallback onFormat;
  final VoidCallback onLint;
  final int issueCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Icon(
              isRemote ? Symbols.cloud : Symbols.computer,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFamily: MaidKitFonts.mono,
                ),
              ),
            ),
            if (kind != null) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: canFormat ? onFormat : null,
                icon: const Icon(Symbols.data_object, size: 16),
                label: Text('fileEditorFormat'.tr()),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: loading || saving ? null : onLint,
                icon: Icon(
                  issueCount > 0 ? Symbols.error : Symbols.checklist,
                  size: 16,
                ),
                label: Text(
                  issueCount > 0
                      ? 'fileEditorLintCount'.tr(args: ['$issueCount'])
                      : 'fileEditorLint'.tr(),
                ),
              ),
              const SizedBox(width: 8),
            ],
            FilledButton.icon(
              onPressed: loading || saving || !dirty ? null : onSave,
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Symbols.save, size: 18),
              label: Text('commonSave'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

class _IssuesBanner extends StatelessWidget {
  const _IssuesBanner({required this.issues, required this.onDismiss});

  final List<StructuredDocumentIssue> issues;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final first = issues.first;
    final extra = issues.length - 1;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(Symbols.error, size: 16, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                extra > 0
                    ? 'fileEditorIssueSummaryMany'.tr(
                        args: ['${first.line + 1}', first.message, '$extra'],
                      )
                    : 'fileEditorIssueSummary'.tr(
                        args: ['${first.line + 1}', first.message],
                      ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer),
              ),
            ),
            IconButton(
              tooltip: 'commonClose'.tr(),
              visualDensity: VisualDensity.compact,
              onPressed: onDismiss,
              icon: Icon(
                Symbols.close,
                size: 16,
                color: scheme.onErrorContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Local analyzer that validates JSON / YAML / TOML for the code editor gutter.
///
/// Heavy parse work is deferred off the UI isolate for larger documents so
/// typing stays responsive. CodeController already debounces analysis (~500ms).
class StructuredDocumentAnalyzer extends AbstractAnalyzer {
  const StructuredDocumentAnalyzer({this.kind});

  final StructuredDocumentKind? kind;

  @override
  Future<AnalysisResult> analyze(Code code) async {
    final foldIssues = code.invalidBlocks
        .map((e) => e.issue)
        .toList(growable: false);
    if (kind == null) {
      return AnalysisResult(issues: foldIssues);
    }

    final text = code.text;
    final documentKind = kind!;
    // Yield so the current keystroke can paint before parse work.
    await Future<void>.delayed(Duration.zero);
    if (text.length >= _lintIsolateThresholdBytes) {
      final lintIssues = await Isolate.run(
        () => lintStructuredDocument(text, documentKind),
      );
      return AnalysisResult(
        issues: [
          ...foldIssues,
          for (final issue in lintIssues)
            Issue(
              line: issue.line,
              message: issue.message,
              type: IssueType.error,
            ),
        ],
      );
    }

    final lintIssues = lintStructuredDocument(text, documentKind);
    return AnalysisResult(
      issues: [
        ...foldIssues,
        for (final issue in lintIssues)
          Issue(
            line: issue.line,
            message: issue.message,
            type: IssueType.error,
          ),
      ],
    );
  }
}

Mode? languageForFileName(String name) {
  final lower = name.toLowerCase();
  if (lower == 'dockerfile' || lower.endsWith('/dockerfile')) {
    return bash.bash;
  }
  final extension = () {
    final dot = name.lastIndexOf('.');
    if (dot == -1 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }();
  return switch (extension) {
    'dart' => dart.dart,
    'html' || 'htm' || 'xml' || 'svg' => xml.xml,
    'css' || 'scss' => css.css,
    'js' || 'mjs' || 'cjs' => javascript.javascript,
    'ts' || 'tsx' => typescript.typescript,
    'json' || 'jsonc' => json_lang.json,
    'py' => python.python,
    'yaml' || 'yml' => yaml_lang.yaml,
    'toml' || 'ini' || 'cfg' || 'conf' => ini.ini,
    'sh' || 'bash' || 'zsh' || 'fish' || 'env' => bash.bash,
    _ => null,
  };
}
