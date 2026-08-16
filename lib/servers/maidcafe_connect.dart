import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'maidcafe_install.dart';
import 'maidcafe_service.dart';
import 'maidcafe_stream.dart';
import 'server_models.dart';
import 'server_providers.dart';

/// State of a server's MaidCafe installation, probed over the live SSH
/// session when the connect dialog opens.
enum MaidCafeServerProbeStatus {
  /// The server has no active SSH session, so nothing can be probed or
  /// configured from this page.
  disconnected,

  /// No MaidKit-managed MaidCafe installation was found. Registering a
  /// daemon for this server performs a full install of the published bundle.
  notInstalled,

  /// A MaidKit-managed MaidCafe daemon is installed and its configuration
  /// could be read. Registering patches the cloud credentials and restarts
  /// the daemon, preserving every other setting.
  installed,

  /// An unmanaged MaidCafe installation would conflict with a managed one.
  conflict,

  /// The probe failed (connection dropped, config unreadable, ...).
  error,
}

/// Result of probing one server for the connect dialog.
class MaidCafeServerProbe {
  const MaidCafeServerProbe(this.status, {this.access, this.message});

  final MaidCafeServerProbeStatus status;

  /// Parsed daemon configuration for an [MaidCafeServerProbeStatus.installed]
  /// probe; null otherwise.
  final MaidCafeDaemonAccess? access;

  /// Human-readable detail for [MaidCafeServerProbeStatus.conflict] and
  /// [MaidCafeServerProbeStatus.error].
  final String? message;
}

/// Whether [probe] lets the user connect the server to the cloud
/// automatically: a managed install that is not already bound to this cloud
/// and workspace, or an unmanaged server that would get the full bundle
/// install. Conflict, disconnected, and errored servers are excluded.
bool _connectable(
  MaidCafeServerProbe probe,
  String cloudUrl,
  List<MaidCafeDaemon> daemons,
) {
  switch (probe.status) {
    case MaidCafeServerProbeStatus.notInstalled:
      return true;
    case MaidCafeServerProbeStatus.installed:
      final already =
          probe.access?.id != null &&
          probe.access?.cloudUrl == cloudUrl &&
          daemons.any((daemon) => daemon.id == probe.access!.id);
      return !already;
    case MaidCafeServerProbeStatus.disconnected:
    case MaidCafeServerProbeStatus.conflict:
    case MaidCafeServerProbeStatus.error:
      return false;
  }
}

/// Probes one server's MaidCafe installation. Requires the server's live SSH
/// session; servers without one report [MaidCafeServerProbeStatus.disconnected]
/// without touching the network.
Future<MaidCafeServerProbe> probeMaidCafeServer({
  required Ref ref,
  required Server server,
}) async {
  final manager = ref.read(connectionManagerProvider);
  if (manager.clientFor(server.id) == null) {
    return const MaidCafeServerProbe(MaidCafeServerProbeStatus.disconnected);
  }
  try {
    final existing = await detectMaidCafeInstallation(
      manager: manager,
      serverId: server.id,
    ).timeout(const Duration(seconds: 20));
    final managed = existing.contains('managed');
    if (managed) {
      try {
        final access = await readMaidCafeConfig(
          manager: manager,
          server: server,
          sudoPassword: await maidCafeSudoPassword(ref, server),
        );
        return MaidCafeServerProbe(
          MaidCafeServerProbeStatus.installed,
          access: access,
        );
      } catch (error) {
        return MaidCafeServerProbe(
          MaidCafeServerProbeStatus.error,
          message: error.toString(),
        );
      }
    }
    final conflicts = existing.where((entry) => entry != 'managed').toList();
    if (conflicts.isNotEmpty) {
      return MaidCafeServerProbe(
        MaidCafeServerProbeStatus.conflict,
        message: conflicts.join('\n'),
      );
    }
    return const MaidCafeServerProbe(MaidCafeServerProbeStatus.notInstalled);
  } catch (error) {
    return MaidCafeServerProbe(
      MaidCafeServerProbeStatus.error,
      message: error.toString(),
    );
  }
}

/// The sudo password for [server]'s SSH credential, or null for key-only
/// credentials (passwordless sudo is assumed then).
Future<String?> maidCafeSudoPassword(Ref ref, Server server) async {
  final credential = await ref
      .read(serverRepositoryProvider)
      .credentialFor(server);
  return credential.type == CredentialType.password
      ? credential.password
      : null;
}

/// Runs one privileged script over the server's SSH session. The production
/// wiring streams output into a deploy terminal; tests inject a bare runner.
typedef MaidCafeConnectScriptRunner =
    Future<void> Function({
      required Server server,
      required String script,
      String? sudoPassword,
    });

/// Persists the daemon's local HTTP endpoint for [server].
typedef MaidCafeSaveDaemonUrl =
    Future<void> Function(Server server, String daemonUrl);

/// Installs the published MaidCafe bundle on [server] bound to [daemon].
typedef MaidCafeInstallDaemon =
    Future<void> Function({
      required WidgetRef ref,
      required Server server,
      required MaidCafeDaemonCredential daemon,
      required String cloudUrl,
      required String? sudoPassword,
      required int port,
    });

/// Registers a server's daemon in the cloud and applies it to the server:
/// a managed installation gets its cloud credentials patched and the daemon
/// restarted; an unmanaged server gets the full bundle install. Either way
/// the server ends up running the cloud-registered daemon automatically.
abstract interface class MaidCafeServerConnector {
  Future<MaidCafeDaemonCredential> connect({
    required Server server,
    required String workspaceId,
    required MaidCafeServerProbe probe,
    required WidgetRef ref,
  });
}

class MaidCafeServerConnectorImpl implements MaidCafeServerConnector {
  MaidCafeServerConnectorImpl({
    required this.service,
    required this.cloudUrl,
    required this.sudoPassword,
    required this.runScript,
    required this.saveDaemonUrl,
    required this.installDaemon,
    required this.invalidateSession,
  });

  final MaidCafeService service;
  final Future<String> Function() cloudUrl;
  final Future<String?> Function(Server server) sudoPassword;
  final MaidCafeConnectScriptRunner runScript;
  final MaidCafeSaveDaemonUrl saveDaemonUrl;
  final MaidCafeInstallDaemon installDaemon;
  final void Function(Server server) invalidateSession;

  @override
  Future<MaidCafeDaemonCredential> connect({
    required Server server,
    required String workspaceId,
    required MaidCafeServerProbe probe,
    required WidgetRef ref,
  }) async {
    final credential = await service.createDaemon(
      name: server.name,
      workspaceId: workspaceId,
    );
    final cloudUrl = await this.cloudUrl();
    final sudoPassword = await this.sudoPassword(server);
    final access = probe.access;
    if (access != null && access.configText.isNotEmpty) {
      final port = access.port ?? maidCafeDefaultPort;
      final listenHost = access.listenHost ?? '127.0.0.1';
      await runScript(
        server: server,
        sudoPassword: sudoPassword,
        script: buildMaidCafeDaemonConfigScript(
          currentConfig: access.configText,
          daemonId: credential.id,
          cloudUrl: cloudUrl,
          cloudSecret: credential.secret,
          transport: access.transport == 'stdio' ? 'stdio' : 'http',
          listenHost: listenHost,
          port: port,
          apiSecret: access.apiSecret ?? '',
          metricsInterval: access.metricsInterval ?? '1m',
          requestTimeout: access.requestTimeout ?? '10s',
          scriptTimeout: access.scriptTimeout ?? '30s',
          maxBodyBytes: access.maxBodyBytes ?? 65536,
          maxConcurrentRuns: access.maxConcurrentRuns ?? 4,
          actions: access.actions,
        ),
      );
      await saveDaemonUrl(server, 'http://$listenHost:$port');
    } else {
      await installDaemon(
        ref: ref,
        server: server,
        daemon: credential,
        cloudUrl: cloudUrl,
        sudoPassword: sudoPassword,
        port: access?.port ?? maidCafeDefaultPort,
      );
    }
    invalidateSession(server);
    return credential;
  }
}

/// Probes every server when the connect dialog opens, keyed by server id so
/// each row refreshes independently.
final maidCafeServerProbeProvider =
    FutureProvider.family<MaidCafeServerProbe, int>((ref, serverId) async {
      final servers = ref.read(serversProvider).asData?.value;
      final server = servers
          ?.where((server) => server.id == serverId)
          .firstOrNull;
      if (server == null) {
        return const MaidCafeServerProbe(
          MaidCafeServerProbeStatus.error,
          message: 'Server not found.',
        );
      }
      return probeMaidCafeServer(ref: ref, server: server);
    });

final maidCafeServerConnectorProvider = Provider<MaidCafeServerConnector>((
  ref,
) {
  return MaidCafeServerConnectorImpl(
    service: ref.read(maidCafeServiceProvider),
    cloudUrl: () async => ref.read(maidCafeCloudUrlProvider),
    sudoPassword: (server) => maidCafeSudoPassword(ref, server),
    runScript: ({required server, required script, sudoPassword}) => ref
        .read(connectionManagerProvider)
        .runPrivilegedScriptSnippet(
          server.id,
          script: script,
          sshUserIsRoot: server.username == 'root',
          sudoPassword: sudoPassword,
        ),
    saveDaemonUrl: (server, daemonUrl) => ref
        .read(serverRepositoryProvider)
        .updateMaidCafeConfig(server, daemonUrl: daemonUrl),
    installDaemon:
        ({
          required ref,
          required server,
          required daemon,
          required cloudUrl,
          required sudoPassword,
          required port,
        }) => installMaidCafeDaemon(
          ref: ref,
          server: server,
          daemon: daemon,
          cloudUrl: cloudUrl,
          cloudSecret: daemon.secret,
          sudoPassword: sudoPassword,
          port: port,
        ),
    invalidateSession: (server) =>
        ref.read(maidCafeSessionRegistryProvider).invalidate(server),
  );
});

/// What the connect dialog decided: a server was connected automatically, or
/// the user chose to register a daemon manually (name + one-time snippet).
class MaidCafeConnectServerResult {
  const MaidCafeConnectServerResult.manual() : credential = null, manual = true;

  const MaidCafeConnectServerResult.connected(
    MaidCafeDaemonCredential this.credential,
  ) : manual = false;

  final MaidCafeDaemonCredential? credential;
  final bool manual;

  bool get connected => credential != null;
}

/// Register-daemon picker: lists the user's servers with their MaidCafe
/// installation state (probed over each live SSH session) and connects the
/// chosen one to the cloud automatically. A manual name-only path remains
/// for hosts that are not managed by MaidKit.
class MaidCafeConnectServerDialog extends ConsumerStatefulWidget {
  const MaidCafeConnectServerDialog({super.key, required this.workspaceId});

  final String workspaceId;

  @override
  ConsumerState<MaidCafeConnectServerDialog> createState() =>
      _MaidCafeConnectServerDialogState();
}

class _MaidCafeConnectServerDialogState
    extends ConsumerState<MaidCafeConnectServerDialog> {
  int? _busyServerId;
  String? _error;

  Future<void> _connect(Server server, MaidCafeServerProbe probe) async {
    setState(() {
      _busyServerId = server.id;
      _error = null;
    });
    try {
      final credential = await ref
          .read(maidCafeServerConnectorProvider)
          .connect(
            server: server,
            workspaceId: widget.workspaceId,
            probe: probe,
            ref: ref,
          );
      if (mounted) {
        Navigator.pop(
          context,
          MaidCafeConnectServerResult.connected(credential),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busyServerId = null;
          _error = error is MaidCafeException
              ? error.message
              : error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final servers = ref.watch(serversProvider);
    final daemonsAsync = ref.watch(maidCafeDaemonsProvider(widget.workspaceId));
    final daemons = daemonsAsync.asData?.value ?? const <MaidCafeDaemon>[];
    final cloudUrl = ref.watch(maidCafeCloudUrlProvider);
    final serverList = servers.asData?.value ?? const <Server>[];
    final probes = [
      for (final server in serverList)
        (
          server: server,
          probe: ref.watch(maidCafeServerProbeProvider(server.id)),
        ),
    ];
    // The manual name-only path is a fallback: it is offered only once every
    // probe has settled and no server can be connected automatically.
    final anyLoading = probes.any((entry) => entry.probe.isLoading);
    final hasConnectable =
        !anyLoading &&
        probes.any(
          (entry) => entry.probe.when(
            data: (value) => _connectable(value, cloudUrl, daemons),
            error: (_, _) => false,
            loading: () => false,
          ),
        );
    return AlertDialog(
      title: Text('maidCafeRegister'.tr()),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'maidCafeConnectHint'.tr(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            servers.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              ),
              error: (_, _) => Text('maidCafeNoServers'.tr()),
              data: (items) {
                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('maidCafeNoServers'.tr()),
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final server in items)
                      _serverRow(context, server, cloudUrl, daemons),
                  ],
                );
              },
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_busyServerId != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text('maidCafeConnectRunning'.tr()),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!anyLoading && !hasConnectable)
          TextButton(
            onPressed: _busyServerId == null
                ? () => Navigator.pop(
                    context,
                    const MaidCafeConnectServerResult.manual(),
                  )
                : null,
            child: Text('maidCafeRegisterManually'.tr()),
          ),
        TextButton(
          onPressed: _busyServerId == null
              ? () => Navigator.pop(context)
              : null,
          child: Text('maidCafeCancel'.tr()),
        ),
      ],
    );
  }

  Widget _serverRow(
    BuildContext context,
    Server server,
    String cloudUrl,
    List<MaidCafeDaemon> daemons,
  ) {
    final probe = ref.watch(maidCafeServerProbeProvider(server.id));
    final colors = Theme.of(context).colorScheme;
    return probe.when(
      loading: () => ListTile(
        dense: true,
        leading: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text(server.name),
        subtitle: Text('maidCafeProbingServer'.tr()),
        enabled: false,
      ),
      error: (error, _) => _statusRow(
        context,
        server,
        icon: const Icon(Symbols.error_outline),
        iconColor: colors.error,
        status: '${'maidCafeProbeError'.tr()} ${error.toString()}',
        enabled: false,
      ),
      data: (value) {
        final alreadyConnected =
            value.access?.id != null &&
            value.access?.cloudUrl == cloudUrl &&
            daemons.any((daemon) => daemon.id == value.access!.id);
        final (icon, status) = switch (value.status) {
          MaidCafeServerProbeStatus.disconnected => (
            const Icon(Symbols.link_off),
            'maidCafeServerNotConnected'.tr(),
          ),
          MaidCafeServerProbeStatus.notInstalled => (
            const Icon(Symbols.download),
            'maidCafeServerNotInstalled'.tr(),
          ),
          MaidCafeServerProbeStatus.installed when alreadyConnected => (
            const Icon(Symbols.check_circle),
            'maidCafeServerAlreadyConnected'.tr(),
          ),
          MaidCafeServerProbeStatus.installed => (
            const Icon(Symbols.check_circle),
            'maidCafeServerConnected'.tr(),
          ),
          MaidCafeServerProbeStatus.conflict => (
            const Icon(Symbols.warning),
            '${'maidCafeExistingInstallation'.tr()}\n'
                '${value.message ?? ''}',
          ),
          MaidCafeServerProbeStatus.error => (
            const Icon(Symbols.error_outline),
            '${'maidCafeProbeError'.tr()}\n${value.message ?? ''}',
          ),
        };
        final connectable = _connectable(value, cloudUrl, daemons);
        return _statusRow(
          context,
          server,
          icon: icon,
          iconColor: colors.onSurfaceVariant,
          status: status,
          enabled: connectable && _busyServerId == null,
          busy: _busyServerId == server.id,
          onTap: connectable && _busyServerId == null
              ? () => _connect(server, value)
              : null,
        );
      },
    );
  }

  Widget _statusRow(
    BuildContext context,
    Server server, {
    required Widget icon,
    required Color iconColor,
    required String status,
    required bool enabled,
    bool busy = false,
    VoidCallback? onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      enabled: enabled,
      leading: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconTheme(
              data: IconThemeData(color: iconColor),
              child: icon,
            ),
      title: Text(server.name),
      subtitle: Text(status, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: enabled ? const Icon(Symbols.chevron_right) : null,
      textColor: enabled ? null : colors.onSurface.withValues(alpha: 0.6),
      onTap: onTap,
    );
  }
}
