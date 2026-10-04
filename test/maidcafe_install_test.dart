import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/maidcafe_install.dart';
import 'package:maid_kit/servers/maidcafe_priv.dart';
import 'package:maid_kit/servers/maidcafe_uninstall.dart';

/// A realistic existing `/etc/maidcafe/config.toml` for patch-based saves.
const _baseConfig = '''
# MaidKit-managed daemon
[daemon]
 id = "maidkit-1"
 transport = "http"
 listen = "127.0.0.1:8747"
 metricsSecret = "metrics-secret"
 cloudUrl = "https://mkc.solsynth.dev"
 cloudSecret = "cloud-secret"
 metricsInterval = "1m"
 requestTimeout = "10s"
 scriptTimeout = "30s"
 maxBodyBytes = 65536
 maxConcurrentRuns = 4
 actionsDir = "/etc/maidcafe/actions"

[[daemon.webhooks]]
name = "ci-deploy"
secret = "webhook-secret"
command = "/usr/local/bin/deploy"
enabled = true
''';

/// Decodes the daemon config.toml embedded in a generated script so tests can
/// assert on the TOML the daemon will actually load.
String decodeMaidCafeConfigFromScript(String script) {
  final install = RegExp(
    r'''printf '%s' '([^']+)' \| base64 -d > "\$work_dir/config\.toml"''',
  ).firstMatch(script);
  if (install != null) {
    return utf8.decode(base64Decode(install.group(1)!));
  }
  final update = RegExp(
    r'''printf '%s' '([^']+)' \| base64 -d \| install''',
  ).firstMatch(script);
  if (update != null) {
    return utf8.decode(base64Decode(update.group(1)!));
  }
  fail('no embedded config.toml found in generated script');
}

/// Decodes the `<name>.toml` action fragment deployed by a generated script.
String decodeFragmentFromScript(String script, String name) {
  final match = RegExp(
    "printf '%s' '([^']+)' \\| base64 -d \\| "
    r'install -o root -g \S+ -m \S+ /dev/stdin '
    '/etc/maidcafe/actions/$name\\.toml',
  ).firstMatch(script);
  if (match == null) {
    fail('no fragment deploy for $name in generated script');
  }
  return utf8.decode(base64Decode(match.group(1)!));
}

/// Decodes the `<kind>.toml` alarm fragment deployed by a generated script.
String decodeAlarmFragmentFromScript(String script, String kind) {
  final match = RegExp(
    "printf '%s' '([^']+)' \\| base64 -d \\| "
    r'install -o root -g \S+ -m \S+ /dev/stdin '
    '/etc/maidcafe/alarms/$kind\\.toml',
  ).firstMatch(script);
  if (match == null) {
    fail('no alarm fragment deploy for $kind in generated script');
  }
  return utf8.decode(base64Decode(match.group(1)!));
}

/// Decodes the `/etc/maidkit/priv.toml` payload a generated script installs, so
/// a test asserts on the grant file itself rather than on a comment near it.
String decodePrivTomlFromScript(String script) {
  final match = RegExp(
    r"printf '%s' '([A-Za-z0-9+/=]+)' \| base64 -d \| "
    r'install -o root -g root -m 0644 /dev/stdin /etc/maidkit/priv\.toml',
  ).firstMatch(script);
  if (match == null) {
    fail('no embedded priv.toml found in generated script');
  }
  return utf8.decode(base64Decode(match.group(1)!));
}

/// The daemon config an install script writes, decoded from the base64 it
/// carries. Grepping the script for config text would pass on the comment above
/// the payload; decoding checks what the daemon will actually read.
String configFromInstallScript(String script) {
  final match = RegExp(
    r'''printf '%s' '([A-Za-z0-9+/=]+)' \| base64 -d > "\$work_dir/config.toml"''',
  ).firstMatch(script);
  expect(match, isNotNull, reason: 'no embedded config found');
  return utf8.decode(base64Decode(match!.group(1)!));
}

void main() {
  test('enabling the terminal always writes a shell allowlist', () {
    // The daemon rejects a configuration that enables the terminal — directly
    // or through the relay — with no shells, and a rejected configuration
    // leaves it running the policy it already had, so the switch would read as
    // on while every session is still refused.
    final script = buildMaidCafeDaemonConfigScript(
      currentConfig: '[daemon]\nlisten = "127.0.0.1:8747"\n',
      daemonId: 'daemon-1',
      cloudUrl: 'https://cloud.example',
      cloudSecret: 'cloud-secret',
      apiSecret: 'metrics-secret',
      transport: 'http',
      terminalEnabled: true,
    );
    final config = decodeMaidCafeConfigFromScript(script);

    expect(config, contains('enabled = true'));
    expect(config, contains('shells = ["/bin/bash"]'));
  });

  test('the relay opt-in also gets a shell allowlist', () {
    final script = buildMaidCafeDaemonConfigScript(
      currentConfig: '[daemon]\nlisten = "127.0.0.1:8747"\n',
      daemonId: 'daemon-1',
      cloudUrl: 'https://cloud.example',
      cloudSecret: 'cloud-secret',
      apiSecret: 'metrics-secret',
      transport: 'stdio',
      terminalRelayEnabled: true,
    );
    final config = decodeMaidCafeConfigFromScript(script);

    expect(config, contains('shells = ["/bin/bash"]'));
  });

  test('a terminal that is not enabled keeps the shells the daemon has', () {
    final script = buildMaidCafeDaemonConfigScript(
      currentConfig:
          '[daemon]\nlisten = "127.0.0.1:8747"\n\n'
          '[daemon.terminal]\nenabled = false\n'
          'shells = ["/bin/zsh"]\n',
      daemonId: 'daemon-1',
      cloudUrl: 'https://cloud.example',
      cloudSecret: 'cloud-secret',
      apiSecret: 'metrics-secret',
      transport: 'http',
    );
    final config = decodeMaidCafeConfigFromScript(script);

    expect(config, contains('shells = ["/bin/zsh"]'));
    expect(config, isNot(contains('/bin/bash')));
  });

  test('the config script writes the daemon terminal table', () {
    final script = buildMaidCafeDaemonConfigScript(
      currentConfig: '[daemon]\nlisten = "127.0.0.1:8747"\n',
      daemonId: 'daemon-1',
      cloudUrl: 'https://cloud.example',
      cloudSecret: 'cloud-secret',
      apiSecret: 'metrics-secret',
      transport: 'http',
      terminalEnabled: true,
      terminalSecret: 'terminal-secret',
      terminalAllowedOrigins: ['https://app.example'],
    );
    final config = decodeMaidCafeConfigFromScript(script);

    expect(config, contains('[daemon.terminal]'));
    expect(config, contains('enabled = true'));
    expect(config, contains('secret = "terminal-secret"'));
    expect(config, contains('allowedOrigins = ["https://app.example"]'));
    // The daemon table keeps being written as before.
    expect(config, contains('id = "daemon-1"'));
    expect(config, contains('listen = "127.0.0.1:8747"'));
  });

  test('the run-as allowlist is written, and only when it is owned', () {
    // A caller that names accounts writes them.
    final named = decodeMaidCafeConfigFromScript(
      buildMaidCafeDaemonConfigScript(
        currentConfig: '[daemon]\nlisten = "127.0.0.1:8747"\n',
        daemonId: 'daemon-1',
        cloudUrl: 'https://cloud.example',
        cloudSecret: 'cloud-secret',
        apiSecret: 'metrics-secret',
        transport: 'http',
        terminalEnabled: true,
        terminalUsers: const ['deploy', 'nginx'],
      ),
    );
    expect(named, contains('users = ["deploy", "nginx"]'));

    // A caller that does not model the list leaves an operator's own one alone,
    // even while it writes the rest of the terminal table.
    final untouched = decodeMaidCafeConfigFromScript(
      buildMaidCafeDaemonConfigScript(
        currentConfig:
            '[daemon]\nlisten = "127.0.0.1:8747"\n\n'
            '[daemon.terminal]\nenabled = true\n'
            'users = ["operator"]\n',
        daemonId: 'daemon-1',
        cloudUrl: 'https://cloud.example',
        cloudSecret: 'cloud-secret',
        apiSecret: 'metrics-secret',
        transport: 'http',
        terminalEnabled: true,
      ),
    );
    expect(untouched, contains('users = ["operator"]'));

    // An empty list from a caller that owns the key clears it.
    final cleared = decodeMaidCafeConfigFromScript(
      buildMaidCafeDaemonConfigScript(
        currentConfig:
            '[daemon]\nlisten = "127.0.0.1:8747"\n\n'
            '[daemon.terminal]\nenabled = true\n'
            'users = ["operator"]\n',
        daemonId: 'daemon-1',
        cloudUrl: 'https://cloud.example',
        cloudSecret: 'cloud-secret',
        apiSecret: 'metrics-secret',
        transport: 'http',
        terminalEnabled: true,
        terminalUsers: const [],
      ),
    );
    expect(cleared, contains('users = []'));
    expect(cleared, isNot(contains('"operator"')));

    // Nothing to write and nothing to clear: the key is not invented.
    final absent = decodeMaidCafeConfigFromScript(
      buildMaidCafeDaemonConfigScript(
        currentConfig: '[daemon]\nlisten = "127.0.0.1:8747"\n',
        daemonId: 'daemon-1',
        cloudUrl: 'https://cloud.example',
        cloudSecret: 'cloud-secret',
        apiSecret: 'metrics-secret',
        transport: 'http',
        terminalEnabled: true,
        terminalUsers: const [],
      ),
    );
    expect(absent, isNot(contains('users =')));
  });

  test('the terminal origin list defaults to the hosted web build', () {
    final script = buildMaidCafeDaemonConfigScript(
      currentConfig: '[daemon]\nlisten = "127.0.0.1:8747"\n',
      daemonId: 'daemon-1',
      cloudUrl: 'https://cloud.example',
      cloudSecret: 'cloud-secret',
      apiSecret: 'metrics-secret',
      transport: 'http',
      terminalEnabled: true,
    );
    final config = decodeMaidCafeConfigFromScript(script);

    expect(config, contains('allowedOrigins = ["https://mkw.solsynth.dev"]'));
  });

  test('an existing terminal origin list is not replaced', () {
    final script = buildMaidCafeDaemonConfigScript(
      currentConfig:
          '[daemon]\nlisten = "127.0.0.1:8747"\n\n'
          '[daemon.terminal]\nenabled = true\n'
          'allowedOrigins = ["https://mine.example"]\n',
      daemonId: 'daemon-1',
      cloudUrl: 'https://cloud.example',
      cloudSecret: 'cloud-secret',
      apiSecret: 'metrics-secret',
      transport: 'http',
      terminalEnabled: true,
    );
    final config = decodeMaidCafeConfigFromScript(script);

    expect(config, contains('https://mine.example'));
    expect(config, isNot(contains('mkw.solsynth.dev')));
  });

  test('the config script can opt the daemon into relayed sessions', () {
    final script = buildMaidCafeDaemonConfigScript(
      currentConfig: '[daemon]\nlisten = "127.0.0.1:8747"\n',
      daemonId: 'daemon-1',
      cloudUrl: 'https://cloud.example',
      cloudSecret: 'cloud-secret',
      apiSecret: 'metrics-secret',
      transport: 'http',
      terminalRelayEnabled: true,
    );
    final config = decodeMaidCafeConfigFromScript(script);

    expect(config, contains('[daemon.terminal.relay]'));
    expect(config, contains('enabled = true'));
    // The direct endpoint is a separate switch and stays unmentioned.
    expect(config, isNot(contains('[daemon.terminal]\nenabled')));
  });

  test('the config script leaves an unknown terminal switch alone', () {
    final script = buildMaidCafeDaemonConfigScript(
      currentConfig:
          '[daemon]\nlisten = "127.0.0.1:8747"\n\n'
          '[daemon.terminal]\nenabled = true\n',
      daemonId: 'daemon-1',
      cloudUrl: 'https://cloud.example',
      cloudSecret: 'cloud-secret',
      apiSecret: 'metrics-secret',
      transport: 'http',
    );
    final config = decodeMaidCafeConfigFromScript(script);

    // Nothing was known about the switch, so the daemon's own stays as it is.
    expect(config, contains('enabled = true'));
  });

  test(
    'installer script encodes cloud credentials outside shell arguments',
    () {
      const secret = 'cloud-secret-with-"-quotes';
      final script = buildMaidCafeDaemonInstallScript(
        daemonId: 'daemon-1',
        cloudUrl: 'https://mkc.solsynth.dev',
        cloudSecret: secret,
        artifactUrl: 'https://dist.example/maidcafe-daemon.tar',
        apiSecret: 'metrics-secret',
      );

      expect(script, contains('curl --fail --location'));
      expect(script, contains('tar -xf "\$work_dir/maidcafe-daemon.tar"'));
      expect(script, contains('find "\$work_dir/extracted"'));
      expect(script, contains('/usr/local/bin/maidcafe-daemon'));
      expect(script, contains('/etc/maidcafe/config.toml'));
      expect(script, contains('printf \'%s\''));
      expect(script, contains('base64 -d'));
      expect(script, contains('http://127.0.0.1:8747/health'));
      // Group-writable by the daemon group: PATCH /api/v1/config persists
      // through the daemon itself (the unit grants ReadWritePaths for it).
      expect(script, contains('install -o root -g maidcafe -m 0660 '));
      expect(script, contains('Authorization: Bearer \$metricsSecret'));
      expect(script, contains('systemctl restart maidcafe-daemon'));
      expect(script, contains('MaidCafe daemon did not become healthy.'));
      expect(script, contains('maidkit-managed'));
      expect(script, isNot(contains('git clone')));
      expect(script, isNot(contains('go build')));
      expect(script, isNot(contains(secret)));
      expect(
        script,
        isNot(contains('https://dist.example/maidcafe-daemon.tar')),
      );
    },
  );

  test('uploads patch script rewrites only the managed keys', () {
    const base =
        '# kept comment\n[daemon]\nid = "host-1"\n'
        'logsUploadEnabled = false\nmanagedContainers = ["old"]\n\n'
        '[[daemon.actions]]\nname = "keep"\ncommand = "/bin/true"\n';
    final script = buildMaidCafeUploadsPatchScript(
      currentConfig: base,
      values: maidCafeUploadsPatchTomlValues({
        'statusUploadEnabled': true,
        'managedContainers': ['web', 'db-'],
        'managedComposes': ['myapp'],
      }),
    );
    expect(script, contains('install -o root -g maidcafe -m 0660 /dev/stdin '));
    final match = RegExp(
      "printf '%s' '([^']+)' \\| base64 -d",
    ).firstMatch(script);
    if (match == null) {
      fail('no embedded config in generated script');
    }
    final patched = utf8.decode(base64Decode(match.group(1)!));
    expect(patched, contains('# kept comment'));
    expect(patched, contains('statusUploadEnabled = true'));
    expect(patched, contains('managedContainers = ["web", "db-"]'));
    expect(patched, contains('managedComposes = ["myapp"]'));
    expect(patched, contains('name = "keep"'));
    expect(patched, isNot(contains('"old"')));
  });

  test('installer script escapes TOML values', () {
    final script = buildMaidCafeDaemonInstallScript(
      daemonId: 'daemon"quoted',
      cloudUrl: 'https://example.test/path?x=1',
      cloudSecret: 'secret',
      artifactUrl: 'https://dist.example/maidcafe-daemon.tar',
    );

    expect(script, isNot(contains('daemon"quoted')));
    expect(script, isNot(contains('https://example.test/path?x=1')));
    expect(script, contains('base64 -d'));
  });

  test('fresh installs write base config and per-action fragments', () {
    const body = 'tar -czf /var/backups/site.tar.gz /srv/site\n';
    final script = buildMaidCafeDaemonInstallScript(
      daemonId: 'daemon-1',
      cloudUrl: '',
      cloudSecret: '',
      artifactUrl: 'https://dist.example/maidcafe-daemon.tar',
      actions: const [
        MaidCafeActionDefinition(
          name: 'backup',
          script: body,
          notifyOnSuccess: true,
        ),
      ],
    );

    // The base config carries no actions; they live in fragments.
    final config = decodeMaidCafeConfigFromScript(script);
    expect(config, isNot(contains('[[daemon.actions]]')));
    expect(config, contains('actionsDir = "/etc/maidcafe/actions"'));
    // The fragment and script body are both deployed.
    final fragment = decodeFragmentFromScript(script, 'backup');
    expect(fragment, contains('name = "backup"'));
    expect(fragment, contains('command = "/etc/maidcafe/actions/backup.sh"'));
    expect(fragment, contains('script = true'));
    expect(fragment, contains('notifyOnSuccess = true'));
    expect(script, isNot(contains(body)));
    expect(
      script,
      contains(
        'install -o root -g maidcafe -m 0750 /dev/stdin '
        '/etc/maidcafe/actions/backup.sh',
      ),
    );
  });

  test('updates replace only the daemon binary and record the new version', () {
    final script = buildMaidCafeDaemonInstallScript(
      daemonId: 'daemon-1',
      cloudUrl: '',
      cloudSecret: '',
      artifactUrl: 'https://dist.example/maidcafe-daemon.tar',
      transport: 'http',
      version: 'v1.2.3',
      actions: const [
        MaidCafeActionDefinition(name: 'backup', script: 'echo hi'),
      ],
      updateOnly: true,
    );

    expect(script, contains('/usr/local/bin/maidcafe-daemon'));
    expect(script, contains('systemctl restart maidcafe-daemon'));
    // The deployed version is recorded in the existing config; only that
    // line is touched. No full config, fragment, script, sudoers or unit
    // writes happen on an update.
    expect(script, contains("version_re='^version[[:space:]]*='"));
    expect(
      script,
      contains(
        'sed -i "s/\$version_re.*/version = \$new_version/" '
        '/etc/maidcafe/config.toml',
      ),
    );
    expect(script, contains('base64 -d'));
    expect(
      script,
      isNot(
        contains(
          'install -o root -g maidcafe -m 0660 /dev/stdin '
          '/etc/maidcafe/config.toml',
        ),
      ),
    );
    expect(script, isNot(contains('maidcafe/actions/backup.sh')));
    expect(script, isNot(contains('visudo')));
    expect(script, isNot(contains('maidcafe-daemon.service')));
    expect(script, isNot(contains('maidkit-managed')));
  });

  test('configuration sync patches only the edited values', () {
    final script = buildMaidCafeDaemonConfigScript(
      currentConfig: _baseConfig,
      daemonId: 'maidkit-1',
      cloudUrl: 'https://mkc.solsynth.dev',
      cloudSecret: 'cloud-secret',
      apiSecret: 'new-secret',
      transport: 'http',
      logsInterval: '0',
      actions: const [
        MaidCafeActionDefinition(name: 'backup', script: 'echo hi'),
      ],
    );

    expect(script, contains('/etc/maidcafe/config.toml'));
    expect(script, contains('base64 -d'));
    expect(script, contains('systemctl restart maidcafe-daemon'));
    // No binary download/install on a config sync.
    expect(script, isNot(contains('curl --fail')));
    expect(script, isNot(contains('maidcafe-daemon.tar')));

    final patched = decodeMaidCafeConfigFromScript(script);
    expect(patched, contains('metricsSecret = "new-secret"'));
    // The webhook block and comments survive the patch verbatim.
    expect(patched, contains('[[daemon.webhooks]]'));
    expect(patched, contains('name = "ci-deploy"'));
    expect(patched, contains('command = "/usr/local/bin/deploy"'));
    expect(patched, contains('secret = "webhook-secret"'));
    expect(patched, contains('# MaidKit-managed daemon'));
    expect(patched, contains('maxBodyBytes = 65536'));
    expect(patched, contains('logsInterval = "0"'));
    // Legacy inline actions are migrated out; the fragment is deployed.
    expect(patched, isNot(contains('[[daemon.actions]]')));
    final fragment = decodeFragmentFromScript(script, 'backup');
    expect(fragment, contains('name = "backup"'));
  });

  test(
    'patchMaidCafeConfigText inserts missing keys and preserves the rest',
    () {
      const existing = '''
[daemon]
 id = "old-id"
 listen = "127.0.0.1:8747"
''';
      final patched = patchMaidCafeConfigText(existing, {
        'id': '"new-id"',
        'maxConcurrentRuns': '8',
        'cloudUrl': '"https://mkc.solsynth.dev"',
      });
      expect(patched, contains('id = "new-id"'));
      expect(patched, contains('listen = "127.0.0.1:8747"'));
      expect(patched, contains('maxConcurrentRuns = 8'));
      expect(patched, contains('cloudUrl = "https://mkc.solsynth.dev"'));
    },
  );

  test('patchMaidCafeConfigText escapes values and keeps inline comments', () {
    final patched = patchMaidCafeConfigText('[daemon]\n id = "a" # keep me\n', {
      'id': '"a\\"b"',
    });
    expect(patched, contains('id = "a\\"b" # keep me'));
  });

  test('stripMaidCafeInlineActions removes legacy action blocks', () {
    const config = '''
[daemon]
 id = "host-1"

[[daemon.actions]]
name = "legacy"
command = "/etc/maidcafe/actions/legacy.sh"

[[daemon.webhooks]]
name = "hook"
secret = "s"
command = "/bin/true"
''';
    final stripped = stripMaidCafeInlineActions(config);
    expect(stripped, isNot(contains('[[daemon.actions]]')));
    expect(stripped, isNot(contains('legacy')));
    expect(stripped, contains('[[daemon.webhooks]]'));
    expect(stripped, contains('secret = "s"'));
  });

  test(
    'run-as users install a sudoers rule and relax the actions directory',
    () {
      final script = buildMaidCafeDaemonInstallScript(
        daemonId: 'daemon-1',
        cloudUrl: '',
        cloudSecret: '',
        artifactUrl: 'https://dist.example/maidcafe-daemon.tar',
        actions: const [
          MaidCafeActionDefinition(
            name: 'deploy',
            script: 'echo hi',
            user: 'deploy',
          ),
          MaidCafeActionDefinition(
            name: 'backup',
            script: 'echo hi',
            user: 'www-data',
          ),
          MaidCafeActionDefinition(name: 'plain', script: 'echo hi'),
        ],
      );

      expect(
        script,
        contains(
          'install -d -o root -g maidcafe -m 0770 /etc/maidcafe/actions',
        ),
      );
      expect(
        script,
        contains(
          'install -d -o root -g maidcafe -m 0770 /etc/maidcafe/actions/run',
        ),
      );
      expect(script, contains('rule_user="maidcafe"'));
      expect(
        script,
        contains(
          '"\$rule_user ALL=(deploy,www-data) NOPASSWD: '
          '/etc/maidcafe/actions/run/*, /etc/maidcafe/actions/*"',
        ),
      );
      expect(script, contains('visudo -cf'));
      expect(script, isNot(contains('NoNewPrivileges=true')));
      expect(script, contains('# NoNewPrivileges'));
    },
  );

  test(
    'without run-as users the unit keeps NoNewPrivileges and no sudoers',
    () {
      final script = buildMaidCafeDaemonInstallScript(
        daemonId: 'daemon-1',
        cloudUrl: '',
        cloudSecret: '',
        artifactUrl: 'https://dist.example/maidcafe-daemon.tar',
        actions: const [
          MaidCafeActionDefinition(name: 'plain', script: 'echo hi'),
        ],
      );

      expect(script, contains('NoNewPrivileges=true'));
      expect(
        script,
        contains('install -d -o root -g root -m 0755 /etc/maidcafe/actions'),
      );
      expect(script, isNot(contains('visudo')));
      expect(script, contains('rm -f /etc/sudoers.d/maidcafe-actions'));
    },
  );

  test('stdio run-as rules name the SSH user through SUDO_USER', () {
    final script = buildMaidCafeDaemonInstallScript(
      daemonId: 'daemon-1',
      cloudUrl: '',
      cloudSecret: '',
      artifactUrl: 'https://dist.example/maidcafe-daemon.tar',
      transport: 'stdio',
      actions: const [
        MaidCafeActionDefinition(
          name: 'deploy',
          script: 'echo hi',
          user: 'deploy',
        ),
      ],
    );

    expect(script, contains('rule_user="\${SUDO_USER:-\$(id -un)}"'));
    expect(
      script,
      contains(
        '"\$rule_user ALL=(deploy) NOPASSWD: '
        '/etc/maidcafe/actions/run/*, /etc/maidcafe/actions/*"',
      ),
    );
    expect(
      script,
      contains('chown "\${SUDO_USER:-\$(id -un)}" /etc/maidcafe/actions'),
    );
    expect(
      script,
      contains(
        'install -d -o "\${SUDO_USER:-\$(id -un)}" -g root -m 0770 '
        '/etc/maidcafe/actions/run',
      ),
    );
  });

  test('stdio installer writes an SSH-stream daemon without systemd', () {
    final script = buildMaidCafeDaemonInstallScript(
      daemonId: 'daemon-1',
      cloudUrl: '',
      cloudSecret: '',
      artifactUrl: 'https://dist.example/maidcafe-daemon.tar',
      transport: 'stdio',
      actions: const [
        MaidCafeActionDefinition(name: 'backup', script: 'echo hi'),
      ],
    );

    expect(script, contains('/etc/maidcafe/config.stdio.toml'));
    expect(script, contains('install -o root -g root -m 0644'));
    expect(script, isNot(contains('systemctl enable --now maidcafe-daemon')));
    expect(script, contains('base64 -d'));
  });

  test('actions serialize all execution fields into the fragment', () {
    final script = buildMaidCafeDaemonConfigScript(
      currentConfig: _baseConfig,
      daemonId: 'maidkit-1',
      cloudUrl: '',
      cloudSecret: '',
      transport: 'http',
      actions: const [
        MaidCafeActionDefinition(
          name: 'deploy',
          script: 'systemctl restart myapp',
          displayName: 'Deploy the web app',
          workingDirectory: '/srv/myapp',
          user: 'deploy',
          scriptTimeout: '2m',
          environment: {'CI_BUILD': '42', 'NODE_ENV': 'production'},
        ),
      ],
    );

    final fragment = decodeFragmentFromScript(script, 'deploy');
    expect(fragment, contains('displayName = "Deploy the web app"'));
    expect(fragment, contains('cwd = "/srv/myapp"'));
    expect(fragment, contains('user = "deploy"'));
    expect(fragment, contains('timeout = "2m"'));
    expect(fragment, contains('env = ["CI_BUILD=42", "NODE_ENV=production"]'));
  });

  test('actions without a display name omit the field', () {
    final script = buildMaidCafeDaemonConfigScript(
      currentConfig: _baseConfig,
      daemonId: 'maidkit-1',
      cloudUrl: '',
      cloudSecret: '',
      transport: 'http',
      actions: const [
        MaidCafeActionDefinition(name: 'backup', script: 'echo hi'),
      ],
    );
    final fragment = decodeFragmentFromScript(script, 'backup');
    expect(fragment, isNot(contains('displayName')));
  });

  test('empty cwd, user and timeout are omitted and accepted', () {
    // Empty strings behave exactly like unset fields: no keys in the
    // fragment, and the save accepts them.
    final script = buildMaidCafeDaemonConfigScript(
      currentConfig: _baseConfig,
      daemonId: 'maidkit-1',
      cloudUrl: '',
      cloudSecret: '',
      transport: 'http',
      actions: const [
        MaidCafeActionDefinition(
          name: 'backup',
          script: 'echo hi',
          workingDirectory: '',
          user: '',
          scriptTimeout: '',
        ),
      ],
    );
    final fragment = decodeFragmentFromScript(script, 'backup');
    expect(fragment, isNot(contains('cwd =')));
    expect(fragment, isNot(contains('user =')));
    expect(fragment, isNot(contains('timeout =')));
  });

  test('rejects malformed per-action timeouts on save', () {
    expect(
      () => buildMaidCafeDaemonConfigScript(
        currentConfig: _baseConfig,
        daemonId: 'maidkit-1',
        cloudUrl: '',
        cloudSecret: '',
        transport: 'http',
        actions: const [
          MaidCafeActionDefinition(
            name: 'deploy',
            script: 'echo hi',
            scriptTimeout: '2 minutes',
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('script deploy prepends a shebang and removes stale files', () {
    const body = 'printf "%s" ok\n';
    final snippet = buildMaidCafeActionScriptsScript(const [
      MaidCafeActionDefinition(name: 'backup', script: body),
    ], stdio: false);

    final deployed = RegExp(
      r"printf '%s' '([^']+)' \| base64 -d \| "
      r'install -o root -g maidcafe -m 0750 /dev/stdin '
      r'/etc/maidcafe/actions/backup\.sh',
    ).firstMatch(snippet);
    expect(deployed, isNotNull);
    final written = utf8.decode(base64Decode(deployed!.group(1)!));
    expect(written, startsWith('#!/bin/sh\n'));
    expect(written, contains(body));
    expect(
      snippet,
      contains(
        'for f in /etc/maidcafe/actions/*.sh '
        '/etc/maidcafe/actions/*.toml; do',
      ),
    );
  });

  test('rejects actions with an empty script body', () {
    expect(
      () => buildMaidCafeDaemonConfigScript(
        currentConfig: _baseConfig,
        daemonId: 'maidkit-1',
        cloudUrl: '',
        cloudSecret: '',
        transport: 'http',
        actions: const [MaidCafeActionDefinition(name: 'backup', script: '')],
      ),
      throwsArgumentError,
    );
  });

  test('rejects action names outside the daemon charset', () {
    expect(
      () => buildMaidCafeDaemonConfigScript(
        currentConfig: _baseConfig,
        daemonId: 'maidkit-1',
        cloudUrl: '',
        cloudSecret: '',
        transport: 'http',
        actions: const [
          MaidCafeActionDefinition(name: 'bad name!', script: 'echo hi'),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('extracts free-form template variables from action scripts', () {
    expect(
      maidCafeActionTemplateVariables(
        'systemctl restart {{ SERVICE_NAME }}\n'
        'echo {{ serviceName }} {{ SERVICE_NAME }}',
      ),
      ['SERVICE_NAME', 'serviceName'],
    );
    expect(maidCafeActionTemplateVariables('echo "no templates"'), isEmpty);
    expect(
      maidCafeActionTemplateVariables('echo {{my-var}} {{ with spaces }}'),
      ['my-var', 'with spaces'],
    );
  });

  test('copyWith clears and sets nullable execution fields', () {
    const action = MaidCafeActionDefinition(
      name: 'deploy',
      script: 'echo hi',
      workingDirectory: '/srv/app',
      user: 'deploy',
      scriptTimeout: '2m',
      environment: {'A': '1'},
    );
    final cleared = action.copyWith(workingDirectory: null, user: null);
    expect(cleared.workingDirectory, isNull);
    expect(cleared.user, isNull);
    expect(cleared.scriptTimeout, '2m');
    expect(cleared.environment, {'A': '1'});
    final changed = action.copyWith(scriptTimeout: null);
    expect(changed.scriptTimeout, isNull);
    expect(changed.workingDirectory, '/srv/app');
  });

  test('configuration sync deploys alarm fragments and removes stale ones', () {
    final script = buildMaidCafeDaemonConfigScript(
      currentConfig: _baseConfig,
      daemonId: 'maidkit-1',
      cloudUrl: 'https://mkc.solsynth.dev',
      cloudSecret: 'cloud-secret',
      transport: 'http',
      alarms: const [
        MaidCafeAlarmDefinition(
          kind: 'cpu_percent',
          threshold: 85,
          cooldownSeconds: 120,
        ),
        MaidCafeAlarmDefinition(
          kind: 'memory_used_percent',
          threshold: 90,
          enabled: false,
        ),
      ],
    );

    final cpu = decodeAlarmFragmentFromScript(script, 'cpu_percent');
    expect(cpu, contains('kind = "cpu_percent"'));
    expect(cpu, contains('threshold = 85.00'));
    expect(cpu, contains('enabled = true'));
    expect(cpu, contains('cooldownSeconds = 120'));
    final memory = decodeAlarmFragmentFromScript(script, 'memory_used_percent');
    expect(memory, contains('threshold = 90.00'));
    expect(memory, contains('enabled = false'));
    expect(memory, contains('cooldownSeconds = 300'));
    // Stale fragments are removed.
    expect(script, contains('for f in /etc/maidcafe/alarms/*.toml; do'));
  });

  test('rejects invalid alarm definitions', () {
    expect(
      () => buildMaidCafeDaemonConfigScript(
        currentConfig: _baseConfig,
        daemonId: 'maidkit-1',
        cloudUrl: '',
        cloudSecret: '',
        transport: 'http',
        alarms: const [
          MaidCafeAlarmDefinition(kind: 'filesystem_health', threshold: 80),
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => buildMaidCafeDaemonConfigScript(
        currentConfig: _baseConfig,
        daemonId: 'maidkit-1',
        cloudUrl: '',
        cloudSecret: '',
        transport: 'http',
        alarms: const [
          MaidCafeAlarmDefinition(kind: 'cpu_percent', threshold: 120),
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => buildMaidCafeDaemonConfigScript(
        currentConfig: _baseConfig,
        daemonId: 'maidkit-1',
        cloudUrl: '',
        cloudSecret: '',
        transport: 'http',
        alarms: const [
          MaidCafeAlarmDefinition(kind: 'cpu_percent', threshold: 80),
          MaidCafeAlarmDefinition(kind: 'cpu_percent', threshold: 90),
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => buildMaidCafeDaemonConfigScript(
        currentConfig: _baseConfig,
        daemonId: 'maidkit-1',
        cloudUrl: '',
        cloudSecret: '',
        transport: 'http',
        alarms: const [
          MaidCafeAlarmDefinition(
            kind: 'cpu_percent',
            threshold: 80,
            cooldownSeconds: 0,
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('fresh installs deploy alarm fragments with the config', () {
    final script = buildMaidCafeDaemonInstallScript(
      daemonId: 'daemon-1',
      cloudUrl: 'https://mkc.solsynth.dev',
      cloudSecret: 'cloud-secret',
      artifactUrl: 'https://dist.example/maidcafe-daemon.tar',
      alarms: const [
        MaidCafeAlarmDefinition(kind: 'cpu_percent', threshold: 85),
      ],
    );
    final cpu = decodeAlarmFragmentFromScript(script, 'cpu_percent');
    expect(cpu, contains('kind = "cpu_percent"'));
    expect(cpu, contains('threshold = 85.00'));
  });

  group('privileged file roots', () {
    const nginx = MaidCafeFileRoot(
      path: '/etc/nginx',
      privileged: true,
      profile: 'nginx',
    );
    const shared = MaidCafeFileRoot(path: '/srv/app');

    test('root validity mirrors what the helper accepts', () {
      expect(nginx.isValid, isTrue);
      expect(shared.isValid, isTrue);
      // A relative path, a profile name the helper's pattern rejects, and a
      // mode the helper refuses are all configuration errors.
      expect(const MaidCafeFileRoot(path: 'srv/app').isValid, isFalse);
      expect(
        const MaidCafeFileRoot(
          path: '/etc/nginx',
          privileged: true,
          profile: 'Nginx Prod',
        ).isValid,
        isFalse,
      );
      expect(
        const MaidCafeFileRoot(
          path: '/etc/nginx',
          privileged: true,
          profile: 'nginx',
          modes: ['0666'],
        ).isValid,
        isFalse,
      );
      expect(
        const MaidCafeFileRoot(
          path: '/etc/nginx',
          privileged: true,
          profile: '',
        ).isValid,
        isFalse,
      );
    });

    test('the daemon config declares every root as a table', () {
      final config = maidCafeFilesConfig(const [shared, nginx]);
      expect(config, contains('[daemon.files]'));
      expect(config, contains('allowWrite = true'));
      // Both roots are tables, so one shape covers privileged and not.
      expect(config, contains('path = "/srv/app"'));
      expect(config, contains('path = "/etc/nginx"'));
      // Only the privileged root names a profile.
      expect(
        'privileged = true'.allMatches(config).length,
        1,
        reason: 'only the privileged root should be marked',
      );
      expect(config, contains('profile = "nginx"'));
    });

    test('no roots leaves the file API out of the config entirely', () {
      expect(maidCafeFilesConfig(const []), isEmpty);
      // An invalid root is dropped rather than written as a broken entry.
      expect(
        maidCafeFilesConfig(const [MaidCafeFileRoot(path: 'rel')]),
        isEmpty,
      );
    });

    test('the profile file carries only privileged roots', () {
      final toml = maidCafePrivToml(const [shared, nginx]);
      expect(toml, contains('name = "nginx"'));
      expect(toml, contains('path = "/etc/nginx"'));
      expect(toml, contains('modes = ["0644", "0640"]'));
      // The unprivileged root must not be reachable through the root helper.
      expect(toml, isNot(contains('/srv/app')));
      expect(maidCafePrivToml(const [shared]), isEmpty);
    });

    test('escaping keeps a path from breaking out of its TOML string', () {
      final config = maidCafeFilesConfig(const [
        MaidCafeFileRoot(path: '/srv/a"b\\c'),
      ]);
      expect(config, contains(r'path = "/srv/a\"b\\c"'));
    });

    test('the install script installs the helper before the config', () {
      final script = buildMaidCafeDaemonInstallScript(
        daemonId: 'daemon-1',
        cloudUrl: 'https://mkc.solsynth.dev',
        cloudSecret: 'cloud-secret',
        artifactUrl: 'https://dist.example/maidcafe-daemon.tar',
        fileRoots: const [nginx],
        privHelperBase64: 'aGVscGVy',
      );
      // The daemon refuses to start when a privileged root's helper is missing,
      // so the helper, its profiles and its rule must land first.
      final privIndex = script.indexOf('/etc/sudoers.d/maidkit-priv');
      final configIndex = script.indexOf('install -o root -g maidcafe -m 0660');
      expect(privIndex, greaterThan(-1));
      expect(configIndex, greaterThan(privIndex));
      // The rule comes from the helper itself and is validated before install.
      expect(script, contains('maidkit-priv" sudoers'));
      expect(script, contains('visudo -cf'));
      // A profile file the helper cannot parse fails the install, not the first
      // write.
      expect(script, contains('fs profiles'));
      // The helper binary is deployed through /dev/stdin, like action scripts.
      expect(
        script,
        contains(
          'install -o root -g root -m 0755 /dev/stdin /usr/local/libexec/maidkit-priv',
        ),
      );
      // The config it writes declares the root the helper was just granted.
      // The config is base64-embedded in the script, so it is decoded the way
      // the install decodes it rather than grepped for.
      expect(configFromInstallScript(script), contains('profile = "nginx"'));
      expect(configFromInstallScript(script), contains('privileged = true'));
    });

    test('without privileged roots the standing grant is removed', () {
      final script = buildMaidCafeDaemonInstallScript(
        daemonId: 'daemon-1',
        cloudUrl: 'https://mkc.solsynth.dev',
        cloudSecret: 'cloud-secret',
        artifactUrl: 'https://dist.example/maidcafe-daemon.tar',
        fileRoots: const [shared],
      );
      expect(script, contains('rm -f /etc/sudoers.d/maidkit-priv'));
      expect(script, contains('rm -f /etc/maidkit/priv.toml'));
      // An unprivileged root is served by the daemon account, so no rule is
      // installed for it.
      expect(script, isNot(contains('NOPASSWD')));
    });

    test('stdio names the SSH account in the rule', () {
      final script = buildMaidCafePrivScript(
        const [nginx],
        stdio: true,
        helperBase64: null,
      );
      expect(script, contains(r'rule_user="${SUDO_USER:-$(id -un)}"'));
      // No bundle for this platform, so the helper binary is not written — the
      // installed one is left alone (the profile file still is, so /dev/stdin
      // appears for that payload).
      expect(
        script,
        isNot(contains('0755 /dev/stdin /usr/local/libexec/maidkit-priv')),
      );
      expect(script, contains('if [ ! -x /usr/local/libexec/maidkit-priv ]'));
    });

    test('privileged roots without a helper on the host fail loudly', () {
      final script = buildMaidCafePrivScript(
        const [nginx],
        stdio: false,
        helperBase64: null,
      );
      expect(script, contains('declare no privileged roots'));
    });
  });

  group('host-wide helper grants', () {
    const packages = MaidCafePackageGrant(
      manager: 'apt',
      verbs: ['refresh', 'install'],
    );
    const firewall = MaidCafeFirewallGrant(
      backend: 'ufw',
      verbs: ['allow', 'deny', 'delete'],
    );

    test('a fresh install writes both halves of the routing', () {
      final script = buildMaidCafeDaemonInstallScript(
        daemonId: 'daemon-1',
        cloudUrl: 'https://mkc.solsynth.dev',
        cloudSecret: 'cloud-secret',
        artifactUrl: 'https://dist.example/maidcafe-daemon.tar',
        priv: const MaidCafePrivSection(packages: true, firewall: true),
        packages: packages,
        firewall: firewall,
      );
      // The grant file carries the tables the daemon routes to.
      final grant = decodePrivTomlFromScript(script);
      expect(grant, contains('[packages]'));
      expect(grant, contains('manager = "apt"'));
      expect(grant, contains('verbs = ["refresh", "install"]'));
      expect(grant, contains('[firewall]'));
      expect(grant, contains('backend = "ufw"'));
      // And the config the daemon loads turns the routing on.
      final config = configFromInstallScript(script);
      expect(config, contains('[daemon.priv]'));
      expect(config, contains('packages = true'));
      expect(config, contains('firewall = true'));
      expect(config, contains('systemd = false'));
      // The helper, its grants and its rule land before the config that routes
      // through them, because the daemon refuses to start without the helper.
      final privIndex = script.indexOf('/etc/sudoers.d/maidkit-priv');
      final configIndex = script.indexOf('install -o root -g maidcafe -m 0660');
      expect(privIndex, greaterThan(-1));
      expect(configIndex, greaterThan(privIndex));
    });

    test('grants alone install the helper and its rule', () {
      final script = buildMaidCafeDaemonInstallScript(
        daemonId: 'daemon-1',
        cloudUrl: 'https://mkc.solsynth.dev',
        cloudSecret: 'cloud-secret',
        artifactUrl: 'https://dist.example/maidcafe-daemon.tar',
        packages: packages,
      );
      expect(script, contains('maidkit-priv" sudoers'));
      expect(script, contains('visudo -cf'));
      final grant = decodePrivTomlFromScript(script);
      expect(grant, contains('[packages]'));
      expect(grant, isNot(contains('[[profiles]]')));
    });

    test('an unmodelled priv table stays out of the config', () {
      final script = buildMaidCafeDaemonInstallScript(
        daemonId: 'daemon-1',
        cloudUrl: 'https://mkc.solsynth.dev',
        cloudSecret: 'cloud-secret',
        artifactUrl: 'https://dist.example/maidcafe-daemon.tar',
      );
      // No priv section is written, so the carry-over loop keeps an operator's
      // own table instead of replacing it with nothing.
      expect(configFromInstallScript(script), isNot(contains('[daemon.priv]')));
      expect(script, contains('for unmodelled in daemon.files daemon.priv'));
      // A caller that models nothing leaves the installed grant file alone.
      expect(script, isNot(contains('/etc/maidkit/priv.toml')));
    });

    test('a save patches only the switches it models', () {
      final script = buildMaidCafeDaemonConfigScript(
        currentConfig: _baseConfig,
        daemonId: 'daemon-1',
        cloudUrl: 'https://mkc.solsynth.dev',
        cloudSecret: 'cloud-secret',
        priv: const MaidCafePrivSection(packages: true, firewall: true),
      );
      final config = decodeMaidCafeConfigFromScript(script);
      expect(config, contains('[daemon.priv]'));
      expect(config, contains('packages = true'));
      expect(config, contains('firewall = true'));
      // The rest of the file the app does not model survives the patch.
      expect(config, contains('ci-deploy'));
      expect(config, contains('metricsSecret = "metrics-secret"'));
    });

    test('a save leaves an operator priv table alone when not modelled', () {
      const existing = '''
[daemon]
id = "maidkit-1"
transport = "http"
cloudUrl = "https://mkc.solsynth.dev"
cloudSecret = "cloud-secret"

[daemon.priv]
systemd = true
helper = "/opt/maidkit-priv"
''';
      final script = buildMaidCafeDaemonConfigScript(
        currentConfig: existing,
        daemonId: 'daemon-1',
        cloudUrl: 'https://mkc.solsynth.dev',
        cloudSecret: 'cloud-secret',
      );
      final config = decodeMaidCafeConfigFromScript(script);
      expect(config, contains('systemd = true'));
      expect(config, contains('helper = "/opt/maidkit-priv"'));
      expect(config, isNot(contains('packages')));
    });
  });

  group('an operator\'s own configuration survives a save', () {
    /// The carry-over loop, run for real in a shell rather than grepped for.
    ///
    /// The generated script bakes the installed config path in at build time
    /// (it is a self-contained script), so the harness points it at a sandbox
    /// file: that exercises the same logic — the guards and the awk — against
    /// paths this test owns.
    String runCarryOverLoop(String script, String existing, String generated) {
      final lines = script.split('\n');
      final start = lines.indexWhere((l) => l.startsWith('for unmodelled in'));
      expect(start, greaterThan(-1), reason: 'no carry-over loop');
      var end = -1;
      for (var i = start + 1; i < lines.length; i++) {
        if (lines[i].trim() == 'done') {
          end = i;
          break;
        }
      }
      expect(end, greaterThan(start), reason: 'unterminated carry-over loop');

      final dir = Directory.systemTemp.createTempSync('carry-');
      final installed = '${dir.path}/installed.toml';
      // The real script keeps the generated config in $work_dir/config.toml and
      // the installed one at $configPath, so the harness must not conflate them:
      // the loop appends what the installed file has to the generated one.
      File('${dir.path}/config.toml').writeAsStringSync(generated);
      File(installed).writeAsStringSync(existing);
      final block = lines
          .sublist(start, end + 1)
          .join('\n')
          .replaceAll('/etc/maidcafe/config.toml', installed);
      final driver = File('${dir.path}/run.sh')
        ..writeAsStringSync(
          'set -e\n'
          'work_dir="${dir.path}"\n'
          'configPath=$installed\n'
          '$block\n'
          'cat "${dir.path}/config.toml"\n',
        );
      final result = Process.runSync('bash', [driver.path]);
      expect(result.exitCode, 0, reason: 'loop failed: ${result.stderr}');
      return result.stdout as String;
    }

    test('the merge runs, and does not duplicate an existing section', () {
      final script = buildMaidCafeDaemonInstallScript(
        daemonId: 'daemon-1',
        cloudUrl: 'https://mkc.solsynth.dev',
        cloudSecret: 'cloud-secret',
        artifactUrl: 'https://dist.example/maidcafe-daemon.tar',
      );
      const existing = '''[daemon]
id = "host"

[daemon.files]
enabled = true

[[daemon.files.roots]]
path = "/etc/nginx"
privileged = true
profile = "nginx"
''';
      const generated = '''[daemon]
id = "host"
transport = "http"
''';

      final merged = runCarryOverLoop(script, existing, generated);
      expect(merged, contains('[daemon.files]'));
      expect(merged, contains('profile = "nginx"'));
      expect(merged, contains('transport = "http"'));

      // Running again with the merged file as the generated one must not append
      // a second copy: the guard is what makes a repeated save idempotent.
      final again = runCarryOverLoop(script, existing, merged);
      expect('[daemon.files]'.allMatches(again).length, 1);
      expect('[daemon.files]'.allMatches(again).length, 1);
      expect('profile = "nginx"'.allMatches(again).length, 1);
    });

    test('an explicit teardown is the only thing that removes the grant', () {
      final script = buildMaidCafePrivScript(
        const [],
        stdio: false,
        helperBase64: null,
      );
      expect(script, contains('rm -f /etc/sudoers.d/maidkit-priv'));
      expect(script, contains('rm -f /etc/maidkit/priv.toml'));

      // A caller with no opinion leaves the host alone.
      final silent = buildMaidCafePrivScript(
        null,
        stdio: false,
        helperBase64: null,
      );
      expect(silent, isEmpty);
      final helperOnly = buildMaidCafePrivScript(
        null,
        stdio: false,
        helperBase64: 'aGVscGVy',
      );
      expect(helperOnly, isNot(contains('rm -f')));
      expect(helperOnly, contains('maidkit-priv'));
    });

    test('uninstall leaves no part of the privileged path behind', () {
      final script = buildMaidCafeDaemonUninstallScript();
      // The grant goes before the binary it names.
      final grant = script.indexOf('rm -f /etc/sudoers.d/maidkit-priv');
      final binary = script.indexOf('rm -f /usr/local/libexec/maidkit-priv');
      final profiles = script.indexOf('rm -rf /etc/maidkit');
      expect(grant, greaterThan(-1));
      expect(binary, greaterThan(grant));
      expect(profiles, greaterThan(binary));
    });
  });

  group('saving configuration writes the file roots', () {
    /// The config a sync script patches, recovered from the base64 it carries.
    ///
    /// Anchored on the config install line: with roots declared the script also
    /// embeds the helper's profile file the same way, and that payload must not
    /// be mistaken for the configuration.
    String syncConfig(String script) {
      final match = RegExp(
        r'''printf '%s' '([A-Za-z0-9+/=]+)' \| base64 -d \| install -o root -g maidcafe -m 0660 /dev/stdin /etc/maidcafe/config.toml''',
      ).firstMatch(script);
      expect(match, isNotNull, reason: 'no embedded config');
      return utf8.decode(base64Decode(match!.group(1)!));
    }

    const current = '''[daemon]
id = "host"
transport = "http"
metricsSecret = "secret"

[daemon.terminal]
enabled = true
''';

    String sync({List<MaidCafeFileRoot>? roots}) =>
        buildMaidCafeDaemonConfigScript(
          currentConfig: current,
          daemonId: 'host',
          cloudUrl: 'https://mkc.solsynth.dev',
          cloudSecret: 'cloud-secret',
          transport: 'http',
          listenHost: '127.0.0.1',
          port: 8747,
          apiSecret: 'secret',
          fileRoots: roots,
        );

    test('null roots leave an operator section untouched', () {
      final script = sync();
      // Nothing about the files table or its grant is mentioned at all.
      expect(script, isNot(contains('[daemon.files]')));
      expect(script, isNot(contains('maidkit-priv')));
      expect(script, isNot(contains('sudoers.d/maidkit-priv')));
    });

    test('declared roots are written and the helper is granted first', () {
      final script = sync(
        roots: const [
          MaidCafeFileRoot(path: '/srv/app'),
          MaidCafeFileRoot(
            path: '/etc/nginx',
            privileged: true,
            profile: 'nginx',
          ),
        ],
      );
      final patched = syncConfig(script);
      expect(patched, contains('[daemon.files]'));
      expect(patched, contains('path = "/srv/app"'));
      expect(patched, contains('profile = "nginx"'));
      expect(patched, contains('[daemon.terminal]'));

      // The grant and the profiles land before the configuration that names
      // them, because the daemon validates its helper at load.
      // The config install line, not the first base64 payload in the script
      // (the profile file is embedded the same way).
      final profiles = script.indexOf(
        'base64 -d | install -o root -g root -m 0644 /dev/stdin /etc/maidkit/priv.toml',
      );
      final rule = script.indexOf(r'/etc/sudoers.d/maidkit-priv');
      final config = script.indexOf(
        'base64 -d | install -o root -g maidcafe -m 0660 /dev/stdin /etc/maidcafe/config.toml',
      );
      expect(profiles, greaterThan(-1));
      expect(rule, greaterThan(-1));
      expect(config, greaterThan(-1));
      expect(rule, greaterThan(profiles));
      expect(config, greaterThan(rule));
    });

    test('an empty list tears the section and the grant down', () {
      final script = sync(roots: const []);
      expect(syncConfig(script), isNot(contains('[daemon.files]')));
      expect(script, contains('rm -f /etc/sudoers.d/maidkit-priv'));
      expect(script, contains('rm -f /etc/maidkit/priv.toml'));
    });

    test('a relative root is rejected before any script is built', () {
      expect(
        () => sync(roots: const [MaidCafeFileRoot(path: 'srv/app')]),
        throwsArgumentError,
      );
      expect(
        () => sync(
          roots: const [MaidCafeFileRoot(path: '/etc/nginx', privileged: true)],
        ),
        throwsArgumentError,
        reason: 'a privileged root needs a profile name',
      );
    });

    test('the install extracts the helper from the bundle', () {
      final script = buildMaidCafeDaemonInstallScript(
        daemonId: 'host',
        cloudUrl: 'https://mkc.solsynth.dev',
        cloudSecret: 'cloud-secret',
        artifactUrl: 'https://dist.example/maidcafe-daemon.tar',
      );
      // The bundle carries the helper; the install must place it, or a
      // privileged root declared later cannot start.
      expect(script, contains('maidkit-priv'));
      expect(script, contains('/usr/local/libexec/maidkit-priv'));
      final extraction = script.indexOf('helper_binary=');
      final configInstall = script.indexOf('-m 0660 "\$work_dir/config.toml"');
      expect(extraction, greaterThan(-1));
      expect(configInstall, greaterThan(extraction));
    });
  });
}
