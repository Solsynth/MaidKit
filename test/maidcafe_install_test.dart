import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/maidcafe_install.dart';

void main() {
  test(
    'installer script encodes cloud credentials outside shell arguments',
    () {
      const secret = 'cloud-secret-with-"-quotes';
      final script = buildMaidCafeDaemonInstallScript(
        daemonId: 'daemon-1',
        cloudUrl: 'https://mk.solsynth.dev',
        cloudSecret: secret,
      );

      expect(
        script,
        contains(
          'git clone --depth 1 https://github.com/Solsynth/MaidCafe.git',
        ),
      );
      expect(script, contains('go build -trimpath'));
      expect(script, contains('/cmd/daemon'));
      expect(script, contains('printf \'%s\''));
      expect(script, contains('base64 -d'));
      expect(script, contains('/etc/maidcafe/config.toml'));
      expect(script, contains('systemctl enable --now maidcafe-daemon'));
      expect(script, isNot(contains(secret)));
    },
  );

  test('installer script escapes TOML values', () {
    final script = buildMaidCafeDaemonInstallScript(
      daemonId: 'daemon"quoted',
      cloudUrl: 'https://example.test/path?x=1',
      cloudSecret: 'secret',
    );

    expect(script, isNot(contains('daemon"quoted')));
    expect(script, isNot(contains('https://example.test/path?x=1')));
    expect(script, contains('base64 -d'));
  });

  test('stdio installer writes an SSH-stream daemon without systemd', () {
    final script = buildMaidCafeDaemonInstallScript(
      daemonId: 'daemon-1',
      cloudUrl: '',
      cloudSecret: '',
      transport: 'stdio',
      actions: const [
        MaidCafeActionDefinition(
          name: 'backup',
          command: '/usr/local/bin/backup',
          arguments: ['--mode', 'incremental'],
        ),
      ],
    );

    expect(script, contains('/etc/maidcafe/config.stdio.toml'));
    expect(script, contains('install -o root -g root -m 0644'));
    expect(script, isNot(contains('systemctl enable --now maidcafe-daemon')));
    expect(script, contains('base64 -d'));
  });
}
