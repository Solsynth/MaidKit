import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/servers/maidcafe_install.dart';
import 'package:maid_kit/servers/maidcafe_stream.dart';

void main() {
  test('the terminal section also carries its secret and origins', () {
    final config = parseMaidCafeTerminalConfig('''
[daemon]
listen = "127.0.0.1:8747"

[daemon.terminal]
enabled = true
secret = "terminal-secret"
allowedOrigins = [
  "https://app.example",
  "http://localhost:8080",
]
''');
    expect(config.enabled, isTrue);
    expect(config.secret, 'terminal-secret');
    expect(config.allowedOrigins, [
      'https://app.example',
      'http://localhost:8080',
    ]);
  });

  test('the dotted spelling carries the same settings', () {
    final config = parseMaidCafeTerminalConfig('''
daemon.terminal.enabled = false
daemon.terminal.secret = "s"
daemon.terminal.allowedOrigins = ["https://one.example"]
''');
    expect(config.enabled, isFalse);
    expect(config.secret, 's');
    expect(config.allowedOrigins, ['https://one.example']);
  });

  test('the relay opt-in is read from its own table', () {
    final config = parseMaidCafeTerminalConfig('''
[daemon.terminal]
enabled = false

[daemon.terminal.relay]
enabled = true
users = ["you@solsynth.dev"]
''');
    expect(config.enabled, isFalse);
    expect(config.relayEnabled, isTrue);
  });

  test('the relay opt-in is also read as a nested or dotted key', () {
    expect(
      parseMaidCafeTerminalConfig('''
[daemon.terminal]
enabled = true
relay.enabled = true
''').relayEnabled,
      isTrue,
    );
    expect(
      parseMaidCafeTerminalConfig(
        'daemon.terminal.relay.enabled = true\n',
      ).relayEnabled,
      isTrue,
    );
    expect(
      parseMaidCafeTerminalConfig(
        '[daemon.terminal]\nenabled = true\n',
      ).relayEnabled,
      isNull,
    );
  });

  test('the shell allowlist is read, including across lines', () {
    final config = parseMaidCafeTerminalConfig('''
[daemon.terminal]
enabled = true
shells = [
  "/bin/bash",
  "/bin/zsh",
]
''');
    expect(config.shells, ['/bin/bash', '/bin/zsh']);
    // Absent means whatever the daemon has, not an empty list that would make
    // an enabled terminal an invalid configuration.
    expect(
      parseMaidCafeTerminalConfig('[daemon.terminal]\nenabled = true\n').shells,
      isEmpty,
    );
  });

  test('terminal settings that are not there stay unset', () {
    final unset = parseMaidCafeTerminalConfig('[daemon]\nlisten = "x"\n');
    expect(unset.relayEnabled, isNull);
    final config = parseMaidCafeTerminalConfig('[daemon]\nlisten = "x"\n');
    expect(config.enabled, isNull);
    expect(config.secret, isNull);
    expect(config.allowedOrigins, isEmpty);
  });

  test('the terminal table is patched, not rewritten', () {
    const current = '''
[daemon]
listen = "127.0.0.1:8747"

[daemon.terminal]
enabled = false
# keep me
secret = "old"

[daemon.webhooks]
url = "https://hook.example"
''';
    final patched = patchMaidCafeTerminalConfigText(current, {
      'enabled': 'true',
      'secret': '"new"',
      'allowedOrigins': '["https://app.example"]',
    });

    expect(patched, contains('enabled = true'));
    expect(patched, contains('secret = "new"'));
    expect(patched, contains('allowedOrigins = ["https://app.example"]'));
    // Comments, unrelated keys and other tables survive untouched.
    expect(patched, contains('# keep me'));
    expect(patched, contains('[daemon.webhooks]'));
    expect(patched, contains('url = "https://hook.example"'));
    expect(patched, contains('listen = "127.0.0.1:8747"'));
  });

  test('the relay table is patched on its own', () {
    const current = '''
[daemon]
listen = "127.0.0.1:8747"

[daemon.terminal]
enabled = true
secret = "terminal"
''';
    final patched = patchMaidCafeTerminalRelayConfigText(current, {
      'enabled': 'true',
    });

    expect(patched, contains('[daemon.terminal.relay]'));
    expect(patched, contains('enabled = true'));
    // The terminal table above it is untouched.
    expect(patched, contains('[daemon.terminal]'));
    expect(patched, contains('secret = "terminal"'));
    // And the relay table is updated, not duplicated, on a second pass.
    final again = patchMaidCafeTerminalRelayConfigText(patched, {
      'enabled': 'false',
    });
    expect(RegExp(r'\[daemon\.terminal\.relay\]').allMatches(again).length, 1);
    expect(again, contains('enabled = false'));
  });

  test('the terminal table is created when the config has none', () {
    final patched = patchMaidCafeTerminalConfigText(
      '[daemon]\nlisten = "127.0.0.1:8747"\n',
      {'enabled': 'true'},
    );
    expect(patched, contains('[daemon.terminal]'));
    expect(patched, contains('enabled = true'));
  });

  test('the terminal switch is read from its section', () {
    expect(
      parseMaidCafeTerminalEnabled('''
[daemon]
listen = "127.0.0.1:8747"

[daemon.terminal]
enabled = true
secret = "s"
'''),
      isTrue,
    );
    expect(
      parseMaidCafeTerminalEnabled('[daemon.terminal]\nenabled = false\n'),
      isFalse,
    );
  });

  test('the terminal switch is read as a dotted key', () {
    expect(
      parseMaidCafeTerminalEnabled('daemon.terminal.enabled = false\n'),
      isFalse,
    );
    expect(
      parseMaidCafeTerminalEnabled('daemon.terminal.enable = "true"\n'),
      isTrue,
    );
  });

  test('a configuration without the switch says nothing', () {
    expect(
      parseMaidCafeTerminalEnabled('[daemon]\nlisten = "127.0.0.1:8747"\n'),
      isNull,
    );
    // A commented-out switch is not a value.
    expect(
      parseMaidCafeTerminalEnabled('# daemon.terminal.enabled = true\n'),
      isNull,
    );
    expect(parseMaidCafeTerminalEnabled(''), isNull);
    // A section that is not the terminal one keeps its own "enabled".
    expect(parseMaidCafeTerminalEnabled('[daemon]\nenabled = true\n'), isNull);
  });
}
