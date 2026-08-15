import 'dart:math';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/shared/presentation/deploy_terminal.dart';
import 'package:maid_kit/servers/ssh_connection_manager.dart';
import 'package:solsynth_express/solsynth_express.dart';

import 'maidcafe_service.dart';
import 'package_models.dart';
import 'server_providers.dart';

const _maidCafeDistributionApiBaseUrl = String.fromEnvironment(
  'DISTRIBUTION_API_BASE_URL',
  defaultValue: 'https://api.solian.app/dist',
);
const _maidCafeDistributionProductId = '36221713-7909-4132-bfca-d800bd69fdc2';
const _maidCafeDistributionChannel = String.fromEnvironment(
  'MAIDCAFE_DISTRIBUTION_CHANNEL',
);
String generateMaidCafeApiSecret() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

/// A preset script the daemon can run on demand.
///
/// The daemon only executes absolute-path commands, so MaidKit deploys the
/// [script] body to `/etc/maidcafe/actions/<name>.sh` (root-owned,
/// executable by the `maidcafe` service user) and records that path as the
/// action's command. [script] is edited exactly like the app's snippets: a
/// multi-line shell body.
///
/// Scripts may reference `{{ name }}` template variables. When the action is
/// invoked, the requester supplies values in the request body and the daemon
/// substitutes them verbatim into the script (the SSH-authenticated runner is
/// a trusted source, so no escaping is applied). Names are free-form; there
/// is no enforced convention.
class MaidCafeActionDefinition {
  const MaidCafeActionDefinition({
    required this.name,
    required this.script,
    this.enabled = true,
    this.notifyOnSuccess = false,
    this.notifyOnFailure = false,
  });

  final String name;
  final String script;
  final bool enabled;
  final bool notifyOnSuccess;
  final bool notifyOnFailure;

  MaidCafeActionDefinition copyWith({
    String? name,
    String? script,
    bool? enabled,
    bool? notifyOnSuccess,
    bool? notifyOnFailure,
  }) => MaidCafeActionDefinition(
    name: name ?? this.name,
    script: script ?? this.script,
    enabled: enabled ?? this.enabled,
    notifyOnSuccess: notifyOnSuccess ?? this.notifyOnSuccess,
    notifyOnFailure: notifyOnFailure ?? this.notifyOnFailure,
  );
}

/// Absolute path where an action's script body is deployed on the server.
String maidCafeActionScriptPath(MaidCafeActionDefinition action) =>
    '/etc/maidcafe/actions/${action.name}.sh';

final _maidCafeActionNamePattern = RegExp(r'^[A-Za-z0-9._-]+$');

final _maidCafeTemplateVarPattern = RegExp(r'\{\{\s*([^{}]+?)\s*\}\}');

/// Extracts the `{{ name }}` template variables [script] references, in first
/// appearance order and deduplicated. Names are kept verbatim (free-form);
/// this is the vocabulary the invoker must supply values for.
List<String> maidCafeActionTemplateVariables(String script) {
  final seen = <String>{};
  final variables = <String>[];
  for (final match in _maidCafeTemplateVarPattern.allMatches(script)) {
    final name = match.group(1)!.trim();
    if (seen.add(name)) variables.add(name);
  }
  return variables;
}

/// Builds a privileged shell snippet that deploys action script bodies to
/// `/etc/maidcafe/actions/<name>.sh` and removes stale scripts.
///
/// The daemon only executes absolute-path commands (no inline scripts), so
/// bodies are installed as executables and the action's `command` points at
/// them. Under systemd the daemon runs as `maidcafe`, so scripts are
/// group-executable but not world-readable; stdio mode runs as the SSH user,
/// so they are world-executable instead.
String buildMaidCafeActionScriptsScript(
  List<MaidCafeActionDefinition> actions, {
  required bool stdio,
}) {
  final writes = <String>[];
  final names = <String>[];
  for (final action in actions) {
    final body = action.script.startsWith('#!')
        ? action.script
        : '#!/bin/sh\n${action.script}';
    final encoded = base64Encode(utf8.encode(body));
    writes.add(
      "printf '%s' '$encoded' | base64 -d | "
      'install -o root -g ${stdio ? "root" : "maidcafe"} '
      '-m ${stdio ? "0755" : "0750"} /dev/stdin '
      '/etc/maidcafe/actions/${action.name}.sh',
    );
    names.add(action.name);
  }
  final keepChecks = names
      .map(
        (name) =>
            '  if [ "\$f" = "/etc/maidcafe/actions/$name.sh" ]; then\n'
            '    keep=true\n'
            '  fi',
      )
      .join('\n');
  return '''
install -d -o root -g root -m 0755 /etc/maidcafe/actions
${writes.join('\n')}
for f in /etc/maidcafe/actions/*.sh; do
  [ -e "\$f" ] || continue
  keep=false
$keepChecks
  if [ "\$keep" != true ]; then
    rm -f "\$f"
  fi
done''';
}

class _MaidCafeArtifact {
  const _MaidCafeArtifact({required this.url, required this.version});

  final String url;
  final String version;
}

/// A published MaidCafe daemon bundle for the Linux amd64 platform.
class MaidCafeDistributionArtifact {
  const MaidCafeDistributionArtifact({
    required this.downloadUrl,
    required this.version,
  });

  final String downloadUrl;
  final String version;
}

/// Returns paths and services that would conflict with a MaidKit-managed
/// MaidCafe installation.
Future<List<String>> detectMaidCafeInstallation({
  required SshConnectionManager manager,
  required int serverId,
}) => manager.withClient(serverId, (client) async {
  final session = await client.execute(r'''
 set +e
 for path in \
   /usr/local/bin/maidcafe-daemon \
   /etc/maidcafe \
   /etc/systemd/system/maidcafe-daemon.service
 do
   if [ -e "$path" ]; then
     printf 'path:%s\n' "$path"
   fi
 done
 if [ -f /etc/maidcafe/maidkit-managed ]; then
   printf '%s\n' 'managed'
 fi
 if command -v systemctl >/dev/null 2>&1 &&
    systemctl is-active --quiet maidcafe-daemon
 then
   printf '%s\n' 'service:maidcafe-daemon(active)'
 fi
 if command -v pgrep >/dev/null 2>&1; then
   for pid in $(pgrep -x maidcafe-daemon 2>/dev/null); do
     printf 'process:maidcafe-daemon(%s)\n' "$pid"
   done
 fi
 ''');
  try {
    final output = await utf8.decoder
        .bind(session.stdout)
        .join()
        .timeout(const Duration(seconds: 15));
    await session.done.timeout(const Duration(seconds: 5));
    return output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  } finally {
    session.close();
  }
});

/// Installs the published MaidCafe daemon bundle on [server].
///
/// The bundle is fetched from Solsynth Express (internally the
/// DistributionCenter service); the remote host does not
/// need Go or a source checkout.
Future<void> installMaidCafeDaemon({
  required WidgetRef ref,
  required Server server,
  required MaidCafeDaemon daemon,
  required String cloudUrl,
  required String cloudSecret,
  required String? sudoPassword,
  String? channel,
  int port = 8747,
  String? apiSecret,
}) => _installMaidCafeDaemon(
  ref: ref,
  server: server,
  daemonId: daemon.id,
  cloudUrl: cloudUrl,
  cloudSecret: cloudSecret,
  sudoPassword: sudoPassword,
  transport: 'http',
  title: 'maidCafeInstallDaemonRunning'.tr(),
  channel: channel,
  port: port,
  apiSecret: apiSecret ?? generateMaidCafeApiSecret(),
);

/// Installs MaidCafe as a systemd-managed local HTTP daemon without cloud
Future<void> installMaidCafeApplication({
  required WidgetRef ref,
  required Server server,
  required String? sudoPassword,
  String? channel,
  List<MaidCafeActionDefinition> actions = const [],
  int port = 8747,
  String? apiSecret,
  String daemonId = '',
  String cloudUrl = '',
  String cloudSecret = '',
  String transport = 'http',
  String listenHost = '127.0.0.1',
  String metricsInterval = '1m',
  String requestTimeout = '10s',
  String scriptTimeout = '30s',
  int maxBodyBytes = 65536,
  int maxConcurrentRuns = 4,
}) => _installMaidCafeDaemon(
  ref: ref,
  server: server,
  daemonId: daemonId.isEmpty ? 'maidkit-${server.id}' : daemonId,
  cloudUrl: cloudUrl,
  cloudSecret: cloudSecret,
  sudoPassword: sudoPassword,
  transport: transport,
  listenHost: listenHost,
  metricsInterval: metricsInterval,
  requestTimeout: requestTimeout,
  scriptTimeout: scriptTimeout,
  maxBodyBytes: maxBodyBytes,
  maxConcurrentRuns: maxConcurrentRuns,
  actions: actions,
  title: 'maidCafeInstallApplicationRunning'.tr(),
  channel: channel,
  port: port,
  apiSecret: apiSecret ?? generateMaidCafeApiSecret(),
);

Future<void> _installMaidCafeDaemon({
  required WidgetRef ref,
  required Server server,
  required String daemonId,
  required String cloudUrl,
  required String cloudSecret,
  required String? sudoPassword,
  required String transport,
  String listenHost = '127.0.0.1',
  String metricsInterval = '1m',
  String requestTimeout = '10s',
  String scriptTimeout = '30s',
  int maxBodyBytes = 65536,
  int maxConcurrentRuns = 4,
  required String title,
  String? channel,
  List<MaidCafeActionDefinition> actions = const [],
  required int port,
  required String apiSecret,
}) async {
  final manager = ref.read(connectionManagerProvider);
  final packageManager = (await manager.getPackageManagerStatus(
    server.id,
  )).preferred;
  void Function()? cancelScript;
  await runWithDeployTerminal(
    ref: ref,
    title: title,
    subtitle: server.name,
    command: transport == 'stdio'
        ? 'download · install MaidCafe stdio daemon'
        : 'download · install · systemctl enable --now maidcafe-daemon',
    onCancel: () => cancelScript?.call(),
    run: (onOutput) async {
      final artifact = await _fetchMaidCafeArtifact(channel: channel);
      if (packageManager != null) {
        await manager.runPackageAction(
          server.id,
          manager: packageManager,
          action: PackageAction.install,
          packageName: _maidCafeDownloadPackage(packageManager),
          sshUserIsRoot: server.username == 'root',
          sudoPassword: sudoPassword,
          onOutput: onOutput,
        );
      } else {
        await manager.runPrivilegedScriptSnippet(
          server.id,
          script: r'''command -v curl >/dev/null 2>&1 || {
  echo "MaidCafe installation requires curl." >&2
  exit 1
}''',
          sshUserIsRoot: server.username == 'root',
          sudoPassword: sudoPassword,
          onOutput: onOutput,
        );
      }
      await manager.runPrivilegedScriptSnippet(
        server.id,
        script: buildMaidCafeDaemonInstallScript(
          daemonId: daemonId,
          cloudUrl: cloudUrl,
          cloudSecret: cloudSecret,
          artifactUrl: artifact.url,
          version: artifact.version,
          transport: transport,
          listenHost: listenHost,
          port: port,
          apiSecret: apiSecret,
          metricsInterval: metricsInterval,
          requestTimeout: requestTimeout,
          scriptTimeout: scriptTimeout,
          maxBodyBytes: maxBodyBytes,
          maxConcurrentRuns: maxConcurrentRuns,
          actions: actions,
        ),
        sshUserIsRoot: server.username == 'root',
        sudoPassword: sudoPassword,
        onOutput: onOutput,
        onCancelReady: (cancel) => cancelScript = cancel,
      );
    },
  );
  await ref
      .read(serverRepositoryProvider)
      .updateMaidCafeConfig(
        server,
        daemonUrl: 'http://$listenHost:$port',
        metricsSecret: apiSecret,
      );
}

String buildMaidCafeDaemonInstallScript({
  required String daemonId,
  required String cloudUrl,
  required String cloudSecret,
  required String artifactUrl,
  String version = '',
  String transport = 'http',
  String listenHost = '127.0.0.1',
  int port = 8747,
  String apiSecret = '',
  String metricsInterval = '1m',
  String requestTimeout = '10s',
  String scriptTimeout = '30s',
  int maxBodyBytes = 65536,
  int maxConcurrentRuns = 4,
  List<MaidCafeActionDefinition> actions = const [],
}) {
  if (transport != 'stdio' && (port < maidCafeMinimumPort || port > 65535)) {
    throw ArgumentError.value(
      port,
      'port',
      'must be between $maidCafeMinimumPort and 65535',
    );
  }
  _validateMaidCafeConfigFields(
    listenHost: listenHost,
    maxBodyBytes: maxBodyBytes,
    maxConcurrentRuns: maxConcurrentRuns,
    actions: actions,
  );
  final resolvedApiSecret = apiSecret.trim().isEmpty
      ? generateMaidCafeApiSecret()
      : apiSecret.trim();
  final healthUrl = 'http://$listenHost:$port/health';
  final stdio = transport == 'stdio';
  final configPath = stdio
      ? '/etc/maidcafe/config.stdio.toml'
      : '/etc/maidcafe/config.toml';
  final configInstall = stdio
      ? 'install -o root -g root -m 0644'
      : 'install -o root -g maidcafe -m 0640';
  final serviceInstall = stdio
      ? ''
      : '''
cat > "\$work_dir/maidcafe-daemon.service" <<'EOF'
[Unit]
Description=MaidCafe daemon
After=network-online.target

[Service]
User=maidcafe
Group=maidcafe
ExecStart=/usr/local/bin/maidcafe-daemon --config /etc/maidcafe/config.toml
Restart=on-failure
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
install -o root -g root -m 0644 "\$work_dir/maidcafe-daemon.service" /etc/systemd/system/maidcafe-daemon.service
systemctl daemon-reload
systemctl enable maidcafe-daemon
systemctl restart maidcafe-daemon
metricsSecret="\$(awk -F'"' '/metricsSecret[[:space:]]*=/{print \$2; exit}' /etc/maidcafe/config.toml)"
 i=0
 while [ "\$i" -lt 10 ]; do
   if curl --fail --silent --max-time 2 \\
     -H "Authorization: Bearer \$metricsSecret" $healthUrl >/dev/null
   then
     break
   fi
   i=\$((i + 1))
   sleep 1
 done
 if ! curl --fail --silent --show-error --max-time 2 \\
   -H "Authorization: Bearer \$metricsSecret" $healthUrl >/dev/null
then
  echo "MaidCafe daemon did not become healthy." >&2
  systemctl status maidcafe-daemon --no-pager || true
  journalctl -u maidcafe-daemon -n 50 --no-pager || true
  exit 1
fi
''';
  final encodedConfig = base64Encode(
    utf8.encode(
      _maidCafeConfig(
        daemonId: daemonId,
        cloudUrl: cloudUrl,
        cloudSecret: cloudSecret,
        metricsSecret: resolvedApiSecret,
        version: version,
        port: port,
        transport: transport,
        listenHost: listenHost,
        metricsInterval: metricsInterval,
        requestTimeout: requestTimeout,
        scriptTimeout: scriptTimeout,
        maxBodyBytes: maxBodyBytes,
        maxConcurrentRuns: maxConcurrentRuns,
        actions: actions,
      ),
    ),
  );
  final encodedArtifactUrl = base64Encode(utf8.encode(artifactUrl));

  return '''set -eu
${stdio ? '' : '''command -v systemctl >/dev/null 2>&1 || {
  echo "MaidCafe daemon installation requires systemd." >&2
  exit 1
}
'''}work_dir="\$(mktemp -d "\${TMPDIR:-/tmp}/maidcafe-install.XXXXXX")"
trap 'rm -rf "\$work_dir"' EXIT

printf '%s' '$encodedArtifactUrl' | base64 -d > "\$work_dir/artifact.url"
mkdir -p "\$work_dir/extracted"
curl --fail --location --retry 3 --silent --show-error "\$(cat "\$work_dir/artifact.url")" \\
  --output "\$work_dir/maidcafe-daemon.tar"
tar -xf "\$work_dir/maidcafe-daemon.tar" -C "\$work_dir/extracted"
daemon_binary="\$(find "\$work_dir/extracted" -type f -name maidcafe-daemon -print -quit)"
test -n "\$daemon_binary"

${stdio ? '' : '''if ! id maidcafe >/dev/null 2>&1; then
  useradd --system --home /var/lib/maidcafe --create-home maidcafe
fi
'''}install -o root -g root -m 0755 "\$daemon_binary" /usr/local/bin/maidcafe-daemon
install -d -o root -g root -m 0755 /etc/maidcafe
printf '%s\n' 'maidkit' > "\$work_dir/maidkit-managed"
install -o root -g root -m 0644 "\$work_dir/maidkit-managed" /etc/maidcafe/maidkit-managed
printf '%s' '$encodedConfig' | base64 -d > "\$work_dir/config.toml"

$configInstall "\$work_dir/config.toml" $configPath
${buildMaidCafeActionScriptsScript(actions, stdio: stdio)}
$serviceInstall''';
}

/// Builds a root-owned MaidCafe configuration update without replacing the
/// daemon binary.
String buildMaidCafeDaemonConfigScript({
  required String daemonId,
  required String cloudUrl,
  required String cloudSecret,
  String version = '',
  String transport = 'stdio',
  String listenHost = '127.0.0.1',
  int port = 8747,
  String apiSecret = '',
  String metricsInterval = '1m',
  String requestTimeout = '10s',
  String scriptTimeout = '30s',
  int maxBodyBytes = 65536,
  int maxConcurrentRuns = 4,
  List<MaidCafeActionDefinition> actions = const [],
}) {
  if (transport != 'stdio' && (port < maidCafeMinimumPort || port > 65535)) {
    throw ArgumentError.value(
      port,
      'port',
      'must be between $maidCafeMinimumPort and 65535',
    );
  }
  _validateMaidCafeConfigFields(
    listenHost: listenHost,
    maxBodyBytes: maxBodyBytes,
    maxConcurrentRuns: maxConcurrentRuns,
    actions: actions,
  );
  final configPath = transport == 'stdio'
      ? '/etc/maidcafe/config.stdio.toml'
      : '/etc/maidcafe/config.toml';
  final resolvedApiSecret = transport == 'stdio' || apiSecret.trim().isNotEmpty
      ? apiSecret.trim()
      : generateMaidCafeApiSecret();
  final installMode = transport == 'stdio' ? '0644' : '0640';
  final installGroup = transport == 'stdio' ? 'root' : 'maidcafe';
  final serviceRestart = transport == 'stdio'
      ? ''
      : 'systemctl restart maidcafe-daemon\n';
  final encodedConfig = base64Encode(
    utf8.encode(
      _maidCafeConfig(
        daemonId: daemonId,
        cloudUrl: cloudUrl,
        version: version,
        cloudSecret: cloudSecret,
        metricsSecret: resolvedApiSecret,
        port: port,
        transport: transport,
        listenHost: listenHost,
        metricsInterval: metricsInterval,
        requestTimeout: requestTimeout,
        scriptTimeout: scriptTimeout,
        maxBodyBytes: maxBodyBytes,
        maxConcurrentRuns: maxConcurrentRuns,
        actions: actions,
      ),
    ),
  );
  return '''set -eu
install -d -o root -g root -m 0755 /etc/maidcafe
printf '%s\n' 'maidkit' | install -o root -g root -m 0644 /dev/stdin /etc/maidcafe/maidkit-managed
printf '%s' '$encodedConfig' | base64 -d | install -o root -g $installGroup -m $installMode /dev/stdin $configPath
${buildMaidCafeActionScriptsScript(actions, stdio: transport == 'stdio')}
$serviceRestart''';
}

void _validateMaidCafeConfigFields({
  required String listenHost,
  required int maxBodyBytes,
  required int maxConcurrentRuns,
  List<MaidCafeActionDefinition> actions = const [],
}) {
  if (!RegExp(r'^[A-Za-z0-9_.:-]+$').hasMatch(listenHost)) {
    throw ArgumentError.value(
      listenHost,
      'listenHost',
      'contains invalid characters',
    );
  }
  if (maxBodyBytes <= 0) {
    throw ArgumentError.value(maxBodyBytes, 'maxBodyBytes', 'must be positive');
  }
  if (maxConcurrentRuns <= 0) {
    throw ArgumentError.value(
      maxConcurrentRuns,
      'maxConcurrentRuns',
      'must be positive',
    );
  }
  for (var i = 0; i < actions.length; i++) {
    final action = actions[i];
    if (!_maidCafeActionNamePattern.hasMatch(action.name)) {
      throw ArgumentError.value(
        action.name,
        'actions[$i].name',
        'must match [A-Za-z0-9._-]+',
      );
    }
    if (action.script.trim().isEmpty) {
      throw ArgumentError.value(
        action.name,
        'actions[$i].script',
        'must not be empty',
      );
    }
  }
}

String _maidCafeConfig({
  required String daemonId,
  required String cloudUrl,
  required String cloudSecret,
  String metricsSecret = '',
  String version = '',
  int port = 8747,
  required String transport,
  String listenHost = '127.0.0.1',
  String metricsInterval = '1m',
  String requestTimeout = '10s',
  String scriptTimeout = '30s',
  int maxBodyBytes = 65536,
  int maxConcurrentRuns = 4,
  required List<MaidCafeActionDefinition> actions,
}) {
  final versionLine = version.trim().isEmpty
      ? ''
      : ' version = ${_tomlString(version.trim())}\n';
  final listenLine = transport == 'stdio'
      ? ''
      : ' listen = ${_tomlString('$listenHost:$port')}\n';
  final metricsSecretLine = metricsSecret.trim().isEmpty
      ? ''
      : ' metricsSecret = ${_tomlString(metricsSecret.trim())}\n';
  return '''[daemon]
 id = ${_tomlString(daemonId)}
$versionLine transport = ${_tomlString(transport)}
$listenLine$metricsSecretLine cloudUrl = ${_tomlString(cloudUrl)}
 cloudSecret = ${_tomlString(cloudSecret)}
 metricsInterval = ${_tomlString(metricsInterval)}
 requestTimeout = ${_tomlString(requestTimeout)}
 scriptTimeout = ${_tomlString(scriptTimeout)}
 maxBodyBytes = $maxBodyBytes
 maxConcurrentRuns = $maxConcurrentRuns
${_tomlActions(actions)}'''
      .replaceAll('\n ', '\n');
}

/// Returns the currently published MaidCafe channels.
Future<List<DistributionChannel>> fetchMaidCafeDistributionChannels() async {
  final endpoint = Uri.parse(
    '$_maidCafeDistributionApiBaseUrl/products/'
    '$_maidCafeDistributionProductId/channels',
  );
  try {
    return await SolsynthExpressApi(
      baseUrl: _maidCafeDistributionApiBaseUrl,
      productId: _maidCafeDistributionProductId,
    ).listChannels();
  } on DioException catch (error) {
    final status = error.response?.statusCode;
    final statusSuffix = status == null ? '' : ' (HTTP $status)';
    throw StateError(
      'MaidCafe channel lookup failed$statusSuffix.\n'
      'URL: $endpoint',
    );
  }
}

/// Returns the latest published MaidCafe release tag for [channel].
Future<String> fetchMaidCafeLatestVersion({String? channel}) async =>
    (await fetchMaidCafeDistributionArtifact(channel: channel)).version;

/// Resolves the latest published MaidCafe bundle for [channel].
///
/// Used by the install preview so the script shown to the user matches the
/// artifact the install flow will actually download.
Future<MaidCafeDistributionArtifact> fetchMaidCafeDistributionArtifact({
  String? channel,
}) async {
  final artifact = await _fetchMaidCafeArtifact(channel: channel);
  return MaidCafeDistributionArtifact(
    downloadUrl: artifact.url,
    version: artifact.version,
  );
}

Future<_MaidCafeArtifact> _fetchMaidCafeArtifact({String? channel}) async {
  final api = SolsynthExpressApi(
    baseUrl: _maidCafeDistributionApiBaseUrl,
    productId: _maidCafeDistributionProductId,
  );
  final channelsEndpoint = Uri.parse(
    '$_maidCafeDistributionApiBaseUrl/products/'
    '$_maidCafeDistributionProductId/channels',
  );
  final channels = await fetchMaidCafeDistributionChannels();
  if (channels.isEmpty) {
    throw StateError(
      'MaidCafe has no published distribution channels.\n'
      'URL: $channelsEndpoint',
    );
  }

  final requestedChannel = (channel ?? _maidCafeDistributionChannel).trim();
  DistributionChannel? selectedChannel;
  if (requestedChannel.isNotEmpty) {
    for (final channel in channels) {
      if (channel.name == requestedChannel || channel.id == requestedChannel) {
        selectedChannel = channel;
        break;
      }
    }
    if (selectedChannel == null) {
      throw StateError(
        'MaidCafe distribution channel "$requestedChannel" is unavailable. '
        'Available channels: ${channels.map((channel) => channel.name).join(', ')}.\n'
        'URL: $channelsEndpoint',
      );
    }
  } else {
    for (final channel in channels) {
      if (channel.latest?.artifactFor('linux', 'amd64') != null) {
        selectedChannel = channel;
        break;
      }
    }
  }
  if (selectedChannel == null) {
    throw StateError(
      'No MaidCafe distribution channel has a Linux amd64 artifact. '
      'Available channels: ${channels.map((channel) => channel.name).join(', ')}.\n'
      'URL: $channelsEndpoint',
    );
  }

  final channelName = selectedChannel.name;
  final endpoint =
      Uri.parse(
        '$_maidCafeDistributionApiBaseUrl/products/'
        '$_maidCafeDistributionProductId/releases',
      ).replace(
        queryParameters: {
          'channel': channelName,
          'platform': 'linux',
          'architecture': 'amd64',
          'limit': '1',
          'offset': '0',
        },
      );
  DistributionReleaseInfo? release;
  try {
    release = await api.fetchLatestRelease(
      channel: channelName,
      platform: 'linux',
      architecture: 'amd64',
    );
  } on DioException catch (error) {
    final status = error.response?.statusCode;
    final statusSuffix = status == null ? '' : ' (HTTP $status)';
    throw StateError(
      'MaidCafe artifact lookup failed$statusSuffix.\n'
      'URL: $endpoint',
    );
  }
  final releaseInfo = release;
  final artifact = releaseInfo?.artifactFor('linux', 'amd64');
  if (artifact == null || releaseInfo == null) {
    throw StateError(
      'No MaidCafe Linux amd64 artifact is available in the '
      '"$channelName" channel.\n'
      'URL: $endpoint',
    );
  }
  return _MaidCafeArtifact(
    url: artifact.downloadUrl,
    version: releaseInfo.tagName,
  );
}

String _maidCafeDownloadPackage(PackageManager manager) => switch (manager) {
  PackageManager.apt ||
  PackageManager.dnf ||
  PackageManager.yum ||
  PackageManager.pacman ||
  PackageManager.zypper ||
  PackageManager.apk ||
  PackageManager.xbps ||
  PackageManager.brew => 'curl',
};

String _tomlActions(List<MaidCafeActionDefinition> actions) => actions
    .map(
      (action) =>
          '''[[daemon.actions]]
name = ${_tomlString(action.name)}
command = ${_tomlString(maidCafeActionScriptPath(action))}
args = []
script = true
enabled = ${action.enabled}
notifyOnSuccess = ${action.notifyOnSuccess}
notifyOnFailure = ${action.notifyOnFailure}
''',
    )
    .join();

String _tomlString(String value) =>
    '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n')}"';
