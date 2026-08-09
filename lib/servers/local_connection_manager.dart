import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'server_models.dart';
import 'ssh_connection_manager.dart';
import 'terminal_session_adapter.dart';

/// The fixed id of the virtual "this computer" server. Database row ids start
/// at 1, so 0 never collides with a stored server.
const int localMachineServerId = 0;

/// Whether the current host machine can appear as a server card. Local
/// management is available on Windows and Linux; macOS is excluded so the app
/// can run inside the macOS sandbox without local process access.
final bool localMachineSupported =
    !kIsWeb && (Platform.isWindows || Platform.isLinux);

/// Collects load, memory, disk, uptime, and OS identity from the machine
/// MaidKit runs on, without any network transport.
class LocalMachineMetricsCollector {
  const LocalMachineMetricsCollector();

  /// Returns null when the platform has no stats source.
  Future<ServerStats?> collect() async {
    if (Platform.isMacOS) return _collectMacos();
    if (Platform.isLinux) return _collectLinux();
    if (Platform.isWindows) return _collectWindows();
    return null;
  }

  /// OS identity for the local machine. Never fails; unknown platforms fall
  /// back to what `dart:io` reports.
  Future<ServerSystemInfo> systemInfo() async {
    if (Platform.isMacOS) return _systemInfoMacos();
    if (Platform.isLinux) return _systemInfoLinux();
    if (Platform.isWindows) return _systemInfoWindows();
    return ServerSystemInfo(
      distribution:
          '${_osName(Platform.operatingSystem)} '
          '${Platform.operatingSystemVersion}',
    );
  }

  Future<ServerStats?> _collectMacos() async {
    final load = await _run('sysctl', const ['-n', 'vm.loadavg']);
    final memoryBytes = await _run('sysctl', const ['-n', 'hw.memsize']);
    final vmStat = await _run('vm_stat', const []);
    final cpuCount = await _run('sysctl', const ['-n', 'hw.ncpu']);
    final bootTime = await _run('sysctl', const ['-n', 'kern.boottime']);
    final swapUsage = await _run('sysctl', const ['-n', 'vm.swapusage']);
    final disk = await _run('df', const ['-Pk', '/']);

    final loads = _parseLoads(load);
    final totalBytes = int.tryParse((memoryBytes ?? '').trim());
    final availableBytes = _parseVmStat(vmStat);
    final swap = _parseSwapUsage(swapUsage);
    return ServerStats(
      collectorId: 'local',
      updatedAt: DateTime.now(),
      loadAverage: loads.$1,
      loadAverage5: loads.$2,
      loadAverage15: loads.$3,
      cpuCount: int.tryParse((cpuCount ?? '').trim()),
      memoryTotalKb: totalBytes == null ? null : totalBytes ~/ 1024,
      memoryAvailableKb: availableBytes == null ? null : availableBytes ~/ 1024,
      swapTotalKb: swap.$1,
      swapFreeKb: swap.$2,
      diskTotalKb: _diskField(disk, 1),
      diskAvailableKb: _diskField(disk, 3),
      uptime: _uptimeFromBootTime(bootTime),
    );
  }

  Future<ServerStats?> _collectLinux() async {
    final load = await _readFile('/proc/loadavg');
    final mem = await _readFile('/proc/meminfo');
    final uptime = await _readFile('/proc/uptime');
    final cpuCount = await _run('nproc', const []);
    final disk = await _run('df', const ['-Pk', '/']);

    final loads = _parseLoads(load);
    int? memKb(String label) {
      final match = RegExp(
        '^$label:\\s+(\\d+)',
        multiLine: true,
      ).firstMatch(mem ?? '');
      return match == null ? null : int.tryParse(match.group(1)!);
    }

    final uptimeSeconds = double.tryParse(
      (uptime ?? '').trim().split(' ').first,
    );
    return ServerStats(
      collectorId: 'local',
      updatedAt: DateTime.now(),
      loadAverage: loads.$1,
      loadAverage5: loads.$2,
      loadAverage15: loads.$3,
      cpuCount: int.tryParse((cpuCount ?? '').trim()),
      memoryTotalKb: memKb('MemTotal'),
      memoryAvailableKb: memKb('MemAvailable'),
      swapTotalKb: memKb('SwapTotal'),
      swapFreeKb: memKb('SwapFree'),
      diskTotalKb: _diskField(disk, 1),
      diskAvailableKb: _diskField(disk, 3),
      uptime: uptimeSeconds == null
          ? null
          : Duration(seconds: uptimeSeconds.round()),
    );
  }

  /// Collects metrics on Windows via a single PowerShell invocation that emits
  /// `key=value` lines, parsed below. CIM classes are the cross-version source
  /// available on Windows 10/11 with Windows PowerShell 5.1 (`powershell.exe`,
  /// always present); missing perf counters degrade gracefully to null.
  Future<ServerStats?> _collectWindows() async {
    // One PowerShell invocation emitting `key=value` lines. `powershell.exe`
    // (Windows PowerShell 5.1) is always present on Win10/11; missing perf
    // counters degrade to null via -ErrorAction SilentlyContinue.
    const script = r'''$os = Get-CimInstance Win32_OperatingSystem
$sys = Get-CimInstance Win32_PerfFormattedData_PerfOS_System -ErrorAction SilentlyContinue
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'" -ErrorAction SilentlyContinue
$pf = Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue
"cpuCount=$($env:NUMBER_OF_PROCESSORS)"
"memTotalKb=$($os.TotalVisibleMemorySize)"
"memFreeKb=$($os.FreePhysicalMemory)"
"queueLen=$($sys.ProcessorQueueLength)"
"diskBytes=$($disk.Size)"
"diskFreeBytes=$($disk.FreeSpace)"
"uptimeSecs=$([Math]::Floor(((Get-Date) - $os.LastBootUpTime).TotalSeconds))"
if ($pf) { "swapTotalKb=$($pf.AllocatedBaseSize * 1024)"; "swapFreeKb=$((($pf.AllocatedBaseSize - $pf.CurrentUsage) * 1024))" }''';
    final output = await _run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      script,
    ]);
    if (output == null) return null;
    int? intField(String key) {
      final match = RegExp(
        '^$key=(-?\\d+)',
        multiLine: true,
      ).firstMatch(output);
      return match == null ? null : int.tryParse(match.group(1)!);
    }
    final diskBytes = intField('diskBytes');
    final diskFreeBytes = intField('diskFreeBytes');
    final uptimeSecs = intField('uptimeSecs');
    final queueLen = intField('queueLen');
    return ServerStats(
      collectorId: 'local',
      updatedAt: DateTime.now(),
      // Windows has no native load average; the processor queue length is the
      // nearest analog and is reported as the 1-minute load. 5/15 are null.
      loadAverage: queueLen == null ? null : queueLen.toDouble(),
      cpuCount: intField('cpuCount'),
      memoryTotalKb: intField('memTotalKb'),
      memoryAvailableKb: intField('memFreeKb'),
      swapTotalKb: intField('swapTotalKb'),
      swapFreeKb: intField('swapFreeKb'),
      diskTotalKb: diskBytes == null ? null : diskBytes ~/ 1024,
      diskAvailableKb: diskFreeBytes == null ? null : diskFreeBytes ~/ 1024,
      uptime: uptimeSecs == null ? null : Duration(seconds: uptimeSecs),
    );
  }

  Future<ServerSystemInfo> _systemInfoWindows() async {
    return ServerSystemInfo(
      distribution: 'Windows ${Platform.operatingSystemVersion}',
    );
  }

  Future<ServerSystemInfo> _systemInfoMacos() async {
    final name =
        (await _run('sw_vers', const ['-productName']))?.trim() ?? 'macOS';
    final version = (await _run('sw_vers', const ['-productVersion']))?.trim();
    final kernel = (await _run('uname', const ['-r']))?.trim();
    return ServerSystemInfo(
      distribution: version == null || version.isEmpty
          ? name
          : '$name $version',
      kernel: kernel,
    );
  }

  Future<ServerSystemInfo> _systemInfoLinux() async {
    final release = await _readFile('/etc/os-release');
    final pretty = RegExp(
      r'^PRETTY_NAME="?([^"\n]+)"?',
      multiLine: true,
    ).firstMatch(release ?? '');
    final kernel = (await _run('uname', const ['-r']))?.trim();
    return ServerSystemInfo(distribution: pretty?.group(1), kernel: kernel);
  }

  /// Parses load-average output. Handles both bare ("1.23 1.45 1.67") and
  /// brace-wrapped (`{ 1.23 1.45 1.67 }` from macOS `vm.loadavg`) formats.
  (double?, double?, double?) _parseLoads(String? output) {
    final values = RegExp(r'[0-9]+(?:\.[0-9]+)?')
        .allMatches(output ?? '')
        .map((match) => double.tryParse(match.group(0)!))
        .whereType<double>()
        .toList();
    double? at(int index) => values.length > index ? values[index] : null;
    return (at(0), at(1), at(2));
  }

  /// Available memory from `vm_stat`: free + inactive + speculative pages.
  int? _parseVmStat(String? output) {
    final text = output ?? '';
    final pageSize = RegExp(
      r'page size of (\d+) bytes',
    ).firstMatch(text)?.group(1);
    if (pageSize == null) return null;
    final size = int.tryParse(pageSize);
    if (size == null) return null;
    int? pages(String label) {
      final match = RegExp('$label:\\s+(\\d+)').firstMatch(text);
      return match == null ? null : int.tryParse(match.group(1)!);
    }

    final free = pages('Pages free');
    final inactive = pages('Pages inactive');
    final speculative = pages('Pages speculative');
    if (free == null || inactive == null || speculative == null) return null;
    return (free + inactive + speculative) * size;
  }

  /// Parses "total = 4096.00M used = 0.00M free = 4096.00M" into KB pairs.
  (int?, int?) _parseSwapUsage(String? output) {
    final text = output ?? '';
    int? value(RegExp pattern) {
      final match = pattern.firstMatch(text);
      if (match == null) return null;
      final megs = double.tryParse(match.group(1)!);
      return megs == null ? null : (megs * 1024).round();
    }

    return (
      value(RegExp(r'total = ([0-9.]+)M')),
      value(RegExp(r'free = ([0-9.]+)M')),
    );
  }

  /// Converts `kern.boottime` output ("{ sec = 1730000000, usec = 0 } …")
  /// into the time elapsed since boot.
  Duration? _uptimeFromBootTime(String? output) {
    final seconds = RegExp(r'sec = (\d+)').firstMatch(output ?? '')?.group(1);
    final boot = seconds == null ? null : int.tryParse(seconds);
    if (boot == null) return null;
    return Duration(
      seconds: DateTime.now().millisecondsSinceEpoch ~/ 1000 - boot,
    );
  }

  /// Extracts a field from `df -Pk` output's data row (0-based field index:
  /// 1 = 1024-blocks, 3 = available).
  int? _diskField(String? output, int fieldIndex) {
    final lines = (output ?? '').trim().split('\n');
    if (lines.length < 2) return null;
    final fields = lines[1].trim().split(RegExp(r'\s+'));
    return fields.length > fieldIndex ? int.tryParse(fields[fieldIndex]) : null;
  }

  String _osName(String operatingSystem) => switch (operatingSystem) {
    'macos' => 'macOS',
    'windows' => 'Windows',
    'linux' => 'Linux',
    final other =>
      other.isEmpty ? other : '${other[0].toUpperCase()}${other.substring(1)}',
  };

  Future<String?> _run(String executable, List<String> arguments) async {
    try {
      final result = await Process.run(
        executable,
        arguments,
      ).timeout(const Duration(seconds: 5));
      if (result.exitCode != 0) return null;
      return result.stdout.toString();
    } catch (_) {
      return null;
    }
  }

  Future<String?> _readFile(String path) async {
    try {
      return await File(
        path,
      ).readAsString().timeout(const Duration(seconds: 3));
    } catch (_) {
      return null;
    }
  }
}

/// Manages terminal sessions and statistics for the machine MaidKit runs on.
///
/// Mirrors [SshConnectionManager]'s terminal lifecycle, but every "session" is
/// a locally spawned shell process instead of an SSH channel, and statistics
/// come from the local OS rather than a remote metrics collector.
class LocalConnectionManager {
  LocalConnectionManager(
    this._terminalAdapterFactory, {
    required this.isEnabled,
    required this.interval,
    required this.serverName,
    LocalMachineMetricsCollector? metricsCollector,
  }) : _metricsCollector =
           metricsCollector ?? const LocalMachineMetricsCollector() {
    _scheduleNext();
    // Emit the first connected session right away instead of waiting for the
    // first timer tick, so an enabled card never looks "not connected".
    unawaited(refreshNow());
  }

  final TerminalSessionAdapterFactory Function() _terminalAdapterFactory;

  /// Whether the local machine is currently managed (settings gate).
  final bool Function() isEnabled;

  /// How often local statistics are re-collected.
  final Duration Function() interval;

  /// The current display name of the local machine.
  final String Function() serverName;
  final LocalMachineMetricsCollector _metricsCollector;

  final _terminals = <String, _LocalTerminalConnection>{};
  final _states = <int, SshSessionInfo>{};
  final _controller = StreamController<List<SshSessionInfo>>.broadcast();
  var _nextTerminalId = 0;
  Timer? _timer;
  var _collecting = false;

  Stream<List<SshSessionInfo>> get sessions => _controller.stream;
  List<SshSessionInfo> get current => _states.values.toList();

  /// Opens a shell on this machine. Returns when the process has started;
  /// [server] must be the local-machine server. [initialDirectory] is used as
  /// the process working directory when it is non-empty.
  Future<TerminalSessionHandle> openTerminal(
    Server server, {
    String? initialDirectory,
  }) async {
    final directory = initialDirectory?.trim();
    final process = await _spawnShell(
      workingDirectory: directory == null || directory.isEmpty
          ? null
          : directory,
    );
    final terminal = _terminalAdapterFactory().create();
    final terminalId = 'local-${_nextTerminalId++}';
    final binding = TerminalSessionBinding(
      adapter: terminal,
      stdout: process.stdout
          .transform(const _LocalShellWarningFilter())
          .map(Uint8List.fromList),
      stderr: process.stderr
          .transform(const _LocalShellWarningFilter())
          .map(Uint8List.fromList),
      send: process.stdin.add,
      resize: (_) {},
    );
    _terminals[terminalId] = _LocalTerminalConnection(
      serverId: server.id,
      process: process,
      binding: binding,
    );
    // Exiting the local shell ends the terminal tab just like `exit` would
    // end an SSH shell. Do not use `whenComplete`: its returned future
    // re-emits a transport error and, because this is fire-and-forget cleanup,
    // would become an unhandled application error.
    process.exitCode.then<void>(
      (_) => _closeTerminalAfterExit(terminalId, process),
      onError: (_, _) => _closeTerminalAfterExit(terminalId, process),
    );
    _set(
      (_states[server.id] ??
              SshSessionInfo(
                serverId: server.id,
                serverName: server.name,
                connectedAt: DateTime.now(),
                status: SessionStatus.connected,
              ))
          .copyWith(status: SessionStatus.connected, latency: Duration.zero),
    );
    return TerminalSessionHandle(
      id: terminalId,
      adapter: terminal,
      done: process.exitCode.then((_) {}),
    );
  }

  /// Closes the local shell with [terminalId]. Idempotent: unknown ids are
  /// ignored, so it is safe to call for SSH and serial tab ids too. Closing a
  /// terminal does not mark the machine "disconnected": it is always reachable.
  Future<void> closeTerminal(String terminalId) async {
    final terminal = _terminals.remove(terminalId);
    if (terminal == null) return;
    try {
      await terminal.binding.close();
    } catch (_) {}
    try {
      terminal.process.kill(ProcessSignal.sigterm);
      await terminal.process.exitCode.timeout(const Duration(seconds: 2));
    } catch (_) {
      // The process already exited or ignored the signal; nothing to clean up.
    }
  }

  /// Re-collects local statistics immediately (used by the card refresh
  /// button and the periodic scheduler).
  Future<void> refreshNow() async {
    if (!isEnabled() || _collecting) return;
    _collecting = true;
    try {
      final stats = await _metricsCollector.collect();
      final systemInfo = await _metricsCollector.systemInfo();
      _set(
        (_states[localMachineServerId] ??
                SshSessionInfo(
                  serverId: localMachineServerId,
                  serverName: serverName(),
                  connectedAt: DateTime.now(),
                  status: SessionStatus.connected,
                ))
            .copyWith(
              status: SessionStatus.connected,
              latency: Duration.zero,
              stats: stats,
              systemInfo: systemInfo,
            ),
      );
    } catch (_) {
      // Keep the previous state on transient collection failures.
    } finally {
      _collecting = false;
    }
  }

  void _scheduleNext() {
    _timer = Timer(interval(), () => unawaited(_tick()));
  }

  Future<void> _tick() async {
    _scheduleNext();
    if (!isEnabled()) {
      // The dashboard hides the local machine; drop its session so a disabled
      // feature never leaves a stale connected entry behind.
      if (_states.isNotEmpty) {
        _states.clear();
        _controller.add(current);
      }
      return;
    }
    await refreshNow();
  }

  void _closeTerminalAfterExit(String terminalId, Process process) {
    if (!identical(_terminals[terminalId]?.process, process)) return;
    unawaited(closeTerminal(terminalId).catchError((_) {}));
  }

  void _set(SshSessionInfo value) {
    _states[value.serverId] = value;
    _controller.add(current);
  }

  void dispose() {
    _timer?.cancel();
    unawaited(_closeAll());
  }

  Future<void> _closeAll() async {
    for (final terminalId in _terminals.keys.toList()) {
      await closeTerminal(terminalId);
    }
    await _controller.close();
  }

  /// POSIX-safe single-quoted string for local shell commands.
  String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

  Future<Process> _spawnShell({String? workingDirectory}) async {
    final home = Platform.environment['HOME'] ?? Directory.current.path;
    final cwd = workingDirectory ?? home;
    final environment = Map<String, String>.of(Platform.environment)
      ..['TERM'] = 'xterm-256color';
    if (Platform.isWindows) {
      // No PTY: `Process.start` gives cmd pipes, so the local terminal tab runs
      // in line mode — no interactive prompt echo, no ANSI color from child
      // programs that detect a non-tty, and resizes are not honored. Remote SSH
      // terminals (the primary feature) are unaffected: they use the SSH
      // channel as their PTY. A true interactive local terminal on Windows
      // requires the ConPTY API (CreatePseudoConsole + pipe bridging + resize
      // pump) via FFI, which is tracked as a follow-up needing a Windows
      // build/test environment.
      return Process.start(
        'cmd.exe',
        const [],
        workingDirectory: cwd,
        environment: environment,
      );
    }
    final shell =
        Platform.environment['SHELL'] ??
        (Platform.isMacOS ? '/bin/zsh' : '/bin/sh');
    final shellArguments = _shellArguments(shell);
    try {
      if (Platform.isMacOS) {
        // BSD `script`: `script -q /dev/null <shell>` allocates a PTY so the
        // shell runs interactively (prompt, job control, colors).
        return await Process.start(
          '/usr/bin/script',
          ['-q', '/dev/null', shell, ...shellArguments],
          workingDirectory: cwd,
          environment: environment,
        );
      }
      // GNU `script` (util-linux): `script -qec <shell> /dev/null`.
      final command = [shell, ...shellArguments].map(_shellQuote).join(' ');
      return await Process.start(
        '/usr/bin/script',
        ['-qec', command, '/dev/null'],
        workingDirectory: cwd,
        environment: environment,
      );
    } on ProcessException {
      // Minimal systems without `script`: run the shell without a PTY.
      return Process.start(
        shell,
        shellArguments,
        workingDirectory: cwd,
        environment: environment,
      );
    }
  }

  List<String> _shellArguments(String shell) {
    final arguments = <String>['-i'];
    if (shell.endsWith('/zsh')) {
      // Spaceship's prompt declares function-local scalars without `typeset`.
      // Newer zsh releases report those declarations when this diagnostic
      // option is enabled, flooding the terminal before the prompt appears.
      arguments.addAll(const ['+o', 'WARN_CREATE_GLOBAL']);
    }
    return arguments;
  }
}

/// Removes only the known Spaceship/zsh global-scope diagnostics from local
/// shell output. Other shell output, including prompts and real errors,
/// remains visible immediately.
class _LocalShellWarningFilter
    extends StreamTransformerBase<List<int>, List<int>> {
  const _LocalShellWarningFilter();

  static const _prefix = <int>[
    0x73,
    0x70,
    0x61,
    0x63,
    0x65,
    0x73,
    0x68,
    0x69,
    0x70,
    0x3a,
    0x3a,
  ];

  @override
  Stream<List<int>> bind(Stream<List<int>> stream) {
    final candidate = <int>[];
    var atLineStart = true;
    var suppressLine = false;
    return stream.transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (chunk, sink) {
          final output = BytesBuilder(copy: false);
          for (final byte in chunk) {
            if (suppressLine) {
              if (byte == 0x0a) {
                suppressLine = false;
                atLineStart = true;
              }
              continue;
            }
            if (atLineStart) {
              candidate.add(byte);
              if (_matchesPrefix(candidate)) {
                candidate.clear();
                suppressLine = true;
                atLineStart = false;
                continue;
              }
              if (_couldStillMatchPrefix(candidate)) {
                continue;
              }
              output.add(candidate);
              atLineStart = candidate.last == 0x0a;
              candidate.clear();
              continue;
            }
            output.addByte(byte);
            if (byte == 0x0a) atLineStart = true;
          }
          if (output.length > 0) sink.add(output.takeBytes());
        },
        handleDone: (sink) {
          if (!suppressLine && candidate.isNotEmpty) {
            sink.add(Uint8List.fromList(candidate));
          }
          sink.close();
        },
      ),
    );
  }

  bool _matchesPrefix(List<int> value) {
    if (value.length != _prefix.length) return false;
    for (var index = 0; index < value.length; index++) {
      if (value[index] != _prefix[index]) return false;
    }
    return true;
  }

  bool _couldStillMatchPrefix(List<int> value) {
    if (value.length >= _prefix.length) return false;
    for (var index = 0; index < value.length; index++) {
      if (value[index] != _prefix[index]) return false;
    }
    return true;
  }
}

class _LocalTerminalConnection {
  const _LocalTerminalConnection({
    required this.serverId,
    required this.process,
    required this.binding,
  });

  final int serverId;
  final Process process;
  final TerminalSessionBinding binding;
}
