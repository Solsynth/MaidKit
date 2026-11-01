import 'dart:async';

import 'package:maid_kit/data/local/app_database.dart';

import 'maidcafe_debug.dart';
import 'maidcafe_stats.dart';

/// Polls the MaidCafe daemons for their hosts' statistics on the same cadence
/// the SSH path uses, without touching SSH at all.
///
/// The point of the daemon route is that it costs the server no connection:
/// every refresh is one HTTP request to an address the client can already
/// reach. Hosts whose daemon answers on no direct address are skipped — the
/// SSH collectors cover them — and a host that stops answering has its snapshot
/// withdrawn so a card never presents stale numbers as live ones.
///
/// A host whose route failed is remembered: it is retried with an exponential
/// backoff (capped at [maxRetryDelay]) instead of being dialled on every tick,
/// which is what keeps a dead tunnel from filling the log and the event loop.
class MaidCafeStatsScheduler {
  /// [serves] answers whether a host has a route this client can take; it is
  /// not "the daemon is up", only "a read can be attempted", so a host whose
  /// daemon turns out to be down still gets its failed read recorded and its
  /// retry backed off.
  MaidCafeStatsScheduler({
    required Future<MaidCafeServerStats?> Function(Server server) collect,
    required void Function(int serverId, MaidCafeServerStats? snapshot)
    onSnapshot,
    required bool Function(Server server) serves,
    Future<void> Function(int serverId)? releaseRoute,
    Future<void> Function()? releaseRoutes,
  }) : this._(collect, onSnapshot, serves, releaseRoute, releaseRoutes);

  MaidCafeStatsScheduler._(
    this._collect,
    this._onSnapshot,
    this._serves,
    this._releaseRoute,
    this._releaseRoutes,
  );

  /// Whether [server] has a daemon route this client can take at all — a
  /// published address, or a session to forward through. A host without one
  /// stays with the SSH collectors instead of being dialled on every tick.
  final bool Function(Server server) _serves;

  final Future<MaidCafeServerStats?> Function(Server server) _collect;
  final void Function(int serverId, MaidCafeServerStats? snapshot) _onSnapshot;

  /// Drops whatever the collector keeps alive for one host: called when the
  /// host leaves the served set, so the daemon socket does not outlive the
  /// readings.
  final Future<void> Function(int serverId)? _releaseRoute;

  /// Drops every cached route. Called when the dashboard stops watching, so no
  /// idle daemon socket outlives the cards that read it.
  final Future<void> Function()? _releaseRoutes;

  Timer? _timer;
  Duration _interval = const Duration(seconds: 30);
  List<Server> _servers = const [];
  Set<int> _serverIds = const {};
  var _refreshing = false;

  /// The hosts whose direct daemon route failed, with the attempt count and
  /// the moment the next one is due.
  final Map<int, _RouteFailure> _failures = {};

  /// Longest a failed route is left alone before the next attempt, so a daemon
  /// that comes back is picked up without the user asking for it.
  static const Duration maxRetryDelay = Duration(minutes: 5);

  /// Ids currently served from a daemon, so callers can tell which hosts are
  /// already covered without asking the daemon again.
  Set<int> get serverIds => _serverIds;

  /// Re-arms the scheduler for [servers] with a direct daemon route.
  ///
  /// A change in the served set triggers one refresh immediately so cards fill
  /// in when the dashboard opens instead of after the first interval; the same
  /// set only re-arms the timer.
  void update({required Duration interval, required List<Server> servers}) {
    // The predicate is answered from the SSH transport as well as the row, and
    // a session comes and goes without the row changing: the served set is
    // what could be served right now, and [refresh] asks again per tick so a
    // host joins or leaves the daemon route as its session does.
    _servers = [
      for (final server in servers)
        if (server.collectStats && _serves(server)) server,
    ];
    final ids = {for (final server in _servers) server.id};
    final changed = !_sameIds(ids, _serverIds);
    final dropped = _serverIds.difference(ids);
    _serverIds = ids;
    _failures.removeWhere((id, _) => !ids.contains(id));
    for (final id in dropped) {
      unawaited(_releaseRoute?.call(id));
    }
    if (_interval != interval) {
      _interval = interval;
      _timer?.cancel();
      _timer = null;
    }
    if (_servers.isEmpty) {
      _timer?.cancel();
      _timer = null;
      // Nothing is watching: close what the last served set left open.
      unawaited(_releaseRoutes?.call());
      return;
    }
    _timer ??= Timer.periodic(_interval, (_) => unawaited(refresh()));
    if (changed) _refreshAfterBuild();
  }

  /// Runs the first read once the current synchronous work has finished.
  ///
  /// [update] is called from the scheduler provider's own build, and publishing
  /// a snapshot there would modify another provider during initialisation —
  /// which Riverpod rejects ("providers are not allowed to modify other
  /// providers during their initialization") and reports as an unhandled
  /// exception on every rebuild. A microtask puts the read after that build.
  void _refreshAfterBuild() {
    scheduleMicrotask(() => unawaited(refresh()));
  }

  /// Reads every served host whose route is due. Concurrent calls are dropped:
  /// a slow daemon must not stack up requests.
  ///
  /// A host whose route went away — its SSH transport dropped, so nothing can
  /// be forwarded — is released here rather than dialled into a backoff it can
  /// never clear.
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      await Future.wait([
        for (final server in _servers)
          if (_serves(server) && _due(server.id))
            refreshServer(server)
          else if (!_serves(server))
            _releaseRoute?.call(server.id) ?? Future<void>.value(),
      ]);
    } finally {
      _refreshing = false;
    }
  }

  /// Whether [serverId]'s direct route is due a read: never tried, the last
  /// attempt succeeded, or the backoff for a failed route has elapsed.
  bool _due(int serverId) {
    final failure = _failures[serverId];
    return failure == null || !failure.nextAttempt.isAfter(DateTime.now());
  }

  /// Reads [server] once and publishes the result (or withdraws the previous
  /// snapshot when the daemon did not answer).
  ///
  /// [force] is what a manual refresh passes: the user asking for a read is
  /// the one reason to ignore a backoff the scheduler set for itself.
  Future<void> refreshServer(Server server, {bool force = false}) async {
    final failure = _failures[server.id];
    if (!force && !_due(server.id)) return;
    MaidCafeServerStats? snapshot;
    try {
      snapshot = await _collect(server);
    } catch (_) {
      // A collector that throws is a bug, not a transport answer; treat it as
      // an unreachable daemon and keep the dashboard.
      snapshot = null;
    }
    if (snapshot == null) {
      _recordFailure(server, failure);
    } else if (failure != null) {
      _failures.remove(server.id);
      maidCafeLog(
        'the daemon route for "${server.name}" answers again after '
        '${failure.attempts} failed ${failure.attempts == 1 ? 'attempt' : 'attempts'}',
      );
    }
    _onSnapshot(server.id, snapshot);
  }

  /// Remembers that [server]'s direct route failed, so the next read waits for
  /// a backoff instead of dialling a dead tunnel on every tick.
  ///
  /// Only the transition is logged: one line when a route goes down and one
  /// when it comes back, rather than two per attempt per host.
  void _recordFailure(Server server, _RouteFailure? previous) {
    final attempts = (previous?.attempts ?? 0) + 1;
    final delay = _retryDelay(attempts);
    _failures[server.id] = _RouteFailure(
      attempts: attempts,
      nextAttempt: DateTime.now().add(delay),
    );
    if (previous == null) {
      maidCafeLog(
        'the daemon route for "${server.name}" did not answer; retrying in '
        '${delay.inSeconds}s, then backing off up to '
        '${maxRetryDelay.inSeconds}s',
      );
    }
  }

  /// Exponential backoff over the poll interval, capped at [maxRetryDelay].
  Duration _retryDelay(int attempts) {
    final factor = 1 << (attempts - 1).clamp(0, 10);
    final seconds = _interval.inSeconds * factor;
    return seconds >= maxRetryDelay.inSeconds
        ? maxRetryDelay
        : Duration(seconds: seconds);
  }

  void dispose() {
    _timer?.cancel();
    unawaited(_releaseRoutes?.call());
  }

  bool _sameIds(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);
}

/// One host's failed direct daemon route: how many reads failed in a row and
/// when the next one may be attempted.
class _RouteFailure {
  const _RouteFailure({required this.attempts, required this.nextAttempt});

  final int attempts;
  final DateTime nextAttempt;
}
