import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/shared/presentation/deploy_terminal.dart';

import 'server_providers.dart';

/// Removes a MaidKit-managed MaidCafe installation from [server].
///
/// The remote script only proceeds when the MaidKit ownership marker contains
/// exactly `maidkit`. This prevents an uninstall action from deleting an
/// unrelated MaidCafe installation. Local MaidCafe credentials are cleared
/// only after the remote cleanup succeeds.
Future<void> uninstallMaidCafeApplication({
  required WidgetRef ref,
  required Server server,
  required String? sudoPassword,
  bool removeUser = false,
}) => _uninstallMaidCafe(
  ref: ref,
  server: server,
  sudoPassword: sudoPassword,
  removeUser: removeUser,
);

/// Removes a MaidKit-managed cloud MaidCafe daemon from [server].
///
/// Cloud and local MaidCafe installations use the same systemd unit and
/// managed files, so their uninstall operation is identical.
Future<void> uninstallMaidCafeDaemon({
  required WidgetRef ref,
  required Server server,
  required String? sudoPassword,
  bool removeUser = false,
}) => _uninstallMaidCafe(
  ref: ref,
  server: server,
  sudoPassword: sudoPassword,
  removeUser: removeUser,
);

Future<void> _uninstallMaidCafe({
  required WidgetRef ref,
  required Server server,
  required String? sudoPassword,
  required bool removeUser,
}) async {
  final manager = ref.read(connectionManagerProvider);
  void Function()? cancelScript;
  await runWithDeployTerminal(
    ref: ref,
    title: 'maidCafeUninstallRunning'.tr(),
    subtitle: server.name,
    command: 'stop · disable · remove MaidCafe daemon',
    onCancel: () => cancelScript?.call(),
    run: (onOutput) => manager.runPrivilegedScriptSnippet(
      server.id,
      script: buildMaidCafeDaemonUninstallScript(removeUser: removeUser),
      sshUserIsRoot: server.username == 'root',
      sudoPassword: sudoPassword,
      onOutput: onOutput,
      onCancelReady: (cancel) => cancelScript = cancel,
    ),
  );
  await ref.read(serverRepositoryProvider).clearMaidCafeConfig(server);
}

/// Builds the guarded cleanup script for a MaidKit-managed MaidCafe
/// installation.
///
/// The ownership marker is checked before any destructive operation. The
/// service is stopped before its unit, binary, configuration, and sudoers
/// drop-in are removed. When [removeUser] is true, the dedicated `maidcafe`
/// account and its home directory are removed as well.
String buildMaidCafeDaemonUninstallScript({bool removeUser = false}) {
  final userCleanup = removeUser
      ? '''
if id maidcafe >/dev/null 2>&1 && command -v userdel >/dev/null 2>&1; then
  userdel --remove maidcafe 2>/dev/null || userdel maidcafe 2>/dev/null || true
fi
'''
      : '';
  return '''set -eu
managed_marker=/etc/maidcafe/maidkit-managed
if [ ! -f "\$managed_marker" ] ||
   [ "\$(cat "\$managed_marker" 2>/dev/null)" != "maidkit" ]; then
  echo "Refusing to remove an installation that MaidKit does not own." >&2
  exit 1
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl disable --now maidcafe-daemon 2>/dev/null || true
  rm -f /etc/systemd/system/maidcafe-daemon.service
  systemctl daemon-reload 2>/dev/null || true
fi

if command -v pgrep >/dev/null 2>&1 && pgrep -x maidcafe-daemon >/dev/null 2>&1; then
  echo "MaidCafe daemon is still running; refusing to remove its binary." >&2
  exit 1
fi

rm -f /etc/sudoers.d/maidcafe-actions
rm -f /usr/local/bin/maidcafe-daemon
rm -rf /etc/maidcafe
$userCleanup''';
}
