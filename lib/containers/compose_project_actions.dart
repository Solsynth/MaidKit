import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:maid_kit/servers/maidcafe_stream.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/shared/presentation/deploy_terminal.dart';
import 'container_models.dart';

/// The daemon's stage labels in the app's words. A step the app has not been
/// taught is shown as the daemon named it, rather than hidden.
String composeStageLabel(String label) => switch (label) {
  'pull' => 'composeStacksStagePull'.tr(),
  'recreate' => 'composeStacksStageRecreate'.tr(),
  _ => label,
};

/// Runs a [ComposeProjectAction] in the shared attention-modal task terminal
/// (same UX as standalone `docker run` / deploy compose).
///
/// Call sites only supply project identity and credentials; streaming logs,
/// hide/show, and success/failure chrome come from [runWithDeployTerminal].
Future<void> runComposeProjectActionWithTerminal({
  required WidgetRef ref,
  required int serverId,
  required String serverName,
  required ContainerRuntime runtime,
  required ContainerScope scope,
  required String projectName,
  required String directory,
  required ComposeProjectAction action,
  String? sudoPassword,
}) {
  // The action runs in an SSH-backed task terminal.
  if (kIsWeb) {
    return Future<void>.error(
      UnsupportedError('Compose actions are not available in this browser.'),
    );
  }
  final command =
      '${runtime.name} compose -p $projectName ${action.composeArgs}'
      '  ($directory)';
  return runWithDeployTerminal(
    ref: ref,
    title: '${action.progressLabel} $projectName',
    subtitle: serverName,
    command: command,
    run: (onOutput) => ref
        .read(connectionManagerProvider)
        .runComposeProjectAction(
          serverId,
          runtime: runtime,
          scope: scope,
          projectName: projectName,
          directory: directory,
          action: action,
          sudoPassword: sudoPassword,
          onOutput: onOutput,
        ),
  );
}

/// Runs one compose action through the daemon, in the same terminal the SSH
/// path uses.
///
/// The actions that pull an image (`pull`, `recreate`, `update`) run as a
/// daemon task, so the terminal follows the run: its output and the stage it is
/// on arrive while it happens, instead of only when it is over — which is the
/// whole difference for a pull that takes minutes. A quick action (up, stop,
/// restart) finished inside its request, and there is nothing to watch, so it
/// reports its result at once and opens no terminal.
Future<void> runComposeProjectActionViaDaemon({
  required WidgetRef ref,
  required MaidCafeStreamSession session,
  required String serverName,
  required ContainerRuntime runtime,
  required ContainerScope scope,
  required String projectName,
  required String directory,
  required ComposeProjectAction action,
  String? invokedBy,
}) async {
  final started = await session.startComposeAction(
    projectName,
    action.name,
    directory,
    invokedBy: invokedBy,
  );
  if (!started.isRunning) {
    started.result.ensureSuccess();
    return;
  }
  await runWithDeployTerminal(
    ref: ref,
    title: '${action.progressLabel} $projectName',
    subtitle: serverName,
    command:
        '${runtime.name} compose -p $projectName ${action.composeArgs}'
        '  ($directory)',
    onCancel: () => session.cancelTask(started.id),
    run: (onOutput) async {
      final task = await session.followTask(
        started,
        onOutput: onOutput,
        onStage: (label) => onOutput('\n==> ${composeStageLabel(label)}\n'),
      );
      task.result.ensureSuccess();
    },
  );
}
