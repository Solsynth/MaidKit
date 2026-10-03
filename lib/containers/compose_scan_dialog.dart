import 'package:easy_localization/easy_localization.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:maid_kit/containers/container_models.dart';
import 'package:maid_kit/servers/maidcafe_stream.dart';

/// Asks where to scan for compose projects, then runs the scan.
///
/// A scan is the only way a project becomes managed, and it is manual on
/// purpose: it decides which directories the daemon will run compose commands
/// in, so the operator names the starting point rather than the daemon
/// discovering one. [policy] is what the daemon would scan with no starting
/// point — shown in the dialog so "leave it empty" is a decision, not a guess.
///
/// The scan runs inside the dialog so the button can hold the in-flight state;
/// on success the outcome is popped back to the caller.
Future<ComposeScanOutcome?> showComposeStackScanDialog({
  required BuildContext context,
  required ComposeScanPolicy policy,
  required Future<ComposeScanOutcome> Function(String path, int? depth) onScan,
}) {
  return showDialog<ComposeScanOutcome>(
    context: context,
    builder: (context) => _ComposeScanDialog(policy: policy, onScan: onScan),
  );
}

/// Runs one daemon scan and reports the daemon's own failure message.
Future<ComposeScanOutcome> runComposeStackScan(
  MaidCafeStreamSession session, {
  required String path,
  required int? depth,
}) async {
  final trimmed = path.trim();
  return ComposeScanOutcome.fromDaemonJson(
    await session.scanComposeStacks(
      path: trimmed.isEmpty ? null : trimmed,
      depth: depth,
    ),
  );
}

class _ComposeScanDialog extends StatefulWidget {
  const _ComposeScanDialog({required this.policy, required this.onScan});

  final ComposeScanPolicy policy;
  final Future<ComposeScanOutcome> Function(String path, int? depth) onScan;

  @override
  State<_ComposeScanDialog> createState() => _ComposeScanDialogState();
}

class _ComposeScanDialogState extends State<_ComposeScanDialog> {
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AlertDialog(
      title: Text('composeStacksScanTitle'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _pathController,
            enabled: !_scanning,
            decoration: InputDecoration(
              labelText: 'composeStacksScanPathLabel'.tr(),
              hintText: 'composeStacksScanPathHint'.tr(),
            ),
          ),
          if (widget.policy.roots.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'composeStacksScanPolicy'.tr(
                  args: [
                    widget.policy.roots.join(', '),
                    '${widget.policy.depth}',
                  ],
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
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
