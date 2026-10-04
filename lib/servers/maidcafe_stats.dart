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

/// Reads statistics straight from the daemon, over the route a client can take
/// **without SSH**.
///
/// A daemon that only listens on the server's own loopback is reached through
/// an SSH forward by the other daemon consumers. Statistics deliberately do not
/// take that route: the point here is to cost the server no SSH connection at
/// all, so a host whose daemon is not directly reachable resolves to null and
/// the SSH collectors stay in charge.
///
/// [ServerMaidCafeRoute.maidCafeBrowserTerminalUrl] is the address a client
/// without a tunnel dials: the endpoint override when one is stored, otherwise
/// the server host on the port the daemon itself reported. It is used on every
/// platform, so a native build prefers a direct dial over opening a session for
/// numbers the daemon already serves.
class MaidCafeStatsCollector {
  MaidCafeStatsCollector({
    required ServerRepository repository,
    required SshConnectionManager manager,
  }) : this._(repository, manager);

  MaidCafeStatsCollector._(this._repository, this._manager);

  final ServerRepository _repository;
  final SshConnectionManager _manager;

  /// The direct daemon address for [server], or null when only an SSH route
  /// exists.
  String? endpointFor(Server server) {
    if (!server.collectStats) return null;
    final url = server.maidCafeBrowserTerminalUrl;
    if (url == null || url.trim().isEmpty) return null;
    return url;
  }

  /// One snapshot, or null when the daemon is unreachable on its direct route
  /// or answered with something unusable. Failures are logged, never thrown:
  /// a host whose daemon is down must not take the dashboard with it.
  Future<MaidCafeServerStats?> collect(Server server) async {
    final endpoint = endpointFor(server);
    if (endpoint == null) {
      // Either collection is switched off for this server or its daemon has no
      // address this client can dial; the SSH collectors cover the second.
      maidCafeLog(
        'no direct daemon address for "${server.name}" '
        '(collectStats=${server.collectStats}); its statistics stay with the '
        'SSH collectors',
      );
      return null;
    }
    maidCafeLog('reading statistics for "${server.name}" from $endpoint');
    final secret =
        await _repository.maidCafeTerminalSecretFor(server) ??
        await _repository.maidCafeMetricsSecretFor(server);
    if (secret == null || secret.isEmpty) {
      maidCafeLog(
        'no daemon credential is stored for "${server.name}", so its '
        'statistics cannot be read directly',
      );
      return null;
    }
    MaidCafeStreamSession? session;
    try {
      session = await MaidCafeStreamSession.openAt(
        manager: _manager,
        baseUrl: endpoint,
        apiSecret: secret,
      );
      final metrics = await session.metrics();
      final stats = parseMaidCafeServerStats(metrics);
      if (stats == null) {
        maidCafeLog(
          'the daemon at $endpoint answered without usable metrics for '
          '"${server.name}"',
        );
        return null;
      }
      return MaidCafeServerStats(
        stats: stats,
        endpoint: endpoint,
        fetchedAt: DateTime.now(),
      );
    } catch (error) {
      maidCafeLog(
        'reading statistics for "${server.name}" from $endpoint failed',
        error: error,
      );
      return null;
    } finally {
      await session?.close();
    }
  }
}
