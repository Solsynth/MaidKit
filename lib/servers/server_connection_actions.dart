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
import 'maidcafe_connectivity.dart';
import 'maidcafe_debug.dart';
import 'maidcafe_service.dart';
import 'maidcafe_stream.dart';
import 'maidcafe_terminal_connection_manager.dart';
import 'port_forwarding_models.dart';
import 'server_models.dart';
import 'server_providers.dart';
import 'server_repository.dart';
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
  // SSH/local-shell entry point goes through. A server that also carries a
  // daemon route (see ServerMaidCafeRoute) is still reachable: the daemon
  // opens one PTY per socket, so every session runs at the same time.
  if (kIsWeb) {
    final daemonRoute = await ref
        .read(serverRepositoryProvider)
        .maidCafeTerminalTargetFor(server);
    if (daemonRoute != null && context.mounted) {
      return openMaidCafeTerminalSession(context, ref, server, paneId: paneId);
    }
    if (context.mounted) {
      showStyledSnackBar(
        message: 'serverTerminalUnavailableInBrowser'.tr(),
        title: 'serverCannotOpenTerminal'.tr(),
        icon: Symbols.terminal,
        accentColor: Theme.of(context).colorScheme.error,
      );
    }
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

/// Which transport a MaidCafe terminal should use.
enum MaidCafeTerminalRoute {
  /// Dial the daemon itself. When it only listens on the server's own loopback,
  /// an existing SSH session carries the terminal there.
  daemon,

  /// Relay the session through the MaidCafe cloud, for a daemon with no
  /// reachable inbound route.
  relay,
}

/// A resolved endpoint plus the cleanup of the temporary SSH forward that
/// carries it, when one was opened.
typedef ResolvedMaidCafeTerminal = ({
  MaidCafeTerminalTarget? target,
  Future<void> Function()? stop,
});

/// Resolves the daemon terminal endpoint for [server] on this client.
///
/// A daemon that only listens on the server's own loopback is reached through a
/// temporary SSH forward when this client already has an SSH session for the
/// server; a browser build has no SSH and dials the server host instead (see
/// [ServerMaidCafeRoute.maidCafeBrowserTerminalUrl]).
///
/// [relay] forces the cloud relay (`true`) or the daemon itself (`false`);
/// null follows the server's own setting.
Future<ResolvedMaidCafeTerminal> resolveMaidCafeTerminal(
  WidgetRef ref,
  Server server, {
  bool? relay,
  bool allowForward = true,
  String? relayDaemonId,
}) async {
  final repository = ref.read(serverRepositoryProvider);
  final target = await repository.maidCafeTerminalTargetFor(
    server,
    useCloudRelay: relay,
    relayDaemonId: relayDaemonId,
  );
  if (kIsWeb || relay == true || !allowForward || target?.isRelayed == true) {
    return (target: target, stop: null);
  }
  final uri = target == null ? null : Uri.tryParse(target.baseUrl);
  final loopback =
      uri != null && const {'127.0.0.1', 'localhost', '::1'}.contains(uri.host);
  // A reachable endpoint is dialed as stored. Loopback and "no endpoint at all"
  // are the two cases a forward serves, the latter with the port a client
  // learned over SSH (see ServerMaidCafeRoute).
  if (target != null && !loopback) return (target: target, stop: null);
  final port =
      server.maidCafeTerminalPort ??
      (uri != null && uri.hasPort ? uri.port : null);
  if (port == null) return (target: target, stop: null);
  final manager = ref.read(connectionManagerProvider);
  if (manager.clientFor(server.id) == null) {
    // No SSH session to carry it; the direct dial is all that is left.
    return (target: target, stop: null);
  }
  final secret =
      target?.secret ?? await _maidCafeTerminalSecret(repository, server);
  if (secret == null || secret.isEmpty) return (target: target, stop: null);
  try {
    final forward = await manager.startPortForward(
      server: server,
      direction: PortForwardDirection.local,
      kind: PortForwardKind.tcp,
      bindHost: '127.0.0.1',
      bindPort: 0,
      targetHost: '127.0.0.1',
      targetPort: port,
      owner: PortForwardOwner.maidCafe,
    );
    return (
      target: MaidCafeTerminalTarget(
        baseUrl: 'http://${forward.bindHost}:${forward.bindPort}',
        secret: secret,
      ),
      stop: () => manager.stopManagedPortForward(forward.id),
    );
  } catch (_) {
    // A forward that cannot start leaves the stored endpoint in place; the
    // transport reports the real failure.
    return (target: target, stop: null);
  }
}

/// The terminal credential for [server]: the dedicated terminal secret when
/// one is stored, the daemon metrics secret otherwise — the same fallback the
/// daemon applies to `daemon.terminal.secret`.
Future<String?> _maidCafeTerminalSecret(
  ServerRepository repository,
  Server server,
) async =>
    await repository.maidCafeTerminalSecretFor(server) ??
    await repository.maidCafeMetricsSecretFor(server);

/// Opens a terminal on [server]'s MaidCafe daemon WebSocket endpoint. Returns
/// whether the terminal tab was opened.
///
/// Unlike SSH and serial terminals this needs no raw socket, so it is the only
/// transport a browser build can use. [route] picks the transport explicitly,
/// which is what the right-click actions on native offer; null follows the
/// server's configured connection type.
Future<bool> openMaidCafeTerminalSession(
  BuildContext context,
  WidgetRef ref,
  Server server, {
  String? paneId,
  MaidCafeTerminalRoute? route,
}) async {
  final relay = route == MaidCafeTerminalRoute.relay;
  maidCafeLog(
    'open requested for "${server.name}": '
    'route=${route?.name ?? 'the server setting'}',
  );
  if (!relay && await _maidCafeCredentialMissing(ref, server)) {
    // Detection stores the endpoint and the switch but leaves the credential
    // unread, and the daemon needs one: without it the route cannot even be
    // built. Reading the daemon's own configuration is what makes the direct
    // route work on a client that never filled the field in by hand.
    await _maidCafeLearnConfig(ref, server);
  }
  final resolution = await resolveMaidCafeTerminal(
    ref,
    server,
    relay: route == null ? null : relay,
    relayDaemonId: relay
        ? (await maidCafeRelayIdentity(ref, server)).daemonId
        : null,
  );
  final target = resolution.target;
  if (target == null) {
    maidCafeLog(
      'no route to "${server.name}" could be built for '
      'route=${route?.name ?? 'the server setting'}; '
      'daemonUrl=${server.maidCafeTerminalUrl} '
      'daemonId=${server.maidCafeDaemonId} '
      'port=${server.maidCafeTerminalPort}',
    );
    await resolution.stop?.call();
    if (context.mounted) {
      _reportUnavailableMaidCafeRoute(context, server, route);
    }
    return false;
  }
  if (!context.mounted) {
    await resolution.stop?.call();
    return false;
  }
  final loading = showMaidKitLoadingModal(
    context,
    message: 'serverOpeningMaidCafeTerminal'.tr(args: [server.name]),
  );
  try {
    await ref
        .read(terminalTabsProvider.notifier)
        .openMaidCafe(
          server,
          target,
          paneId: paneId,
          // The forward, when there is one, lives exactly as long as the tab.
          onClose: resolution.stop,
        );
    return true;
  } catch (error) {
    maidCafeLog('the terminal for "${server.name}" did not open', error: error);
    await resolution.stop?.call();
    if (context.mounted) {
      showStyledSnackBar(
        // An unreachable direct route is usually a closed port or a daemon that
        // only listens on the server itself: say what to open.
        message: route == MaidCafeTerminalRoute.relay
            ? describeMaidCafeError(error)
            : [
                describeMaidCafeError(error),
                maidCafeRouteFailureSuffix(server, error),
              ].where((part) => part.isNotEmpty).join(' '),
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

/// What to open on the server when its daemon cannot be reached directly.
String maidCafeExposeHint(Server server) {
  final exposure = maidCafeExposure(server);
  return 'maidCafeCheckExposeHint'.tr(
    args: ['${exposure.port}', exposure.listenHost],
  );
}

/// The one-line form of [maidCafeExposeHint], for a failure message.
String maidCafeExposePortHint(Server server) =>
    'maidCafeExposePortShort'.tr(args: ['${maidCafeExposure(server).port}']);

/// What to do about a direct route that failed, or an empty string when the
/// message already says it.
///
/// A diagnosed handshake refusal means the endpoint answered, so the port is
/// open and reachable: advising the user to expose it would send them after a
/// firewall that is not in the way. Only a route that never answered is a port
/// problem, and a daemon whose terminal endpoint is off has to be switched on
/// first in any case.
String maidCafeRouteFailureSuffix(Server server, Object error) {
  final handshake = error is MaidCafeTerminalException ? error.handshake : null;
  if (handshake != null) {
    if (handshake != MaidCafeTerminalHandshakeFailure.disabled) return '';
    // The configuration this client read says the endpoint is on, yet the
    // running daemon refuses: it never applied that configuration, and a
    // rejected one leaves the daemon on its previous policy. Telling the user
    // to enable it again changes nothing, which is how this looks from outside.
    return server.maidCafeTerminalEnabled == true
        ? 'maidCafeTerminalConfigRejected'.tr()
        : 'maidCafeTerminalDisabledShort'.tr();
  }
  if (server.maidCafeTerminalEnabled == false ||
      _maidCafeErrorMentionsDisabledTerminal(error)) {
    return 'maidCafeTerminalDisabledShort'.tr();
  }
  return maidCafeExposePortHint(server);
}

/// Whether a transport failure reads as "the daemon's terminal is off".
///
/// The daemon reports that in its own words, so this stays a heuristic; it only
/// picks which advice is shown, never whether a terminal opens.
bool _maidCafeErrorMentionsDisabledTerminal(Object error) {
  final text = error is MaidCafeTerminalException
      ? '${error.message} ${error.reason ?? ''}'
      : error.toString();
  final lower = text.toLowerCase();
  return lower.contains('terminal') &&
      (lower.contains('disabl') ||
          lower.contains('not allowed') ||
          lower.contains('not enabled') ||
          lower.contains('turned off'));
}

/// Says why a MaidCafe route could not be built, per the route that was asked
/// for: a relay needs the daemon identity and a cloud session, the daemon needs
/// an endpoint.
void _reportUnavailableMaidCafeRoute(
  BuildContext context,
  Server server,
  MaidCafeTerminalRoute? route,
) {
  final message = switch (route) {
    MaidCafeTerminalRoute.relay =>
      (server.maidCafeDaemonId?.trim().isEmpty ?? true)
          ? 'serverMaidCafeDaemonIdRequired'.tr()
          : 'maidCafeSignInRequired'.tr(),
    _ => 'serverMaidCafeTerminalNotConfigured'.tr(),
  };
  showStyledSnackBar(
    message: message,
    title: 'serverCannotOpenTerminal'.tr(),
    icon: Symbols.terminal,
    accentColor: Theme.of(context).colorScheme.error,
  );
}

/// Checks whether this device can actually reach [server]'s MaidCafe daemon and
/// the cloud relay, so a firewall, an origin list, or a wrong endpoint is
/// visible before a terminal is opened.
///
/// Both routes run the same three steps a real session does: resolve the
/// endpoint, read `/health`, and complete the terminal handshake.
Future<void> checkMaidCafeConnectivity(
  BuildContext context,
  WidgetRef ref,
  Server server,
) async {
  final manager = ref.read(maidCafeTerminalConnectionManagerProvider);
  // Read (or refresh) the daemon's own terminal switch first: it decides
  // whether an unreachable route is a config problem or a network one.
  final terminalEnabled = await _maidCafeTerminalEnabled(ref, server);
  // A daemon registered in the cloud is not "not configured": find its uuid
  // again before the relay route is called missing.
  final relayIdentity = await maidCafeRelayIdentity(ref, server);

  Future<MaidCafeConnectivityReport> run({required bool relay}) async {
    Future<void> Function()? stop;
    try {
      return await runMaidCafeConnectivityCheck(
        MaidCafeConnectivityProbes(
          resolveTarget: ({required relay}) async {
            final resolution = await resolveMaidCafeTerminal(
              ref,
              server,
              relay: relay,
              relayDaemonId: relay ? relayIdentity.daemonId : null,
            );
            stop = resolution.stop;
            return resolution.target;
          },
          checkHealth: probeMaidCafeHealth,
          openTerminal: (target) async {
            final handle = await manager.openTerminal(server, target);
            await manager.closeTerminal(handle.id);
          },
        ),
        relay: relay,
        terminalEnabled: terminalEnabled,
        // Say why the relay is missing: no session, or no daemon registered
        // under this server's name.
        notConfiguredKey: relay
            ? relayIdentity.missingKey
            : 'maidCafeCheckNotConfigured',
      );
    } finally {
      await stop?.call();
    }
  }

  // Reading the daemon's configuration above is an async gap the sheet's
  // context must not cross.
  if (!context.mounted) return;
  await showMaidCafeConnectivitySheet(
    context,
    serverName: server.name,
    run: run,
    // A direct route that never answers names the port to expose — unless the
    // terminal endpoint is switched off, which the sheet checks first.
    directUnreachableHint: maidCafeExposeHint(server),
  );
}

/// The cloud daemon uuid to address the relay with, and what to say when there
/// is none.
///
/// A row that never stored the uuid — an import, a row synced from another
/// device, a daemon registered elsewhere — is not "not configured": the
/// workspace is asked for the daemon registered under this server's name, and
/// the answer is stored so the next attempt is immediate.
Future<({String? daemonId, String missingKey})> maidCafeRelayIdentity(
  WidgetRef ref,
  Server server,
) async {
  final stored = server.maidCafeDaemonId?.trim();
  final storedId = stored == null || stored.isEmpty ? null : stored;
  try {
    final workspaces = await ref.read(cloudWorkspacesProvider.future);
    if (workspaces.isEmpty) {
      // No Solarpass session on this device: address whatever the row stored and
      // let the cloud answer; the report says which step refused.
      return (daemonId: storedId, missingKey: 'maidCafeSignInRequired');
    }
    final workspaceId =
        ref.read(maidCafeWorkspaceIdProvider) ?? workspaces.first.id;
    final daemons = await ref.read(maidCafeDaemonsProvider(workspaceId).future);
    final daemon = resolveMaidCafeDaemon(
      daemons,
      server.name,
      daemonId: storedId,
    );
    if (daemon == null) {
      return (daemonId: null, missingKey: 'maidCafeCheckRelayUnregistered');
    }
    if (!daemon.enabled) {
      // The cloud refuses relay sessions for a disabled daemon; an open port or
      // a fresh ticket cannot change that.
      return (daemonId: null, missingKey: 'maidCafeCheckRelayDisabled');
    }
    if (!daemon.terminalRelayEnabled) {
      // The daemon has not opted into cloud-relayed terminals, so the cloud
      // would answer the ticket with a bare "forbidden". Say it here instead.
      return (daemonId: null, missingKey: 'maidCafeCheckRelayNotOptedIn');
    }
    // Repair the identity: a uuid the workspace no longer has — or none at all —
    // is replaced by the one it actually registered.
    if (storedId != daemon.id) {
      await ref
          .read(serverRepositoryProvider)
          .setMaidCafeDaemonId(server, daemon.id);
    }
    return (daemonId: daemon.id, missingKey: 'maidCafeCheckRelayUnregistered');
  } catch (_) {
    // Listing failed: most often no Solarpass session on this device.
    return (daemonId: storedId, missingKey: 'maidCafeSignInRequired');
  }
}

/// Whether this row has no credential for a direct daemon route.
///
/// Both credentials count: the daemon accepts its dedicated terminal secret, or
/// its metrics secret when no terminal secret is set.
Future<bool> _maidCafeCredentialMissing(WidgetRef ref, Server server) async {
  if (kIsWeb) return false;
  if (ref.read(connectionManagerProvider).clientFor(server.id) == null) {
    return false;
  }
  final secrets = ref.read(serverRepositoryProvider);
  for (final secret in [
    await secrets.maidCafeTerminalSecretFor(server),
    await secrets.maidCafeMetricsSecretFor(server),
  ]) {
    if (secret != null && secret.trim().isNotEmpty) return false;
  }
  return true;
}

/// Reads the daemon's configuration over SSH and stores what this client needs
/// from it: the terminal switch the check reports, and the metrics secret the
/// daemon accepts when this row has none (or a stale one).
///
/// The secret is read only for the row's own daemon, over its own SSH session,
/// and stored the same way an entered one is. Without it a client that never
/// filled the field is told to "check the credential" on a route that cannot
/// work, which is the state a freshly detected installation is in.
Future<bool?> _maidCafeLearnConfig(WidgetRef ref, Server server) async {
  final manager = ref.read(connectionManagerProvider);
  if (manager.clientFor(server.id) == null) {
    return server.maidCafeTerminalEnabled;
  }
  try {
    final credential = await ref
        .read(serverRepositoryProvider)
        .credentialFor(server);
    final access = await readMaidCafeConfig(
      manager: manager,
      server: server,
      sudoPassword: credential.type == CredentialType.password
          ? credential.password
          : null,
    );
    final secrets = ref.read(serverRepositoryProvider);
    await secrets.setMaidCafeTerminalEnabled(server, access.terminalEnabled);
    final reported = access.apiSecret?.trim();
    final stored = await secrets.maidCafeMetricsSecretFor(server);
    if (reported != null && reported.isNotEmpty && reported != stored) {
      await secrets.setMaidCafeMetricsSecret(server, reported);
    }
    return access.terminalEnabled;
  } catch (_) {
    // Keep whatever was known; the check still runs.
    return server.maidCafeTerminalEnabled;
  }
}

/// Whether the daemon's terminal endpoint is enabled.
///
/// What a previous probe recorded is enough. On a native client with an SSH
/// session the daemon's configuration is read when the answer is not known — or
/// when the switch is known to be on but this row has no credential, which is
/// the one case where the session is about to fail for a reason the check can
/// fix.
Future<bool?> _maidCafeTerminalEnabled(WidgetRef ref, Server server) async {
  if (kIsWeb) return server.maidCafeTerminalEnabled;
  final manager = ref.read(connectionManagerProvider);
  if (manager.clientFor(server.id) == null) {
    return server.maidCafeTerminalEnabled;
  }
  if (server.maidCafeTerminalEnabled == true) {
    final stored = await ref
        .read(serverRepositoryProvider)
        .maidCafeMetricsSecretFor(server);
    if (stored != null && stored.isNotEmpty) {
      return server.maidCafeTerminalEnabled;
    }
  }
  return _maidCafeLearnConfig(ref, server);
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
