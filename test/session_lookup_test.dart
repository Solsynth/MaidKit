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
  test('an SSH row can fall back to SSH', () {
    expect(sshFallbackAvailable(_server()), isTrue);
    // The fallback has nothing to do with whether a session is up right now:
    // the daemon leads, and SSH answers a failed daemon read by reconnecting.
    expect(sshFallbackAvailable(_server(connectionType: 'maidcafe')), isFalse);
    expect(sshFallbackAvailable(_server(connectionType: 'serial')), isFalse);
  });

  test('a daemon terminal is not an SSH session', () {
    // The reason the feed carries a transport at all: a daemon terminal is
    // `connected` on the same feed, and reading it as SSH would hand the
    // daemon's own session the SSH route's work.
    expect(
      isLiveSshSession(_session(transport: SessionTransport.maidcafe)),
      isFalse,
    );
    expect(
      isLiveSshSession(_session(status: SessionStatus.connecting)),
      isFalse,
    );
    expect(isLiveSshSession(_session(latency: Duration.zero)), isTrue);
    expect(
      isLiveSshSession(_session(transport: SessionTransport.serial)),
      isFalse,
    );
  });

  test('another server\'s session does not claim this one', () {
    expect(isLiveSshSession(_session(serverId: 2), 1), isFalse);
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
