import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:maid_kit/containers/compose_project_actions.dart';
import 'package:maid_kit/containers/container_models.dart';
import 'package:maid_kit/servers/maidcafe_stream.dart';
import 'package:maid_kit/shared/presentation/deploy_terminal.dart';
import 'package:maid_kit/shared/presentation/maidkit_alert.dart';

/// Updating a whole compose stack, and every stack on a server.
///
/// One stack's update is the daemon's `compose.update`: it pulls every
/// service's image and then recreates the project's containers on them, in the
/// directory the daemon's registry holds for that project. The app asks for it
/// without a directory, so the daemon answers where to run — a project nothing
/// assigned is refused instead of updated somewhere this app guessed.
///
/// The daemon answers that call with a task, not a result: a pull is minutes,
/// and this client's own read timeout is ten seconds. So the app starts the
/// update, shows it in the shared task terminal — the run's output, its stage,
/// its cancel — and keeps following it after the modal is hidden, because the
/// run is the daemon's and no longer dies with the view that asked for it.
///
/// Updating every stack is that same call per assigned stack, run one at a
/// time: each is a pull and a recreate on a real host, and running them
/// together would trade the host's capacity for nothing an operator asked for.
/// A stack that fails does not stop the rest, and the failure keeps the
/// daemon's own words.

/// One stack's outcome in a bulk update.
class ComposeStackUpdateOutcome {
  const ComposeStackUpdateOutcome({required this.stack, this.error});

  final ComposeStack stack;

  /// The daemon's message when this stack could not be updated.
  final String? error;

  bool get ok => error == null;
}

/// The command a stack update runs, as the terminal header shows it: the two
/// stages the daemon performs, in the project's own directory.
String composeStackUpdateCommand(ComposeStack stack) {
  final directory = stack.directory.trim();
  final where = directory.isEmpty ? '' : 'cd $directory && ';
  return '${where}compose -p ${stack.project} pull && '
      'compose -p ${stack.project} up -d --force-recreate';
}

/// Asks whether to update one whole stack, naming what that does.
Future<bool> confirmComposeStackUpdate(
  BuildContext context,
  ComposeStack stack,
) {
  return showMaidKitConfirmAlert(
    'composeStacksUpdateConfirm'.tr(args: [stack.project]),
    'composeStacksUpdate'.tr(),
  );
}

/// Asks whether to update every assigned stack.
Future<bool> confirmComposeStackUpdateAll(BuildContext context, int count) {
  return showMaidKitConfirmAlert(
    'composeStacksUpdateAllConfirm'.tr(args: ['$count']),
    'composeStacksUpdateAll'.tr(),
  );
}

/// Runs one stack's update in the shared task terminal and reports it the way
/// the rest of the app reports a daemon operation: the terminal is where the
/// run is watched — its output as it arrives, the stage it is on, and its
/// cancel — and hiding it leaves the update running, because the daemon is the
/// one running it.
Future<bool> updateComposeStack(
  BuildContext context, {
  required WidgetRef ref,
  required MaidCafeStreamSession session,
  required ComposeStack stack,
  String? invokedBy,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final MaidCafeTask started;
  try {
    started = await session.startComposeAction(
      stack.project,
      'update',
      '',
      invokedBy: invokedBy,
    );
  } catch (error) {
    if (!context.mounted) return false;
    showStyledSnackBar(
      title: 'composeStacksUpdate'.tr(),
      message: error.toString(),
      icon: Symbols.error,
      accentColor: scheme.error,
    );
    return false;
  }

  var finished = started;
  try {
    await runWithDeployTerminal(
      ref: ref,
      title: 'composeStacksUpdate'.tr(),
      subtitle: stack.project,
      command: composeStackUpdateCommand(stack),
      onCancel: started.id.isEmpty
          ? null
          : () => session.cancelTask(started.id),
      run: (onOutput) async {
        final task = await session.followTask(
          started,
          onOutput: onOutput,
          onStage: (label) => onOutput('\n==> ${composeStageLabel(label)}\n'),
        );
        finished = task;
        // The terminal reports what the daemon said, so a failed update reads
        // there the same way it reads in a snackbar.
        task.result.ensureSuccess();
      },
    );
  } catch (error) {
    if (!context.mounted) return false;
    showStyledSnackBar(
      title: 'composeStacksUpdate'.tr(),
      message: error.toString(),
      icon: Symbols.error,
      accentColor: scheme.error,
    );
    return false;
  }
  // A cancel is the operator's own answer, and they already saw it happen.
  if (finished.isCancelled) return false;
  if (!context.mounted) return true;
  showStyledSnackBar(
    title: 'composeStacksUpdateDone'.tr(),
    message: stack.project,
    icon: Symbols.check_circle,
    accentColor: scheme.primary,
  );
  return true;
}

/// Runs the bulk update behind a dialog that reports each stack as it lands.
///
/// The dialog is the progress and the report: every stack is listed with what
/// happened to it and, while it runs, the stage its update is on — a pull is
/// minutes, so a row that only spins says nothing — and it stays up until it is
/// closed, so a failure on the fourth stack is still readable after the fifth
/// has finished.
Future<void> showComposeStackUpdateAllDialog({
  required BuildContext context,
  required List<ComposeStack> stacks,
  required Future<ComposeStackUpdateOutcome> Function(
    ComposeStack stack,
    void Function(String label) onStage,
  )
  run,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ComposeStackUpdateDialog(stacks: stacks, run: run),
  );
}

class _ComposeStackUpdateDialog extends StatefulWidget {
  const _ComposeStackUpdateDialog({required this.stacks, required this.run});

  final List<ComposeStack> stacks;
  final Future<ComposeStackUpdateOutcome> Function(
    ComposeStack stack,
    void Function(String label) onStage,
  )
  run;

  @override
  State<_ComposeStackUpdateDialog> createState() =>
      _ComposeStackUpdateDialogState();
}

class _ComposeStackUpdateDialogState extends State<_ComposeStackUpdateDialog> {
  final _outcomes = <String, ComposeStackUpdateOutcome>{};
  final _stages = <String, String>{};
  var _running = false;
  var _finished = false;
  var _index = 0;
  String? _runningProject;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _finished = false;
      _index = 0;
      _runningProject = null;
      _stages.clear();
    });
    for (var i = 0; i < widget.stacks.length; i++) {
      if (!mounted) return;
      final stack = widget.stacks[i];
      setState(() {
        _index = i;
        _runningProject = stack.project;
      });
      ComposeStackUpdateOutcome outcome;
      try {
        outcome = await widget.run(stack, (label) {
          if (!mounted) return;
          setState(() => _stages[stack.project] = label);
        });
      } catch (error) {
        outcome = ComposeStackUpdateOutcome(
          stack: stack,
          error: error.toString(),
        );
      }
      if (!mounted) return;
      setState(() {
        _outcomes[stack.project] = outcome;
        _index = i + 1;
        _runningProject = null;
      });
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _finished = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final done = _outcomes.values.where((outcome) => outcome.ok).length;
    final failed = _outcomes.values.length - done;
    return AlertDialog(
      title: Text('composeStacksUpdateAll'.tr()),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_finished)
              Text(
                'composeStacksUpdateSummary'.tr(args: ['$done', '$failed']),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: failed > 0 ? scheme.error : scheme.onSurfaceVariant,
                ),
              )
            else
              Text(
                'composeStacksUpdateProgress'.tr(
                  args: ['${_index + 1}', '${widget.stacks.length}'],
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final stack in widget.stacks)
                    _row(context, stack, _outcomes[stack.project]),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _running ? null : () => Navigator.of(context).pop(),
          child: Text('commonClose'.tr()),
        ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    ComposeStack stack,
    ComposeStackUpdateOutcome? outcome,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final Widget trailing;
    if (outcome == null) {
      trailing = _running && _runningProject == stack.project
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Symbols.schedule, size: 18);
    } else if (outcome.ok) {
      trailing = Icon(Symbols.check_circle, size: 18, color: scheme.primary);
    } else {
      trailing = Icon(Symbols.error, size: 18, color: scheme.error);
    }
    // A running row says which stage the update is on: a stack pulls its images
    // before it recreates anything, and that gap is where the minutes go.
    final stage = _stages[stack.project];
    final runningStage = outcome == null && stage != null
        ? composeStageLabel(stage)
        : null;
    final error = outcome?.error;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(stack.project, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: error == null && runningStage == null
          ? null
          : Text(
              error ?? runningStage!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: error == null ? scheme.onSurfaceVariant : scheme.error,
              ),
            ),
      trailing: trailing,
    );
  }
}
