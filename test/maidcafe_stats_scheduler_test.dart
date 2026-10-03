import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/maidcafe_stats.dart';
import 'package:maid_kit/servers/maidcafe_stats_scheduler.dart';

Server _server({
  required int id,
  String? terminalUrl = 'https://c01.example',
  int? terminalPort,
  bool collectStats = true,
}) => Server(
  id: id,
  name: 'server-$id',
  host: '10.0.0.$id',
  port: 22,
  username: 'root',
  collectStats: collectStats,
  collectSystemInfo: false,
  connectionType: 'ssh',
  maidCafeTerminalUrl: terminalUrl,
  maidCafeTerminalViaCloud: false,
  maidCafeTerminalPort: terminalPort,
);

MaidCafeServerStats _snapshot() => MaidCafeServerStats(
  stats: parseMaidCafeServerStats(const {'uptime_seconds': 60})!,
  endpoint: 'https://c01.example',
  fetchedAt: DateTime.now(),
);

void main() {
  test('serves only hosts with a direct daemon route and stats enabled', () {
    final scheduler = MaidCafeStatsScheduler(
      collect: (_) async => null,
      onSnapshot: (_, _) {},
    );
    addTearDown(scheduler.dispose);

    scheduler.update(
      interval: const Duration(seconds: 30),
      servers: [
        _server(id: 1),
        _server(id: 2, collectStats: false),
        _server(id: 3, terminalUrl: null, terminalPort: null),
        _server(id: 4, terminalPort: 8747),
      ],
    );

    expect(scheduler.serverIds, {1, 4});
  });

  test('publishes a snapshot per host and withdraws it when the daemon '
      'stops answering', () async {
    final published = <String, MaidCafeServerStats?>{};
    var answering = true;
    final scheduler = MaidCafeStatsScheduler(
      collect: (_) async => answering ? _snapshot() : null,
      onSnapshot: (id, snapshot) => published['$id-$answering'] = snapshot,
    );
    addTearDown(scheduler.dispose);

    scheduler.update(
      interval: const Duration(seconds: 30),
      servers: [_server(id: 1)],
    );
    await Future<void>.delayed(Duration.zero);

    expect(published['1-true'], isNotNull);
    expect(published['1-true']!.stats.uptime, const Duration(minutes: 1));

    answering = false;
    await scheduler.refreshServer(_server(id: 1));
    // A withdrawn snapshot is what keeps a card from presenting an old reading
    // as live; null is the signal, not a missing callback.
    expect(published.containsKey('1-false'), isTrue);
    expect(published['1-false'], isNull);
  });

  test('a collector that throws is treated as an unreachable daemon', () async {
    final published = <int, MaidCafeServerStats?>{};
    final scheduler = MaidCafeStatsScheduler(
      collect: (_) async => throw StateError('boom'),
      onSnapshot: (id, snapshot) => published[id] = snapshot,
    );
    addTearDown(scheduler.dispose);

    await scheduler.refreshServer(_server(id: 7));

    expect(published[7], isNull);
  });
}
