import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/runtime_metrics_collector.dart';
import 'package:maid_kit/servers/server_models.dart';

const _gnuPsFixture = '''
    1 root      0.1   0.2  12345  100 init /sbin/init
  123 root      1.5   0.3  67890   45 java -Xmx2g -jar app.jar
 4567 jane     12.25  1.75 1048576   12 python3 /usr/bin/python3 server.py --port 8080
garbage
 8901 deploy   2.0   1.0 204800   30 dotnet run --project app.csproj
''';

const _bsdPsFixture = '''
    1 root      0.1   0.2  12345 init /sbin/init
  123 root      1.5   0.3  67890 java -Xmx2g -jar app.jar
 4567 jane     12.25  1.75 1048576 python3 /usr/bin/python3 server.py --port 8080
''';

const _jpsFixture = '''
12345 app.Main
67890
99999 sun.tools.jps.Jps
''';

const _jstatFixture = '''
  S0     S1     E      O      M     CCS    YGC     YGCT    FGC    FGCT     GCT
  0.00  57.14  45.00  23.40  95.20  90.00  12      0.400   0      0.000    0.400
''';

void main() {
  group('parseRuntimeProcessesOutput', () {
    test('parses GNU ps rows with thread counts', () {
      final processes = parseRuntimeProcessesOutput(
        _gnuPsFixture,
        hasThreads: true,
      );
      expect(processes, hasLength(4));
      final java = processes[1];
      expect(java.pid, 123);
      expect(java.user, 'root');
      expect(java.cpuPercent, 1.5);
      expect(java.memoryPercent, 0.3);
      expect(java.rssKb, 67890);
      expect(java.threads, 45);
      expect(java.command, 'java -Xmx2g -jar app.jar');
      final python = processes[2];
      expect(python.pid, 4567);
      expect(python.command, 'python3 /usr/bin/python3 server.py --port 8080');
      final dotnet = processes[3];
      expect(dotnet.pid, 8901);
      expect(dotnet.threads, 30);
      expect(dotnet.command, 'dotnet run --project app.csproj');
    });

    test('parses BSD rows without thread counts', () {
      final processes = parseRuntimeProcessesOutput(
        _bsdPsFixture,
        hasThreads: false,
      );
      expect(processes, hasLength(3));
      expect(processes[1].pid, 123);
      expect(processes[1].threads, isNull);
      expect(processes[1].command, 'java -Xmx2g -jar app.jar');
      expect(processes[2].pid, 4567);
      expect(processes[2].threads, isNull);
    });

    test('skips malformed rows', () {
      final processes = parseRuntimeProcessesOutput(
        'short\n'
        '  123 root      1.5   0.3  67890   45 java -jar app.jar\n'
        '  456 bad cpu 1.5 0.3 1000 5 nope\n'
        '  789 root   abc   0.3  1000   5 java -version\n',
        hasThreads: true,
      );
      expect(processes, hasLength(1));
      expect(processes.single.pid, 123);
    });
  });

  group('groupRuntimeProcesses', () {
    test('splits rows into fixed-order groups with availability flags', () {
      final processes = parseRuntimeProcessesOutput(
        _gnuPsFixture,
        hasThreads: true,
      );
      final groups = groupRuntimeProcesses(processes);
      expect(groups, hasLength(RuntimeKind.values.length));
      expect(groups.map((g) => g.kind).toList(), RuntimeKind.values);
      expect(groups[0].available, isTrue);
      expect(groups[0].processes.single.pid, 123);
      expect(groups[1].available, isTrue);
      expect(groups[1].processes.single.pid, 8901);
      expect(groups[2].available, isTrue);
      expect(groups[2].processes.single.pid, 4567);
      // The extended runtimes (node/deno/go/ruby/php) are absent on this host.
      for (final group in groups.skip(3)) {
        expect(group.available, isFalse);
      }
    });

    test('marks absent runtimes unavailable with an error', () {
      final processes = parseRuntimeProcessesOutput(
        '  123 root  1.5 0.3 67890 java -jar app.jar\n',
        hasThreads: false,
      );
      final groups = groupRuntimeProcesses(processes);
      expect(groups[0].available, isTrue);
      expect(groups[1].available, isFalse);
      expect(groups[1].error, 'no dotnet processes found');
      expect(groups[2].available, isFalse);
      expect(groups[2].error, 'no python processes found');
    });
  });

  group('parseJpsOutput', () {
    test('parses pid and optional main class', () {
      final jvms = parseJpsOutput(_jpsFixture);
      expect(jvms, hasLength(3));
      expect(jvms[0].pid, 12345);
      expect(jvms[0].mainClass, 'app.Main');
      expect(jvms[1].pid, 67890);
      expect(jvms[1].mainClass, '');
      expect(jvms[2].pid, 99999);
      expect(jvms[2].mainClass, 'sun.tools.jps.Jps');
    });

    test('skips non-numeric first columns', () {
      expect(parseJpsOutput('notapid garbage\n'), isEmpty);
    });
  });

  group('parseJstatGcutilOutput', () {
    test('extracts old-gen, YGC, FGC and GCT', () {
      final parsed = parseJstatGcutilOutput(_jstatFixture);
      expect(parsed, isNotNull);
      expect(parsed!.oldPercent, 23.40);
      expect(parsed.ygc, 12);
      expect(parsed.fgc, 0);
      expect(parsed.gctSeconds, 0.400);
    });

    test('returns null for garbage output', () {
      expect(parseJstatGcutilOutput('garbage\n'), isNull);
    });
  });
}
