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
}
