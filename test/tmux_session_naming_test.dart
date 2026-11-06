import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/server_connection_actions.dart';
import 'package:maid_kit/servers/tmux_preferences.dart';
import 'package:maid_kit/servers/tmux_sessions.dart';

Server _server({int id = 1, String name = 'build host'}) => Server(
  id: id,
  name: name,
  host: 'build.example',
  port: 22,
  username: 'deploy',
  collectStats: true,
  collectSystemInfo: false,
  connectionType: 'ssh',
  maidCafeTerminalViaCloud: false,
);

void main() {
  test('the default session name lives inside tmux\'s own alphabet', () {
    expect(
      defaultTmuxSessionName(_server(name: 'build host')),
      'maidkit-build-host',
    );
    expect(
      defaultTmuxSessionName(_server(name: 'prod/web #2')),
      'maidkit-prod-web--2',
    );
    // A name that folds away entirely falls back to the server id, which is
    // always a valid body.
    expect(defaultTmuxSessionName(_server(id: 42, name: '!!!')), 'maidkit-42');
    expect(defaultTmuxSessionName(_server(name: '  ')), 'maidkit-1');
  });

  test('a long server name is truncated to the 40-byte budget', () {
    final name = defaultTmuxSessionName(
      _server(name: 'a-very-long-server-name-that-goes-on-and-on'),
    );
    expect(name.length, lessThanOrEqualTo(40));
    expect(name, startsWith('maidkit-a-very-long'));
    // No trailing dash left over from the cut.
    expect(name.endsWith('-'), isFalse);
  });

  test('the tmux switches default to on', () {
    final settings = InMemoryTmuxSettings();
    expect(settings.tmuxEnabled, isTrue);
    expect(settings.detachOnClose, isTrue);
    expect(TmuxPreferences.defaultTmuxEnabled, isTrue);
    expect(TmuxPreferences.defaultDetachOnClose, isTrue);
  });

  test('the in-memory settings record what is saved', () async {
    final settings = InMemoryTmuxSettings();
    await settings.saveTmuxEnabled(false);
    await settings.saveDetachOnClose(false);
    expect(settings.tmuxEnabled, isFalse);
    expect(settings.detachOnClose, isFalse);
  });

  test('tmux session rows parse into the listing shape', () {
    final sessions = parseTmuxSessionRows(
      'work\t2\t1700000000\t1\nbg\t1\t1700000100\t0\nbroken\n',
    );
    expect(sessions, hasLength(2));
    expect(sessions.first.name, 'work');
    expect(sessions.first.windows, 2);
    expect(sessions.first.attached, 1);
    expect(
      sessions.first.createdAt,
      DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
    );
    expect(sessions.last.attached, 0);
  });
}
