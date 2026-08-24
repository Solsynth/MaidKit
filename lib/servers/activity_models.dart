import 'server_models.dart';

/// One point in the live activity history used by the Activity tab charts.
class ActivitySample {
  const ActivitySample({
    required this.at,
    this.cpuPercent,
    this.load1,
    this.load5,
    this.load15,
    this.cpuCount,
    this.memoryUsedKb,
    this.memoryTotalKb,
    this.swapUsedKb,
    this.swapTotalKb,
    this.diskUsedKb,
    this.diskTotalKb,
    this.netRxBytes,
    this.netTxBytes,
    this.netRxBps,
    this.netTxBps,
    this.uptime,
    this.disks = const [],
  });

  final DateTime at;
  final double? cpuPercent;
  final double? load1;
  final double? load5;
  final double? load15;
  final int? cpuCount;
  final int? memoryUsedKb;
  final int? memoryTotalKb;
  final int? swapUsedKb;
  final int? swapTotalKb;
  final int? diskUsedKb;
  final int? diskTotalKb;

  /// Cumulative counters from `/proc/net/dev` (all non-loopback interfaces).
  final int? netRxBytes;
  final int? netTxBytes;

  /// Bytes/sec derived from consecutive samples.
  final double? netRxBps;
  final double? netTxBps;
  final Duration? uptime;

  /// Every reportable mounted filesystem, root first; empty for legacy
  /// single-disk samples.
  final List<DiskUsage> disks;

  double? get memoryPercent {
    final used = memoryUsedKb;
    final total = memoryTotalKb;
    if (used == null || total == null || total == 0) return null;
    return (used / total * 100).clamp(0, 100);
  }

  double? get swapPercent {
    final used = swapUsedKb;
    final total = swapTotalKb;
    if (used == null || total == null || total == 0) return null;
    return (used / total * 100).clamp(0, 100);
  }

  double? get diskPercent {
    final used = diskUsedKb;
    final total = diskTotalKb;
    if (used == null || total == null || total == 0) return null;
    return (used / total * 100).clamp(0, 100);
  }

  /// Load average normalized to a rough 0–100% scale using CPU count.
  double? get loadPercent {
    final load = load1;
    final cpus = cpuCount;
    if (load == null || cpus == null || cpus == 0) return null;
    return (load / cpus * 100).clamp(0, 200);
  }
}

/// Raw counters collected in a single SSH round-trip; deltas are computed in the UI.
class ActivityCounters {
  const ActivityCounters({
    required this.at,
    this.cpuIdle,
    this.cpuTotal,
    this.cpuPercent,
    this.load1,
    this.load5,
    this.load15,
    this.cpuCount,
    this.memoryTotalKb,
    this.memoryAvailableKb,
    this.swapTotalKb,
    this.swapFreeKb,
    this.diskTotalKb,
    this.diskAvailableKb,
    this.netRxBytes,
    this.netTxBytes,
    this.netRxBps,
    this.netTxBps,
    this.uptime,
    this.disks = const [],
  });

  final DateTime at;
  final int? cpuIdle;
  final int? cpuTotal;

  /// Direct CPU utilization for platforms without cumulative CPU counters.
  final double? cpuPercent;
  final double? load1;
  final double? load5;
  final double? load15;
  final int? cpuCount;
  final int? memoryTotalKb;
  final int? memoryAvailableKb;
  final int? swapTotalKb;
  final int? swapFreeKb;
  final int? diskTotalKb;
  final int? diskAvailableKb;
  final int? netRxBytes;

  /// Direct rates supplied by MaidCafe when cumulative counters are absent.
  final double? netRxBps;
  final double? netTxBps;
  final int? netTxBytes;
  final Duration? uptime;

  /// Every reportable mounted filesystem, root first; empty for legacy
  /// single-disk counters.
  final List<DiskUsage> disks;
  ActivitySample toSample({ActivityCounters? previous}) {
    double? cpuPercent = this.cpuPercent;
    double? netRxBps = this.netRxBps;
    double? netTxBps = this.netTxBps;
    if (cpuPercent == null &&
        previous != null &&
        cpuIdle != null &&
        cpuTotal != null &&
        previous.cpuIdle != null &&
        previous.cpuTotal != null) {
      final idleDelta = cpuIdle! - previous.cpuIdle!;
      final totalDelta = cpuTotal! - previous.cpuTotal!;
      if (totalDelta > 0) {
        cpuPercent = ((1 - idleDelta / totalDelta) * 100).clamp(0, 100);
      }
    }
    if (previous != null &&
        netRxBytes != null &&
        netTxBytes != null &&
        previous.netRxBytes != null &&
        previous.netTxBytes != null) {
      final seconds = at.difference(previous.at).inMilliseconds / 1000.0;
      if (seconds > 0) {
        final rxDelta = netRxBytes! - previous.netRxBytes!;
        final txDelta = netTxBytes! - previous.netTxBytes!;
        if (rxDelta >= 0) netRxBps = rxDelta / seconds;
        if (txDelta >= 0) netTxBps = txDelta / seconds;
      }
    }
    final memUsed = memoryTotalKb == null || memoryAvailableKb == null
        ? null
        : memoryTotalKb! - memoryAvailableKb!;
    final swapUsed = swapTotalKb == null || swapFreeKb == null
        ? null
        : swapTotalKb! - swapFreeKb!;
    final diskUsed = diskTotalKb == null || diskAvailableKb == null
        ? null
        : diskTotalKb! - diskAvailableKb!;
    return ActivitySample(
      at: at,
      cpuPercent: cpuPercent,
      load1: load1,
      load5: load5,
      load15: load15,
      cpuCount: cpuCount,
      memoryUsedKb: memUsed,
      memoryTotalKb: memoryTotalKb,
      swapUsedKb: swapUsed,
      swapTotalKb: swapTotalKb,
      diskUsedKb: diskUsed,
      diskTotalKb: diskTotalKb,
      netRxBytes: netRxBytes,
      netTxBytes: netTxBytes,
      netRxBps: netRxBps,
      netTxBps: netTxBps,
      uptime: uptime,
      disks: disks,
    );
  }
}

/// Converts the MaidCafe `/api/v1/metrics` payload into activity counters.
ActivityCounters? parseMaidCafeMetrics(Map<String, dynamic> response) {
  final cpuPercent = _metricDouble(response['cpu_percent']);
  final memoryUsedBytes = _metricInt(response['memory_used_bytes']);
  final memoryTotalBytes = _metricInt(response['memory_total_bytes']);
  final uptimeSeconds = _metricInt(response['uptime_seconds']);
  if (cpuPercent == null &&
      memoryUsedBytes == null &&
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
  return ActivityCounters(
    at:
        DateTime.tryParse(response['sent_at']?.toString() ?? '') ??
        DateTime.now(),
    cpuPercent: cpuPercent,
    cpuCount: _metricInt(response['cpu_count']),
    load1: _metricDouble(response['load1']),
    load5: _metricDouble(response['load5']),
    load15: _metricDouble(response['load15']),
    memoryTotalKb: memoryTotalKb,
    memoryAvailableKb: memoryAvailableKb,
    swapTotalKb: _metricInt(response['swap_total_kb']),
    swapFreeKb: _metricInt(response['swap_free_kb']),
    diskTotalKb: _metricInt(response['disk_total_kb']),
    diskAvailableKb: _metricInt(response['disk_available_kb']),
    disks: [
      for (final item in (response['disks'] as List? ?? const []))
        if (item is Map)
          DiskUsage(
            mount: item['mount']?.toString() ?? '',
            filesystem: item['filesystem']?.toString(),
            totalKb: _metricInt(item['total_kb']),
            availableKb: _metricInt(item['available_kb']),
          ),
    ],
    netRxBytes: _metricInt(response['net_rx_bytes']),
    netTxBytes: _metricInt(response['net_tx_bytes']),
    uptime: uptimeSeconds == null ? null : Duration(seconds: uptimeSeconds),
  );
}

double? _metricDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

int? _metricInt(Object? value) => _metricDouble(value)?.round();
