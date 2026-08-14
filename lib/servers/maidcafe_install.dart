import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/shared/presentation/deploy_terminal.dart';

import 'maidcafe_service.dart';
import 'package_models.dart';
import 'server_providers.dart';

const _maidCafeRepository = 'https://github.com/Solsynth/MaidCafe.git';

class MaidCafeActionDefinition {
  const MaidCafeActionDefinition({
    required this.name,
    required this.command,
    required this.arguments,
  });

  final String name;
  final String command;
  final List<String> arguments;
}

/// Installs the MaidCafe daemon and enables its systemd service on [server].
///
/// The daemon is built from the upstream source because MaidCafe currently
/// publishes its daemon as a CI artifact rather than a package repository.
Future<void> installMaidCafeDaemon({
  required WidgetRef ref,
  required Server server,
  required MaidCafeDaemon daemon,
  required String cloudUrl,
  required String cloudSecret,
  required String? sudoPassword,
}) => _installMaidCafeDaemon(
  ref: ref,
  server: server,
  daemonId: daemon.id,
  cloudUrl: cloudUrl,
  cloudSecret: cloudSecret,
  sudoPassword: sudoPassword,
  transport: 'http',
  title: 'maidCafeInstallDaemonRunning'.tr(),
);

/// Installs MaidCafe in standalone stdio mode without cloud registration.
Future<void> installMaidCafeApplication({
  required WidgetRef ref,
  required Server server,
  required String? sudoPassword,
  List<MaidCafeActionDefinition> actions = const [],
}) => _installMaidCafeDaemon(
  ref: ref,
  server: server,
  daemonId: 'maidkit-${server.id}',
  cloudUrl: '',
  cloudSecret: '',
  sudoPassword: sudoPassword,
  transport: 'stdio',
  actions: actions,
  title: 'maidCafeInstallApplicationRunning'.tr(),
);

Future<void> _installMaidCafeDaemon({
  required WidgetRef ref,
  required Server server,
  required String daemonId,
  required String cloudUrl,
  required String cloudSecret,
  required String? sudoPassword,
  required String transport,
  required String title,
  List<MaidCafeActionDefinition> actions = const [],
}) async {
  final manager = ref.read(connectionManagerProvider);
  final packageManager = (await manager.getPackageManagerStatus(
    server.id,
  )).preferred;
  if (packageManager == null) {
    throw StateError('No supported system package manager was found.');
  }

  void Function()? cancelScript;
  await runWithDeployTerminal(
    ref: ref,
    title: title,
    subtitle: server.name,
    command: transport == 'stdio'
        ? 'git clone · go build · install MaidCafe stdio daemon'
        : 'git clone · go build · systemctl enable --now maidcafe-daemon',
    onCancel: () => cancelScript?.call(),
    run: (onOutput) async {
      for (final package in [
        _maidCafeGitPackage(),
        _maidCafeGoPackage(packageManager),
      ]) {
        await manager.runPackageAction(
          server.id,
          manager: packageManager,
          action: PackageAction.install,
          packageName: package,
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
          transport: transport,
          actions: actions,
        ),
        sshUserIsRoot: server.username == 'root',
        sudoPassword: sudoPassword,
        onOutput: onOutput,
        onCancelReady: (cancel) => cancelScript = cancel,
      );
    },
  );
}

/// Builds the non-interactive Linux/systemd installation script.
///
/// Configuration is encoded before it enters the shell script so the cloud
/// secret is not present in a command argument or terminal status line.
String buildMaidCafeDaemonInstallScript({
  required String daemonId,
  required String cloudUrl,
  required String cloudSecret,
  String transport = 'http',
  List<MaidCafeActionDefinition> actions = const [],
}) {
  final stdio = transport == 'stdio';
  final listenLine = stdio ? '' : ' listen = "127.0.0.1:8747"\n';
  final configPath = stdio
      ? '/etc/maidcafe/config.stdio.toml'
      : '/etc/maidcafe/config.toml';
  final configInstall = stdio
      ? 'install -o root -g root -m 0644'
      : 'install -o root -g maidcafe -m 0640';
  final serviceInstall = stdio
      ? ''
      : '''
install -o root -g root -m 0644 "\$work_dir/source/deploy/maidcafe-daemon.service" /etc/systemd/system/maidcafe-daemon.service
systemctl daemon-reload
systemctl enable --now maidcafe-daemon
''';
  final config =
      '''[daemon]
 id = ${_tomlString(daemonId)}
 transport = ${_tomlString(transport)}
$listenLine cloudUrl = ${_tomlString(cloudUrl)}
 cloudSecret = ${_tomlString(cloudSecret)}
 metricsInterval = "1m"
 requestTimeout = "10s"
 scriptTimeout = "30s"
 maxBodyBytes = 65536
 maxConcurrentRuns = 4
${_tomlActions(actions)}'''
          .replaceAll('\n ', '\n');
  final encodedConfig = base64Encode(utf8.encode(config));

  return '''set -eu
${stdio ? '' : '''command -v systemctl >/dev/null 2>&1 || {
  echo "MaidCafe daemon installation requires systemd." >&2
  exit 1
}
'''}work_dir="\$(mktemp -d "\${TMPDIR:-/tmp}/maidcafe-install.XXXXXX")"
trap 'rm -rf "\$work_dir"' EXIT

git clone --depth 1 $_maidCafeRepository "\$work_dir/source"
go build -trimpath -ldflags='-s -w' \\
  -o "\$work_dir/maidcafe-daemon" "\$work_dir/source/cmd/daemon"

${stdio ? '' : '''if ! id maidcafe >/dev/null 2>&1; then
  useradd --system --home /var/lib/maidcafe --create-home maidcafe
fi
'''}install -o root -g root -m 0755 "\$work_dir/maidcafe-daemon" /usr/local/bin/maidcafe-daemon
install -d -o root -g root -m 0755 /etc/maidcafe
printf '%s' '$encodedConfig' | base64 -d > "\$work_dir/config.toml"

$configInstall "\$work_dir/config.toml" $configPath
$serviceInstall''';
}

String _maidCafeGitPackage() => 'git';

String _maidCafeGoPackage(PackageManager manager) => switch (manager) {
  PackageManager.apt => 'golang-go',
  PackageManager.dnf || PackageManager.yum => 'golang',
  PackageManager.pacman ||
  PackageManager.zypper ||
  PackageManager.apk ||
  PackageManager.xbps ||
  PackageManager.brew => 'go',
};

String _tomlActions(List<MaidCafeActionDefinition> actions) => actions
    .map(
      (action) =>
          '''[[daemon.actions]]
name = ${_tomlString(action.name)}
command = ${_tomlString(action.command)}
args = [${action.arguments.map(_tomlString).join(', ')}]
enabled = true
notifyOnSuccess = false
notifyOnFailure = false
''',
    )
    .join();

String _tomlString(String value) =>
    '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n')}"';
