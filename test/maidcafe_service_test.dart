import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/cloud_sync_service.dart';
import 'package:maid_kit/servers/maidcafe_service.dart';

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
}
