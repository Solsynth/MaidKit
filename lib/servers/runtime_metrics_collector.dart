import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import 'server_models.dart';

/// Head cap on the ps pipe read per collection, mirroring the daemon's
/// runtimeProcessTableLimit.
const runtimeProcessTableLimit = 300;

/// Per-runtime process cap, mirroring the daemon's ProcessesLimit default.
const runtimeGroupLimit = 50;

/// jstat runs once per JVM and shares the host; cap the probes per collection.
const maxJvmProbePids = 8;

const _runtimeGnuPsCommand =
    'sh -c \'ps -eo pid=,user=,%cpu=,%mem=,rss=,nlwp=,comm=,args= --sort=-%cpu | head -n $runtimeProcessTableLimit\'';
const _runtimeBsdPsCommand =
    'sh -c \'ps -Ao pid=,user=,%cpu=,%mem=,rss=,comm=,args= -r | head -n $runtimeProcessTableLimit\'';

/// Collects a per-runtime process snapshot (java/dotnet/python) over direct
/// SSH, mirroring the daemon's `runtimes` SSE payload. Returns null only when
/// both ps forms fail; a host without a runtime still yields that group with
/// available:false, and java process rows carry JVM/GC detail when a JDK is
/// present.
Future<RuntimeSnapshot?> collectRuntimeMetricsOverSsh(SSHClient client) async {
  var output = await _runOrNull(client, _runtimeGnuPsCommand);
  var hasThreads = true;
  if (output == null || output.trim().isEmpty) {
    output = await _runOrNull(client, _runtimeBsdPsCommand);
    hasThreads = false;
  }
  if (output == null) return null;
  final groups = groupRuntimeProcesses(
    parseRuntimeProcessesOutput(output, hasThreads: hasThreads),
  );
  // groups[0] is always java (fixed order); the java key is present only when
  // at least one java process exists.
  if (groups[0].processes.isNotEmpty) {
    final java = await _collectJavaDetail(client);
    groups[0] = RuntimeGroup(
      kind: groups[0].kind,
      available: groups[0].available,
      error: groups[0].error,
      processes: groups[0].processes,
      java: java,
    );
  }
  return RuntimeSnapshot(groups: groups, collectedAt: DateTime.now());
}

/// Partitions runtime processes into the fixed java, dotnet, python groups in
/// CPU order, capping each at [runtimeGroupLimit]. A group with no matching
/// process reports available:false.
List<RuntimeGroup> groupRuntimeProcesses(List<RuntimeProcessInfo> entries) {
  const names = ['java', 'dotnet', 'python'];
  final groups = <RuntimeGroup>[];
  for (final name in names) {
    final matching = <RuntimeProcessInfo>[];
    for (final entry in entries) {
      if (matching.length >= runtimeGroupLimit) break;
      final comm = entry.command.split(' ').first;
      if (comm.startsWith(name)) matching.add(entry);
    }
    groups.add(
      RuntimeGroup(
        kind: RuntimeKindFromWire(name)!,
        available: matching.isNotEmpty,
        error: matching.isEmpty ? 'no $name processes found' : null,
        processes: matching,
      ),
    );
  }
  return groups;
}

/// Runs `jps -l` then `jstat -gcutil <pid>` for the first [maxJvmProbePids]
/// JVMs. Per-JVM failures become [JavaJvmInfo.error] entries and never abort
/// the collection; missing tools flip the jdk probe to unavailable.
Future<JavaRuntimeInfo> _collectJavaDetail(SSHClient client) async {
  final whichOutput = await _runOrNull(
    client,
    'sh -c \'command -v jps && command -v jstat\'',
  );
  if (whichOutput == null || whichOutput.trim().isEmpty) {
    return JavaRuntimeInfo(
      jdkAvailable: false,
      jdkError: 'jps/jstat were not found on this host (no JDK)',
      jvms: const [],
    );
  }
  final jpsOutput = await _runOrNull(client, 'jps -l');
  if (jpsOutput == null) {
    return JavaRuntimeInfo(
      jdkAvailable: false,
      jdkError: 'jps -l failed',
      jvms: const [],
    );
  }
  final jvms = parseJpsOutput(jpsOutput).take(maxJvmProbePids);
  final entries = <JavaJvmInfo>[];
  for (final jvm in jvms) {
    final jstatOutput = await _runOrNull(client, 'jstat -gcutil ${jvm.pid}');
    if (jstatOutput == null) {
      entries.add(
        JavaJvmInfo(
          pid: jvm.pid,
          mainClass: jvm.mainClass,
          error: 'jstat -gcutil failed',
        ),
      );
      continue;
    }
    final parsed = parseJstatGcutilOutput(jstatOutput);
    if (parsed == null) {
      entries.add(
        JavaJvmInfo(
          pid: jvm.pid,
          mainClass: jvm.mainClass,
          error: 'parse jstat output failed',
        ),
      );
      continue;
    }
    entries.add(
      JavaJvmInfo(
        pid: jvm.pid,
        mainClass: jvm.mainClass,
        oldPercent: parsed.oldPercent,
        ygc: parsed.ygc,
        fgc: parsed.fgc,
        gctSeconds: parsed.gctSeconds,
      ),
    );
  }
  return JavaRuntimeInfo(jdkAvailable: true, jvms: entries);
}

/// Parses `ps -eo pid=,user=,%cpu=,%mem=,rss=,nlwp=,comm=,args=` (hasThreads)
/// or the BSD form without nlwp. Fixed columns are pid user cpu mem rss
/// [nlwp] comm; the command is the rest of the line joined with single
/// spaces. Malformed rows are skipped; threads is null on BSD hosts.
List<RuntimeProcessInfo> parseRuntimeProcessesOutput(
  String output, {
  required bool hasThreads,
}) {
  final minFields = hasThreads ? 7 : 6;
  final processes = <RuntimeProcessInfo>[];
  for (final rawLine in output.split('\n')) {
    final fields = rawLine
        .trim()
        .split(RegExp(r'\s+'))
        .where((field) => field.isNotEmpty)
        .toList();
    if (fields.length < minFields) continue;
    final pid = int.tryParse(fields[0]);
    final cpu = double.tryParse(fields[2]);
    final mem = double.tryParse(fields[3]);
    final rss = int.tryParse(fields[4]);
    if (pid == null || cpu == null || mem == null || rss == null) continue;
    if (hasThreads) {
      final threads = int.tryParse(fields[5]);
      if (threads == null) continue;
      processes.add(
        RuntimeProcessInfo(
          pid: pid,
          user: fields[1],
          cpuPercent: cpu,
          memoryPercent: mem,
          rssKb: rss,
          threads: threads,
          command: fields.skip(6).join(' '),
        ),
      );
    } else {
      processes.add(
        RuntimeProcessInfo(
          pid: pid,
          user: fields[1],
          cpuPercent: cpu,
          memoryPercent: mem,
          rssKb: rss,
          command: fields.skip(5).join(' '),
        ),
      );
    }
  }
  return processes;
}

/// Parses `jps -l` output: `<pid> [<main-class>]`. Main class is empty when
/// jps could not resolve it; malformed lines are skipped.
List<({int pid, String mainClass})> parseJpsOutput(String output) {
  final jvms = <({int pid, String mainClass})>[];
  for (final rawLine in output.split('\n')) {
    final fields = rawLine
        .trim()
        .split(RegExp(r'\s+'))
        .where((field) => field.isNotEmpty)
        .toList();
    if (fields.isEmpty) continue;
    final pid = int.tryParse(fields[0]);
    if (pid == null) continue;
    jvms.add((
      pid: pid,
      mainClass: fields.length > 1 ? fields.skip(1).join(' ') : '',
    ));
  }
  return jvms;
}

/// Parses one `jstat -gcutil <pid>` line (header S0 S1 E O M CCS YGC YGCT FGC
/// FGCT GCT): O = fields[3], YGC = fields[6], FGC = fields[8], GCT =
/// fields[10]. Returns null when no valid data line is found.
({double oldPercent, int ygc, int fgc, double gctSeconds})?
parseJstatGcutilOutput(String output) {
  for (final rawLine in output.split('\n')) {
    final fields = rawLine
        .trim()
        .split(RegExp(r'\s+'))
        .where((field) => field.isNotEmpty)
        .toList();
    if (fields.length < 11) continue;
    final old = double.tryParse(fields[3]);
    final ygc = int.tryParse(fields[6]);
    final fgc = int.tryParse(fields[8]);
    final gct = double.tryParse(fields[10]);
    if (old == null || ygc == null || fgc == null || gct == null) continue;
    return (oldPercent: old, ygc: ygc, fgc: fgc, gctSeconds: gct);
  }
  return null;
}

Future<String?> _runOrNull(SSHClient client, String command) async {
  try {
    return await _run(client, command);
  } catch (_) {
    return null;
  }
}

Future<String> _run(SSHClient client, String command) async {
  final session = await client.execute(command);
  final output = await utf8.decoder.bind(session.stdout).join();
  await session.done;
  return output;
}
