import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/shared/presentation/deploy_terminal.dart';
import 'container_models.dart';

/// Runs `docker|podman image prune` in the shared attention-modal task
/// terminal (same UX as compose pull / deploy).
Future<void> runImagePruneWithTerminal({
  required WidgetRef ref,
  required int serverId,
  required String serverName,
  required ContainerRuntime runtime,
  required ContainerScope scope,
  bool force = true,
  bool allUnused = false,
  String? sudoPassword,
}) {
  // Both image actions run in an SSH-backed task terminal.
  if (kIsWeb) {
    return Future<void>.error(
      UnsupportedError('Image actions are not available in this browser.'),
    );
  }
  final flags = [if (allUnused) '-a', if (force) '-f'].join(' ');
  final command =
      '${runtime.name} image prune${flags.isEmpty ? '' : ' $flags'}';
  final scopeLabel = scope == ContainerScope.root ? 'root' : 'user';
  return runWithDeployTerminal(
    ref: ref,
    title: allUnused
        ? 'Pruning unused ${runtime.name} images'
        : 'Pruning dangling ${runtime.name} images',
    subtitle: '$serverName · $scopeLabel',
    command: command,
    run: (onOutput) => ref
        .read(connectionManagerProvider)
        .pruneImages(
          serverId,
          runtime: runtime,
          scope: scope,
          force: force,
          allUnused: allUnused,
          sudoPassword: sudoPassword,
          onOutput: onOutput,
        ),
  );
}

/// Runs `docker|podman rmi` in the shared attention-modal task terminal.
Future<void> runImageRemoveWithTerminal({
  required WidgetRef ref,
  required int serverId,
  required String serverName,
  required ContainerRuntime runtime,
  required ContainerScope scope,
  required String imageId,
  required String imageLabel,
  String? sudoPassword,
}) {
  if (kIsWeb) {
    return Future<void>.error(
      UnsupportedError('Image actions are not available in this browser.'),
    );
  }
  final command = '${runtime.name} rmi $imageId';
  final scopeLabel = scope == ContainerScope.root ? 'root' : 'user';
  return runWithDeployTerminal(
    ref: ref,
    title: 'Removing $imageLabel',
    subtitle: '$serverName · $scopeLabel',
    command: command,
    run: (onOutput) => ref
        .read(connectionManagerProvider)
        .runImageAction(
          serverId,
          runtime: runtime,
          scope: scope,
          imageId: imageId,
          action: ImageAction.remove,
          sudoPassword: sudoPassword,
          onOutput: onOutput,
        ),
  );
}
