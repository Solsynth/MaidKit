import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/maidcafe_install.dart';

/// A realistic existing `/etc/maidcafe/config.toml` for patch-based saves.
const _baseConfig = '''
# MaidKit-managed daemon
[daemon]
 id = "maidkit-1"
 transport = "http"
 listen = "127.0.0.1:8747"
 metricsSecret = "metrics-secret"
 cloudUrl = "https://mk.solsynth.dev"
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

void main() {
  test(
    'installer script encodes cloud credentials outside shell arguments',
    () {
      const secret = 'cloud-secret-with-"-quotes';
      final script = buildMaidCafeDaemonInstallScript(
        daemonId: 'daemon-1',
        cloudUrl: 'https://mk.solsynth.dev',
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
      cloudUrl: 'https://mk.solsynth.dev',
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
        'cloudUrl': '"https://mk.solsynth.dev"',
      });
      expect(patched, contains('id = "new-id"'));
      expect(patched, contains('listen = "127.0.0.1:8747"'));
      expect(patched, contains('maxConcurrentRuns = 8'));
      expect(patched, contains('cloudUrl = "https://mk.solsynth.dev"'));
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
      cloudUrl: 'https://mk.solsynth.dev',
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
      cloudUrl: 'https://mk.solsynth.dev',
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
}
