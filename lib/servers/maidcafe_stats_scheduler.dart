import 'dart:async';

import 'package:maid_kit/data/local/app_database.dart';

import 'maidcafe_stats.dart';

/// Polls the MaidCafe daemons for their hosts' statistics on the same cadence
/// the SSH path uses, without touching SSH at all.
///
/// The point of the daemon route is that it costs the server no connection:
/// every refresh is one HTTP request to an address the client can already
/// reach. Hosts whose daemon answers on no direct address are skipped — the
/// SSH collectors cover them — and a host that stops answering has its snapshot
/// withdrawn so a card never presents stale numbers as live ones.
class MaidCafeStatsScheduler {
  MaidCafeStatsScheduler({
    required Future<MaidCafeServerStats?> Function(Server server) collect,
    required void Function(int serverId, MaidCafeServerStats? snapshot)
    onSnapshot,
  }) : this._(collect, onSnapshot);

  MaidCafeStatsScheduler._(this._collect, this._onSnapshot);

  final Future<MaidCafeServerStats?> Function(Server server) _collect;
  final void Function(int serverId, MaidCafeServerStats? snapshot) _onSnapshot;

  Timer? _timer;
  Duration _interval = const Duration(seconds: 30);
  List<Server> _servers = const [];
  Set<int> _serverIds = const {};
  var _refreshing = false;

  /// Ids currently served from a daemon, so callers can tell which hosts are
  /// already covered without asking the daemon again.
  Set<int> get serverIds => _serverIds;

  /// Re-arms the scheduler for [servers] with a direct daemon route.
  ///
  /// A change in the served set triggers one refresh immediately so cards fill
  /// in when the dashboard opens instead of after the first interval; the same
  /// set only re-arms the timer.
  void update({required Duration interval, required List<Server> servers}) {
    _servers = [
      for (final server in servers)
        if (server.collectStats && server.maidCafeBrowserTerminalUrl != null)
          server,
    ];
    final ids = {for (final server in _servers) server.id};
    final changed = !_sameIds(ids, _serverIds);
    _serverIds = ids;
    if (_interval != interval) {
      _interval = interval;
      _timer?.cancel();
      _timer = null;
    }
    if (_servers.isEmpty) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(_interval, (_) => unawaited(refresh()));
    if (changed) unawaited(refresh());
  }

  /// Reads every served host once. Concurrent calls are dropped: a slow daemon
  /// must not stack up requests.
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      await Future.wait([for (final server in _servers) refreshServer(server)]);
    } finally {
      _refreshing = false;
    }
  }

  /// Reads [server] once and publishes the result (or withdraws the previous
  /// snapshot when the daemon did not answer).
  Future<void> refreshServer(Server server) async {
    MaidCafeServerStats? snapshot;
    try {
      snapshot = await _collect(server);
    } catch (_) {
      // A collector that throws is a bug, not a transport answer; treat it as
      // an unreachable daemon and keep the dashboard.
      snapshot = null;
    }
    _onSnapshot(server.id, snapshot);
  }

  void dispose() => _timer?.cancel();

  bool _sameIds(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);
}
