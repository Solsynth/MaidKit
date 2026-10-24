import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/server_metrics_refresh_scheduler.dart';
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/ssh_connection_manager.dart';

class _RecordingManager extends SshConnectionManager {
  _RecordingManager() : super(() => throw UnimplementedError());

  final refreshed = <int>[];

  @override
  Future<void> refreshBasicServerInfo(Server server) async {
    refreshed.add(server.id);
  }
}

Server _server(int id) => Server(
  id: id,
  name: 'server-$id',
  host: '10.0.0.$id',
  port: 22,
  username: 'root',
  collectStats: true,
  collectSystemInfo: false,
  connectionType: 'ssh',
  maidCafeTerminalViaCloud: false,
);

SshSessionInfo _connected(int id) => SshSessionInfo(
  serverId: id,
  serverName: 'server-$id',
  connectedAt: DateTime(2026, 1, 1),
  status: SessionStatus.connected,
);

void main() {
  test('a host whose daemon answers is not refreshed over SSH', () async {
    // The daemon owns the numbers for such a host; running SSH metric
    // commands for it would collect a second copy of readings nothing reads.
    final manager = _RecordingManager();
    final scheduler = ServerMetricsRefreshScheduler(manager);
    addTearDown(scheduler.dispose);

    scheduler.update(
      interval: const Duration(milliseconds: 10),
      servers: [_server(1), _server(2)],
      sessions: [_connected(1), _connected(2)],
      focusedServerId: null,
      daemonBackedServerIds: {1},
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(manager.refreshed, isNotEmpty);
    expect(manager.refreshed.toSet(), {2});
  });
}
