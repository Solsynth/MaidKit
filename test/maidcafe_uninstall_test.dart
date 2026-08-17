import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/maidcafe_uninstall.dart';

void main() {
  test('uninstall script requires the MaidKit ownership marker', () {
    final script = buildMaidCafeDaemonUninstallScript();

    expect(script, contains('managed_marker=/etc/maidcafe/maidkit-managed'));
    expect(
      script,
      contains(r'''[ "$(cat "$managed_marker" 2>/dev/null)" != "maidkit" ]'''),
    );
    expect(
      script,
      contains('Refusing to remove an installation that MaidKit does not own.'),
    );
    expect(script, contains('exit 1'));
  });

  test('uninstall script stops the service before removing managed files', () {
    final script = buildMaidCafeDaemonUninstallScript();

    final stop = script.indexOf('systemctl disable --now maidcafe-daemon');
    final unit = script.indexOf(
      'rm -f /etc/systemd/system/maidcafe-daemon.service',
    );
    final binary = script.indexOf('rm -f /usr/local/bin/maidcafe-daemon');
    final config = script.indexOf('rm -rf /etc/maidcafe');

    expect(stop, greaterThanOrEqualTo(0));
    expect(unit, greaterThan(stop));
    expect(binary, greaterThan(unit));
    expect(config, greaterThan(binary));
    expect(script, contains('rm -f /etc/sudoers.d/maidcafe-actions'));
  });

  test('uninstall script can preserve the dedicated account', () {
    final script = buildMaidCafeDaemonUninstallScript(removeUser: false);

    expect(script, isNot(contains('userdel --remove maidcafe')));
    expect(script, isNot(contains('userdel maidcafe')));
    expect(script, contains('rm -rf /etc/maidcafe'));
  });

  test('uninstall script optionally removes the dedicated account', () {
    final script = buildMaidCafeDaemonUninstallScript(removeUser: true);

    expect(script, contains('userdel --remove maidcafe'));
    expect(script, contains('userdel maidcafe'));
  });
}
