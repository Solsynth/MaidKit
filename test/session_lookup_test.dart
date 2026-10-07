import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/session_lookup.dart';

Server _server({int id = 1, String connectionType = 'ssh'}) => Server(
  id: id,
  name: 'server-$id',
  host: '10.0.0.$id',
  port: 22,
  username: 'root',
  collectStats: true,
  collectSystemInfo: false,
  connectionType: connectionType,
  maidCafeTerminalUrl: 'https://c01.example',
  maidCafeTerminalViaCloud: false,
);

SshSessionInfo _session({
  int serverId = 1,
  SessionStatus status = SessionStatus.connected,
  SessionTransport transport = SessionTransport.ssh,
  Duration? latency,
}) => SshSessionInfo(
  serverId: serverId,
  serverName: 'server-$serverId',
  connectedAt: DateTime(2026, 10, 7),
  status: status,
  transport: transport,
  networkLatency: latency,
);

void main() {
  // These run on the VM, so `kIsWeb` is false throughout: every case below is
  // the native build's rule.
  test('SSH owns a server only while one of its sessions is connected', () {
    expect(sshPreferredOverDaemon(_server(), const []), isFalse);
    expect(
      sshPreferredOverDaemon(_server(), [
        _session(status: SessionStatus.connecting),
      ]),
      isFalse,
    );
    expect(
      sshPreferredOverDaemon(_server(), [_session(latency: Duration.zero)]),
      isTrue,
    );
  });

  test('a daemon terminal is not an SSH session', () {
    // The reason the feed carries a transport at all: a daemon terminal is
    // `connected` on the same feed, and reading it as SSH would hand the
    // daemon's own session the SSH route's work.
    expect(
      sshPreferredOverDaemon(_server(), [
        _session(transport: SessionTransport.maidcafe),
      ]),
      isFalse,
    );
    expect(
      sshPreferredOverDaemon(_server(), [
        _session(transport: SessionTransport.serial),
      ]),
      isFalse,
    );
    expect(
      isLiveSshSession(_session(transport: SessionTransport.maidcafe)),
      isFalse,
    );
  });

  test('a row with no SSH route never prefers SSH', () {
    for (final type in const ['maidcafe', 'serial']) {
      expect(
        sshPreferredOverDaemon(_server(connectionType: type), [_session()]),
        isFalse,
        reason: type,
      );
    }
  });

  test('another server\'s session does not claim this one', () {
    expect(sshPreferredOverDaemon(_server(), [_session(serverId: 2)]), isFalse);
  });

  test('the pick keeps a daemon terminal from standing in for SSH', () {
    final daemonTerminal = _session(transport: SessionTransport.maidcafe);
    final ssh = _session(latency: const Duration(milliseconds: 4));

    // Both entries are `connected`; only one of them carries readings.
    expect(
      sessionForServer([daemonTerminal, ssh], 1)?.transport,
      SessionTransport.ssh,
    );

    // With no SSH session the daemon terminal is still what represents the
    // server, rather than nothing.
    expect(
      sessionForServer([daemonTerminal], 1)?.transport,
      SessionTransport.maidcafe,
    );

    // A connecting SSH session does not outrank a connected one.
    expect(
      sessionForServer([
        _session(status: SessionStatus.connecting),
        daemonTerminal,
      ], 1)?.transport,
      SessionTransport.maidcafe,
    );
  });
}
