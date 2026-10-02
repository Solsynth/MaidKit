import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/maidcafe_service.dart';
import 'package:maid_kit/servers/maidcafe_stream.dart';
import 'package:maid_kit/servers/ssh_connection_manager.dart';

List<int> _bytes(String text) => utf8.encode(text);

Future<List<MaidCafeStreamEvent>> _frames(String text) =>
    parseMaidCafeSseFrames(Stream.value(_bytes(text))).toList();

String _hexEncode(String text) => utf8
    .encode(text)
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join();

/// A stand-in for the daemon's native-op routes: it records every request and
/// answers the execution response shape the Go daemon produces, so the client's
/// paths, bodies and headers are exercised over real HTTP.
class _OpDaemon {
  HttpServer? _server;
  final List<({String method, String path, Map<String, Object?> body})>
  requests = [];
  final Map<String, String> headers = {};

  /// Paths that answer a body-less 404, the way a daemon older than the route
  /// does. Everything else answers an op result.
  final Set<String> missingRoutes = {};

  /// Paths that answer a 404 with the daemon's own JSON error body.
  final Map<String, String> errorRoutes = {};

  String get baseUrl => 'http://127.0.0.1:${_server!.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle);
  }

  Future<void> stop() async => _server?.close(force: true);

  void _handle(HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    for (final name in [
      'authorization',
      'x-maidcafe-signature',
      'x-maidcafe-invoked-by',
    ]) {
      final value = request.headers.value(name);
      if (value != null) headers[name] = value;
    }
    final path = request.uri.path;
    if (path == '/health') {
      _json(request, {'ok': true, 'mode': 'daemon', 'id': 'host-1'});
      return;
    }
    requests.add((
      method: request.method,
      path: path,
      body: raw.isEmpty
          ? const <String, Object?>{}
          : (jsonDecode(raw) as Map).cast<String, Object?>(),
    ));
    if (missingRoutes.contains(path)) {
      request.response.statusCode = 404;
      await request.response.close();
      return;
    }
    final error = errorRoutes[path];
    if (error != null) {
      request.response.statusCode = 404;
      _json(request, {'error': error});
      return;
    }
    _json(request, {
      'ok': true,
      'name': path,
      'exit_code': 0,
      'stdout': 'done\n',
      'stderr': '',
    });
  }

  void _json(HttpRequest request, Map<String, Object?> body) {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    request.response.close();
  }
}

void main() {
  group('parseMaidCafeActionScripts', () {
    test('decodes hex-encoded action scripts by name', () {
      const backup = '#!/bin/sh\ntar -czf /var/backups/site.tar.gz /srv/site\n';
      const cleanup = '#!/bin/sh\nrm -rf /tmp/old';
      final blob =
          '###FILE:backup.sh###\n${_hexEncode(backup)}\n'
          '###FILE:cleanup.sh###\n${_hexEncode(cleanup)}\n';

      final scripts = parseMaidCafeActionScripts(blob);
      expect(scripts.keys, ['backup', 'cleanup']);
      expect(scripts['backup'], backup);
      expect(scripts['cleanup'], cleanup);
    });

    test('preserves a trailing newline verbatim', () {
      const body = 'echo done\n';
      final blob = '###FILE:run.sh###\n${_hexEncode(body)}\n';
      expect(parseMaidCafeActionScripts(blob)['run'], body);
    });

    test('round-trips non-ASCII bytes', () {
      const body = 'echo "备份完成"\n';
      final blob = '###FILE:backup.sh###\n${_hexEncode(body)}\n';
      expect(parseMaidCafeActionScripts(blob)['backup'], body);
    });

    test('ignores empty blobs and non-script files', () {
      expect(parseMaidCafeActionScripts(''), isEmpty);
      expect(
        parseMaidCafeActionScripts('###FILE:notes.txt###\n68656c6c6f\n'),
        isEmpty,
      );
      // An empty script body leaves no hex and is skipped.
      expect(parseMaidCafeActionScripts('###FILE:empty.sh###\n'), isEmpty);
    });
  });

  group('parseMaidCafeTomlStringArray', () {
    test('parses single-line arrays', () {
      expect(parseMaidCafeTomlStringArray('"A=1", "B=two words"'), [
        'A=1',
        'B=two words',
      ]);
      expect(parseMaidCafeTomlStringArray(''), isEmpty);
      expect(parseMaidCafeTomlStringArray('"only"'), ['only']);
    });

    test('parses multi-line arrays with escapes', () {
      expect(
        parseMaidCafeTomlStringArray(
          '"A=1",\n  "B=\\"quoted\\"",\n  "C=line\\nfeed",\n',
        ),
        ['A=1', 'B="quoted"', 'C=line\nfeed'],
      );
    });

    test('drops empty entries', () {
      expect(parseMaidCafeTomlStringArray('"A=1", ,  "B=2",'), ['A=1', 'B=2']);
    });
  });

  group('parseMaidCafeActionDefinitions', () {
    test('reads cwd, user and environment from action blocks', () {
      const config = '''
[daemon]
 id = "host-1"
[[daemon.actions]]
name = "deploy"
command = "/etc/maidcafe/actions/deploy.sh"
script = true
enabled = true
notifyOnSuccess = false
notifyOnFailure = true
displayName = "Deploy the web app"
cwd = "/srv/myapp"
user = "deploy"
env = ["CI_BUILD=42", "NODE_ENV=production"]
[[daemon.actions]]
name = "plain"
command = "/etc/maidcafe/actions/plain.sh"
''';
      final actions = parseMaidCafeActionDefinitions(config);
      expect(actions, hasLength(2));
      final deploy = actions.first;
      expect(deploy.name, 'deploy');
      expect(deploy.displayName, 'Deploy the web app');
      expect(deploy.workingDirectory, '/srv/myapp');
      expect(deploy.user, 'deploy');
      expect(deploy.environment, {'CI_BUILD': '42', 'NODE_ENV': 'production'});
      expect(deploy.notifyOnFailure, isTrue);
      final plain = actions.last;
      expect(plain.displayName, isNull);
      expect(plain.workingDirectory, isNull);
      expect(plain.user, isNull);
      expect(plain.environment, isEmpty);
      expect(plain.enabled, isTrue);
    });

    test('tolerates hand-edited multi-line env arrays', () {
      const config = '''
[[daemon.actions]]
name = "deploy"
command = "/etc/maidcafe/actions/deploy.sh"
env = [
  "A=1",
  "B=2",
]
''';
      final actions = parseMaidCafeActionDefinitions(config);
      expect(actions.single.environment, {'A': '1', 'B': '2'});
    });
  });

  group('MaidCafeAuditEntry', () {
    test('parses a daemon audit record', () {
      final entry = MaidCafeAuditEntry.fromJson({
        'timestamp': '2026-08-16T01:00:00.000Z',
        'name': 'deploy',
        'display_name': 'Deploy the web app',
        'source': 'relay',
        'invoked_by': 'ci-backup',
        'ok': true,
        'exit_code': 0,
        'duration_ms': 142,
        'stdout': 'deploy-ok',
        'stderr': '',
      });
      expect(entry.name, 'deploy');
      expect(entry.label, 'Deploy the web app');
      expect(entry.source, 'relay');
      expect(entry.invokedBy, 'ci-backup');
      expect(entry.ok, isTrue);
      expect(entry.exitCode, 0);
      expect(entry.durationMs, 142);
      expect(entry.error, isNull);
      expect(entry.stdout, 'deploy-ok');
      expect(entry.stderr, isEmpty);
    });

    test(
      'falls back to the slug for the label and tolerates missing fields',
      () {
        final entry = MaidCafeAuditEntry.fromJson({
          'name': 'cleanup',
          'ok': false,
          'exit_code': 2,
          'error': 'something broke',
        });
        expect(entry.label, 'cleanup');
        expect(entry.ok, isFalse);
        expect(entry.exitCode, 2);
        expect(entry.error, 'something broke');
        expect(entry.source, isEmpty);
        expect(entry.durationMs, 0);
      },
    );
  });

  group('parseMaidCafeActionFragment', () {
    test('reads every field from a flat fragment', () {
      final action = parseMaidCafeActionFragment('''
name = "deploy"
command = "/etc/maidcafe/actions/deploy.sh"
script = true
enabled = false
notifyOnSuccess = true
displayName = "Deploy the web app"
cwd = "/srv/myapp"
user = "deploy"
timeout = "2m"
env = ["CI_BUILD=42"]
''');
      expect(action.name, 'deploy');
      expect(action.enabled, isFalse);
      expect(action.notifyOnSuccess, isTrue);
      expect(action.displayName, 'Deploy the web app');
      expect(action.workingDirectory, '/srv/myapp');
      expect(action.user, 'deploy');
      expect(action.scriptTimeout, '2m');
      expect(action.environment, {'CI_BUILD': '42'});
    });

    test('defaults enabled and leaves optional fields null', () {
      final action = parseMaidCafeActionFragment('''
name = "cleanup"
command = "/etc/maidcafe/actions/cleanup.sh"
''');
      expect(action.enabled, isTrue);
      expect(action.workingDirectory, isNull);
      expect(action.user, isNull);
      expect(action.scriptTimeout, isNull);
      expect(action.environment, isEmpty);
    });
  });

  group('parseMaidCafeAlarmFragment', () {
    test('reads threshold, enabled and cooldown from a flat fragment', () {
      final alarm = parseMaidCafeAlarmFragment('''
kind = "cpu_percent"
threshold = 85.50
enabled = false
cooldownSeconds = 120
''');
      expect(alarm.kind, 'cpu_percent');
      expect(alarm.threshold, 85.5);
      expect(alarm.enabled, isFalse);
      expect(alarm.cooldownSeconds, 120);
    });

    test('defaults enabled on and cooldown to five minutes', () {
      final alarm = parseMaidCafeAlarmFragment('''
kind = "memory_used_percent"
threshold = 90
''');
      expect(alarm.kind, 'memory_used_percent');
      expect(alarm.threshold, 90);
      expect(alarm.enabled, isTrue);
      expect(alarm.cooldownSeconds, 300);
    });
    test('reads a targeted container alarm without a threshold', () {
      final alarm = parseMaidCafeAlarmFragment('''
kind = "container_down"
target = "maid-worker"
enabled = true
cooldownSeconds = 60
''');
      expect(alarm.kind, 'container_down');
      expect(alarm.target, 'maid-worker');
      expect(alarm.threshold, 0);
      expect(alarm.cooldownSeconds, 60);
    });
  });

  group('parseMaidCafeConfigFiles', () {
    test('decodes hex files by name', () {
      final blob =
          '###FILE:deploy.toml###\n${_hexEncode('name = "deploy"')}\n'
          '###FILE:cleanup.toml###\n${_hexEncode('name = "cleanup"')}\n';
      final files = parseMaidCafeConfigFiles(blob, '.toml');
      expect(files.keys, ['deploy', 'cleanup']);
      expect(files['deploy'], 'name = "deploy"');
    });
  });

  group('parseMaidCafeSseFrames', () {
    test('parses hello and metric frames from bytes', () async {
      final events = await _frames(
        'event: hello\ndata: {"stream":"v1","version":"0.1.0"}\n\n'
        'event: metric\ndata: {"cpu_percent":1.2,"sent_at":"2026-08-15T00:00:00Z"}\n\n',
      );
      expect(events, hasLength(2));
      expect(events[0].type, MaidCafeStreamEventType.hello);
      expect(events[0].data['stream'], 'v1');
      expect(events[1].type, MaidCafeStreamEventType.metric);
      expect(events[1].data['cpu_percent'], 1.2);
      expect(events[1].data['sent_at'], '2026-08-15T00:00:00Z');
    });

    test(
      'ignores comment lines and joins multi-line data with newlines',
      () async {
        final events = await _frames(
          ': ping\n\n'
          'event: processes\n'
          'data: {"processes":[\n'
          'data: {"pid":1,"user":"root"},\n'
          'data: {"pid":2,"user":"nobody"}]\n'
          'data: }\n\n',
        );
        expect(events, hasLength(1));
        expect(events[0].type, MaidCafeStreamEventType.processes);
        final processes = events[0].data['processes'] as List;
        expect(processes, hasLength(2));
        expect(processes[1]['pid'], 2);
      },
    );

    test('skips frames with unknown event names', () async {
      final events = await _frames(
        'event: unknown\ndata: {"anything":true}\n\n'
        'event: metric\ndata: {"cpu_percent":3.0}\n\n',
      );
      expect(events, hasLength(1));
      expect(events[0].type, MaidCafeStreamEventType.metric);
    });

    test('skips frames with malformed JSON or no event name', () async {
      final events = await _frames(
        'event: metric\ndata: {not json}\n\n'
        'data: {"cpu_percent":1.0}\n\n'
        'event: metric\n\n'
        ': comment only\n\n',
      );
      expect(events, isEmpty);
    });

    test('strips a single leading space after data:', () async {
      final events = await _frames(
        'event: metric\ndata: {"cpu_percent": 7.5}\n\n',
      );
      expect(events, hasLength(1));
      expect(events[0].data['cpu_percent'], 7.5);
    });

    test('parses images frames', () async {
      final events = await _frames(
        'event: images\ndata: {"runtimes":[{"runtime":"podman","available":true,"images":[]}]}\n\n',
      );
      expect(events, hasLength(1));
      expect(events[0].type, MaidCafeStreamEventType.images);
      final runtimes = events[0].data['runtimes'] as List;
      expect(runtimes, hasLength(1));
    });
  });

  group('parseMaidCafeContainers', () {
    test('maps runtimes incl. compose_project', () {
      final snapshot = parseMaidCafeContainers({
        'runtimes': [
          {
            'runtime': 'podman',
            'available': true,
            'error': null,
            'containers': [
              {
                'id': 'abc123',
                'name': 'web',
                'image': 'nginx:1.25',
                'state': 'running',
                'status': 'Up 2 hours',
                'compose_project': 'myapp',
              },
            ],
          },
        ],
      });
      expect(snapshot.hasRuntimes, isTrue);
      final runtime = snapshot.runtimes.single;
      expect(runtime.runtime, 'podman');
      expect(runtime.available, isTrue);
      expect(runtime.error, isNull);
      expect(runtime.containers, hasLength(1));
      final container = runtime.containers.single;
      expect(container.id, 'abc123');
      expect(container.name, 'web');
      expect(container.image, 'nginx:1.25');
      expect(container.state, 'running');
      expect(container.status, 'Up 2 hours');
      expect(container.composeProject, 'myapp');
    });

    test('skips malformed entries and reports an empty runtimes list', () {
      final snapshot = parseMaidCafeContainers({
        'runtimes': [
          {'available': true, 'containers': []},
          {
            'runtime': 'docker',
            'containers': [
              {'name': 'no-id'},
              {'id': 'x', 'name': 42},
              'not a map',
              null,
            ],
          },
        ],
      });
      expect(snapshot.hasRuntimes, isTrue);
      expect(snapshot.runtimes.single.runtime, 'docker');
      expect(snapshot.runtimes.single.containers, isEmpty);
    });

    test('reports no runtimes when the daemon found no runtime', () {
      final snapshot = parseMaidCafeContainers({'runtimes': []});
      expect(snapshot.hasRuntimes, isFalse);
      expect(snapshot.runtimes, isEmpty);
    });

    test('keeps per-runtime errors and defaults missing scalars', () {
      final snapshot = parseMaidCafeContainers({
        'runtimes': [
          {
            'runtime': 'docker',
            'available': 'yes',
            'error': 'list containers: boom',
            'containers': [
              {'id': 'id1', 'name': 'n1'},
            ],
          },
        ],
      });
      final runtime = snapshot.runtimes.single;
      expect(runtime.available, isTrue);
      expect(runtime.error, 'list containers: boom');
      final container = runtime.containers.single;
      expect(container.image, '');
      expect(container.state, '');
      expect(container.status, '');
      expect(container.composeProject, isNull);
    });
  });

  group('parseMaidCafeImages', () {
    int unixSecondsAgo(Duration ago) =>
        DateTime.now().toUtc().subtract(ago).millisecondsSinceEpoch ~/ 1000;

    test('expands one daemon entry into one row per tag', () {
      final snapshot = parseMaidCafeImages({
        'runtimes': [
          {
            'runtime': 'docker',
            'available': true,
            'error': null,
            'images': [
              {
                'id': 'abc123def456',
                'tags': ['nginx:latest', 'localhost:5000/nginx:1.25'],
                'size': 192560829,
                'created': unixSecondsAgo(
                  const Duration(hours: 2, seconds: 30),
                ),
                'digest': 'sha256:aaaa',
              },
            ],
          },
        ],
      });
      expect(snapshot.hasRuntimes, isTrue);
      final runtime = snapshot.runtimes.single;
      expect(runtime.runtime, 'docker');
      expect(runtime.available, isTrue);
      expect(runtime.error, isNull);
      final images = runtime.images;
      expect(images, hasLength(2));
      final first = images[0];
      expect(first.id, 'abc123def456');
      expect(first.reference, 'nginx:latest');
      expect(first.repository, 'nginx');
      expect(first.tag, 'latest');
      expect(first.size, '193 MB');
      expect(first.created, '2h ago');
      // A registry host with a port must not split at its colon.
      final second = images[1];
      expect(second.reference, 'localhost:5000/nginx:1.25');
      expect(second.repository, 'localhost:5000/nginx');
      expect(second.tag, '1.25');
    });

    test('dangling images fall back to the id reference', () {
      final snapshot = parseMaidCafeImages({
        'runtimes': [
          {
            'runtime': 'podman',
            'images': [
              {'id': 'sha256:deadbeef', 'tags': [], 'size': 0},
            ],
          },
        ],
      });
      final image = snapshot.runtimes.single.images.single;
      expect(image.id, 'sha256:deadbeef');
      expect(image.reference, 'sha256:deadbeef');
      expect(image.isDangling, isTrue);
      expect(image.size, '0 B');
      expect(image.created, isEmpty);
    });

    test('skips entries without an id and tolerates missing tags', () {
      final snapshot = parseMaidCafeImages({
        'runtimes': [
          {
            'runtime': 'docker',
            'images': [
              {
                'tags': ['no-id'],
              },
              {
                'id': '',
                'tags': ['x'],
              },
              {'id': 'ok1'},
              {'id': 'ok2', 'tags': 'not-a-list'},
            ],
          },
        ],
      });
      final images = snapshot.runtimes.single.images;
      expect(images, hasLength(2));
      expect(images[0].id, 'ok1');
      expect(images[0].reference, 'ok1');
      expect(images[1].id, 'ok2');
      expect(images[1].reference, 'ok2');
    });

    test('reports no runtimes when the daemon found no runtime', () {
      final snapshot = parseMaidCafeImages({'runtimes': []});
      expect(snapshot.hasRuntimes, isFalse);
      expect(snapshot.runtimes, isEmpty);
    });

    test('handles non-list payloads gracefully', () {
      final snapshot = parseMaidCafeImages({'runtimes': 'nope'});
      expect(snapshot.hasRuntimes, isFalse);
    });
  });

  group('parseMaidCafeProcesses', () {
    test('maps a valid payload with tolerant numeric conversion', () {
      final snapshot = parseMaidCafeProcesses({
        'processes': [
          {
            'pid': 123,
            'user': 'root',
            'cpu_percent': 1.2,
            'memory_percent': 0,
            'rss_kb': 12345,
            'command': 'nginx: worker process',
          },
        ],
      });
      final process = snapshot.processes.single;
      expect(process.pid, 123);
      expect(process.user, 'root');
      expect(process.cpuPercent, 1.2);
      expect(process.memoryPercent, 0.0);
      expect(process.rssKb, 12345);
      expect(process.command, 'nginx: worker process');
    });

    test('skips entries missing pid or user', () {
      final snapshot = parseMaidCafeProcesses({
        'processes': [
          {'user': 'root', 'cpu_percent': 1.0},
          {'pid': 2, 'cpu_percent': 1.0},
          {'pid': 'three', 'user': 'root'},
          {'pid': 4, 'user': 'root', 'cpu_percent': 'fast'},
        ],
      });
      expect(snapshot.processes, hasLength(1));
      expect(snapshot.processes.single.pid, 4);
      expect(snapshot.processes.single.cpuPercent, 0.0);
    });

    test('handles non-list payloads gracefully', () {
      final snapshot = parseMaidCafeProcesses({'processes': 'nope'});
      expect(snapshot.processes, isEmpty);
    });
  });

  group('parseMaidCafeSystemd', () {
    test('maps a valid payload incl. unit_file_state', () {
      final snapshot = parseMaidCafeSystemd({
        'available': true,
        'error': null,
        'units': [
          {
            'name': 'nginx.service',
            'load_state': 'loaded',
            'active_state': 'active',
            'sub_state': 'running',
            'description': 'A high performance web server',
            'unit_file_state': 'enabled',
          },
        ],
      });
      expect(snapshot.available, isTrue);
      expect(snapshot.error, isNull);
      final unit = snapshot.units.single;
      expect(unit.name, 'nginx.service');
      expect(unit.loadState, 'loaded');
      expect(unit.activeState, 'active');
      expect(unit.subState, 'running');
      expect(unit.description, 'A high performance web server');
      expect(unit.unitFileState, 'enabled');
    });

    test('defaults unit_file_state and skips malformed units', () {
      final snapshot = parseMaidCafeSystemd({
        'available': false,
        'error': 'systemctl not found',
        'units': [
          {'active_state': 'active'},
          {'name': 42},
          {'name': 'valid.service'},
        ],
      });
      expect(snapshot.available, isFalse);
      expect(snapshot.error, 'systemctl not found');
      expect(snapshot.units, hasLength(1));
      final unit = snapshot.units.single;
      expect(unit.name, 'valid.service');
      expect(unit.unitFileState, '');
      expect(unit.loadState, '');
      expect(unit.activeState, '');
    });
  });

  group('MaidCafeOpResult', () {
    test('parses a successful execution response', () {
      final result = MaidCafeOpResult.parse({
        'ok': true,
        'name': 'container.restart',
        'exit_code': 0,
        'stdout': 'web\n',
        'stderr': '',
      });
      expect(result.ok, isTrue);
      expect(result.exitCode, 0);
      expect(result.stdout, 'web\n');
      expect(result.stderr, isEmpty);
      expect(() => result.ensureSuccess(), returnsNormally);
    });

    test('parses a failed execution response', () {
      final result = MaidCafeOpResult.parse({
        'ok': false,
        'name': 'container.restart',
        'exit_code': 125,
        'stdout': '',
        'stderr': 'Error: no such container: web\n',
      });
      expect(result.ok, isFalse);
      expect(result.exitCode, 125);
      expect(
        () => result.ensureSuccess(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('no such container'),
          ),
        ),
      );
    });

    test('fails with the exit code when stderr is empty', () {
      final result = MaidCafeOpResult.parse({
        'ok': false,
        'exit_code': 3,
        'stdout': '',
        'stderr': '',
      });
      expect(
        () => result.ensureSuccess('restart'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('exit code 3'),
          ),
        ),
      );
    });

    test('accepts a numeric exit code from JSON', () {
      final result = MaidCafeOpResult.parse({'ok': false, 'exit_code': 1.0});
      expect(result.exitCode, 1);
    });
  });

  group('runPackageAction', () {
    late _OpDaemon daemon;
    late MaidCafeStreamSession session;
    const secret = 'metrics-secret';

    setUp(() async {
      daemon = _OpDaemon();
      await daemon.start();
      session = await MaidCafeStreamSession.openAt(
        manager: SshConnectionManager(() => throw UnimplementedError()),
        baseUrl: daemon.baseUrl,
        apiSecret: secret,
      );
    });

    tearDown(() async => daemon.stop());

    test('refresh posts an empty body to the refresh route', () async {
      final result = await session.runPackageAction('refresh');
      expect(result.ok, isTrue);
      final request = daemon.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/api/v1/packages/refresh');
      // refresh and upgrade take no package, and the daemon refuses one; a
      // name passed anyway must never reach the wire.
      expect(request.body, isEmpty);
      expect(daemon.headers['authorization'], 'Bearer $secret');
    });

    test('install carries the package name', () async {
      await session.runPackageAction('install', name: 'nginx');
      final request = daemon.requests.single;
      expect(request.path, '/api/v1/packages/install');
      expect(request.body, {'name': 'nginx'});
    });

    test('remove trims the name and omits an empty one', () async {
      await session.runPackageAction('remove', name: '  nginx  ');
      expect(daemon.requests.last.body, {'name': 'nginx'});
      await session.runPackageAction('remove', name: '   ');
      expect(daemon.requests.last.body, isEmpty);
    });

    test('forwards the invoking user', () async {
      await session.runPackageAction('upgrade', invokedBy: 'alice');
      expect(daemon.headers['x-maidcafe-invoked-by'], 'alice');
    });
  });

  group('runFirewallAction', () {
    late _OpDaemon daemon;
    late MaidCafeStreamSession session;

    setUp(() async {
      daemon = _OpDaemon();
      await daemon.start();
      session = await MaidCafeStreamSession.openAt(
        manager: SshConnectionManager(() => throw UnimplementedError()),
        baseUrl: daemon.baseUrl,
      );
    });

    tearDown(() async => daemon.stop());

    test('enable posts no rule fields', () async {
      await session.runFirewallAction('enable');
      final request = daemon.requests.single;
      expect(request.path, '/api/v1/firewall/enable');
      expect(request.body, isEmpty);
    });

    test('allow carries the rule and omits empty fields', () async {
      await session.runFirewallAction(
        'allow',
        port: '80',
        protocol: 'tcp',
        source: 'any',
      );
      expect(daemon.requests.last.path, '/api/v1/firewall/allow');
      expect(daemon.requests.last.body, {
        'port': '80',
        'protocol': 'tcp',
        'source': 'any',
      });
      // An empty source means "any" to the daemon, so it is left out rather
      // than sent as a blank string.
      await session.runFirewallAction('deny', port: '22', protocol: 'tcp');
      expect(daemon.requests.last.body, {'port': '22', 'protocol': 'tcp'});
    });

    test('delete names the action it deletes', () async {
      await session.runFirewallAction(
        'delete',
        ruleAction: 'allow',
        port: '8080',
        protocol: 'tcp',
        source: '203.0.113.4',
      );
      expect(daemon.requests.last.path, '/api/v1/firewall/delete');
      expect(daemon.requests.last.body, {
        'port': '8080',
        'protocol': 'tcp',
        'source': '203.0.113.4',
        'rule_action': 'allow',
      });
      // enable/disable never take the field, whichever other fields arrive.
      await session.runFirewallAction('disable', ruleAction: 'allow');
      expect(daemon.requests.last.body, isEmpty);
    });
  });

  group('a route the daemon does not have', () {
    late _OpDaemon daemon;
    late MaidCafeStreamSession session;

    setUp(() async {
      daemon = _OpDaemon();
      await daemon.start();
      session = await MaidCafeStreamSession.openAt(
        manager: SshConnectionManager(() => throw UnimplementedError()),
        baseUrl: daemon.baseUrl,
      );
    });

    tearDown(() async => daemon.stop());

    test('is reported as a missing route, so a caller can fall back', () async {
      daemon.missingRoutes.addAll([
        '/api/v1/packages/refresh',
        '/api/v1/firewall/enable',
      ]);
      await expectLater(
        session.runPackageAction('refresh'),
        throwsA(isA<MaidCafeRouteMissingException>()),
      );
      await expectLater(
        session.runFirewallAction('enable'),
        throwsA(isA<MaidCafeRouteMissingException>()),
      );
    });

    test('a 404 the handler wrote is a failure, not a missing route', () async {
      // The daemon's own handler answering means the endpoint exists: the
      // caller must not fall back and re-run the operation over SSH.
      daemon.errorRoutes['/api/v1/packages/install'] = 'invalid package name';
      await expectLater(
        session.runPackageAction('install', name: 'nginx'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('invalid package name'),
          ),
        ),
      );
    });
  });
}
