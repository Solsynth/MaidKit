import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/containers/container_models.dart';
import 'package:maid_kit/servers/maidcafe_stream.dart';
import 'package:maid_kit/servers/ssh_connection_manager.dart';

/// A stand-in for the daemon's per-container endpoints: it records every
/// request and answers with the JSON shapes the Go daemon produces, so the
/// client's URLs, query parameters and payload mapping are exercised for real
/// over HTTP.
class _FakeDaemon {
  HttpServer? _server;

  /// Every request the session made, in order, including the `/health`
  /// handshake [MaidCafeStreamSession.openAt] performs.
  final requests = <String>[];

  /// The same list without the handshake, for URL assertions.
  List<String> get apiRequests => [
    for (final request in requests)
      if (request != 'GET /health') request,
  ];

  /// Answers keyed by `METHOD /path?query`, with a body to return.
  final answers = <String, (int, Object?)>{
    'GET /health': (200, {'version': 'test'}),
  };

  String get baseUrl => 'http://127.0.0.1:${_server!.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle);
  }

  /// The raw body of every request that carried one, in order.
  final bodies = <String>[];

  /// The `X-MaidCafe-Signature` header of every request, in order (`''` when
  /// the request did not carry one).
  final signatures = <String>[];

  /// The bodies and signatures of the API requests, without the `/health`
  /// handshake [MaidCafeStreamSession.openAt] performs.
  List<String> get apiBodies => _withoutHandshake(bodies);

  List<String> get apiSignatures => _withoutHandshake(signatures);

  List<String> _withoutHandshake(List<String> values) {
    final index = requests.indexOf('GET /health');
    if (index < 0) return values;
    return [
      for (var i = 0; i < values.length; i++)
        if (i != index) values[i],
    ];
  }

  Future<void> stop() async => _server?.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final uri = request.uri;
    final key =
        '${request.method} ${uri.path}'
        '${uri.hasQuery ? '?${uri.query}' : ''}';
    requests.add(key);
    bodies.add(await utf8.decodeStream(request));
    signatures.add(request.headers.value('X-MaidCafe-Signature') ?? '');
    final answer = answers[key];
    final response = request.response;
    if (answer == null) {
      // The daemon's miss for an unknown route: a body-less 404, which the
      // client reads as "this daemon has no such endpoint".
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    final (status, body) = answer;
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(body == null ? '' : jsonEncode(body));
    await response.close();
  }
}

/// A docker-shaped inspect document, the same one both transports parse.
Map<String, Object?> _inspectPayload() => {
  'Id': 'abcdef1234567890',
  'Name': '/web',
  'Created': '2026-10-01T10:00:00Z',
  'Image': 'sha256:deadbeef',
  'Platform': 'linux',
  'State': {
    'Status': 'running',
    'StartedAt': '2026-10-01T10:00:05Z',
    'FinishedAt': '0001-01-01T00:00:00Z',
    'ExitCode': 0,
  },
  'Config': {
    'Image': 'nginx:1.25',
    'Env': ['TZ=UTC', ''],
    'Entrypoint': ['/docker-entrypoint.sh'],
    'Cmd': ['nginx', '-g', 'daemon off;'],
    'WorkingDir': '/etc/nginx',
    'User': 'root',
    'Labels': {
      'com.docker.compose.project': 'myapp',
      'com.docker.compose.service': 'web',
    },
  },
  'HostConfig': {
    'Binds': ['/srv/web:/usr/share/nginx/html'],
    'NetworkMode': 'bridge',
    'RestartPolicy': {'Name': 'unless-stopped'},
    'PortBindings': {
      '80/tcp': [
        {'HostIp': '0.0.0.0', 'HostPort': '8080'},
      ],
    },
  },
  'NetworkSettings': {
    'Networks': {
      'myapp_default': {'IPAddress': '172.18.0.2'},
    },
  },
};

void main() {
  late _FakeDaemon daemon;
  late MaidCafeStreamSession session;
  const secret = 'metrics-secret';

  setUp(() async {
    daemon = _FakeDaemon();
    await daemon.start();
    session = await MaidCafeStreamSession.openAt(
      manager: SshConnectionManager(() => throw UnimplementedError()),
      baseUrl: daemon.baseUrl,
      apiSecret: secret,
    );
  });

  tearDown(() async => daemon.stop());

  test(
    'inspect reads the runtime document the daemon passes through',
    () async {
      daemon.answers['GET /api/v1/containers/web/inspect'] = (
        200,
        {
          'container': 'abcdef123456',
          'name': 'web',
          'runtime': 'docker',
          'inspect': _inspectPayload(),
        },
      );

      final payload = await session.containerInspect('web');
      final object = payload['inspect']! as Map<String, Object?>;
      final detail = ContainerInspectDetail.fromInspectJson(
        object.map((key, value) => MapEntry(key, value)),
        rawJson: jsonEncode(object),
      );

      expect(daemon.apiRequests, ['GET /api/v1/containers/web/inspect']);
      expect(detail.name, 'web');
      expect(detail.image, 'nginx:1.25');
      expect(detail.state, 'running');
      expect(detail.isRunning, isTrue);
      expect(detail.restartPolicy, 'unless-stopped');
      expect(detail.networkMode, 'bridge');
      expect(detail.workingDir, '/etc/nginx');
      // An empty environment entry is dropped, as the SSH path drops it.
      expect(detail.env, ['TZ=UTC']);
      expect(detail.command, ['nginx', '-g', 'daemon off;']);
      expect(detail.ports, ['8080:80']);
      expect(detail.binds, ['/srv/web:/usr/share/nginx/html']);
      expect(detail.labels['com.docker.compose.project'], 'myapp');
      expect(detail.networks, ['myapp_default']);
    },
  );

  test('an id with a slash is escaped into one path segment', () async {
    daemon.answers['GET /api/v1/containers/a%2Fb/stats'] = (
      200,
      {'container': 'a/b'},
    );

    await session.containerStats('a/b');

    expect(daemon.apiRequests, ['GET /api/v1/containers/a%2Fb/stats']);
  });

  test(
    'stats map the daemon\'s normalized fields onto the tile model',
    () async {
      daemon.answers['GET /api/v1/containers/web/stats'] = (
        200,
        {
          'container': 'abcdef123456',
          'name': '/web',
          'runtime': 'docker',
          'cpu_percent': 12.5,
          'memory_usage_bytes': 20 * 1024 * 1024,
          'memory_limit_bytes': 1024 * 1024 * 1024,
          'memory_percent': 2.0,
          'network_input_bytes': 2048,
          'network_output_bytes': 4096,
          'block_input_bytes': null,
          'block_output_bytes': null,
          'pids': 7,
          'fetched_at': '2026-10-03T02:00:00Z',
        },
      );

      final stats = ContainerStats.fromDaemonJson(
        await session.containerStats('web'),
      );

      expect(stats.id, 'abcdef123456');
      expect(stats.name, 'web');
      expect(stats.cpuPercent, 12.5);
      expect(stats.memPercent, 2.0);
      expect(stats.memUsedBytes, 20 * 1024 * 1024);
      expect(stats.memLimitBytes, 1024 * 1024 * 1024);
      expect(stats.memUsage, '20.0 MB / 1.0 GB');
      expect(stats.netRxBytes, 2048);
      expect(stats.netTxBytes, 4096);
      expect(stats.netIO, '2.0 KB / 4.0 KB');
      expect(stats.pids, 7);
      // A measurement a rootless runtime cannot take stays unset rather than
      // becoming a zero it never measured.
      expect(stats.blockReadBytes, isNull);
      expect(stats.blockIO, '');
    },
  );

  test('logs carry the source and line count the tail asked for', () async {
    daemon.answers['GET /api/v1/containers/web/logs?source=runtime&lines=50'] =
        (
          200,
          {
            'container': 'abcdef123456',
            'source': 'runtime',
            'lines': [
              {'ts': '2026-10-03T02:00:00Z', 'line': 'listening on 80'},
              {'ts': '2026-10-03T02:00:01Z', 'line': 'ready'},
            ],
          },
        );

    final lines = parseContainerLogLines(
      await session.containerLogs('web', source: 'runtime', lines: 50),
    );

    expect(daemon.apiRequests, [
      'GET /api/v1/containers/web/logs?source=runtime&lines=50',
    ]);
    expect(lines.map((line) => line.line), ['listening on 80', 'ready']);
    expect(
      lines.first.timestamp!.toUtc().toIso8601String(),
      '2026-10-03T02:00:00.000Z',
    );
  });

  test(
    'the batch updates payload keeps an unanswered check unanswered',
    () async {
      daemon.answers['GET /api/v1/updates'] = (
        200,
        {
          'interval_seconds': 3600,
          'containers': [
            {
              'container': 'abcdef123456',
              'name': 'web',
              'runtime': 'docker',
              'image': 'nginx:1.25',
              'checked_at': '2026-10-03T02:00:00Z',
              'outdated': true,
              'pinned': false,
              'restart_required': false,
            },
            {
              'container': '999999999999',
              'name': 'worker',
              'runtime': 'podman',
              'image': 'ghcr.io/acme/worker:edge',
              'outdated': null,
              'error': 'registry unreachable',
            },
            {
              'container': 'cafebabecafe',
              'name': 'db',
              'runtime': 'docker',
              'image': 'postgres@sha256:abc',
              'outdated': false,
              'pinned': true,
              'restart_required': true,
            },
          ],
        },
      );

      final updates = parseContainerUpdates(await session.containerUpdates());

      expect(updates.intervalSeconds, 3600);
      expect(updates.containers, hasLength(3));

      final web = updates.forContainer('abcdef123456');
      expect(web!.hasUpdate, isTrue);
      expect(web.outdated, isTrue);

      // Null is not false: an unanswered check must not read as "current".
      final worker = updates.forContainer('999999999999');
      expect(worker!.outdated, isNull);
      expect(worker.hasUpdate, isFalse);
      expect(worker.error, 'registry unreachable');

      // A pinned container is never outdated, but a newer local image still
      // means a recreate is wanted.
      final db = updates.forContainer('', name: '/db');
      expect(db!.pinned, isTrue);
      expect(db.outdated, isFalse);
      expect(db.hasUpdate, isTrue);
    },
  );

  test('a single update check unwraps the nested status', () async {
    daemon.answers['GET /api/v1/containers/cafebabecafe/update-check'] = (
      200,
      {
        'container': {
          'container': 'cafebabecafe',
          'name': 'db',
          'runtime': 'docker',
          'image': 'postgres:16',
          'outdated': true,
        },
      },
    );

    final updates = parseContainerUpdates(
      await session.containerUpdateCheck('cafebabecafe'),
      single: true,
    );

    expect(daemon.apiRequests, [
      'GET /api/v1/containers/cafebabecafe/update-check',
    ]);
    expect(updates.containers, hasLength(1));
    expect(updates.forContainer('cafebabecafe')!.outdated, isTrue);
  });

  test('an unknown container surfaces the daemon\'s own words', () async {
    daemon.answers['GET /api/v1/containers/ghost/inspect'] = (
      404,
      {'ok': false, 'error': 'no such container'},
    );

    await expectLater(
      session.containerInspect('ghost'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('no such container'),
        ),
      ),
    );
  });

  test('a daemon without the detail reads reports a missing route', () async {
    // No answer registered: the stand-in serves the body-less 404 an older
    // daemon answers for a route it does not have.
    await expectLater(
      session.containerStats('web'),
      throwsA(isA<MaidCafeRouteMissingException>()),
    );
  });

  test('the stack registry carries its health and scan policy', () async {
    daemon.answers['GET /api/v1/compose/stacks'] = (
      200,
      {
        'ok': true,
        'stacks': [
          {
            'project': 'storefront',
            'directory': '/opt/stacks/web',
            'files': ['/opt/stacks/web/compose.yaml'],
            'services': ['web', 'worker'],
            'scanned_at': '2026-10-03T02:00:00Z',
            'running': 1,
            'total': 2,
            'containers': [
              {
                'id': 'abcdef123456',
                'name': 'web',
                'image': 'nginx:1.25',
                'state': 'running',
                'runtime': 'podman',
              },
              {
                'id': '999999999999',
                'name': 'worker',
                'image': 'busybox',
                'state': 'exited',
                'runtime': 'podman',
              },
            ],
          },
        ],
        'scan': {
          'roots': ['/opt', '/srv'],
          'depth': 3,
          'max_files': 400,
        },
      },
    );

    final snapshot = parseComposeStacks(await session.composeStacks());

    expect(daemon.apiRequests, ['GET /api/v1/compose/stacks']);
    expect(snapshot.scan.roots, ['/opt', '/srv']);
    expect(snapshot.scan.depth, 3);
    expect(snapshot.stacks, hasLength(1));
    final stack = snapshot.stacks.single;
    expect(stack.project, 'storefront');
    expect(stack.directory, '/opt/stacks/web');
    expect(stack.services, ['web', 'worker']);
    expect(stack.running, 1);
    expect(stack.total, 2);
    // One container is down, so the stack is not healthy.
    expect(stack.isHealthy, isFalse);
    expect(stack.containers.map((item) => item.name), ['web', 'worker']);
    expect(stack.containers.first.isRunning, isTrue);
    expect(stack.containers.last.isRunning, isFalse);
  });

  test('a scan is a signed request and reports what changed', () async {
    daemon.answers['POST /api/v1/compose/stacks/scan'] = (
      200,
      {
        'ok': true,
        'roots': ['/opt/stacks/web'],
        'found': 1,
        'added': ['web'],
        'updated': <String>[],
        'removed': <String>[],
        'stacks': [
          {
            'project': 'web',
            'directory': '/opt/stacks/web',
            'files': ['/opt/stacks/web/compose.yaml'],
            'services': ['web'],
            'running': 1,
            'total': 1,
          },
        ],
      },
    );

    final outcome = ComposeScanOutcome.fromDaemonJson(
      await session.scanComposeStacks(path: '/opt/stacks/web'),
    );

    expect(daemon.apiRequests, ['POST /api/v1/compose/stacks/scan']);
    // The body signature is what authorizes the daemon to act in the scanned
    // directories, so a scan without one is refused.
    expect(daemon.apiSignatures.single, isNotEmpty);
    expect(jsonDecode(daemon.apiBodies.single), {'path': '/opt/stacks/web'});
    expect(outcome.roots, ['/opt/stacks/web']);
    expect(outcome.added, ['web']);
    expect(outcome.changed, isTrue);
    expect(outcome.stacks.stacks.single.isHealthy, isTrue);
  });

  test('a scan with no starting point sends no path', () async {
    daemon.answers['POST /api/v1/compose/stacks/scan'] = (
      200,
      {
        'ok': true,
        'roots': ['/opt'],
        'found': 0,
        'added': <String>[],
        'updated': <String>[],
        'removed': <String>[],
        'stacks': <Object?>[],
      },
    );

    final outcome = ComposeScanOutcome.fromDaemonJson(
      await session.scanComposeStacks(),
    );

    // Removing the key entirely is what makes "the daemon's configured roots"
    // the answer, rather than an empty path the daemon has to interpret.
    expect(jsonDecode(daemon.apiBodies.single), <String, Object?>{});
    expect(outcome.changed, isFalse);
    expect(outcome.stacks.isEmpty, isTrue);
  });

  test('unassigning a stack is a delete of its own route', () async {
    daemon.answers['DELETE /api/v1/compose/stacks/myapp'] = (
      200,
      {
        'ok': true,
        'stack': {'project': 'myapp', 'directory': '/opt/myapp'},
      },
    );

    await session.unassignComposeStack('myapp');

    expect(daemon.apiRequests, ['DELETE /api/v1/compose/stacks/myapp']);
  });

  test(
    'a stack upgrade names no directory, so the daemon uses its own',
    () async {
      daemon.answers['POST /api/v1/compose/myapp/update'] = (
        200,
        {'ok': true, 'exit_code': 0},
      );

      await session.runComposeAction('myapp', 'update', '');

      expect(daemon.apiRequests, ['POST /api/v1/compose/myapp/update']);
      expect(daemon.apiSignatures.single, isNotEmpty);
      expect(jsonDecode(daemon.apiBodies.single), {'directory': ''});
    },
  );
}
