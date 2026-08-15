import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/activity_models.dart';

void main() {
  test('parseMaidCafeMetrics maps system, disk and network counters', () {
    final counters = parseMaidCafeMetrics({
      'sent_at': '2026-08-15T08:00:00.000Z',
      'cpu_percent': 12.5,
      'cpu_count': 4,
      'load1': 0.75,
      'load5': 0.5,
      'load15': 0.25,
      'memory_used_bytes': 1 << 30,
      'memory_total_bytes': 4 << 30,
      'swap_total_kb': 2000000,
      'swap_free_kb': 1500000,
      'disk_total_kb': 50000000,
      'disk_available_kb': 10000000,
      'net_rx_bytes': 123456789,
      'net_tx_bytes': 987654321,
      'uptime_seconds': 3600,
    });
    expect(counters, isNotNull);
    expect(counters!.cpuPercent, 12.5);
    expect(counters.cpuCount, 4);
    expect(counters.load1, 0.75);
    expect(counters.load5, 0.5);
    expect(counters.load15, 0.25);
    expect(counters.memoryTotalKb, 4 << 20);
    expect(counters.swapTotalKb, 2000000);
    expect(counters.diskTotalKb, 50000000);
    expect(counters.diskAvailableKb, 10000000);
    expect(counters.netRxBytes, 123456789);
    expect(counters.netTxBytes, 987654321);

    final sample = counters.toSample();
    expect(sample.diskUsedKb, 50000000 - 10000000);
    expect(sample.diskPercent, closeTo(80, 0.001));
    expect(sample.netRxBytes, 123456789);
    expect(sample.uptime, const Duration(hours: 1));
  });

  test(
    'parseMaidCafeMetrics derives network rates from consecutive samples',
    () {
      final first = parseMaidCafeMetrics({
        'sent_at': '2026-08-15T08:00:00.000Z',
        'cpu_percent': 1,
        'net_rx_bytes': 1000,
        'net_tx_bytes': 2000,
      })!;
      final second = parseMaidCafeMetrics({
        'sent_at': '2026-08-15T08:00:02.000Z',
        'cpu_percent': 1,
        'net_rx_bytes': 3000,
        'net_tx_bytes': 3000,
      })!;
      final sample = second.toSample(previous: first);
      expect(sample.netRxBps, 1000);
      expect(sample.netTxBps, 500);
    },
  );

  test('parseMaidCafeMetrics returns null without core fields', () {
    expect(parseMaidCafeMetrics(const {'disk_total_kb': 1}), isNull);
  });
}
