import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:maid_kit/containers/container_models.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/maidcafe_stream.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/shared/presentation/maidkit_alert.dart';
import 'package:maid_kit/theme.dart';

/// The daemon's registry of compose projects a scan assigned to it.
///
/// Renders nothing when [ensureSession] yields no session: without the daemon
/// route there is no registry to read, and no SSH fallback either — the
/// registry only exists daemon-side.
class ComposeStacksSection extends ConsumerStatefulWidget {
  const ComposeStacksSection({
    super.key,
    required this.server,
    required this.ensureSession,
    required this.refreshToken,
  });

  final Server server;
  final Future<MaidCafeStreamSession?> Function() ensureSession;

  /// The tab bumps this on a manual refresh; the section reloads when it
  /// changes.
  final int refreshToken;

  @override
  ConsumerState<ComposeStacksSection> createState() =>
      _ComposeStacksSectionState();
}

class _ComposeStacksSectionState extends ConsumerState<ComposeStacksSection> {
  /// Null until the first [ensureSession] call settles; false once it returns
  /// no session, which hides the section for the rest of this mount.
  bool? _hasSession;
  ComposeStacksSnapshot? _snapshot;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ComposeStacksSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _load();
    }
  }

  Future<void> _load() async {
    final session = await widget.ensureSession();
    if (!mounted) return;
    if (session == null) {
      setState(() {
        _hasSession = false;
        _snapshot = null;
        _error = null;
      });
      return;
    }
    setState(() => _hasSession = true);
    try {
      final snapshot = parseComposeStacks(await session.composeStacks());
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  /// Raised for a call that cannot run without the daemon's route. The
  /// section itself only mounts with a session, so this path is defensive.
  Never _noDaemon() {
    throw StateError('composeStacksNoDaemon'.tr());
  }

  Future<void> _copyDirectory(String directory) async {
    await Clipboard.setData(ClipboardData(text: directory));
    if (!mounted) return;
    showStyledSnackBar(
      title: 'composeDetailFieldDirectory'.tr(),
      message: 'commonCopiedToClipboard'.tr(),
      icon: Symbols.content_copy,
      accentColor: Theme.of(context).colorScheme.primary,
    );
  }

  Future<void> _runStackAction(ComposeStack stack, _StackAction action) async {
    if (action == _StackAction.unassign) {
      await _unassign(stack);
      return;
    }
    final verb = action == _StackAction.upgrade ? 'update' : 'pull';
    final title =
        (action == _StackAction.upgrade
                ? 'composeStacksUpgrade'
                : 'composeStacksPull')
            .tr();
    final session = await widget.ensureSession();
    if (!mounted) return;
    if (session == null) {
      _showError(title, 'composeStacksNoDaemon'.tr());
      return;
    }
    try {
      final result = await session.runComposeAction(
        stack.project,
        verb,
        '',
        invokedBy: ref.read(cloudUserProvider).asData?.value?.handle,
      );
      result.ensureSuccess();
      if (!mounted) return;
      showStyledSnackBar(
        title:
            (action == _StackAction.upgrade
                    ? 'composeStacksUpgradeDone'
                    : 'composeStacksPullDone')
                .tr(),
        message: stack.project,
        icon: Symbols.check_circle,
        accentColor: Theme.of(context).colorScheme.primary,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showError(title, error.toString());
    }
  }

  Future<void> _unassign(ComposeStack stack) async {
    final approved = await showMaidKitConfirmAlert(
      'composeStacksUnassignConfirm'.tr(args: [stack.project]),
      'composeStacksUnassign'.tr(),
      isDanger: true,
    );
    if (!approved || !mounted) return;
    final session = await widget.ensureSession();
    if (!mounted) return;
    if (session == null) {
      _showError('composeStacksUnassign'.tr(), 'composeStacksNoDaemon'.tr());
      return;
    }
    try {
      await session.unassignComposeStack(stack.project);
      if (!mounted) return;
      // Drop it from the local list immediately; the reload that follows
      // reconciles the rest.
      final current = _snapshot;
      if (current != null) {
        setState(() {
          _snapshot = ComposeStacksSnapshot(
            stacks: [
              for (final entry in current.stacks)
                if (entry.project != stack.project) entry,
            ],
            scan: current.scan,
          );
        });
      }
      showStyledSnackBar(
        title: 'composeStacksUnassignDone'.tr(),
        message: stack.project,
        icon: Symbols.check_circle,
        accentColor: Theme.of(context).colorScheme.primary,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showError('composeStacksUnassign'.tr(), error.toString());
    }
  }

  void _showError(String title, String message) {
    showStyledSnackBar(
      title: title,
      message: message,
      icon: Symbols.error,
      accentColor: Theme.of(context).colorScheme.error,
    );
  }

  Future<void> _openScanDialog() async {
    final outcome = await showDialog<ComposeScanOutcome>(
      context: context,
      builder: (context) => _StackScanDialog(onScan: _scan),
    );
    if (outcome == null || !mounted) return;
    // A scan answers with the registry list only; the read endpoint carries
    // the scan policy beside it, and a path/depth scan does not change it.
    setState(() {
      _snapshot = ComposeStacksSnapshot(
        stacks: outcome.stacks.stacks,
        scan: _snapshot?.scan ?? const ComposeScanPolicy(),
      );
      _error = null;
    });
    showStyledSnackBar(
      title: 'composeStacksScan'.tr(),
      message: _scanReport(outcome),
      icon: Symbols.check_circle,
      accentColor: Theme.of(context).colorScheme.primary,
    );
  }

  Future<ComposeScanOutcome> _scan(String path, int? depth) async {
    final session = await widget.ensureSession();
    if (session == null) _noDaemon();
    final json = await session.scanComposeStacks(
      path: path.trim().isEmpty ? null : path.trim(),
      depth: depth,
    );
    return ComposeScanOutcome.fromDaemonJson(json);
  }

  String _scanReport(ComposeScanOutcome outcome) {
    if (!outcome.changed) {
      return 'composeStacksScanNoChange'.tr(args: ['${outcome.found}']);
    }
    return 'composeStacksScanResult'.tr(
      args: [
        '${outcome.found}',
        '${outcome.added.length}',
        '${outcome.updated.length}',
        '${outcome.removed.length}',
      ],
    );
  }

  String _scanPolicyLine(ComposeScanPolicy scan) {
    final roots = scan.roots.join(', ');
    return 'composeStacksScanPolicy'.tr(
      args: [roots.isEmpty ? '—' : roots, '${scan.depth}'],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hasSession != true) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final stacks = _snapshot?.stacks ?? const <ComposeStack>[];
    final scan = _snapshot?.scan ?? const ComposeScanPolicy();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: false,
            tilePadding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
            childrenPadding: EdgeInsets.zero,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            collapsedShape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            title: Text(
              'composeStacksTitle'.tr(args: ['${stacks.length}']),
              style: theme.textTheme.titleSmall,
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _scanPolicyLine(scan),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            trailing: IconButton(
              tooltip: 'composeStacksScan'.tr(),
              onPressed: _openScanDialog,
              icon: const Icon(Symbols.scan),
            ),
            children: [
              Divider(height: 1, color: scheme.outlineVariant),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    _error.toString(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ),
              if (stacks.isEmpty && _snapshot != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Text(
                    'composeStacksEmpty'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                for (final stack in stacks) _buildStackRow(context, stack),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStackRow(BuildContext context, ComposeStack stack) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      title: Text(
        stack.project,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    stack.directory,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: MaidKitFonts.mono,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'composeStacksCopyDirectory'.tr(),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  iconSize: 16,
                  onPressed: () => _copyDirectory(stack.directory),
                  icon: const Icon(Symbols.content_copy),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _StackChip(
                  // The fraction is locale-neutral, so it stays literal while
                  // the surrounding chrome is translated.
                  label: '${stack.running}/${stack.total}',
                  tone: stack.isHealthy ? scheme.primary : scheme.error,
                ),
                _StackChip(
                  label: 'composeStacksServices'.tr(
                    args: ['${stack.services.length}'],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      trailing: PopupMenuButton<_StackAction>(
        tooltip: 'containersActionTooltip'.tr(),
        icon: const Icon(Symbols.more_vert),
        onSelected: (action) => _runStackAction(stack, action),
        itemBuilder: (context) => [
          PopupMenuItem<_StackAction>(
            value: _StackAction.upgrade,
            child: _menuRow(Symbols.upgrade, 'composeStacksUpgrade'.tr()),
          ),
          PopupMenuItem<_StackAction>(
            value: _StackAction.pull,
            child: _menuRow(Symbols.download, 'composeStacksPull'.tr()),
          ),
          const PopupMenuDivider(),
          PopupMenuItem<_StackAction>(
            value: _StackAction.unassign,
            child: _menuRow(Symbols.link_off, 'composeStacksUnassign'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _menuRow(IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 20),
      const SizedBox(width: 12),
      Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
    ],
  );
}

enum _StackAction { upgrade, pull, unassign }

/// A count chip in the section's own voice; the container rows' `_MetaChip` is
/// private to their file, so this mirrors its shape.
class _StackChip extends StatelessWidget {
  const _StackChip({required this.label, this.tone});

  final String label;

  /// Tints the chip for a health reading; null keeps the neutral chip style.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tone = this.tone;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tone == null
            ? scheme.surfaceContainerLow
            : tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: tone == null
              ? scheme.outlineVariant
              : tone.withValues(alpha: 0.5),
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: tone ?? scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The starting point and depth dialog for a scan.
///
/// The scan runs inside the dialog so the button can hold the in-flight state;
/// on success the outcome is popped back to the section, and on failure the
/// daemon's message is shown both inline and as a snackbar.
class _StackScanDialog extends StatefulWidget {
  const _StackScanDialog({required this.onScan});

  final Future<ComposeScanOutcome> Function(String path, int? depth) onScan;

  @override
  State<_StackScanDialog> createState() => _StackScanDialogState();
}

class _StackScanDialogState extends State<_StackScanDialog> {
  final _pathController = TextEditingController();
  final _depthController = TextEditingController();
  var _scanning = false;
  String? _error;

  @override
  void dispose() {
    _pathController.dispose();
    _depthController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final outcome = await widget.onScan(
        _pathController.text,
        int.tryParse(_depthController.text.trim()),
      );
      if (!mounted) return;
      Navigator.of(context).pop(outcome);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _error = error.toString();
      });
      showStyledSnackBar(
        title: 'composeStacksScan'.tr(),
        message: error.toString(),
        icon: Symbols.error,
        accentColor: Theme.of(context).colorScheme.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text('composeStacksScanTitle'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _pathController,
            enabled: !_scanning,
            decoration: InputDecoration(
              labelText: 'composeStacksScanPathLabel'.tr(),
              hintText: 'composeStacksScanPathHint'.tr(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _depthController,
            enabled: !_scanning,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'composeStacksScanDepthLabel'.tr(),
              hintText: 'composeStacksScanDepthHint'.tr(),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: scheme.error)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _scanning ? null : () => Navigator.of(context).pop(),
          child: Text('commonCancel'.tr()),
        ),
        FilledButton(
          onPressed: _scanning ? null : _submit,
          child: _scanning
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('composeStacksScan'.tr()),
        ),
      ],
    );
  }
}
