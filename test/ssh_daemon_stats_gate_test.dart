import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/ssh_connection_manager.dart';

/// Pins the SSH side of the daemon-first statistics rule.
///
/// A host whose MaidCafe daemon answers has its numbers from that HTTP poll, so
/// the SSH collectors must stand aside — running them anyway is what made a
/// MaidCafe-backed server look like it still used SSH metrics.
Server _server({bool collectStats = true}) => Server(
  id: 1,
  name: 'Build host',
  host: 'build.example',
  port: 22,
  username: 'builder',
  collectStats: collectStats,
  collectSystemInfo: false,
  connectionType: 'ssh',
  maidCafeTerminalViaCloud: false,
);

SshConnectionManager _manager({bool Function(Server)? daemonOwnsStats}) =>
    SshConnectionManager(
      () => throw UnimplementedError(),
      daemonOwnsStats: daemonOwnsStats,
    );

void main() {
  test('a daemon-served host is not probed over SSH', () {
    final manager = _manager(daemonOwnsStats: (server) => true);
    addTearDown(manager.dispose);

    expect(manager.collectsStatsOverSsh(_server()), isFalse);
  });

  test('a host whose daemon stops answering falls back to SSH', () {
    // The gate reads the daemon's published snapshots each call, so a daemon
    // that goes quiet hands the numbers back without a reconnect or a restart.
    var daemonServes = true;
    final manager = _manager(daemonOwnsStats: (_) => daemonServes);
    addTearDown(manager.dispose);

    expect(manager.collectsStatsOverSsh(_server()), isFalse);
    daemonServes = false;
    expect(manager.collectsStatsOverSsh(_server()), isTrue);
  });

  test('an unrelated host keeps its SSH statistics', () {
    // The answer is per host: one answered daemon must not silence the rest.
    final manager = _manager(daemonOwnsStats: (server) => server.id == 2);
    addTearDown(manager.dispose);

    expect(manager.collectsStatsOverSsh(_server()), isTrue);
  });

  test('the per-row switch and the app switch still win', () {
    final manager = _manager(daemonOwnsStats: (_) => false);
    addTearDown(manager.dispose);

    expect(manager.collectsStatsOverSsh(_server()), isTrue);
    expect(manager.collectsStatsOverSsh(_server(collectStats: false)), isFalse);

    final disabled = SshConnectionManager(
      () => throw UnimplementedError(),
      metricsEnabled: () => false,
    );
    addTearDown(disabled.dispose);
    expect(disabled.collectsStatsOverSsh(_server()), isFalse);
  });
}
