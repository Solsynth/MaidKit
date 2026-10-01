import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/shared/presentation/cloud_file_picker.dart';
import 'package:maid_kit/shared/presentation/maidkit_alert.dart';
import 'auth_challenge_dialog.dart';
import 'server_models.dart';
import 'server_providers.dart';
import 'ssh_connection_manager.dart';
import 'terminal_tabs_provider.dart';

/// Ensures the server is connected, then opens the reusable cloud file picker.
///
/// Returns `null` if the user cancels or the connection cannot be established.
Future<List<CloudPickedPath>?> pickRemotePaths(
  BuildContext context,
  WidgetRef ref,
  Server server, {
  String? title,
  String initialPath = '.',
  CloudFilePickerSelection selection = CloudFilePickerSelection.file,
  bool allowMultiple = false,
}) async {
  final manager = ref.read(connectionManagerProvider);
  if (manager.clientFor(server.id) == null) {
    final connected = await connectForStatistics(context, ref, server);
    if (!connected || !context.mounted) return null;
  }
  return showCloudFilePicker(
    context,
    sftp: () => manager.withClient(server.id, (client) => client.sftp()),
    title: title,
    subtitle: server.name,
    initialPath: initialPath,
    selection: selection,
    allowMultiple: allowMultiple,
  );
}

Future<bool> connectForStatistics(
  BuildContext context,
  WidgetRef ref,
  Server server,
) async {
  // Every SSH-dependent action funnels through here (server rail actions, the
  // command palette, container/project detail pages, the file manager): a
  // browser cannot open a raw socket, so report it once, in one place.
  if (kIsWeb) {
    showStyledSnackBar(
      message: 'serverTerminalUnavailableInBrowser'.tr(),
      title: 'serverCannotConnect'.tr(),
      icon: Symbols.link_off,
      accentColor: Theme.of(context).colorScheme.error,
    );
    return false;
  }
  try {
    final repository = ref.read(serverRepositoryProvider);
    final servers = await repository.all();
    if (!context.mounted) return false;
    await _ensureJumpHostsConnected(
      context,
      ref,
      server,
      servers,
      <int>{},
      approveAuth: approveAuthChallenge,
    );
    if (!context.mounted) return false;
    await _connectSingleServer(
      context,
      ref,
      server,
      approveAuth: approveAuthChallenge,
    );
  } catch (error) {
    if (context.mounted) {
      showStyledSnackBar(
        message: error.toString(),
        title: 'serverCannotConnect'.tr(),
        icon: Symbols.link_off,
        accentColor: Theme.of(context).colorScheme.error,
      );
    }
    return false;
  }

  return true;
}

Future<void> _ensureJumpHostsConnected(
  BuildContext context,
  WidgetRef ref,
  Server server,
  List<Server> servers,
  Set<int> visiting, {
  VoidCallback? onHostKeyPrompt,
  AuthChallengeApproval? approveAuth,
}) async {
  if (ref.read(connectionManagerProvider).clientFor(server.id) != null) {
    return;
  }
  final jumpHostServerId = server.jumpHostServerId;
  if (jumpHostServerId == null) return;
  if (!visiting.add(server.id)) {
    throw StateError('Jump-host cycle detected at ${server.name}.');
  }
  final jumpHost = servers
      .where((candidate) => candidate.id == jumpHostServerId)
      .firstOrNull;
  if (jumpHost == null) {
    throw StateError(
      'Jump host $jumpHostServerId for ${server.name} no longer exists.',
    );
  }
  if (jumpHost.connectionType != ServerConnectionType.ssh.name) {
    throw StateError('Jump host ${jumpHost.name} is not an SSH server.');
  }
  await _ensureJumpHostsConnected(
    context,
    ref,
    jumpHost,
    servers,
    visiting,
    onHostKeyPrompt: onHostKeyPrompt,
    approveAuth: approveAuth,
  );
  if (!context.mounted) throw StateError('The connection request was closed.');
  if (ref.read(connectionManagerProvider).clientFor(jumpHost.id) == null) {
    await _connectSingleServer(
      context,
      ref,
      jumpHost,
      onHostKeyPrompt: onHostKeyPrompt,
      approveAuth: approveAuth,
    );
  }
  visiting.remove(server.id);
}

Future<void> _connectSingleServer(
  BuildContext context,
  WidgetRef ref,
  Server server, {
  VoidCallback? onHostKeyPrompt,
  AuthChallengeApproval? approveAuth,
}) async {
  HostKeyPrompt? approvedHostKey;
  final repository = ref.read(serverRepositoryProvider);
  final credential = await repository.credentialFor(server);
  final proxy = await repository.proxyFor(server);
  if (!context.mounted) throw StateError('The connection request was closed.');
  await ref
      .read(connectionManagerProvider)
      .connect(
        server,
        credential,
        (prompt) async {
          onHostKeyPrompt?.call();
          if (!context.mounted) return false;
          final approved = await _approveHostKey(context, prompt);
          if (approved) approvedHostKey = prompt;
          return approved;
        },
        knownHostKeyFingerprint: server.hostKeyFingerprint,
        proxy: proxy,
        approveAuth: approveAuth,
      );
  await repository.markConnected(server.id);
  if (approvedHostKey != null) {
    await repository.rememberHostKey(server.id, approvedHostKey!);
  }
}

Future<bool> shouldReconnectAndRetry(
  BuildContext context,
  Object error,
  Server server,
) {
  if (error is! ServerConnectionRequiredException) {
    return Future.value(false);
  }
  return showMaidKitReconnectAlert(server.name);
}

Future<bool> openTerminalSession(
  BuildContext context,
  WidgetRef ref,
  Server server, {
  String? initialDirectory,
  List<String>? initialScripts,
  String? paneId,
}) async {
  // SSH needs a raw socket, which a browser cannot open. Only the MaidCafe
  // daemon transport works there, and this is the single funnel every
  // SSH/local-shell entry point goes through.
  if (kIsWeb) {
    showStyledSnackBar(
      message: 'serverTerminalUnavailableInBrowser'.tr(),
      title: 'serverCannotOpenTerminal'.tr(),
      icon: Symbols.terminal,
      accentColor: Theme.of(context).colorScheme.error,
    );
    return false;
  }
  HostKeyPrompt? approvedHostKey;
  final loading = showMaidKitLoadingModal(
    context,
    message: 'serverOpeningTerminal'.tr(args: [server.name]),
  );
  try {
    final repository = ref.read(serverRepositoryProvider);
    final servers = await repository.all();
    if (!context.mounted) return false;
    await _ensureJumpHostsConnected(
      context,
      ref,
      server,
      servers,
      <int>{},
      onHostKeyPrompt: loading.dismiss,
      approveAuth: (challenge) =>
          approveAuthChallenge(challenge, onBeforePrompt: loading.dismiss),
    );
    if (!context.mounted) return false;
    final credential = await repository.credentialFor(server);
    final proxy = await repository.proxyFor(server);
    if (!context.mounted) return false;
    await ref
        .read(terminalTabsProvider.notifier)
        .open(
          server,
          credential,
          (prompt) async {
            // A host-key prompt must remain interactive, so release the blocking
            // loading overlay before presenting it.
            loading.dismiss();
            if (!context.mounted) return false;
            final approved = await _approveHostKey(context, prompt);
            if (approved) approvedHostKey = prompt;
            return approved;
          },
          knownHostKeyFingerprint: server.hostKeyFingerprint,
          initialDirectory: initialDirectory,
          initialScripts: initialScripts,
          paneId: paneId,
          proxy: proxy,
          approveAuth: (challenge) =>
              approveAuthChallenge(challenge, onBeforePrompt: loading.dismiss),
        );
    if (approvedHostKey != null) {
      await ref
          .read(serverRepositoryProvider)
          .rememberHostKey(server.id, approvedHostKey!);
    }
    return true;
  } catch (error) {
    if (context.mounted) {
      showStyledSnackBar(
        message: error.toString(),
        title: 'serverCannotOpenTerminal'.tr(),
        icon: Symbols.terminal,
        accentColor: Theme.of(context).colorScheme.error,
      );
    }
    return false;
  } finally {
    loading.dismiss();
  }
}

/// Opens the terminal appropriate for [server]'s transport: serial, local
/// shell, MaidCafe daemon WebSocket, or SSH. Returns whether the terminal tab
/// was opened.
Future<bool> openTerminalFor(
  BuildContext context,
  WidgetRef ref,
  Server server, {
  String? paneId,
}) {
  if (server.connectionType == ServerConnectionType.serial.name) {
    return openSerialTerminalSession(context, ref, server, paneId: paneId);
  }
  if (server.connectionType == ServerConnectionType.maidcafe.name) {
    return openMaidCafeTerminalSession(context, ref, server, paneId: paneId);
  }
  return openTerminalSession(context, ref, server, paneId: paneId);
}

/// Opens a terminal on [server]'s MaidCafe daemon WebSocket endpoint. Returns
/// whether the terminal tab was opened.
///
/// Unlike SSH and serial terminals this needs no raw socket, so it is the only
/// transport a browser build can use.
Future<bool> openMaidCafeTerminalSession(
  BuildContext context,
  WidgetRef ref,
  Server server, {
  String? paneId,
}) async {
  final target = await ref
      .read(serverRepositoryProvider)
      .maidCafeTerminalTargetFor(server);
  if (target == null) {
    if (context.mounted) {
      showStyledSnackBar(
        message: 'serverMaidCafeTerminalNotConfigured'.tr(),
        title: 'serverCannotOpenTerminal'.tr(),
        icon: Symbols.terminal,
        accentColor: Theme.of(context).colorScheme.error,
      );
    }
    return false;
  }
  if (!context.mounted) return false;
  final loading = showMaidKitLoadingModal(
    context,
    message: 'serverOpeningMaidCafeTerminal'.tr(args: [server.name]),
  );
  try {
    await ref
        .read(terminalTabsProvider.notifier)
        .openMaidCafe(server, target, paneId: paneId);
    return true;
  } catch (error) {
    if (context.mounted) {
      showStyledSnackBar(
        message: error.toString(),
        title: 'serverCannotOpenTerminal'.tr(),
        icon: Symbols.terminal,
        accentColor: Theme.of(context).colorScheme.error,
      );
    }
    return false;
  } finally {
    loading.dismiss();
  }
}

/// Opens a terminal over [server]'s local serial port. Returns whether the
/// terminal tab was opened.
Future<bool> openSerialTerminalSession(
  BuildContext context,
  WidgetRef ref,
  Server server, {
  String? paneId,
}) async {
  if (!serialPortsSupported) {
    if (context.mounted) {
      showStyledSnackBar(
        message: 'serverSerialNotSupported'.tr(),
        title: 'serverCannotOpenSerialTerminal'.tr(),
        icon: Symbols.terminal,
        accentColor: Theme.of(context).colorScheme.error,
      );
    }
    return false;
  }
  final loading = showMaidKitLoadingModal(
    context,
    message: 'serverOpeningSerialTerminal'.tr(args: [server.name]),
  );
  try {
    await ref
        .read(terminalTabsProvider.notifier)
        .openSerial(server, paneId: paneId);
    return true;
  } catch (error) {
    if (context.mounted) {
      showStyledSnackBar(
        message: error.toString(),
        title: 'serverCannotOpenSerialTerminal'.tr(),
        icon: Symbols.terminal,
        accentColor: Theme.of(context).colorScheme.error,
      );
    }
    return false;
  } finally {
    loading.dismiss();
  }
}

Future<bool> _approveHostKey(BuildContext context, HostKeyPrompt prompt) async {
  return await showMaidKitOverlayDialog<bool>(
        barrierDismissible: false,
        builder: (context, close) => ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Symbols.verified_user,
                    color: Theme.of(context).colorScheme.primary,
                    size: 36,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'serverVerifyHostKey'.tr(),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    prompt.replacesExisting
                        ? 'serverHostKeyChanged'.tr()
                        : 'serverHostKeyNew'.tr(),
                  ),
                  const SizedBox(height: 16),
                  SelectableText('${prompt.algorithm}\n${prompt.fingerprint}'),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => close(false),
                        child: const Text('serverReject').tr(),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => close(true),
                        child: const Text('serverApprove').tr(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ) ??
      false;
}
