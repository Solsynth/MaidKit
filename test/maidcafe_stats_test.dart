import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/maidcafe_stats.dart';

void main() {
  test('parses a daemon metrics payload into host statistics', () {
    final stats = parseMaidCafeServerStats({
      'sent_at': '2026-08-15T08:00:00.000Z',
      'cpu_percent': 12.5,
      'cpu_count': 8,
      'load1': 0.75,
      'load5': 1.25,
      'load15': 1.5,
      'memory_used_bytes': 2 << 30,
      'memory_total_bytes': 8 << 30,
      'swap_total_kb': 2000000,
      'swap_free_kb': 1500000,
      'disk_total_kb': 50000000,
      'disk_available_kb': 10000000,
      'uptime_seconds': 90061,
    });

    expect(stats, isNotNull);
    // Bytes are reported by the daemon and kilobytes by the SSH collectors;
    // the parse must land on the same unit or every card renders a wrong figure.
    expect(stats!.memoryTotalKb, 8 << 20);
    expect(stats.memoryAvailableKb, 6 << 20);
    expect(stats.loadAverage, 0.75);
    expect(stats.loadAverage5, 1.25);
    expect(stats.loadAverage15, 1.5);
    expect(stats.cpuCount, 8);
    expect(stats.swapTotalKb, 2000000);
    expect(stats.swapFreeKb, 1500000);
    expect(stats.diskTotalKb, 50000000);
    expect(stats.diskAvailableKb, 10000000);
    expect(
      stats.uptime,
      const Duration(days: 1, hours: 1, minutes: 1, seconds: 1),
    );
    expect(stats.updatedAt, DateTime.utc(2026, 8, 15, 8));
    expect(stats.collectorId, 'maidcafe');
  });

  test('keeps the mount list and falls back to it for the root aggregate', () {
    final stats = parseMaidCafeServerStats({
      'uptime_seconds': 10,
      'disks': [
        {
          'mount': '/data',
          'filesystem': '/dev/vdb1',
          'total_kb': 100,
          'available_kb': 40,
        },
        {
          'mount': '/',
          'filesystem': '/dev/vda1',
          'total_kb': 200,
          'available_kb': 50,
        },
      ],
    });

    expect(stats!.disks, hasLength(2));
    expect(stats.disks.first.mount, '/data');
    // No top-level disk fields: the root entry of the list stands in.
    expect(stats.diskTotalKb, 200);
    expect(stats.diskAvailableKb, 50);
  });

  test('uses the first mount when the daemon reports no root entry', () {
    final stats = parseMaidCafeServerStats({
      'uptime_seconds': 10,
      'disks': [
        {'mount': '/srv', 'total_kb': 300, 'available_kb': 120},
      ],
    });

    expect(stats!.diskTotalKb, 300);
    expect(stats.diskAvailableKb, 120);
  });

  test('returns null for a payload with nothing usable in it', () {
    // A truncated body, an error envelope, or another endpoint's JSON must not
    // be mistaken for a host with no load, no memory and no uptime.
    expect(parseMaidCafeServerStats(const {}), isNull);
    expect(
      parseMaidCafeServerStats(const {'ok': false, 'error': 'unauthorized'}),
      isNull,
    );
  });

  test('keeps an absent uptime null instead of a zero duration', () {
    final stats = parseMaidCafeServerStats(const {'load1': 0.1});

    expect(stats, isNotNull);
    expect(stats!.uptime, isNull);
    expect(stats.memoryTotalKb, isNull);
    expect(stats.loadAverage, 0.1);
  });
}
