import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import 'server_models.dart';

abstract interface class ServerMetricsCollector {
  String get id;
  String get label;

  Future<ServerStats?> collect(SSHClient client);
}

/// Selects the first collector that can return a valid result for the host.
class AutoServerMetricsCollector implements ServerMetricsCollector {
  AutoServerMetricsCollector({List<ServerMetricsCollector>? collectors})
    : _collectors =
          collectors ??
          const [
            LinuxProcfsMetricsCollector(),
            MacosSysctlMetricsCollector(),
            WindowsPowerShellMetricsCollector(),
            UptimeMetricsCollector(),
          ];

  final List<ServerMetricsCollector> _collectors;

  @override
  String get id => 'auto';

  @override
  String get label => 'Automatic';

  @override
  Future<ServerStats?> collect(SSHClient client) async {
    for (final collector in _collectors) {
      try {
        final stats = await collector.collect(client);
        if (stats != null) return stats;
      } catch (_) {
        // Try the next compatible collector.
      }
    }
    return null;
  }
}

class MacosSysctlMetricsCollector implements ServerMetricsCollector {
  const MacosSysctlMetricsCollector();

  @override
  String get id => 'macos-sysctl';

  @override
  String get label => 'macOS sysctl';

  @override
  Future<ServerStats?> collect(SSHClient client) async {
    final output = await _run(client, r"""sh -c '
if [ "$(uname -s 2>/dev/null)" != "Darwin" ]; then exit 1; fi
echo --LOAD--
sysctl -n vm.loadavg 2>/dev/null || true
echo --CPU--
sysctl -n hw.ncpu 2>/dev/null || true
echo --MEMTOTAL--
sysctl -n hw.memsize 2>/dev/null || true
echo --VMSTAT--
vm_stat 2>/dev/null || true
echo --SWAP--
sysctl -n vm.swapusage 2>/dev/null || true
echo --DISK--
df -Pk 2>/dev/null || true
echo --GPU--
nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null || true
echo --UPTIME--
sysctl -n kern.boottime 2>/dev/null || true
'""");
    return parseMacosMetricsOutput(output);
  }
}

class WindowsPowerShellMetricsCollector implements ServerMetricsCollector {
  const WindowsPowerShellMetricsCollector();

  @override
  String get id => 'windows-powershell';

  @override
  String get label => 'Windows PowerShell';

  @override
  Future<ServerStats?> collect(SSHClient client) async {
    final output = await _run(
      client,
      encodePowerShellCommand(r'''
$ErrorActionPreference = 'Stop'
$os = Get-CimInstance Win32_OperatingSystem
$processors = @(Get-CimInstance Win32_Processor)
$cpuCount = [int](($processors | Measure-Object NumberOfLogicalProcessors -Sum).Sum)
$loadPercent = [double](($processors | Measure-Object LoadPercentage -Average).Average)
$load = if ($cpuCount -gt 0) { $loadPercent * $cpuCount / 100 } else { $null }
$pageFiles = @(Get-CimInstance Win32_PageFileUsage)
$swapTotalKb = [int64](($pageFiles | Measure-Object AllocatedBaseSize -Sum).Sum)
$swapUsedKb = [int64](($pageFiles | Measure-Object CurrentUsage -Sum).Sum)
$disks = @(Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 -or $_.DriveType -eq 4 })
Write-Output '--LOAD--'
if ($null -ne $load) { $load.ToString('0.##', [Globalization.CultureInfo]::InvariantCulture) }
Write-Output '--CPU--'
$cpuCount
Write-Output '--MEM--'
"MemTotal: $($os.TotalVisibleMemorySize)"
"MemAvailable: $($os.FreePhysicalMemory)"
Write-Output '--SWAP--'
"SwapTotal: $swapTotalKb"
"SwapFree: $([math]::Max(0, $swapTotalKb - $swapUsedKb))"
Write-Output '--DISK--'
foreach ($disk in $disks) {
  "Disk $($disk.DeviceID) $([int64]($disk.Size / 1KB)) $([int64]($disk.FreeSpace / 1KB)) $($disk.VolumeName)"
}
Write-Output '--GPU--'
if (Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue) {
  & nvidia-smi.exe '--query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu' '--format=csv,noheader,nounits' 2>$null
}
Write-Output '--UPTIME--'
[int64](([DateTime]::UtcNow - $os.LastBootUpTime.ToUniversalTime()).TotalSeconds)
'''),
    );
    return parseWindowsMetricsOutput(output);
  }
}

class LinuxProcfsMetricsCollector implements ServerMetricsCollector {
  const LinuxProcfsMetricsCollector();

  @override
  String get id => 'linux-procfs';

  @override
  String get label => 'Linux procfs';

  @override
  Future<ServerStats?> collect(SSHClient client) async {
    final output = await _run(
      client,
      "sh -c 'cat /proc/loadavg; echo --CPU--; getconf _NPROCESSORS_ONLN 2>/dev/null || nproc; echo --MEM--; cat /proc/meminfo; echo --DISK--; df -Pk; echo --GPU--; nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null || true; echo --UPTIME--; cut -d. -f1 /proc/uptime'",
    );
    final sections = output.split('--CPU--');
    if (sections.length != 2) return null;
    final loads = sections.first.trim().split(RegExp(r'\s+'));
    final load = double.tryParse(loads.first);
    final cpuAndRest = sections[1].split('--MEM--');
    if (cpuAndRest.length != 2 || load == null) return null;
    final memoryAndRest = cpuAndRest[1].split('--DISK--');
    if (memoryAndRest.length != 2) return null;
    final diskAndGpu = memoryAndRest[1].split('--GPU--');
    if (diskAndGpu.length != 2) return null;
    final gpuAndUptime = diskAndGpu[1].split('--UPTIME--');
    if (gpuAndUptime.length != 2) return null;
    int? valueFor(String label) {
      final match = RegExp('$label:\\s+(\\d+)').firstMatch(memoryAndRest[0]);
      return match == null ? null : int.tryParse(match.group(1)!);
    }

    final disks = parseDiskUsageLines(diskAndGpu[0]);
    final root = rootDiskUsage(disks);

    return ServerStats(
      collectorId: id,
      updatedAt: DateTime.now(),
      loadAverage: load,
      loadAverage5: loads.length > 1 ? double.tryParse(loads[1]) : null,
      loadAverage15: loads.length > 2 ? double.tryParse(loads[2]) : null,
      cpuCount: int.tryParse(cpuAndRest[0].trim()),
      memoryTotalKb: valueFor('MemTotal'),
      memoryAvailableKb: valueFor('MemAvailable'),
      swapTotalKb: valueFor('SwapTotal'),
      swapFreeKb: valueFor('SwapFree'),
      diskTotalKb: root?.totalKb,
      diskAvailableKb: root?.availableKb,
      gpus: parseNvidiaGpuMetricsOutput(gpuAndUptime[0]),
      uptime: Duration(seconds: int.tryParse(gpuAndUptime[1].trim()) ?? 0),
      disks: disks,
    );
  }
}

/// Parses the normalized output emitted by [MacosSysctlMetricsCollector].
ServerStats? parseMacosMetricsOutput(String output, {DateTime? now}) {
  final loads = _parseLoadTriple(_metricSection(output, 'LOAD'));
  final load = loads.$1;
  if (load == null) return null;

  final totalBytes = int.tryParse(_metricSection(output, 'MEMTOTAL').trim());
  final availableBytes = _parseMacosAvailableMemory(
    _metricSection(output, 'VMSTAT'),
  );
  final swap = _parseMacosSwap(_metricSection(output, 'SWAP'));
  final disks = parseDiskUsageLines(_metricSection(output, 'DISK'));
  final root = rootDiskUsage(disks);
  final bootSeconds = RegExp(
    r'sec\s*=\s*(\d+)',
  ).firstMatch(_metricSection(output, 'UPTIME'))?.group(1);
  final boot = bootSeconds == null ? null : int.tryParse(bootSeconds);
  final currentTime = now ?? DateTime.now();
  final uptime = boot == null
      ? null
      : Duration(
          seconds: (currentTime.millisecondsSinceEpoch ~/ 1000 - boot).clamp(
            0,
            0x7fffffffffffffff,
          ),
        );

  return ServerStats(
    collectorId: 'macos-sysctl',
    updatedAt: currentTime,
    loadAverage: load,
    loadAverage5: loads.$2,
    loadAverage15: loads.$3,
    cpuCount: int.tryParse(_metricSection(output, 'CPU').trim()),
    memoryTotalKb: totalBytes == null ? null : totalBytes ~/ 1024,
    memoryAvailableKb: availableBytes == null ? null : availableBytes ~/ 1024,
    swapTotalKb: swap.$1,
    swapFreeKb: swap.$2,
    diskTotalKb: root?.totalKb,
    diskAvailableKb: root?.availableKb,
    gpus: parseNvidiaGpuMetricsOutput(_metricSection(output, 'GPU')),
    uptime: uptime,
    disks: disks,
  );
}

/// Parses `nvidia-smi --query-gpu=... --format=csv,noheader,nounits` rows.
///
/// NVIDIA reports memory in MiB; the app's resource model stores memory in
/// KiB. A row is retained when its index and name are valid, even if an
/// individual sensor returns `N/A`.
List<ServerGpuStats> parseNvidiaGpuMetricsOutput(String output) {
  final gpus = <ServerGpuStats>[];
  for (final line in output.split('\n')) {
    final fields = line.trim().split(',').map((field) => field.trim()).toList();
    if (fields.length < 6) continue;
    final index = int.tryParse(fields[0]);
    final name = fields[1];
    if (index == null || name.isEmpty) continue;
    int? memoryKb(String value) {
      final mib = int.tryParse(value);
      return mib == null ? null : mib * 1024;
    }

    gpus.add(
      ServerGpuStats(
        index: index,
        name: name,
        utilizationPercent: double.tryParse(fields[2]),
        memoryUsedKb: memoryKb(fields[3]),
        memoryTotalKb: memoryKb(fields[4]),
        temperatureC: double.tryParse(fields[5]),
      ),
    );
  }
  return gpus;
}

/// Parses the normalized output emitted by [WindowsPowerShellMetricsCollector].
ServerStats? parseWindowsMetricsOutput(String output, {DateTime? now}) {
  final load = double.tryParse(_metricSection(output, 'LOAD').trim());
  if (load == null) return null;
  int? value(String section, String label) {
    final match = RegExp(
      '^$label:\\s*(\\d+)',
      multiLine: true,
    ).firstMatch(_metricSection(output, section));
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  final currentTime = now ?? DateTime.now();
  final uptimeSeconds = int.tryParse(_metricSection(output, 'UPTIME').trim());
  final disks = parseDiskUsageLines(_metricSection(output, 'DISK'));
  final root = rootDiskUsage(disks);
  return ServerStats(
    collectorId: 'windows-powershell',
    updatedAt: currentTime,
    loadAverage: load,
    cpuCount: int.tryParse(_metricSection(output, 'CPU').trim()),
    memoryTotalKb: value('MEM', 'MemTotal'),
    memoryAvailableKb: value('MEM', 'MemAvailable'),
    swapTotalKb: value('SWAP', 'SwapTotal'),
    swapFreeKb: value('SWAP', 'SwapFree'),
    diskTotalKb: root?.totalKb,
    diskAvailableKb: root?.availableKb,
    gpus: parseNvidiaGpuMetricsOutput(_metricSection(output, 'GPU')),
    uptime: uptimeSeconds == null
        ? null
        : Duration(seconds: uptimeSeconds.clamp(0, 0x7fffffffffffffff)),
    disks: disks,
  );
}

/// Filesystem identifiers that never back user data; `df` rows for these are
/// skipped so the disk list stays limited to physical and network storage.
const _virtualFilesystems = <String>{
  'tmpfs',
  'devtmpfs',
  'devfs',
  'udev',
  'proc',
  'sysfs',
  'cgroup',
  'cgroup2',
  'overlay',
  'squashfs',
  'ramfs',
  'hugetlbfs',
  'mqueue',
  'shm',
  'devpts',
  'debugfs',
  'tracefs',
  'securityfs',
  'configfs',
  'fusectl',
  'pstore',
  'efivarfs',
  'autofs',
  'binfmt_misc',
  'rpc_pipefs',
  'nsfs',
  'bpf',
  'iso9660',
  'udf',
  'none',
  'map',
};

bool _isReportableFilesystem(String filesystem) {
  if (_virtualFilesystems.contains(filesystem)) return false;
  return filesystem.startsWith('/dev/') ||
      filesystem.startsWith('//') || // SMB/CIFS share
      filesystem.contains(':'); // NFS `host:/export`
}

/// Parses a `--DISK--` section into per-filesystem capacity snapshots.
///
/// Two shapes are accepted:
/// - `df -Pk` tabular output (Linux/macOS): a data row has six or more
///   whitespace-separated fields with numeric 1024-block, used, and available
///   columns and a capacity column ending in `%`. The locale-dependent header
///   is skipped by that shape check, so non-English `df` output still parses.
/// - Windows per-disk lines emitted by the PowerShell collectors:
///   `Disk C: <totalKb> <availableKb> [VolumeName]`.
///
/// Virtual filesystems and duplicate devices (bind mounts, macOS synthesized
/// snapshots) are skipped; the list keeps `df` order, root first.
List<DiskUsage> parseDiskUsageLines(String output) {
  final disks = <DiskUsage>[];
  final seenFilesystems = <String>{};
  for (final rawLine in output.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final fields = line.split(RegExp(r'\s+'));
    DiskUsage? disk;
    if (fields.length >= 4 && fields[0] == 'Disk' && fields[1].endsWith(':')) {
      final total = int.tryParse(fields[2]);
      final available = int.tryParse(fields[3]);
      if (total == null || available == null) continue;
      disk = DiskUsage(
        filesystem: fields[1],
        mount: fields[1],
        totalKb: total,
        availableKb: available,
      );
    } else if (fields.length >= 6 &&
        int.tryParse(fields[1]) != null &&
        int.tryParse(fields[2]) != null &&
        int.tryParse(fields[3]) != null &&
        fields[4].endsWith('%')) {
      final filesystem = fields[0];
      if (!_isReportableFilesystem(filesystem)) continue;
      disk = DiskUsage(
        filesystem: filesystem,
        mount: fields.sublist(5).join(' '),
        totalKb: int.tryParse(fields[1]),
        availableKb: int.tryParse(fields[3]),
      );
    }
    if (disk == null) continue;
    final filesystem = disk.filesystem;
    if (filesystem != null && !seenFilesystems.add(filesystem)) continue;
    disks.add(disk);
  }
  return disks;
}

/// The root/boot filesystem for aggregate views and legacy fields: the disk
/// mounted at '/' on POSIX hosts, otherwise the first reported disk (C: on
/// Windows). Null when no disk was collected.
DiskUsage? rootDiskUsage(List<DiskUsage> disks) {
  for (final disk in disks) {
    if (disk.mount == '/') return disk;
  }
  return disks.isEmpty ? null : disks.first;
}

/// A portable fallback for POSIX-like hosts where procfs is unavailable.
class UptimeMetricsCollector implements ServerMetricsCollector {
  const UptimeMetricsCollector();

  @override
  String get id => 'uptime';

  @override
  String get label => 'Uptime command';

  @override
  Future<ServerStats?> collect(SSHClient client) async {
    final output = await _run(client, 'uptime');
    final match = RegExp(
      r'load averages?:\s*(.*)',
      caseSensitive: false,
    ).firstMatch(output);
    final loads = _parseLoadTriple(match?.group(1));
    if (loads.$1 == null) return null;
    return ServerStats(
      collectorId: id,
      updatedAt: DateTime.now(),
      loadAverage: loads.$1,
      loadAverage5: loads.$2,
      loadAverage15: loads.$3,
    );
  }
}

String _metricSection(String output, String label) {
  final start = output.indexOf('--$label--');
  if (start < 0) return '';
  final after = start + label.length + 4;
  final next = output.indexOf('--', after);
  return (next < 0 ? output.substring(after) : output.substring(after, next))
      .trim();
}

(double?, double?, double?) _parseLoadTriple(String? output) {
  final values = RegExp(r'[0-9]+(?:\.[0-9]+)?')
      .allMatches(output ?? '')
      .map((match) => double.tryParse(match.group(0)!))
      .whereType<double>()
      .toList();
  double? at(int index) => values.length > index ? values[index] : null;
  return (at(0), at(1), at(2));
}

int? _parseMacosAvailableMemory(String output) {
  final pageSize = int.tryParse(
    RegExp(r'page size of (\d+) bytes').firstMatch(output)?.group(1) ?? '',
  );
  if (pageSize == null) return null;
  int? pages(String label) => int.tryParse(
    RegExp('$label:\\s+(\\d+)').firstMatch(output)?.group(1) ?? '',
  );
  final availablePages = [
    pages('Pages free'),
    pages('Pages inactive'),
    pages('Pages speculative'),
  ].whereType<int>().toList();
  if (availablePages.isEmpty) return null;
  return availablePages.fold<int>(0, (sum, value) => sum + value) * pageSize;
}

(int?, int?) _parseMacosSwap(String output) {
  int? value(String label) {
    final match = RegExp(
      '$label\\s*=\\s*([0-9]+(?:\\.[0-9]+)?)([KMGT])',
      caseSensitive: false,
    ).firstMatch(output);
    if (match == null) return null;
    final amount = double.tryParse(match.group(1)!);
    if (amount == null) return null;
    final multiplier = switch (match.group(2)!.toUpperCase()) {
      'K' => 1,
      'M' => 1024,
      'G' => 1024 * 1024,
      'T' => 1024 * 1024 * 1024,
      _ => 1,
    };
    return (amount * multiplier).round();
  }

  return (value('total'), value('free'));
}

/// Encodes an ASCII PowerShell script for OpenSSH's Windows shell.
///
/// `-EncodedCommand` requires UTF-16LE rather than UTF-8.
String encodePowerShellCommand(String script) {
  final bytes = <int>[];
  for (final codeUnit in script.codeUnits) {
    bytes
      ..add(codeUnit & 0xff)
      ..add((codeUnit >> 8) & 0xff);
  }
  return 'powershell.exe -NoLogo -NoProfile -NonInteractive '
      '-ExecutionPolicy Bypass -EncodedCommand ${base64.encode(bytes)}';
}

Future<String> _run(SSHClient client, String command) async {
  final session = await client.execute(command);
  final output = await utf8.decoder.bind(session.stdout).join();
  await session.done;
  return output;
}
