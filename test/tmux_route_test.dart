// Which transport carries a tmux terminal. The rule is the same one the plain
// terminal follows: an SSH server opens over SSH even when it also stores a
// daemon endpoint, because that endpoint is a browser fallback and a native
// client would dial a loopback port only its own SSH forward serves.
import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/server_connection_actions.dart';
import 'package:maid_kit/servers/server_models.dart';

Server _server({
  required String connectionType,
  String? terminalUrl = 'http://127.0.0.1:8747',
}) => Server(
  id: 1,
  name: 'build host',
  host: 'build.example',
  port: 22,
  username: 'deploy',
  collectStats: true,
  collectSystemInfo: false,
  connectionType: connectionType,
  maidCafeTerminalUrl: terminalUrl,
  maidCafeTerminalViaCloud: false,
);

void main() {
  test('an SSH server opens tmux over SSH even with a daemon endpoint', () {
    final server = _server(connectionType: 'ssh');
    expect(server.hasMaidCafeTerminalRoute, isTrue);
    expect(
      shouldOpenTmuxViaDaemon(server, preferDaemon: false, browserBuild: false),
      isFalse,
    );
  });

  test('a daemon server opens tmux through its daemon', () {
    final server = _server(connectionType: 'maidcafe');
    expect(
      shouldOpenTmuxViaDaemon(server, preferDaemon: false, browserBuild: false),
      isTrue,
    );
  });

  test('a caller that chose the daemon route is obeyed', () {
    final server = _server(connectionType: 'ssh');
    expect(
      shouldOpenTmuxViaDaemon(server, preferDaemon: true, browserBuild: false),
      isTrue,
    );
  });

  test('a browser build has no raw socket, so it uses the daemon', () {
    final server = _server(connectionType: 'ssh');
    expect(
      shouldOpenTmuxViaDaemon(server, preferDaemon: false, browserBuild: true),
      isTrue,
    );
  });

  test(
    'a server without a daemon endpoint still follows its own transport',
    () {
      final daemon = _server(connectionType: 'maidcafe', terminalUrl: null);
      expect(
        shouldOpenTmuxViaDaemon(
          daemon,
          preferDaemon: false,
          browserBuild: false,
        ),
        isTrue,
      );
    },
  );
}
