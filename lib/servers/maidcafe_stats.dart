import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:maid_kit/data/local/app_database.dart';

import 'maidcafe_debug.dart';
import 'maidcafe_stream.dart';
import 'server_models.dart';
import 'server_repository.dart';
import 'ssh_connection_manager.dart';
export 'server_models.dart' show ServerMaidCafeRoute;

/// One statistics snapshot read from a MaidCafe daemon.
class MaidCafeServerStats {
  const MaidCafeServerStats({
    required this.stats,
    required this.endpoint,
    required this.fetchedAt,
  });

  /// The host figures, in the same shape the SSH collectors produce so every
  /// surface renders either route identically.
  final ServerStats stats;

  /// The direct daemon address the numbers were read from — the endpoint
  /// override, or the server host on the port the daemon reported. Recorded so
  /// the route behind a card is answerable without reading the console log.
  final String endpoint;

  final DateTime fetchedAt;
}

/// Largest integer JavaScript represents exactly (2^53 - 1); keeps an absurd
/// uptime reading from overflowing `Duration` on any platform.
const _maxDurationSeconds = 9007199254740991;

/// Converts one `/api/v1/metrics` response into [ServerStats].
///
/// The daemon reports memory in bytes and swap/disk in kilobytes; the SSH
/// collectors report kilobytes throughout, so the byte fields are scaled here
/// and the result renders identically whichever route produced it. The
/// daemon's own health score rides the same payload (`health_score`/
/// `health_status`), so the overview reads health without a second request.
///
/// Returns null when the payload carries nothing usable, so a truncated or
/// non-daemon response is never mistaken for a host with no load, no memory and
/// no uptime.
ServerStats? parseMaidCafeServerStats(
  Map<String, dynamic> response, {
  DateTime? now,
}) {
  final cpuCount = _metricInt(response['cpu_count']);
  final load1 = _metricDouble(response['load1']);
  final memoryTotalBytes = _metricInt(response['memory_total_bytes']);
  final memoryUsedBytes = _metricInt(response['memory_used_bytes']);
  final uptimeSeconds = _metricInt(response['uptime_seconds']);
  if (cpuCount == null &&
      load1 == null &&
      memoryTotalBytes == null &&
      uptimeSeconds == null) {
    return null;
  }
  final memoryTotalKb = memoryTotalBytes == null
      ? null
      : memoryTotalBytes ~/ 1024;
  final memoryAvailableKb = memoryTotalBytes == null || memoryUsedBytes == null
      ? null
      : (memoryTotalBytes - memoryUsedBytes) ~/ 1024;
  final disks = _parseMaidCafeDisks(response['disks']);
  final root = _rootDiskUsage(disks);
  return ServerStats(
    collectorId: 'maidcafe',
    updatedAt:
        DateTime.tryParse(response['sent_at']?.toString() ?? '') ??
        now ??
        DateTime.now(),
    loadAverage: load1,
    loadAverage5: _metricDouble(response['load5']),
    loadAverage15: _metricDouble(response['load15']),
    cpuCount: cpuCount,
    memoryTotalKb: memoryTotalKb,
    memoryAvailableKb: memoryAvailableKb,
    swapTotalKb: _metricInt(response['swap_total_kb']),
    swapFreeKb: _metricInt(response['swap_free_kb']),
    diskTotalKb: _metricInt(response['disk_total_kb']) ?? root?.totalKb,
    diskAvailableKb:
        _metricInt(response['disk_available_kb']) ?? root?.availableKb,
    uptime: uptimeSeconds == null
        ? null
        : Duration(seconds: uptimeSeconds.clamp(0, _maxDurationSeconds)),
    disks: disks,
    health: serverHealthFromWire(
      response['health_score'],
      response['health_status'],
    ),
  );
}

List<DiskUsage> _parseMaidCafeDisks(Object? raw) {
  final entries = raw is List ? raw : const [];
  final disks = <DiskUsage>[];
  for (final item in entries) {
    if (item is! Map) continue;
    final mount = item['mount']?.toString() ?? '';
    if (mount.isEmpty) continue;
    disks.add(
      DiskUsage(
        mount: mount,
        filesystem: item['filesystem']?.toString(),
        totalKb: _metricInt(item['total_kb']),
        availableKb: _metricInt(item['available_kb']),
      ),
    );
  }
  return disks;
}

DiskUsage? _rootDiskUsage(List<DiskUsage> disks) {
  for (final disk in disks) {
    if (disk.mount == '/') return disk;
  }
  return disks.isEmpty ? null : disks.first;
}

int? _metricInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString().trim() ?? '');
}

double? _metricDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString().trim() ?? '');
}

/// Severity of one scored dimension of the daemon's health report: `ok` at or
/// below the dimension's warning threshold, `warning` between the two
/// thresholds, `critical` at or above its critical one.
enum MaidCafeHealthCheckStatus { ok, warning, critical }

MaidCafeHealthCheckStatus? _healthCheckStatusFromWire(Object? raw) {
  final value = raw?.toString().trim().toLowerCase();
  if (value == null || value.isEmpty) return null;
  for (final status in MaidCafeHealthCheckStatus.values) {
    if (status.name == value) return status;
  }
  return null;
}

/// One scored dimension of the daemon's overview health report.
class MaidCafeHealthCheck {
  const MaidCafeHealthCheck({
    required this.name,
    required this.status,
    required this.score,
    required this.value,
    required this.unit,
    required this.warn,
    required this.crit,
    this.detail = '',
    this.skipped = false,
  });

  /// Wire name of the dimension: `cpu`, `memory`, `swap`, `disk`, `load`,
  /// `process_memory` or `webhooks`.
  final String name;

  final MaidCafeHealthCheckStatus status;

  /// This dimension's own 0..100 score, at the daemon's built-in thresholds.
  final double score;

  /// The measured value, in [unit].
  final double value;

  /// How [value] is measured: `percent`, `per_core`, `ratio` or `bytes`.
  final String unit;

  /// The thresholds [value] was scored against.
  final double warn;
  final double crit;

  /// What the value belongs to when that is not the whole host: the mount a
  /// disk dimension measured.
  final String detail;

  /// Whether the dimension applies to this host at all — no swap configured,
  /// no webhook runs yet, no disk data. A skipped dimension is excluded from
  /// the report's weighted score, so its value is the daemon's placeholder
  /// rather than a reading.
  final bool skipped;
}

/// The daemon's own overview of host health (`GET /api/v1/health`): the
/// weighted score it computed for the current metric sample and every scored
/// dimension behind it.
class MaidCafeHealthReport {
  const MaidCafeHealthReport({
    required this.health,
    required this.hostId,
    this.evaluatedAt,
    this.checks = const [],
  });

  /// The score and band, in the same shape a metric sample carries, so the
  /// overview and this breakdown never disagree.
  final ServerHealth health;

  /// The daemon's host id, empty when it reports none.
  final String hostId;

  /// When the daemon evaluated the sample, null when it did not say.
  final DateTime? evaluatedAt;

  /// Every dimension the daemon scores, applicable or not.
  final List<MaidCafeHealthCheck> checks;

  /// The dimensions that crossed a threshold, in the daemon's own order.
  List<MaidCafeHealthCheck> get issues => [
    for (final check in checks)
      if (!check.skipped && check.status != MaidCafeHealthCheckStatus.ok) check,
  ];
}

/// Parses one `/api/v1/health` body, or null when it carries no usable score.
///
/// The report's own `issues` list is deliberately not read: it is the daemon's
/// English sentences, and these surfaces render the same findings from the
/// structured checks instead.
MaidCafeHealthReport? parseMaidCafeHealthReport(Map<String, dynamic> response) {
  final health = serverHealthFromWire(response['score'], response['status']);
  if (health == null) return null;
  final rawChecks = response['checks'];
  return MaidCafeHealthReport(
    health: health,
    hostId: response['host_id']?.toString() ?? '',
    evaluatedAt: DateTime.tryParse(response['evaluated_at']?.toString() ?? ''),
    checks: [
      for (final item in rawChecks is List ? rawChecks : const [])
        if (item is Map) ?_parseHealthCheck(item),
    ],
  );
}

MaidCafeHealthCheck? _parseHealthCheck(Map<dynamic, dynamic> raw) {
  final name = raw['name']?.toString().trim() ?? '';
  final status = _healthCheckStatusFromWire(raw['status']);
  if (name.isEmpty || status == null) return null;
  return MaidCafeHealthCheck(
    name: name,
    status: status,
    score: _metricDouble(raw['score']) ?? 0,
    value: _metricDouble(raw['value']) ?? 0,
    unit: raw['unit']?.toString() ?? '',
    warn: _metricDouble(raw['warn']) ?? 0,
    crit: _metricDouble(raw['crit']) ?? 0,
    detail: raw['detail']?.toString() ?? '',
    skipped: raw['skipped'] == true,
  );
}

/// Renders one check's measurement for display. The daemon measures each
/// dimension in its own unit, so the suffix is chosen here: percentages for
/// percent and ratio dimensions, binary units for byte counts, and a bare
/// number for load per core.
String formatMaidCafeHealthValue(String unit, double value) => switch (unit) {
  'percent' => '${value.toStringAsFixed(1)}%',
  'ratio' => '${(value * 100).toStringAsFixed(1)}%',
  'per_core' => value.toStringAsFixed(2),
  'bytes' => _formatHealthBytes(value),
  _ => value.toStringAsFixed(1),
};

/// Renders a byte count in binary units, e.g. 1536 -> "1.5 KiB".
String _formatHealthBytes(double value) {
  const unit = 1024;
  if (value < unit) return '${value.round()} B';
  final units = ['KiB', 'MiB', 'GiB', 'TiB', 'PiB'];
  var scaled = value / unit;
  var index = 0;
  while (scaled >= unit && index < units.length - 1) {
    scaled /= unit;
    index++;
  }
  return '${scaled.toStringAsFixed(1)} ${units[index]}';
}

/// Why a daemon statistics read produced no numbers.
///
/// Only the first of these is about the transport; the other two are
/// configuration, which is why a caller reports which one it hit rather than
/// blaming the build it runs in.
enum MaidCafeStatsBlocker {
  /// Collection is switched off for the server, or its daemon has no address
  /// this client can dial — a loopback-only daemon whose port was never
  /// learned.
  routeMissing,

  /// The daemon's address is known but no credential is stored for it.
  credentialMissing,
}

/// Reads host statistics from the daemon over the route this client can take.
///
/// Three routes answer, in this order:
///
/// 1. A stored endpoint that is **not** loopback is the user's own address for
///    the daemon — typically an HTTPS reverse proxy. It is dialed as stored,
///    because it reaches a published daemon without costing the host anything.
/// 2. Otherwise, a native build with a live SSH session **forwards** the
///    daemon's port and dials that forward. This is what makes a stock
///    installation, whose daemon listens only on `127.0.0.1:8747`, readable
///    without publishing it — and it is also what makes a daemon bound to
///    `0.0.0.0` but firewalled off from this client readable, which a blind
///    dial at the server host is not.
/// 3. With no SSH transport (a browser build, above all) the address is
///    [ServerMaidCafeRoute.maidCafeBrowserTerminalUrl]: the server host on the
///    port the daemon reported, which only answers when it is published.
///
/// A route that fails withdraws the snapshot, so the SSH collectors take the
/// host back rather than a card showing numbers that stopped arriving.
class MaidCafeStatsCollector {
  MaidCafeStatsCollector({
    required ServerRepository repository,
    required SshConnectionManager manager,
  }) : this._(repository, manager);

  MaidCafeStatsCollector._(this._repository, this._manager);

  final ServerRepository _repository;
  final SshConnectionManager _manager;

  /// The resolved route per server id: how it was reached, the credential
  /// version it was resolved against, and the session it opened.
  ///
  /// The scheduler polls every served host on a fixed cadence, so resolving
  /// the route again on every read would decrypt the vault secret and open a
  /// fresh TCP connection — and re-run the daemon's `/health` handshake — for
  /// numbers that come from the same place every time. A cached session is
  /// reused until the route or the stored credential changes, the transport
  /// it rides dies, or the session itself does.
  final Map<int, _StatsRoute> _routes = {};

  /// Reads already running per server id, so a manual refresh landing on top
  /// of a scheduled poll shares one dial instead of opening a second session.
  final Map<int, Future<MaidCafeServerStats?>> _inFlight = {};

  /// The address a statistics read dials directly, or null when the read has
  /// to go through an SSH forward instead.
  ///
  /// A stored non-loopback endpoint is the user's own route and always wins.
  /// With no SSH session to forward through — a browser above all, but also a
  /// desktop that has not connected yet — the browser view of the row is what
  /// there is: the server host on the daemon port it reported, which answers
  /// only when the daemon is published. A live session makes the read forward
  /// instead, because that is the transport that reaches a daemon listening on
  /// the server's own loopback.
  String? endpointFor(Server server) {
    if (!server.collectStats) return null;
    final override = server.maidCafeEndpointOverride;
    if (override != null) return override;
    if (kIsWeb || _manager.clientFor(server.id) == null) {
      return server.maidCafeBrowserTerminalUrl;
    }
    return null;
  }

  /// Whether [server]'s daemon can be reached through an SSH forward: a native
  /// build with a live session, and no published endpoint that already answers.
  ///
  /// The address is not required: a row that never probed its daemon carries
  /// neither a port nor a daemon URL, and a stock installation is exactly that
  /// case. The forward path reads the daemon's own configuration in that state
  /// — once, before the route is cached — which is what a probe would have
  /// stored.
  bool forwardsFor(Server server) {
    if (!server.collectStats || kIsWeb) return false;
    if (server.maidCafeEndpointOverride != null) return false;
    return _manager.clientFor(server.id) != null;
  }

  /// Whether a read of [server]'s statistics can reach its daemon at all: a
  /// published endpoint this client dials, or a session it forwards through.
  ///
  /// It says nothing about the daemon answering — a route that fails is what
  /// withdraws the snapshot — so it is the predicate the scheduler serves by
  /// and the one a surface checks before asking for a read.
  bool canServe(Server server) =>
      endpointFor(server) != null || forwardsFor(server);

  /// Why [server]'s statistics cannot be read from its daemon, or null when a
  /// read can be attempted.
  ///
  /// A caller that has to explain the failure — the dashboard's connect action,
  /// which is the only way a browser has to fill a card in — needs these told
  /// apart: no route this client can take, a credential that was never stored,
  /// and a daemon that stayed silent are three different things to fix.
  Future<MaidCafeStatsBlocker?> blockerFor(Server server) async {
    if (!canServe(server)) return MaidCafeStatsBlocker.routeMissing;
    return await _credentialFor(server) == null
        ? MaidCafeStatsBlocker.credentialMissing
        : null;
  }

  /// The credential a read presents: the dedicated terminal secret when one is
  /// stored, the metrics secret otherwise — the same fallback the daemon
  /// itself applies to `daemon.terminal.secret`.
  Future<String?> _credentialFor(Server server) async {
    final secret =
        await _repository.maidCafeTerminalSecretFor(server) ??
        await _repository.maidCafeMetricsSecretFor(server);
    return secret == null || secret.isEmpty ? null : secret;
  }

  /// Identifies the credential a route was resolved against.
  ///
  /// A stored secret's nonce is regenerated whenever the secret is written, so
  /// the pair of nonces changes exactly when the secret does — without the
  /// plaintext being read, or the vault decrypted, to find that out.
  String _credentialVersion(Server server) =>
      '${server.maidCafeTerminalSecretNonce ?? '-'}/'
      '${server.maidCafeMetricsSecretNonce ?? '-'}';

  /// One snapshot, or null when the daemon is unreachable on every route this
  /// client can take, or answered with something unusable. Failures are
  /// logged, never thrown: a host whose daemon is down must not take the
  /// dashboard with it.
  Future<MaidCafeServerStats?> collect(Server server) {
    final pending = _inFlight[server.id];
    if (pending != null) return pending;
    final future = _collectOnce(server);
    _inFlight[server.id] = future;
    return future.whenComplete(() => _inFlight.remove(server.id));
  }

  Future<MaidCafeServerStats?> _collectOnce(Server server) async {
    final endpoint = endpointFor(server);
    final forward = endpoint == null && forwardsFor(server);
    if (endpoint == null && !forward) {
      // Collection is off for this host, or it has neither a published address
      // this client can dial nor a session to forward through; the SSH
      // collectors cover the second case.
      maidCafeLog(
        'no daemon route for "${server.name}" '
        '(collectStats=${server.collectStats}, '
        'stored=${server.maidCafeTerminalUrl ?? 'none'}, '
        'port=${server.maidCafeTerminalPort ?? 'none'}, '
        'ssh=${_manager.clientFor(server.id) == null ? 'none' : 'available'}); '
        'its statistics stay with the SSH collectors',
      );
      return null;
    }
    // The route identity: what the read dials, or the forward it rides.
    // A change here — an endpoint saved, a session appearing or going — is a
    // different route, so the cached session speaks to a configuration that
    // no longer exists.
    final routeKey =
        endpoint ??
        'forward:${server.maidCafeTerminalUrl ?? ''}/'
            '${server.maidCafeTerminalPort ?? ''}';
    final version = _credentialVersion(server);
    var route = _routes[server.id];
    if (route != null &&
        (route.key != routeKey ||
            route.credentialVersion != version ||
            route.session.isClosed)) {
      await closeSession(server.id);
      route = null;
    }
    if (route == null) {
      final secret = await _credentialFor(server);
      if (secret == null && !forward) {
        maidCafeLog(
          'no daemon credential is stored for "${server.name}", so its '
          'statistics cannot be read from $endpoint',
        );
        return null;
      }
      maidCafeLog(
        forward
            ? 'reading statistics for "${server.name}" through an SSH forward '
                  'to its daemon'
            : 'reading statistics for "${server.name}" from $endpoint',
      );
      final MaidCafeStreamSession session;
      try {
        session = forward
            ? await _openThroughForward(server, secret)
            : await MaidCafeStreamSession.openAt(
                manager: _manager,
                baseUrl: endpoint!,
                apiSecret: secret,
              );
      } catch (error) {
        maidCafeLog(
          forward
              ? 'the SSH forward to the daemon of "${server.name}" failed'
              : 'opening $endpoint for "${server.name}" failed',
          error: error,
        );
        return null;
      }
      route = _StatsRoute(
        key: routeKey,
        credentialVersion: version,
        session: session,
      );
      _routes[server.id] = route;
    }
    final baseUrl = route.session.baseUrl;
    try {
      final metrics = await route.session.metrics();
      final stats = parseMaidCafeServerStats(metrics);
      if (stats == null) {
        maidCafeLog(
          'the daemon at $baseUrl answered without usable metrics for '
          '"${server.name}"',
        );
        return null;
      }
      return MaidCafeServerStats(
        stats: stats,
        endpoint: baseUrl,
        fetchedAt: DateTime.now(),
      );
    } catch (error) {
      maidCafeLog(
        'reading statistics for "${server.name}" from $baseUrl failed',
        error: error,
      );
      // A failed read is what a dead socket, a dropped SSH transport or a
      // restarted daemon looks like; the next read has to open a fresh route
      // rather than retry the corpse.
      await closeSession(server.id);
      return null;
    }
  }

  /// Opens the daemon through a local SSH forward, which is the route a stock
  /// installation needs: the daemon listens on the server's own loopback, so
  /// nothing but a forward reaches it without publishing it first.
  ///
  /// A port the row already carries — the one a probe learned, or the one in a
  /// stored tunnel address — opens the forward with no SSH command at all. A
  /// row that never probed its daemon is the one case that has to read the
  /// daemon's configuration first, which is what `open` does; that read happens
  /// once per cached route, not per poll.
  Future<MaidCafeStreamSession> _openThroughForward(
    Server server,
    String? storedSecret,
  ) async {
    final stored = Uri.tryParse(server.maidCafeTerminalUrl?.trim() ?? '');
    final port =
        server.maidCafeTerminalPort ??
        (stored != null && stored.hasPort ? stored.port : null);
    if (port == null) {
      final credential = await _repository.credentialFor(server);
      return MaidCafeStreamSession.open(
        manager: _manager,
        server: server,
        apiSecret: storedSecret,
        sudoPassword: credential.type == CredentialType.password
            ? credential.password
            : null,
      );
    }
    return MaidCafeStreamSession.openThroughForward(
      manager: _manager,
      server: server,
      port: port,
      apiSecret: storedSecret,
    );
  }

  /// Drops the cached session for [serverId], if one is open. A forwarded
  /// session closes its own forward.
  Future<void> closeSession(int serverId) async {
    final route = _routes.remove(serverId);
    await route?.session.close();
  }

  /// Drops every cached session — what the scheduler does when no dashboard is
  /// watching, so no idle daemon socket, and no idle SSH forward, outlives the
  /// readings it served.
  Future<void> closeAll() async {
    final routes = _routes.values.toList();
    _routes.clear();
    for (final route in routes) {
      await route.session.close();
    }
  }
}

/// One server's resolved statistics route: what it dials (a published address,
/// or the forward it rides), the credential version behind it, and the session
/// that serves it.
class _StatsRoute {
  const _StatsRoute({
    required this.key,
    required this.credentialVersion,
    required this.session,
  });

  final String key;
  final String credentialVersion;
  final MaidCafeStreamSession session;
}
