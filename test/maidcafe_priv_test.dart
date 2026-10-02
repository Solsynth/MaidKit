import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/maidcafe_priv.dart';

void main() {
  group('parseMaidCafeFileRoots', () {
    test('reads the current array-of-tables shape', () {
      const config = '''
[daemon]
id = "host"

[daemon.files]
enabled = true
allowWrite = true

[[daemon.files.roots]]
path = "/srv/app"

[[daemon.files.roots]]
path = "/etc/nginx"
privileged = true
profile = "nginx"
modes = ["0644", "0640"]

[daemon.terminal]
enabled = true
''';
      final roots = parseMaidCafeFileRoots(config);
      expect(roots, hasLength(2));
      expect(roots[0].path, '/srv/app');
      expect(roots[0].privileged, isFalse);
      expect(roots[0].profile, isEmpty);
      expect(roots[1].path, '/etc/nginx');
      expect(roots[1].privileged, isTrue);
      expect(roots[1].profile, 'nginx');
      expect(roots[1].modes, ['0644', '0640']);
      expect(roots[1].isValid, isTrue);
    });

    test('reads the bare path list the first release wrote', () {
      const config = '''
[daemon.files]
enabled = true
roots = ["/srv", "/etc/maidcafe"]
''';
      final roots = parseMaidCafeFileRoots(config);
      expect(roots.map((r) => r.path), ['/srv', '/etc/maidcafe']);
      expect(roots.every((r) => !r.privileged), isTrue);
    });

    test('reads a multi-line array and ignores other tables', () {
      const config = '''
[[daemon.files.roots]]
path = "/srv"
modes = [
  "0644",
  "0755",
]

[daemon.webhooks]
name = "backup"
path = "/not/a/root"
''';
      final roots = parseMaidCafeFileRoots(config);
      expect(roots, hasLength(1));
      expect(roots.single.modes, ['0644', '0755']);
    });

    test('no files section means no roots', () {
      expect(parseMaidCafeFileRoots('[daemon]\nid = "host"\n'), isEmpty);
      expect(parseMaidCafeFileRoots(''), isEmpty);
    });
  });

  group('patchMaidCafeFilesConfigText', () {
    const base = '''
[daemon]
id = "host"
# a comment that must survive

[daemon.files]
enabled = true

[[daemon.files.roots]]
path = "/old"

[daemon.terminal]
enabled = true
''';

    test('null leaves the section and the comment alone', () {
      final patched = patchMaidCafeFilesConfigText(base, null);
      expect(patched, base);
    });

    test('replaces the section, roots included, and nothing else', () {
      final patched = patchMaidCafeFilesConfigText(base, const [
        MaidCafeFileRoot(path: '/srv/app'),
        MaidCafeFileRoot(
          path: '/etc/nginx',
          privileged: true,
          profile: 'nginx',
        ),
      ]);
      expect(patched, contains('# a comment that must survive'));
      expect(patched, contains('[daemon.terminal]'));
      expect(patched, contains('path = "/srv/app"'));
      expect(patched, contains('profile = "nginx"'));
      // The old root is gone, not left beside the new set.
      expect(patched, isNot(contains('/old')));
      expect('[[daemon.files.roots]]'.allMatches(patched).length, 2);
      // Parsing it back gives exactly what was written.
      final round = parseMaidCafeFileRoots(patched);
      expect(round.map((r) => r.path), ['/srv/app', '/etc/nginx']);
      expect(round[1].privileged, isTrue);
      expect(round[1].profile, 'nginx');
    });

    test('an empty list removes the section entirely', () {
      final patched = patchMaidCafeFilesConfigText(base, const []);
      expect(patched, isNot(contains('[daemon.files]')));
      expect(patched, isNot(contains('/old')));
      expect(patched, contains('[daemon]\nid = "host"'));
      expect(patched, contains('[daemon.terminal]'));
      expect(patched, contains('# a comment that must survive'));
    });

    test('writes a section into a config that has none', () {
      const plain = '[daemon]\nid = "host"\n';
      final patched = patchMaidCafeFilesConfigText(plain, const [
        MaidCafeFileRoot(path: '/srv'),
      ]);
      expect(parseMaidCafeFileRoots(patched), hasLength(1));
      expect(patched, contains('enabled = true'));
    });

    test('is idempotent', () {
      const roots = [MaidCafeFileRoot(path: '/srv/app')];
      final once = patchMaidCafeFilesConfigText(base, roots);
      final twice = patchMaidCafeFilesConfigText(once, roots);
      expect(twice, once);
    });
  });

  group('mergeMaidCafeFilesConfig', () {
    const existing = '''[daemon]
id = "host"

[daemon.files]
enabled = true
allowWrite = false
maxReadBytes = 1048576
secret = "files-secret"

[[daemon.files.roots]]
path = "/old"
''';

    test('keeps the keys it does not generate', () {
      final merged = mergeMaidCafeFilesConfig(
        existing,
        maidCafeFilesConfig(const [MaidCafeFileRoot(path: '/srv/app')]),
      );
      // The app owns enabled/allowWrite; everything else in the table is the
      // operator's, and losing a read cap or a secret to an unrelated save is
      // exactly the kind of silent change this avoids.
      expect(merged, contains('maxReadBytes = 1048576'));
      expect(merged, contains('secret = "files-secret"'));
      expect(merged, contains('allowWrite = true'));
      expect('enabled = true'.allMatches(merged).length, 1);
      expect(merged, contains('path = "/srv/app"'));
      expect(merged, isNot(contains('/old')));
      // The kept keys land in the table, not inside a root entry.
      final rootsAt = merged.indexOf('[[daemon.files.roots]]');
      expect(merged.indexOf('maxReadBytes'), lessThan(rootsAt));
      // And the result still parses back to what was intended.
      expect(parseMaidCafeFileRoots(merged), hasLength(1));
      expect(merged, contains('[daemon]'));
    });

    test('an empty generation leaves the file alone', () {
      expect(mergeMaidCafeFilesConfig(existing, ''), existing);
    });

    test('a file with no section gains one, and keeps the rest', () {
      const plain = '[daemon]\nid = "host"\n';
      final merged = mergeMaidCafeFilesConfig(
        plain,
        maidCafeFilesConfig(const [MaidCafeFileRoot(path: '/srv')]),
      );
      // The section is appended; the file it was appended to survives, which
      // is the whole point of merging rather than replacing the text.
      expect(merged, startsWith('[daemon]\nid = "host"'));
      expect(merged, contains('[daemon.files]'));
      expect(merged, contains('path = "/srv"'));
      expect(parseMaidCafeFileRoots(merged), hasLength(1));
      expect(merged.trim().endsWith('path = "/srv"'), isTrue);
    });

    test('is idempotent', () {
      const roots = [MaidCafeFileRoot(path: '/srv/app')];
      final once = mergeMaidCafeFilesConfig(
        existing,
        maidCafeFilesConfig(roots),
      );
      final twice = mergeMaidCafeFilesConfig(once, maidCafeFilesConfig(roots));
      expect(twice, once);
    });
  });

  group('the generated pair of allowlists', () {
    test('a privileged root appears in both, an ordinary one in one', () {
      const roots = [
        MaidCafeFileRoot(path: '/srv/app'),
        MaidCafeFileRoot(
          path: '/etc/nginx',
          privileged: true,
          profile: 'nginx',
          modes: ['0644'],
        ),
      ];
      final daemonConfig = maidCafeFilesConfig(roots);
      final helperProfiles = maidCafePrivToml(roots);
      // The daemon routes the privileged root to the helper...
      expect(daemonConfig, contains('profile = "nginx"'));
      // ...and the helper is allowed to reach it, and only it.
      expect(helperProfiles, contains('/etc/nginx'));
      expect(helperProfiles, contains('modes = ["0644"]'));
      expect(helperProfiles, isNot(contains('/srv/app')));
    });
  });

  group('the helper grant file', () {
    test('carries a package grant only when one is given', () {
      const grant = MaidCafePackageGrant(
        manager: 'apt',
        verbs: ['refresh', 'upgrade'],
      );
      // A caller that asks for nothing gets a file with no [packages] table.
      expect(maidCafePrivToml(const []), isEmpty);
      final toml = maidCafePrivToml(const [], packages: grant);
      expect(toml, contains('[packages]'));
      expect(toml, contains('manager = "apt"'));
      expect(toml, contains('verbs = ["refresh", "upgrade"]'));
      expect(toml, isNot(contains('[firewall]')));
    });

    test('carries a firewall grant only when one is given', () {
      const grant = MaidCafeFirewallGrant(
        backend: 'ufw',
        verbs: ['allow', 'deny', 'delete'],
      );
      final toml = maidCafePrivToml(const [], firewall: grant);
      expect(toml, contains('[firewall]'));
      expect(toml, contains('backend = "ufw"'));
      expect(toml, contains('verbs = ["allow", "deny", "delete"]'));
      expect(toml, isNot(contains('[packages]')));
    });

    test('brew is deliberately un-grantable', () {
      const brew = MaidCafePackageGrant(
        manager: 'brew',
        verbs: ['install', 'remove'],
      );
      // Homebrew installs into a user-owned prefix, so a root grant for it
      // buys nothing and is refused rather than written.
      expect(brew.isValid, isFalse);
      expect(maidCafePrivToml(const [], packages: brew), isEmpty);
      expect(
        () => buildMaidCafePrivScript(
          null,
          stdio: false,
          packages: brew,
          helperBase64: 'aGVscGVy',
        ),
        throwsArgumentError,
      );
    });

    test('a grant with an unknown verb is refused, not trimmed', () {
      const unknown = MaidCafePackageGrant(
        manager: 'apt',
        verbs: ['refresh', 'upgrade-all'],
      );
      expect(unknown.isValid, isFalse);
      expect(maidCafePrivToml(const [], packages: unknown), isEmpty);
      const unknownFirewall = MaidCafeFirewallGrant(
        backend: 'nftables',
        verbs: ['allow'],
      );
      expect(unknownFirewall.isValid, isFalse);
      expect(maidCafePrivToml(const [], firewall: unknownFirewall), isEmpty);
    });

    test('a grant and privileged roots share one file', () {
      const roots = [
        MaidCafeFileRoot(
          path: '/etc/nginx',
          privileged: true,
          profile: 'nginx',
        ),
      ];
      final toml = maidCafePrivToml(
        roots,
        packages: const MaidCafePackageGrant(
          manager: 'apt',
          verbs: ['refresh'],
        ),
        firewall: const MaidCafeFirewallGrant(backend: 'ufw', verbs: ['allow']),
      );
      expect(toml, contains('name = "nginx"'));
      expect(toml, contains('[packages]'));
      expect(toml, contains('[firewall]'));
    });
  });

  group('the daemon priv switches', () {
    test('render all four keys, and the helper only when named', () {
      final config = maidCafePrivConfig(
        const MaidCafePrivSection(
          helper: '/usr/local/libexec/maidkit-priv',
          systemd: true,
          packages: true,
          firewall: true,
        ),
      );
      expect(config, contains('[daemon.priv]'));
      expect(config, contains('helper = "/usr/local/libexec/maidkit-priv"'));
      expect(config, contains('systemd = true'));
      expect(config, contains('packages = true'));
      expect(config, contains('firewall = true'));

      // Empty means the daemon's compiled default, which is not a value to
      // write; a section that names no helper still spells the switches out.
      final bare = maidCafePrivConfig(
        const MaidCafePrivSection(packages: true),
      );
      expect(bare, isNot(contains('helper')));
      expect(bare, contains('systemd = false'));
      expect(bare, contains('packages = true'));
      expect(bare, contains('firewall = false'));

      // Null is "this caller has no opinion" and renders nothing, so an
      // operator's own table survives an unrelated save.
      expect(maidCafePrivConfig(null), isEmpty);
    });

    test('round-trip through the parser', () {
      const section = MaidCafePrivSection(
        helper: '/opt/maidkit-priv',
        systemd: false,
        packages: true,
        firewall: true,
      );
      final parsed = parseMaidCafePrivConfig(maidCafePrivConfig(section));
      expect(parsed, isNotNull);
      expect(parsed!.helper, '/opt/maidkit-priv');
      expect(parsed.systemd, isFalse);
      expect(parsed.packages, isTrue);
      expect(parsed.firewall, isTrue);
    });

    test('reads dotted keys and ignores other tables', () {
      const config = '''
[daemon]
id = "host"
daemon.priv.packages = true

[daemon.files]
enabled = true
''';
      final parsed = parseMaidCafePrivConfig(config);
      expect(parsed, isNotNull);
      expect(parsed!.packages, isTrue);
      expect(parsed.systemd, isFalse);
      expect(parsed.firewall, isFalse);
      expect(parsed.helper, isEmpty);
    });

    test('no table means not configured, which is not "all off"', () {
      expect(parseMaidCafePrivConfig('[daemon]\nid = "host"\n'), isNull);
      // A table the operator wrote with everything off is a real answer.
      final parsed = parseMaidCafePrivConfig('[daemon.priv]\n');
      expect(parsed, isNotNull);
      expect(parsed!.systemd, isFalse);
      expect(parsed.packages, isFalse);
      expect(parsed.firewall, isFalse);
    });
  });
}
