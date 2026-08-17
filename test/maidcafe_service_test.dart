import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/cloud_sync_service.dart';
import 'package:maid_kit/servers/maidcafe_service.dart';
import 'package:maid_kit/servers/server_models.dart';

class _MemoryStorage extends FlutterSecureStorage {
  final values = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values.remove(key);
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, int status) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Map<String, dynamic> _daemon({String id = 'daemon-1'}) => {
  'id': id,
  'name': 'host',
  'enabled': true,
  'last_seen_at': null,
  'created_at': '2026-08-13T00:00:00Z',
  'updated_at': '2026-08-13T00:00:00Z',
};

void main() {
  test(
    'cloud create uses Solarpass bearer and stores one-time secret',
    () async {
      late RequestOptions request;
      final storage = _MemoryStorage();
      final dio = Dio()
        ..httpClientAdapter = _Adapter((options) async {
          request = options;
          return _json({..._daemon(), 'secret': 'cloud-secret'}, 201);
        });
      final service = MaidCafeService(
        baseUrl: 'https://mk.solsynth.dev///',
        cloudSync: CloudSyncService(vaultId: 'test'),
        accessToken: () async => 'solar-token',
        dio: dio,
        secureStorage: storage,
      );
      final daemon = await service.createDaemon(
        name: 'host',
        workspaceId: 'ws-1',
      );
      expect(request.method, 'POST');
      expect(request.uri.toString(), 'https://mk.solsynth.dev/api/daemons');
      expect(request.headers['Authorization'], 'Bearer solar-token');
      expect((request.data as Map)['workspace_id'], 'ws-1');
      expect((request.data as Map)['name'], 'host');
      expect(daemon.secret, 'cloud-secret');
      expect(storage.values['maidcafe_cloud_secret_daemon-1'], 'cloud-secret');
    },
  );

  test(
    'workspace quota is fetched with the Solarpass bearer and parsed',
    () async {
      late RequestOptions request;
      final dio = Dio()
        ..httpClientAdapter = _Adapter((options) async {
          request = options;
          return _json({
            'workspace_id': 'ws-1',
            'quotas': {
              'max_daemons': 5,
              'polling_interval_seconds': 30,
              'metrics_retention_days': 30,
            },
          }, 200);
        });
      final service = MaidCafeService(
        baseUrl: 'https://mk.solsynth.dev',
        cloudSync: CloudSyncService(vaultId: 'test'),
        accessToken: () async => 'solar-token',
        dio: dio,
      );
      final quota = await service.fetchWorkspaceQuota('ws-1');
      expect(request.method, 'GET');
      expect(
        request.uri.toString(),
        'https://mk.solsynth.dev/api/workspaces/ws-1/quota',
      );
      expect(request.headers['Authorization'], 'Bearer solar-token');
      expect(quota.workspaceId, 'ws-1');
      expect(quota.maxDaemons, 5);
      expect(quota.pollingIntervalSeconds, 30);
      expect(quota.metricsRetentionDays, 30);
    },
  );

  test('missing or non-positive quota dimensions mean no enforcement', () {
    final quota = MaidCafeQuota.fromJson({
      'workspace_id': 'ws-1',
      'quotas': {
        'max_daemons': 0,
        'polling_interval_seconds': -1,
        'metrics_retention_days': 'unlimited',
      },
    });
    expect(quota.maxDaemons, isNull);
    expect(quota.pollingIntervalSeconds, isNull);
    expect(quota.metricsRetentionDays, isNull);

    final empty = MaidCafeQuota.fromJson(const {'workspace_id': 'ws-1'});
    expect(empty.workspaceId, 'ws-1');
    expect(empty.maxDaemons, isNull);
    expect(empty.pollingIntervalSeconds, isNull);
    expect(empty.metricsRetentionDays, isNull);
  });

  test(
    'local invocation keeps raw bytes and signs with the local secret',
    () async {
      late RequestOptions request;
      final dio = Dio()
        ..httpClientAdapter = _Adapter((options) async {
          request = options;
          return ResponseBody.fromBytes(utf8.encode('accepted'), 200);
        });
      final service = MaidCafeService(
        baseUrl: 'https://mk.solsynth.dev',
        cloudSync: CloudSyncService(vaultId: 'test'),
        accessToken: () async => 'solar-token',
        dio: dio,
      );
      final payload = utf8.encode('{"job":"incremental"}');
      final result = await service.invokeWebhook(
        daemonBaseUrl: 'http://127.0.0.1:8747/',
        webhookName: 'backup',
        localWebhookSecret: 'local-secret',
        payload: payload,
      );
      expect(request.method, 'POST');
      expect(request.uri.path, '/api/v1/webhooks/backup');
      expect(
        request.headers['X-MaidCafe-Signature'],
        await maidCafeHmacSignature('local-secret', payload),
      );
      expect(request.headers.containsKey('Authorization'), isFalse);
      expect(request.headers.containsKey('cloud-token'), isFalse);
      expect(request.data, payload);
      expect(result.text, 'accepted');
    },
  );

  test(
    'webhook relay enqueues signed request and polls for the result',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio()
        ..httpClientAdapter = _Adapter((options) async {
          requests.add(options);
          if (options.method == 'POST') {
            return _json({'id': 'req-1', 'status': 'pending'}, 201);
          }
          return _json({
            'status': 'done',
            'result_code': 200,
            'result_body': base64Encode(utf8.encode('relayed-ok')),
            'result_error': '',
          }, 200);
        });
      final service = MaidCafeService(
        baseUrl: 'https://mk.solsynth.dev',
        cloudSync: CloudSyncService(vaultId: 'test'),
        accessToken: () async => 'solar-token',
        dio: dio,
      );
      final payload = utf8.encode('{"job":"incremental"}');
      final id = await service.enqueueWebhookRequest(
        daemonId: 'daemon-1',
        webhookName: 'backup',
        webhookSecret: 'local-secret',
        payload: payload,
      );
      expect(id, 'req-1');
      final post = requests.first;
      expect(post.uri.path, '/api/daemons/daemon-1/webhook-requests');
      final body = post.data as Map;
      expect(body['name'], 'backup');
      expect(body['body'], base64Encode(payload));
      expect(
        body['signature'],
        await maidCafeHmacSignature('local-secret', payload),
      );
      final result = await service.waitForWebhookResult(
        daemonId: 'daemon-1',
        requestId: id,
        timeout: const Duration(seconds: 2),
        interval: const Duration(milliseconds: 10),
      );
      expect(result.text, 'relayed-ok');
      expect(result.statusCode, 200);
      expect(
        requests.last.uri.path,
        '/api/daemons/daemon-1/webhook-requests/req-1',
      );
    },
  );

  test(
    'cloud lists daemon actions and invokes them through the relay',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio()
        ..httpClientAdapter = _Adapter((options) async {
          requests.add(options);
          final path = options.uri.path;
          if (options.method == 'POST') {
            return _json({'id': 'req-1', 'status': 'pending'}, 201);
          }
          if (path.endsWith('/actions')) {
            return _json([
              {
                'name': 'backup',
                'display_name': 'Backup data',
                'enabled': true,
              },
              {'name': 'cleanup', 'enabled': false},
            ], 200);
          }
          return _json({
            'status': 'done',
            'result_code': 0,
            'result_body': base64Encode(utf8.encode('backup-ok')),
            'result_error': '',
          }, 200);
        });
      final service = MaidCafeService(
        baseUrl: 'https://mk.solsynth.dev',
        cloudSync: CloudSyncService(vaultId: 'test'),
        accessToken: () async => 'solar-token',
        dio: dio,
      );

      final actions = await service.listActions('daemon-1');
      expect(actions, hasLength(2));
      expect(actions.first.name, 'backup');
      expect(actions.first.label, 'Backup data');
      expect(actions.last.enabled, isFalse);
      expect(requests.first.uri.path, '/api/daemons/daemon-1/actions');

      final result = await service.invokeActionViaCloud(
        daemonId: 'daemon-1',
        actionName: 'backup',
      );
      final post = requests.firstWhere((r) => r.method == 'POST');
      expect(post.uri.path, '/api/daemons/daemon-1/webhook-requests');
      expect(post.headers['Authorization'], 'Bearer solar-token');
      expect((post.data as Map)['name'], 'backup');
      expect((post.data as Map)['signature'], '');
      expect(
        base64Decode((post.data as Map)['body'] as String),
        utf8.encode('{}'),
      );
      expect(result.text, 'backup-ok');
    },
  );

  test('cloud credentials create, list and delete', () async {
    final requests = <RequestOptions>[];
    final dio = Dio()
      ..httpClientAdapter = _Adapter((options) async {
        requests.add(options);
        if (options.method == 'POST') {
          return _json({
            'id': 'cred-1',
            'label': 'ci-backup',
            'daemon_ids': <String>[],
            'host_ids': ['h1'],
            'action_names': ['backup'],
            'created_at': '2026-08-13T00:00:00Z',
            'token': 'mk_abc',
          }, 201);
        }
        if (options.method == 'DELETE') {
          return ResponseBody.fromString('', 204);
        }
        return _json([
          {
            'id': 'cred-1',
            'label': 'ci-backup',
            'daemon_ids': <String>[],
            'host_ids': ['h1'],
            'action_names': ['backup'],
            'created_at': '2026-08-13T00:00:00Z',
          },
        ], 200);
      });
    final service = MaidCafeService(
      baseUrl: 'https://mk.solsynth.dev',
      cloudSync: CloudSyncService(vaultId: 'test'),
      accessToken: () async => 'solar-token',
      dio: dio,
    );

    final created = await service.createCredential(
      label: 'ci-backup',
      hostIds: ['h1'],
      actionNames: ['backup'],
    );
    expect(created.token, 'mk_abc');
    expect(created.hostIds, ['h1']);
    final post = requests.first;
    expect(post.uri.path, '/api/credentials');
    expect(post.headers['Authorization'], 'Bearer solar-token');
    expect((post.data as Map)['label'], 'ci-backup');
    expect((post.data as Map)['host_ids'], ['h1']);
    expect((post.data as Map)['action_names'], ['backup']);

    final listed = await service.listCredentials();
    expect(listed, hasLength(1));
    expect(listed.single.label, 'ci-backup');
    expect(listed.single.token, isEmpty);

    await service.deleteCredential('cred-1');
    expect(requests.last.method, 'DELETE');
    expect(requests.last.uri.path, '/api/credentials/cred-1');
  });

  test('MaidCafeMetric.fromJson parses the full daemon sample', () {
    final metric = MaidCafeMetric.fromJson({
      'id': 'm1',
      'daemon_id': 'd1',
      'sent_at': '2026-08-16T10:00:00Z',
      'received_at': '2026-08-16T10:00:01Z',
      'uptime_seconds': 259200,
      'process_memory_bytes': 1073741824,
      'cpu_percent': 41.2,
      'cpu_count': 8,
      'load1': 2.5,
      'load5': 1.8,
      'load15': 1.2,
      'memory_used_percent': 58.3,
      'memory_used_bytes': 11918589952,
      'memory_total_bytes': 20462829568,
      'swap_total_kb': 2097152,
      'swap_free_kb': 1048576,
      'disk_total_kb': 102400,
      'disk_available_kb': 51200,
      'net_rx_bytes': 100,
      'net_tx_bytes': 200,
      'webhook_executions': 42,
      'webhook_failures': 1,
    });
    expect(metric.cpuCount, 8);
    expect(metric.load1, 2.5);
    expect(metric.load5, 1.8);
    expect(metric.load15, 1.2);
    expect(metric.swapTotalKb, 2097152);
    expect(metric.swapFreeKb, 1048576);
    expect(metric.diskTotalKb, 102400);
    expect(metric.diskAvailableKb, 51200);
    expect(metric.netRxBytes, 100);
    expect(metric.netTxBytes, 200);
  });

  test('MaidCafeMetric.fromJson tolerates missing extras', () {
    final metric = MaidCafeMetric.fromJson({
      'id': 'm1',
      'daemon_id': 'd1',
      'sent_at': '2026-08-16T10:00:00Z',
      'received_at': '2026-08-16T10:00:01Z',
      'uptime_seconds': 60,
      'process_memory_bytes': 0,
      'cpu_percent': 1,
      'memory_used_percent': 2,
      'memory_used_bytes': 3,
      'memory_total_bytes': 4,
      'webhook_executions': 0,
      'webhook_failures': 0,
    });
    expect(metric.cpuCount, 0);
    expect(metric.load1, 0);
    expect(metric.diskTotalKb, 0);
    expect(metric.netTxBytes, 0);
  });

  test('HMAC signature matches the RFC 4231 test vector', () async {
    expect(
      await maidCafeHmacSignature(
        'key',
        utf8.encode('The quick brown fox jumps over the lazy dog'),
      ),
      'f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8',
    );
  });

  test('missing Solarpass token fails before network request', () async {
    var requests = 0;
    final dio = Dio()
      ..httpClientAdapter = _Adapter((_) async {
        requests++;
        return _json({}, 500);
      });
    final service = MaidCafeService(
      baseUrl: maidCafeDefaultCloudUrl,
      cloudSync: CloudSyncService(vaultId: 'test'),
      accessToken: () async => null,
      dio: dio,
    );
    expect(
      () => service.listDaemons(workspaceId: 'ws-1'),
      throwsA(isA<MaidCafeException>()),
    );
    expect(requests, 0);
  });

  test('parseMaidCafeRuntimes parses the full payload', () {
    final snapshot = parseMaidCafeRuntimes({
      'runtimes': [
        {
          'runtime': 'java',
          'available': true,
          'error': null,
          'processes': [
            {
              'pid': 123,
              'user': 'root',
              'cpu_percent': 1.2,
              'memory_percent': 2.1,
              'rss_kb': 1048576,
              'threads': 45,
              'command': 'java -Xmx2g -jar app.jar',
            },
          ],
          'java': {
            'jdk': {'available': true, 'error': null},
            'jvms': [
              {
                'pid': 123,
                'main_class': 'app.Main',
                'old_percent': 23.4,
                'ygc': 12,
                'fgc': 0,
                'gct_seconds': 0.579,
                'error': null,
              },
            ],
          },
        },
        {
          'runtime': 'dotnet',
          'available': false,
          'error': 'no dotnet processes found',
          'processes': [],
        },
        {
          'runtime': 'python',
          'available': true,
          'processes': [
            {
              'pid': 456,
              'user': 'jane',
              'cpu_percent': 7.5,
              'memory_percent': 0.4,
              'rss_kb': 20480,
              'command': 'python3 server.py --port 8080',
            },
          ],
        },
      ],
      'watched': [
        {
          'name': 'nginx',
          'available': true,
          'error': null,
          'processes': [
            {
              'pid': 789,
              'user': 'www',
              'cpu_percent': 0.5,
              'memory_percent': 0.1,
              'rss_kb': 8192,
              'command': 'nginx: worker process',
            },
          ],
        },
      ],
    });
    expect(snapshot.groups, hasLength(3));
    final java = snapshot.groups[0];
    expect(java.kind, RuntimeKind.java);
    expect(java.available, isTrue);
    expect(java.processes, hasLength(1));
    expect(java.processes[0].pid, 123);
    expect(java.processes[0].threads, 45);
    expect(java.processes[0].command, 'java -Xmx2g -jar app.jar');
    expect(java.java, isNotNull);
    expect(java.java!.jdkAvailable, isTrue);
    expect(java.java!.jvms, hasLength(1));
    expect(java.java!.jvms[0].mainClass, 'app.Main');
    expect(java.java!.jvms[0].oldPercent, 23.4);
    expect(java.java!.jvms[0].ygc, 12);
    expect(java.java!.jvms[0].fgc, 0);
    expect(java.java!.jvms[0].gctSeconds, 0.579);
    final dotnet = snapshot.groups[1];
    expect(dotnet.kind, RuntimeKind.dotnet);
    expect(dotnet.available, isFalse);
    expect(dotnet.error, 'no dotnet processes found');
    expect(dotnet.java, isNull);
    // Python group omits `threads`: stays null.
    final python = snapshot.groups[2];
    expect(python.kind, RuntimeKind.python);
    expect(python.processes[0].threads, isNull);
    expect(snapshot.watched, hasLength(1));
    expect(snapshot.watched[0].name, 'nginx');
    expect(snapshot.watched[0].available, isTrue);
    expect(
      snapshot.watched[0].processes.single.command,
      'nginx: worker process',
    );
  });

  test('parseMaidCafeRuntimes parses unavailable watched groups', () {
    final snapshot = parseMaidCafeRuntimes({
      'runtimes': [],
      'watched': [
        {
          'name': 'redis',
          'available': false,
          'error': 'no redis processes found',
          'processes': [],
        },
        'not-a-map',
      ],
    });
    expect(snapshot.groups, isEmpty);
    expect(snapshot.watched, hasLength(1));
    expect(snapshot.watched[0].available, isFalse);
    expect(snapshot.watched[0].error, 'no redis processes found');
  });

  test(
    'parseMaidCafeRuntimes tolerates missing java key and unknown runtimes',
    () {
      final snapshot = parseMaidCafeRuntimes({
        'runtimes': [
          {
            'runtime': 'java',
            'available': true,
            'processes': [
              {'pid': 1, 'user': 'root', 'command': 'java -jar x.jar'},
            ],
          },
          {'runtime': 'rust', 'available': true, 'processes': []},
          'not-a-map',
        ],
      });
      expect(snapshot.groups, hasLength(1));
      expect(snapshot.groups[0].kind, RuntimeKind.java);
      // Missing `java` key leaves the java info null.
      expect(snapshot.groups[0].java, isNull);
    },
  );

  test('parseMaidCafeRuntimes preserves per-JVM errors', () {
    final snapshot = parseMaidCafeRuntimes({
      'runtimes': [
        {
          'runtime': 'java',
          'available': true,
          'processes': [
            {'pid': 1, 'user': 'root', 'command': 'java -jar x.jar'},
          ],
          'java': {
            'jdk': {'available': true, 'error': null},
            'jvms': [
              {
                'pid': 1,
                'main_class': 'app.Main',
                'error': 'jstat -gcutil: exit status 1',
              },
            ],
          },
        },
      ],
    });
    final jvm = snapshot.groups.single.java!.jvms.single;
    expect(jvm.oldPercent, isNull);
    expect(jvm.ygc, isNull);
    expect(jvm.error, 'jstat -gcutil: exit status 1');
  });

  test(
    'parseMaidCafeProcessHistory parses samples and skips malformed rows',
    () {
      final history = parseMaidCafeProcessHistory({
        'name': 'nginx',
        'samples': [
          {
            'name': 'nginx',
            'ts': '2026-08-16T21:00:00Z',
            'cpu_percent': 1.2,
            'rss_kb': 1048576,
            'process_count': 2,
            'threads': 45,
          },
          {
            'name': 'nginx',
            'ts': '2026-08-16T21:00:10Z',
            'cpu_percent': 0.0,
            'rss_kb': 2048,
            'process_count': 0,
          },
          'not-a-map',
          {
            'name': 'nginx',
            'ts': 'not-a-date',
            'cpu_percent': 1,
            'rss_kb': 1,
            'process_count': 1,
          },
        ],
      });
      expect(history.name, 'nginx');
      expect(history.samples, hasLength(2));
      expect(
        history.samples[0].timestamp,
        DateTime.parse('2026-08-16T21:00:00Z'),
      );
      expect(history.samples[0].cpuPercent, 1.2);
      expect(history.samples[0].rssKb, 1048576);
      expect(history.samples[0].processCount, 2);
      expect(history.samples[0].threads, 45);
      // Missing threads stays null.
      expect(history.samples[1].threads, isNull);
      expect(history.samples[1].processCount, 0);
    },
  );
}
