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
///
/// [workingDirectory], [user] and [environment] control how the daemon runs
/// the script. [user] switches the execution account through sudo, so the
/// daemon needs the sudoers rule MaidKit deploys for it; [environment] holds
/// KEY=VALUE assignments added to the script's environment.
class MaidCafeActionDefinition {
  const MaidCafeActionDefinition({
    required this.name,
    required this.script,
    this.enabled = true,
    this.notifyOnSuccess = false,
    this.notifyOnFailure = false,
    this.displayName,
    this.workingDirectory,
    this.user,
    this.scriptTimeout,
    this.environment = const {},
  });

  final String name;
  final String script;
  final bool enabled;
  final bool notifyOnSuccess;
  final bool notifyOnFailure;

  /// Human-readable label shown in the UI and notifications. [name] stays
  /// the API slug (route, script file, audit records); null falls back to
  /// [name] everywhere.
  final String? displayName;

  /// Absolute directory the script runs in; null keeps the daemon's own.
  final String? workingDirectory;

  /// Account the script runs as; null keeps the daemon user. Runs through
  /// sudo, so the daemon needs the sudoers rule MaidKit installs.
  final String? user;

  /// Per-action script timeout override (a duration like "30s" or "2m");
  /// null uses the daemon-wide script timeout.
  final String? scriptTimeout;

  /// KEY=VALUE assignments added to the script's environment.
  final Map<String, String> environment;

  MaidCafeActionDefinition copyWith({
    String? name,
    String? script,
    bool? enabled,
    bool? notifyOnSuccess,
    bool? notifyOnFailure,
    Object? displayName = _unset,
    Object? workingDirectory = _unset,
    Object? user = _unset,
    Object? scriptTimeout = _unset,
    Map<String, String>? environment,
  }) => MaidCafeActionDefinition(
    name: name ?? this.name,
    script: script ?? this.script,
    enabled: enabled ?? this.enabled,
    notifyOnSuccess: notifyOnSuccess ?? this.notifyOnSuccess,
    notifyOnFailure: notifyOnFailure ?? this.notifyOnFailure,
    displayName: identical(displayName, _unset)
        ? this.displayName
        : displayName as String?,
    workingDirectory: identical(workingDirectory, _unset)
        ? this.workingDirectory
        : workingDirectory as String?,
    user: identical(user, _unset) ? this.user : user as String?,
    scriptTimeout: identical(scriptTimeout, _unset)
        ? this.scriptTimeout
        : scriptTimeout as String?,
    environment: environment ?? this.environment,
  );
}

/// Sentinel for [MaidCafeActionDefinition.copyWith]: absent means "keep the
/// current value", while an explicit null clears a nullable field.
const _unset = Object();

/// One alarm condition the daemon evaluates locally. Percentage kinds use
/// [threshold]; `container_down` optionally matches [target].
class MaidCafeAlarmDefinition {
  const MaidCafeAlarmDefinition({
    required this.kind,
    this.threshold = 0,
    this.target = '',
    this.enabled = true,
    this.cooldownSeconds = 300,
  });

  final String kind;
  final double threshold;
  final String target;
  final bool enabled;
  final int cooldownSeconds;

  MaidCafeAlarmDefinition copyWith({
    String? kind,
    double? threshold,
    String? target,
    bool? enabled,
    int? cooldownSeconds,
  }) => MaidCafeAlarmDefinition(
    kind: kind ?? this.kind,
    threshold: threshold ?? this.threshold,
    target: target ?? this.target,
    enabled: enabled ?? this.enabled,
    cooldownSeconds: cooldownSeconds ?? this.cooldownSeconds,
  );
}

/// Distinct run-as users across [actions], sorted; empty when no action
/// switches users. Drives the sudoers rule and the systemd unit hardening.
List<String> maidCafeActionRunAsUsers(List<MaidCafeActionDefinition> actions) {
  final users = <String>{
    for (final action in actions)
      if (action.user?.trim().isNotEmpty ?? false) action.user!.trim(),
  }.toList();
  users.sort();
  return users;
}

/// Absolute path where an action's script body is deployed on the server.
String maidCafeActionScriptPath(MaidCafeActionDefinition action) =>
    '/etc/maidcafe/actions/${action.name}.sh';

final _maidCafeActionNamePattern = RegExp(r'^[A-Za-z0-9._-]+$');

final _maidCafeActionUserPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_.-]*$');

final _maidCafeEnvKeyPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// Go-style duration: one or more number+unit pairs, e.g. `30s`, `2m`, `1h30m`.
final _maidCafeDurationPattern = RegExp(r'^(\d+(\.\d+)?(ns|us|µs|ms|s|m|h))+$');

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

/// Builds a privileged shell snippet that deploys action script bodies and
/// config fragments to `/etc/maidcafe/actions/` and removes stale files.
///
/// Each action gets a `<name>.toml` fragment (the daemon merges every
/// fragment at load) and a `<name>.sh` script body; both are removed when the
/// action is gone. Under systemd the daemon runs as `maidcafe`, so scripts
/// are group-executable but not world-readable and fragments are group-
/// readable only; stdio mode runs as the SSH user, so they are world-
/// readable instead.
///
/// [runAsUsers] lists the distinct accounts the actions run as. When
/// non-empty the actions directory becomes group-writable for `maidcafe` (the
/// daemon renders substituted scripts into `/etc/maidcafe/actions/run` there)
/// and a sudoers drop-in grants the daemon user the right to run those scripts
/// as the listed accounts; `visudo` validates the rule before it is installed.
/// An empty list removes any stale drop-in.
String buildMaidCafeActionScriptsScript(
  List<MaidCafeActionDefinition> actions, {
  required bool stdio,
  List<String> runAsUsers = const [],
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
    final fragment = base64Encode(
      utf8.encode(maidCafeActionFragments([action])[action.name]!),
    );
    writes.add(
      "printf '%s' '$fragment' | base64 -d | "
      'install -o root -g ${stdio ? "root" : "maidcafe"} '
      '-m ${stdio ? "0644" : "0640"} /dev/stdin '
      '/etc/maidcafe/actions/${action.name}.toml',
    );
    names.add(action.name);
  }
  final keepChecks = names
      .map(
        (name) =>
            '  if [ "\$f" = "/etc/maidcafe/actions/$name.sh" ] || '
            '[ "\$f" = "/etc/maidcafe/actions/$name.toml" ]; then\n'
            '    keep=true\n'
            '  fi',
      )
      .join('\n');
  final runAs = runAsUsers.isNotEmpty;
  // install -d leaves an existing directory alone, so ownership/mode are
  // fixed explicitly when the daemon must render scripts into .run. Under
  // systemd the daemon is in the maidcafe group; in stdio mode it runs as the
  // SSH user, so the directory is owned by that account instead.
  final actionsDirInstall = runAs
      ? '''
chown ${stdio ? '"\${SUDO_USER:-\$(id -un)}"' : 'root:maidcafe'} /etc/maidcafe/actions 2>/dev/null || true
chmod 0770 /etc/maidcafe/actions
install -d -o ${stdio ? '"\${SUDO_USER:-\$(id -un)}"' : 'root'} -g ${stdio ? 'root' : 'maidcafe'} -m 0770 /etc/maidcafe/actions
install -d -o ${stdio ? '"\${SUDO_USER:-\$(id -un)}"' : 'root'} -g ${stdio ? 'root' : 'maidcafe'} -m 0770 /etc/maidcafe/actions/run'''
      : 'install -d -o root -g root -m 0755 /etc/maidcafe/actions';
  // The daemon runs as the SSH user in stdio mode; sudo sets SUDO_USER when
  // the install was elevated, so that is the account the rule must name. The
  // expression is evaluated by the install script, not written literally.
  final ruleUserExpr = stdio ? '"\${SUDO_USER:-\$(id -un)}"' : '"maidcafe"';
  final runAsList = runAsUsers.join(',');
  final sudoersBlock = runAs
      ? '''
command -v visudo >/dev/null 2>&1 || {
  echo "Running actions as another user requires visudo (sudo)." >&2
  exit 1
}
rule_user=$ruleUserExpr
sudoers_tmp="\$(mktemp "\${TMPDIR:-/tmp}/maidcafe-actions.XXXXXX")"
# User-mode actions execute the rendered script under .run; sudoers
# wildcards do not cross "/", so both segments need their own spec.
printf '%s\\n' "\$rule_user ALL=($runAsList) NOPASSWD: /etc/maidcafe/actions/run/*, /etc/maidcafe/actions/*" > "\$sudoers_tmp"
visudo -cf "\$sudoers_tmp" >/dev/null 2>&1 || {
  echo "MaidCafe rejected its own sudoers rule; no changes were made." >&2
  rm -f "\$sudoers_tmp"
  exit 1
}
install -o root -g root -m 0440 "\$sudoers_tmp" /etc/sudoers.d/maidcafe-actions
rm -f "\$sudoers_tmp"
'''
      : 'rm -f /etc/sudoers.d/maidcafe-actions';
  return '''
$actionsDirInstall
${writes.join('\n')}
for f in /etc/maidcafe/actions/*.sh /etc/maidcafe/actions/*.toml; do
  [ -e "\$f" ] || continue
  keep=false
$keepChecks
  if [ "\$keep" != true ]; then
    rm -f "\$f"
  fi
done
$sudoersBlock''';
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
  List<MaidCafeAlarmDefinition> alarms = const [],
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
  alarms: alarms,
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
  List<MaidCafeAlarmDefinition> alarms = const [],
  int port = 8747,
  String? apiSecret,
  String daemonId = '',
  String cloudUrl = '',
  String cloudSecret = '',
  String transport = 'http',
  String listenHost = '127.0.0.1',
  String metricsInterval = '1m',
  String logsInterval = '30s',
  String requestTimeout = '10s',
  String scriptTimeout = '30s',
  int maxBodyBytes = 65536,
  int maxConcurrentRuns = 4,
  bool updateOnly = false,
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
  logsInterval: logsInterval,
  requestTimeout: requestTimeout,
  scriptTimeout: scriptTimeout,
  maxBodyBytes: maxBodyBytes,
  maxConcurrentRuns: maxConcurrentRuns,
  actions: actions,
  alarms: alarms,
  title: 'maidCafeInstallApplicationRunning'.tr(),
  channel: channel,
  port: port,
  apiSecret: apiSecret ?? generateMaidCafeApiSecret(),
  updateOnly: updateOnly,
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
  String logsInterval = '30s',
  String requestTimeout = '10s',
  String scriptTimeout = '30s',
  int maxBodyBytes = 65536,
  int maxConcurrentRuns = 4,
  required String title,
  String? channel,
  List<MaidCafeActionDefinition> actions = const [],
  List<MaidCafeAlarmDefinition> alarms = const [],
  required int port,
  required String apiSecret,
  bool updateOnly = false,
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
        : updateOnly
        ? 'download · replace binary · restart systemd service'
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
          logsInterval: logsInterval,
          requestTimeout: requestTimeout,
          scriptTimeout: scriptTimeout,
          maxBodyBytes: maxBodyBytes,
          maxConcurrentRuns: maxConcurrentRuns,
          actions: actions,
          alarms: alarms,
          updateOnly: updateOnly,
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

/// The systemd unit MaidKit owns for the daemon. sudo needs its setuid bit
/// for user-switching actions, so `NoNewPrivileges` is dropped only when a
/// run-as user is configured; the install and config-sync scripts keep this
/// in lockstep with the sudoers rule. `ExecReload` lets `systemctl reload`
/// hot-reload the daemon (SIGHUP) instead of restarting it; the config API
/// needs the daemon user to be able to write /etc/maidcafe.
String _maidCafeSystemdUnit(List<String> runAsUsers) =>
    '''
[Unit]
Description=MaidCafe daemon
After=network-online.target

[Service]
User=maidcafe
Group=maidcafe
ExecStart=/usr/local/bin/maidcafe-daemon --config /etc/maidcafe/config.toml
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
${runAsUsers.isEmpty ? 'NoNewPrivileges=true' : '# NoNewPrivileges: actions run as another user through sudo'}
ReadWritePaths=/etc/maidcafe
PrivateTmp=true

[Install]
WantedBy=multi-user.target
''';

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
  String logsInterval = '30s',
  String requestTimeout = '10s',
  String scriptTimeout = '30s',
  int maxBodyBytes = 65536,
  int maxConcurrentRuns = 4,
  List<MaidCafeActionDefinition> actions = const [],
  List<MaidCafeAlarmDefinition> alarms = const [],
  // When true the script replaces only the daemon binary, records the new
  // version in the existing config and restarts the service; everything else
  // (action fragments, scripts, sudoers rule and systemd unit) is left
  // untouched, so an upgrade can never lose settings.
  bool updateOnly = false,
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
    alarms: alarms,
  );
  final runAsUsers = maidCafeActionRunAsUsers(actions);
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
      // 0660: group-writable by the daemon group so PATCH /api/v1/config can
      // persist — the unit grants ReadWritePaths=/etc/maidcafe for it.
      : 'install -o root -g maidcafe -m 0660';
  final encodedArtifactUrl = base64Encode(utf8.encode(artifactUrl));
  final binaryInstall =
      '''work_dir="\$(mktemp -d "\${TMPDIR:-/tmp}/maidcafe-install.XXXXXX")"
trap 'rm -rf "\$work_dir"' EXIT

printf '%s' '$encodedArtifactUrl' | base64 -d > "\$work_dir/artifact.url"
mkdir -p "\$work_dir/extracted"
curl --fail --location --retry 3 --silent --show-error "\$(cat "\$work_dir/artifact.url")" \\
  --output "\$work_dir/maidcafe-daemon.tar"
tar -xf "\$work_dir/maidcafe-daemon.tar" -C "\$work_dir/extracted"
daemon_binary="\$(find "\$work_dir/extracted" -type f -name maidcafe-daemon -print -quit)"
test -n "\$daemon_binary"

install -o root -g root -m 0755 "\$daemon_binary" /usr/local/bin/maidcafe-daemon
''';
  // Restart the service and verify health using the secret in the existing
  // config (never rewritten by an update).
  final restartHealth = stdio
      ? ''
      : '''
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
  // An update records the deployed version in the existing config (only the
  // `version` line is touched) so /health reports the new build; the value
  // is base64-embedded to keep arbitrary version strings out of the shell
  // and sed-escaped so the replacement cannot be misread.
  final sedEscapedVersion = _tomlString(
    version.trim(),
  ).replaceAll('\\', '\\\\').replaceAll('&', '\\&');
  final versionBump = version.trim().isEmpty
      ? ''
      : '''
new_version="\$(printf '%s' '${base64Encode(utf8.encode(sedEscapedVersion))}' | base64 -d)"
if [ -n "\$new_version" ]; then
  version_re='^version[[:space:]]*='
  if grep -q "\$version_re" /etc/maidcafe/config.toml; then
    sed -i "s/\$version_re.*/version = \$new_version/" /etc/maidcafe/config.toml
  else
    printf '\\nversion = %s\\n' "\$new_version" >> /etc/maidcafe/config.toml
  fi
fi
''';
  if (updateOnly) {
    return '''set -eu
${stdio ? '' : '''command -v systemctl >/dev/null 2>&1 || {
  echo "MaidCafe daemon installation requires systemd." >&2
  exit 1
}
'''}$binaryInstall$versionBump$restartHealth''';
  }
  final serviceInstall = stdio
      ? ''
      : '''
cat > "\$work_dir/maidcafe-daemon.service" <<'EOF'
${_maidCafeSystemdUnit(runAsUsers)}
EOF
install -o root -g root -m 0644 "\$work_dir/maidcafe-daemon.service" /etc/systemd/system/maidcafe-daemon.service
systemctl daemon-reload
systemctl enable maidcafe-daemon
$restartHealth''';
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
        logsInterval: logsInterval,
        requestTimeout: requestTimeout,
        scriptTimeout: scriptTimeout,
        maxBodyBytes: maxBodyBytes,
        maxConcurrentRuns: maxConcurrentRuns,
      ),
    ),
  );

  return '''set -eu
${stdio ? '' : '''command -v systemctl >/dev/null 2>&1 || {
  echo "MaidCafe daemon installation requires systemd." >&2
  exit 1
}
'''}${stdio ? '' : '''if ! id maidcafe >/dev/null 2>&1; then
  useradd --system --home /var/lib/maidcafe --create-home maidcafe
fi
'''}$binaryInstall
install -d -o root -g root -m 0755 /etc/maidcafe
printf '%s\n' 'maidkit' > "\$work_dir/maidkit-managed"
install -o root -g root -m 0644 "\$work_dir/maidkit-managed" /etc/maidcafe/maidkit-managed
printf '%s' '$encodedConfig' | base64 -d > "\$work_dir/config.toml"

$configInstall "\$work_dir/config.toml" $configPath
# The stable machine identity: written once and never touched again, so the
# cloud can link the host across daemon reinstalls and credential scopes.
if [ ! -f /etc/maidcafe/host-id ]; then
  host_id="\$(cat /proc/sys/kernel/random/uuid 2>/dev/null || printf '%s-%s' "\$(date +%s)" "\$\$")"
  printf '%s\\n' "\$host_id" > /etc/maidcafe/host-id
  chmod 0644 /etc/maidcafe/host-id
fi
${buildMaidCafeActionScriptsScript(actions, stdio: stdio, runAsUsers: runAsUsers)}
${buildMaidCafeAlarmFragmentsScript(alarms, stdio: stdio)}
$serviceInstall''';
}

/// Strips legacy `[[daemon.actions]]` blocks from [currentConfig]: actions now
/// live in per-file fragments, and the daemon would see both otherwise. A
/// block ends at the next table header of any kind.
String stripMaidCafeInlineActions(String currentConfig) => currentConfig
    .replaceAll(
      RegExp(r'\[\[daemon\.actions\]\](.*?)(?=\n\[\[|\Z)', dotAll: true),
      '',
    )
    .replaceAll(RegExp(r'\n{3,}'), '\n\n');

/// Patches [currentConfig] (the raw `/etc/maidcafe/config.toml` text) by
/// replacing only the keys in [values], leaving every other line — webhooks,
/// comments, unknown fields, formatting — untouched. Values are pre-formatted
/// TOML literals (strings already quoted, integers bare), written verbatim.
/// Keys absent from the `[daemon]` section are appended at its end.
String patchMaidCafeConfigText(
  String currentConfig,
  Map<String, String> values,
) {
  if (values.isEmpty) return currentConfig;
  final lines = currentConfig.split('\n');
  final missing = <String>{...values.keys};
  final result = <String>[];
  var inDaemon = false;
  var daemonEnd = -1;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('[')) {
      if (inDaemon) daemonEnd = result.length;
      inDaemon = trimmed == '[daemon]';
      result.add(line);
      continue;
    }
    if (!inDaemon) {
      result.add(line);
      continue;
    }
    var replaced = false;
    for (final entry in values.entries) {
      if (RegExp(r'^\s*' + RegExp.escape(entry.key) + r'\s*=').hasMatch(line)) {
        // Keep a trailing comment (`key = "v" # note`) attached to the line.
        final comment = RegExp(
          r'^(?:[^#]|"(?:[^"\\]|\\.)*")*(#.*)$',
        ).firstMatch(line.trimLeft());
        final suffix = comment == null ? '' : ' ${comment.group(1)}';
        result.add('${entry.key} = ${entry.value}$suffix');
        missing.remove(entry.key);
        replaced = true;
        break;
      }
    }
    if (!replaced) result.add(line);
  }
  if (inDaemon) daemonEnd = result.length;
  if (missing.isNotEmpty) {
    final insertion = missing.map((key) => '$key = ${values[key]}');
    if (daemonEnd >= 0) {
      result.insertAll(
        daemonEnd,
        ['', ...insertion, ''].where((l) => l.isNotEmpty),
      );
    } else {
      result.addAll(['', '[daemon]', ...insertion]);
    }
  }
  return result.join('\n');
}

/// Serializes a managed-upload patch (`statusUploadEnabled` bool,
/// `managedContainers` / `managedComposes` string lists) into pre-formatted
/// TOML literals for [buildMaidCafeUploadsPatchScript].
Map<String, String> maidCafeUploadsPatchTomlValues(
  Map<String, Object?> patch,
) => {
  for (final entry in patch.entries)
    entry.key: switch (entry.value) {
      final bool value => value.toString(),
      final List<String> value =>
        '[${[for (final item in value) _tomlString(item)].join(', ')}]',
      _ => throw ArgumentError.value(
        entry.value,
        entry.key,
        'must be bool or List<String>',
      ),
    },
};

/// Builds a root-owned script that patches only the managed-upload keys in
/// [values] (pre-formatted TOML literals) into the existing
/// `/etc/maidcafe/config.toml` — webhooks, comments and every other line are
/// preserved verbatim, and the installed file stays group-writable so the
/// daemon's own config API keeps working. The daemon's config watcher
/// hot-reloads the file; the caller decides whether to also reload it.
String buildMaidCafeUploadsPatchScript({
  required String currentConfig,
  required Map<String, String> values,
  bool stdio = false,
}) {
  final patched = patchMaidCafeConfigText(currentConfig, values);
  final encodedConfig = base64Encode(utf8.encode(patched));
  final configPath = stdio
      ? '/etc/maidcafe/config.stdio.toml'
      : '/etc/maidcafe/config.toml';
  final installMode = stdio ? '0644' : '0660';
  final installGroup = stdio ? 'root' : 'maidcafe';
  return '''set -eu
printf '%s' '$encodedConfig' | base64 -d | install -o root -g $installGroup -m $installMode /dev/stdin $configPath''';
}

/// Builds a root-owned MaidCafe save script: patches only the edited values
/// into the existing `/etc/maidcafe/config.toml` (webhooks, comments and any
/// other setting are preserved verbatim), migrates legacy inline
/// `[[daemon.actions]]` blocks out into fragments, deploys the action files,
/// reconciles the sudoers rule and systemd unit, and restarts the daemon.
/// The daemon binary is never replaced.
String buildMaidCafeDaemonConfigScript({
  required String currentConfig,
  required String daemonId,
  required String cloudUrl,
  required String cloudSecret,
  String transport = 'stdio',
  String listenHost = '127.0.0.1',
  int port = 8747,
  String apiSecret = '',
  String metricsInterval = '1m',
  String logsInterval = '30s',
  String requestTimeout = '10s',
  String scriptTimeout = '30s',
  int maxBodyBytes = 65536,
  int maxConcurrentRuns = 4,
  List<MaidCafeActionDefinition> actions = const [],
  List<MaidCafeAlarmDefinition> alarms = const [],
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
    alarms: alarms,
  );
  final runAsUsers = maidCafeActionRunAsUsers(actions);
  final configPath = transport == 'stdio'
      ? '/etc/maidcafe/config.stdio.toml'
      : '/etc/maidcafe/config.toml';
  // 0660: group-writable by the daemon group so PATCH /api/v1/config can
  // persist — the unit grants ReadWritePaths=/etc/maidcafe for it. Also
  // heals configs deployed by older MaidKit versions (0640).
  final installMode = transport == 'stdio' ? '0644' : '0660';
  final installGroup = transport == 'stdio' ? 'root' : 'maidcafe';
  // The unit must match the sudoers state: NoNewPrivileges blocks sudo, so it
  // is dropped exactly when a run-as user is configured.
  final serviceReconcile = transport == 'stdio'
      ? ''
      : '''
unit_tmp="\$(mktemp "\${TMPDIR:-/tmp}/maidcafe-daemon.service.XXXXXX")"
cat > "\$unit_tmp" <<'EOF'
${_maidCafeSystemdUnit(runAsUsers)}
EOF
install -o root -g root -m 0644 "\$unit_tmp" /etc/systemd/system/maidcafe-daemon.service
rm -f "\$unit_tmp"
systemctl daemon-reload
# Prefer a hot reload (SIGHUP re-reads the config); old units without
# ExecReload fall back to a restart, which picks the config up anyway.
systemctl reload maidcafe-daemon 2>/dev/null || systemctl restart maidcafe-daemon
''';
  final patched =
      patchMaidCafeConfigText(stripMaidCafeInlineActions(currentConfig), {
        'id': _tomlString(daemonId.trim()),
        'transport': _tomlString(transport.trim()),
        if (transport != 'stdio') 'listen': _tomlString('$listenHost:$port'),
        if (apiSecret.trim().isNotEmpty)
          'metricsSecret': _tomlString(apiSecret.trim()),
        'cloudUrl': _tomlString(cloudUrl.trim()),
        'cloudSecret': _tomlString(cloudSecret),
        'metricsInterval': _tomlString(metricsInterval.trim()),
        'logsInterval': _tomlString(logsInterval.trim()),
        'requestTimeout': _tomlString(requestTimeout.trim()),
        'scriptTimeout': _tomlString(scriptTimeout.trim()),
        'maxBodyBytes': '$maxBodyBytes',
        'maxConcurrentRuns': '$maxConcurrentRuns',
      });
  final encodedConfig = base64Encode(utf8.encode(patched));
  return '''set -eu
install -d -o root -g root -m 0755 /etc/maidcafe
printf '%s' '$encodedConfig' | base64 -d | install -o root -g $installGroup -m $installMode /dev/stdin $configPath
${buildMaidCafeActionScriptsScript(actions, stdio: transport == 'stdio', runAsUsers: runAsUsers)}
${buildMaidCafeAlarmFragmentsScript(alarms, stdio: transport == 'stdio')}
$serviceReconcile''';
}

void _validateMaidCafeConfigFields({
  required String listenHost,
  required int maxBodyBytes,
  required int maxConcurrentRuns,
  List<MaidCafeActionDefinition> actions = const [],
  List<MaidCafeAlarmDefinition> alarms = const [],
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
  final alarmKinds = <String>{};
  for (var i = 0; i < alarms.length; i++) {
    final alarm = alarms[i];
    if (alarm.kind != 'cpu_percent' &&
        alarm.kind != 'memory_used_percent' &&
        alarm.kind != 'disk_used_percent' &&
        alarm.kind != 'container_down') {
      throw ArgumentError.value(
        alarm.kind,
        'alarms[$i].kind',
        'must be a supported alarm kind',
      );
    }
    final key = '${alarm.kind}\u0000${alarm.target}';
    if (!alarmKinds.add(key)) {
      throw ArgumentError.value(alarm.kind, 'alarms[$i].kind', 'is duplicated');
    }
    if (alarm.kind != 'container_down' &&
        (alarm.threshold <= 0 || alarm.threshold > 100)) {
      throw ArgumentError.value(
        alarm.threshold,
        'alarms[$i].threshold',
        'must be between 0 and 100',
      );
    }
    if (alarm.kind == 'container_down' &&
        !RegExp(r'^[A-Za-z0-9_.:-]*$').hasMatch(alarm.target)) {
      throw ArgumentError.value(
        alarm.target,
        'alarms[$i].target',
        'must contain only letters, numbers, dots, underscores, colons, or hyphens',
      );
    }
    if (alarm.cooldownSeconds <= 0) {
      throw ArgumentError.value(
        alarm.cooldownSeconds,
        'alarms[$i].cooldownSeconds',
        'must be positive',
      );
    }
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
    final workingDirectory = action.workingDirectory?.trim() ?? '';
    if (workingDirectory.isNotEmpty && !workingDirectory.startsWith('/')) {
      throw ArgumentError.value(
        action.name,
        'actions[$i].workingDirectory',
        'must be an absolute path',
      );
    }
    final user = action.user?.trim() ?? '';
    if (user.isNotEmpty && !_maidCafeActionUserPattern.hasMatch(user)) {
      throw ArgumentError.value(
        action.name,
        'actions[$i].user',
        'must be a valid user name',
      );
    }
    final scriptTimeout = action.scriptTimeout?.trim() ?? '';
    if (scriptTimeout.isNotEmpty &&
        !_maidCafeDurationPattern.hasMatch(scriptTimeout)) {
      throw ArgumentError.value(
        action.name,
        'actions[$i].scriptTimeout',
        'must be a duration like 30s or 2m',
      );
    }
    for (final key in action.environment.keys) {
      if (!_maidCafeEnvKeyPattern.hasMatch(key)) {
        throw ArgumentError.value(
          action.name,
          'actions[$i].environment',
          'variable name "$key" must match [A-Za-z_][A-Za-z0-9_]*',
        );
      }
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
  String logsInterval = '30s',
  String requestTimeout = '10s',
  String scriptTimeout = '30s',
  int maxBodyBytes = 65536,
  int maxConcurrentRuns = 4,
  String actionsDir = '/etc/maidcafe/actions',
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
 logsInterval = ${_tomlString(logsInterval)}
 requestTimeout = ${_tomlString(requestTimeout)}
 scriptTimeout = ${_tomlString(scriptTimeout)}
 maxBodyBytes = $maxBodyBytes
 maxConcurrentRuns = $maxConcurrentRuns
 actionsDir = ${_tomlString(actionsDir)}
'''
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

/// Builds the `<slug>.toml` config fragment for each action, keyed by name.
/// The daemon merges every fragment in the actions directory at load, so
/// action changes never rewrite the main config file.
Map<String, String> maidCafeActionFragments(
  List<MaidCafeActionDefinition> actions,
) {
  return {
    for (final action in actions) action.name: _tomlActionFragment(action),
  };
}

/// Builds one fragment per alarm. Targeted container alarms use a distinct
/// filename so multiple containers can be monitored independently.
Map<String, String> maidCafeAlarmFragments(
  List<MaidCafeAlarmDefinition> alarms,
) {
  return {
    for (final alarm in alarms) _alarmSlug(alarm): _tomlAlarmFragment(alarm),
  };
}

String _alarmSlug(MaidCafeAlarmDefinition alarm) =>
    alarm.target.isEmpty ? alarm.kind : '${alarm.kind}_${alarm.target}';

String _tomlAlarmFragment(MaidCafeAlarmDefinition alarm) =>
    '''
kind = ${_tomlString(alarm.kind)}
${alarm.kind == 'container_down' && alarm.target.isNotEmpty ? 'target = ${_tomlString(alarm.target)}\n' : ''}threshold = ${alarm.threshold.toStringAsFixed(2)}
enabled = ${alarm.enabled}
cooldownSeconds = ${alarm.cooldownSeconds}
''';

/// Builds a privileged shell snippet that deploys alarm config fragments to
/// `/etc/maidcafe/alarms/` and removes stale files.
String buildMaidCafeAlarmFragmentsScript(
  List<MaidCafeAlarmDefinition> alarms, {
  required bool stdio,
}) {
  final writes = <String>[];
  final slugs = <String>[];
  for (final alarm in alarms) {
    final slug = _alarmSlug(alarm);
    final fragment = base64Encode(
      utf8.encode(maidCafeAlarmFragments([alarm])[slug]!),
    );
    writes.add(
      "printf '%s' '$fragment' | base64 -d | "
      'install -o root -g ${stdio ? "root" : "maidcafe"} '
      '-m ${stdio ? "0644" : "0640"} /dev/stdin '
      '/etc/maidcafe/alarms/$slug.toml',
    );
    slugs.add(slug);
  }
  final keepChecks = slugs
      .map(
        (slug) =>
            '  if [ "\$f" = "/etc/maidcafe/alarms/$slug.toml" ]; then\n'
            '    keep=true\n'
            '  fi',
      )
      .join('\n');
  return '''
install -d -o root -g root -m 0755 /etc/maidcafe/alarms
${writes.join('\n')}
for f in /etc/maidcafe/alarms/*.toml; do
  [ -e "\$f" ] || continue
  keep=false
$keepChecks
  if [ "\$keep" != true ]; then
    rm -f "\$f"
  fi
done
''';
}

String _tomlActionFragment(MaidCafeActionDefinition action) {
  final buffer = StringBuffer('''
name = ${_tomlString(action.name)}
command = ${_tomlString(maidCafeActionScriptPath(action))}
script = true
enabled = ${action.enabled}
notifyOnSuccess = ${action.notifyOnSuccess}
notifyOnFailure = ${action.notifyOnFailure}
''');
  final displayName = action.displayName?.trim() ?? '';
  if (displayName.isNotEmpty) {
    buffer.write('displayName = ${_tomlString(displayName)}\n');
  }
  final workingDirectory = action.workingDirectory?.trim() ?? '';
  if (workingDirectory.isNotEmpty) {
    buffer.write('cwd = ${_tomlString(workingDirectory)}\n');
  }
  final user = action.user?.trim() ?? '';
  if (user.isNotEmpty) {
    buffer.write('user = ${_tomlString(user)}\n');
  }
  final scriptTimeout = action.scriptTimeout?.trim() ?? '';
  if (scriptTimeout.isNotEmpty) {
    buffer.write('timeout = ${_tomlString(scriptTimeout)}\n');
  }
  if (action.environment.isNotEmpty) {
    final entries = [
      for (final entry in action.environment.entries)
        '${entry.key}=${entry.value}',
    ]..sort();
    buffer.write('env = [${entries.map(_tomlString).join(', ')}]\n');
  }
  return buffer.toString();
}

String _tomlString(String value) =>
    '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n')}"';
