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
      final daemon = await service.createDaemon(name: 'host');
      expect(request.method, 'POST');
      expect(request.uri.toString(), 'https://mk.solsynth.dev/api/daemons');
      expect(request.headers['Authorization'], 'Bearer solar-token');
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
    expect(() => service.listDaemons(), throwsA(isA<MaidCafeException>()));
    expect(requests, 0);
  });
}
