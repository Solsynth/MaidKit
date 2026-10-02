import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/session_lookup.dart';

SshSessionInfo _session(
  int serverId, {
  required SessionStatus status,
  double? load,
}) => SshSessionInfo(
  serverId: serverId,
  serverName: 'server-$serverId',
  connectedAt: DateTime.utc(2026),
  status: status,
  stats: load == null
      ? null
      : ServerStats(
          collectorId: 'test',
          updatedAt: DateTime.utc(2026),
          loadAverage: load,
        ),
);

void main() {
  test('a connected session wins over a closed one for the same server', () {
    // A MaidCafe terminal closing writes a closed entry for the server while
    // its SSH session is still up; picking the first entry would drop the
    // readings the status bar shows.
    final sessions = [
      _session(1, status: SessionStatus.closed),
      _session(1, status: SessionStatus.connected, load: 0.5),
    ];

    final picked = sessionForServer(sessions, 1);

    expect(picked?.status, SessionStatus.connected);
    expect(picked?.stats?.loadAverage, 0.5);
  });

  test('a closed session is still reported when nothing else is connected', () {
    final sessions = [_session(2, status: SessionStatus.closed)];
    expect(sessionForServer(sessions, 2)?.status, SessionStatus.closed);
  });

  test('another server is never substituted', () {
    final sessions = [_session(1, status: SessionStatus.connected)];
    expect(sessionForServer(sessions, 2), isNull);
  });
}
