import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/activity_models.dart';
import 'package:maid_kit/servers/server_metrics_collector.dart';

void main() {
  test('parses macOS sysctl metrics output', () {
    final now = DateTime.fromMillisecondsSinceEpoch(2_000_000_000_000);
    final bootSeconds = now.millisecondsSinceEpoch ~/ 1000 - 86_400;
    final stats = parseMacosMetricsOutput('''
--LOAD--
{ 1.25 0.75 0.50 }
--CPU--
10
--MEMTOTAL--
17179869184
--VMSTAT--
Mach Virtual Memory Statistics: (page size of 16384 bytes)
Pages free:                               100.
Pages inactive:                           200.
Pages speculative:                         50.
--SWAP--
total = 4096.00M  used = 1024.00M  free = 3072.00M
--DISK--
Filesystem 1024-blocks Used Available Capacity Mounted on
/dev/disk3s1 104857600 52428800 52428800 50% /
/dev/disk3s5 209715200 104857600 104857600 50% /System/Volumes/Data
devfs 100 50 50 50% /dev
map auto_home 0 0 0 0% /System/Volumes/Data/home
--GPU--
0, NVIDIA A100, 12.5, 1024, 40960, 45
1, NVIDIA A100, 0, 0, 40960, N/A
--UPTIME--
{ sec = $bootSeconds, usec = 0 } Mon Jan  1 00:00:00 2024
''', now: now);

    expect(stats, isNotNull);
    expect(stats!.collectorId, 'macos-sysctl');
    expect(stats.loadAverage, 1.25);
    expect(stats.loadAverage5, 0.75);
    expect(stats.loadAverage15, 0.5);
    expect(stats.cpuCount, 10);
    expect(stats.memoryTotalKb, 16 * 1024 * 1024);
    expect(stats.memoryAvailableKb, 350 * 16);
    expect(stats.swapTotalKb, 4096 * 1024);
    expect(stats.gpus, hasLength(2));
    expect(stats.swapFreeKb, 3072 * 1024);
    expect(stats.diskTotalKb, 104857600);
    expect(stats.diskAvailableKb, 52428800);
    expect(stats.uptime, const Duration(days: 1));
    expect(stats.disks, hasLength(2));
    expect(stats.disks[0].mount, '/');
    expect(stats.disks[0].percent, 50);
    expect(stats.disks[1].mount, '/System/Volumes/Data');
    expect(stats.disks[1].filesystem, '/dev/disk3s5');
  });

  test('rejects output without a macOS load average', () {
    expect(parseMacosMetricsOutput('--CPU--\n8\n'), isNull);
  });

  test('parses Windows PowerShell metrics output', () {
    final now = DateTime(2026, 8, 8);
    final stats = parseWindowsMetricsOutput('''
--WINDOWS--
--LOAD--
2.4
--CPU--
8
--MEM--
MemTotal: 16777216
MemAvailable: 8388608
--SWAP--
SwapTotal: 4194304
SwapFree: 3145728
--DISK--
Disk C: 52428800 26214400 System
Disk D: 209715200 104857600 New Volume
--UPTIME--
86400
''', now: now);

    expect(stats, isNotNull);
    expect(stats!.collectorId, 'windows-powershell');
    expect(stats.loadAverage, 2.4);
    expect(stats.cpuCount, 8);
    expect(stats.memoryTotalKb, 16777216);
    expect(stats.memoryAvailableKb, 8388608);
    expect(stats.swapTotalKb, 4194304);
    expect(stats.swapFreeKb, 3145728);
    expect(stats.diskTotalKb, 52428800);
    expect(stats.diskAvailableKb, 26214400);
    expect(stats.uptime, const Duration(days: 1));
    expect(stats.updatedAt, now);
    expect(stats.disks, hasLength(2));
    expect(stats.disks[0].mount, 'C:');
    expect(stats.disks[0].percent, 50);
    expect(stats.disks[1].mount, 'D:');
  });

  test('parses all NVIDIA GPUs and converts memory to KiB', () {
    final gpus = parseNvidiaGpuMetricsOutput('''
0, NVIDIA A100, 12.5, 1024, 40960, 45
1, NVIDIA A100, 0, 0, 40960, N/A
''');

    expect(gpus, hasLength(2));
    expect(gpus[0].index, 0);
    expect(gpus[0].name, 'NVIDIA A100');
    expect(gpus[0].utilizationPercent, 12.5);
    expect(gpus[0].memoryUsedKb, 1024 * 1024);
    expect(gpus[0].memoryTotalKb, 40960 * 1024);
    expect(gpus[0].temperatureC, 45);
    expect(gpus[1].index, 1);
    expect(gpus[1].temperatureC, isNull);
  });

  test('activity counters preserve direct Windows CPU utilization', () {
    final sample = ActivityCounters(
      at: DateTime(2026, 8, 8),
      cpuPercent: 37.5,
      memoryTotalKb: 100,
      memoryAvailableKb: 25,
    ).toSample();

    expect(sample.cpuPercent, 37.5);
    expect(sample.memoryUsedKb, 75);
  });

  test('parses MaidCafe metrics into activity counters', () {
    final counters = parseMaidCafeMetrics({
      'sent_at': '2026-08-15T12:00:00Z',
      'cpu_percent': 37.5,
      'memory_used_bytes': 768000,
      'memory_total_bytes': 1024000,
      'uptime_seconds': 60,
      'disk_total_kb': 1000,
      'disk_available_kb': 500,
      'disks': [
        {
          'mount': '/',
          'filesystem': '/dev/vda1',
          'total_kb': 1000,
          'available_kb': 500,
        },
        {
          'mount': '/data',
          'filesystem': '/dev/vdb1',
          'total_kb': 4000,
          'available_kb': 1000,
        },
      ],
    });

    expect(counters, isNotNull);
    expect(counters!.cpuPercent, 37.5);
    expect(counters.memoryTotalKb, 1000);
    expect(counters.memoryAvailableKb, 250);
    expect(counters.uptime, const Duration(minutes: 1));
    expect(counters.toSample().memoryUsedKb, 750);
    expect(counters.disks, hasLength(2));
    expect(counters.disks[0].mount, '/');
    expect(counters.disks[0].percent, 50);
    expect(counters.disks[1].mount, '/data');
    expect(counters.toSample().disks, hasLength(2));
  });

  test(
    'parseDiskUsageLines keeps physical and network disks, skips virtual',
    () {
      final disks = parseDiskUsageLines('''
Filesystem 1024-blocks Used Available Capacity Mounted on
/dev/vda1 104857600 58654720 47104000 56% /
/dev/vdb1 516555776 77594624 412876800 16% /data
tmpfs 8171520 0 8171520 0% /dev/shm
tmpfs 8171520 839680 7331840 11% /run
10.0.0.5:/export 209715200 104857600 104857600 50% /mnt/nfs
''');

      expect(disks, hasLength(3));
      expect(disks[0].mount, '/');
      expect(disks[0].filesystem, '/dev/vda1');
      // percent is derived from total − available, not df's rounded column.
      expect(disks[0].usedKb, 57753600);
      expect(disks[0].percent, closeTo(55.08, 0.01));
      expect(disks[1].mount, '/data');
      expect(disks[1].availableKb, 412876800);
      expect(disks[2].mount, '/mnt/nfs');
      expect(disks[2].filesystem, '10.0.0.5:/export');
      expect(rootDiskUsage(disks)!.mount, '/');
    },
  );

  test('parseDiskUsageLines handles localized df headers', () {
    final disks = parseDiskUsageLines('''
文件系统 1024-blocks 已用 可用 容量 挂载点
/dev/vda1 104857600 58654720 47104000 56% /
/dev/vdb1 516555776 77594624 412876800 16% /data
''');

    expect(disks, hasLength(2));
  });

  test('parseDiskUsageLines dedupes a device mounted twice', () {
    final disks = parseDiskUsageLines('''
Filesystem 1024-blocks Used Available Capacity Mounted on
/dev/vda1 100 50 50 50% /
/dev/vda1 100 50 50 50% /var/lib/docker
''');

    expect(disks, hasLength(1));
    expect(disks.single.mount, '/');
  });

  test('parseDiskUsageLines parses Windows per-disk lines', () {
    final disks = parseDiskUsageLines('''
Disk C: 524288000 262144000 System
Disk D: 2097152000 1048576000 New Volume
''');

    expect(disks, hasLength(2));
    expect(disks[0].mount, 'C:');
    expect(disks[0].filesystem, 'C:');
    expect(disks[0].totalKb, 524288000);
    expect(disks[1].mount, 'D:');
    expect(rootDiskUsage(disks)!.mount, 'C:');
  });
}
