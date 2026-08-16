import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/maidcafe_metoer.dart';

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

ResponseBody _json(Object body, int status, {Map<String, String>? headers}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        if (headers != null)
          for (final entry in headers.entries) entry.key: [entry.value],
      },
    );

Map<String, dynamic> _notification({String id = 'n1', bool unread = true}) => {
  'id': id,
  'topic': 'maidcafe.daemon.alert',
  'title': 'Webhook backup failed',
  'content': 'exit code 1',
  'meta': {'daemon_id': 'daemon-1'},
  'viewed_at': unread ? null : '2026-08-14T01:00:00Z',
  'app_id': 'dev.solsynth.maidkit',
  'account_id': 'acc-1',
  'created_at': '2026-08-13T00:00:00Z',
};

void main() {
  test('list sends app query with bearer token and parses the feed', () async {
    late RequestOptions request;
    final dio = Dio()
      ..httpClientAdapter = _Adapter((options) async {
        request = options;
        return _json(
          [_notification(), _notification(id: 'n2', unread: false)],
          200,
          headers: {'X-Total': '12'},
        );
      });
    final client = MaidCafeMetoerClient(
      baseUrl: 'https://api.solian.app',
      accessToken: () async => 'solar-token',
      dio: dio,
    );

    final page = await client.list();

    expect(request.method, 'GET');
    expect(request.uri.path, '/metoer/notifications');
    expect(request.uri.queryParameters['app'], 'dev.solsynth.maidkit');
    expect(request.uri.queryParameters['offset'], '0');
    expect(request.uri.queryParameters['take'], '50');
    expect(request.headers['Authorization'], 'Bearer solar-token');
    expect(page.total, 12);
    expect(page.items, hasLength(2));
    final first = page.items.first;
    expect(first.id, 'n1');
    expect(first.topic, 'maidcafe.daemon.alert');
    expect(first.title, 'Webhook backup failed');
    expect(first.body, 'exit code 1');
    expect(first.meta['daemon_id'], 'daemon-1');
    expect(first.unread, isTrue);
    expect(first.accountId, 'acc-1');
    final second = page.items.last;
    expect(second.unread, isFalse);
    expect(second.viewedAt, isNotNull);
  });

  test('list with unmark adds the opt-out query flag', () async {
    late RequestOptions request;
    final dio = Dio()
      ..httpClientAdapter = _Adapter((options) async {
        request = options;
        return _json(const [], 200);
      });
    final client = MaidCafeMetoerClient(
      baseUrl: 'https://api.solian.app',
      accessToken: () async => 'solar-token',
      dio: dio,
    );

    await client.list(unmark: true);

    expect(request.uri.queryParameters['unmark'], 'true');
  });

  test('unreadCount parses a bare int and a count object', () async {
    final responses = [
      _json(3, 200),
      _json({'count': 5}, 200),
    ];
    final dio = Dio()
      ..httpClientAdapter = _Adapter((options) async {
        final response = responses.removeAt(0);
        return response;
      });
    final client = MaidCafeMetoerClient(
      baseUrl: 'https://api.solian.app',
      accessToken: () async => 'solar-token',
      dio: dio,
    );

    expect(await client.unreadCount(), 3);
    expect(await client.unreadCount(), 5);
  });

  test(
    'markAllRead posts to the all-read endpoint with the app query',
    () async {
      late RequestOptions request;
      final dio = Dio()
        ..httpClientAdapter = _Adapter((options) async {
          request = options;
          return ResponseBody.fromString('', 204);
        });
      final client = MaidCafeMetoerClient(
        baseUrl: 'https://api.solian.app',
        accessToken: () async => 'solar-token',
        dio: dio,
      );

      await client.markAllRead();

      expect(request.method, 'POST');
      expect(request.uri.path, '/metoer/notifications/all/read');
      expect(request.uri.queryParameters['app'], 'dev.solsynth.maidkit');
      expect(request.headers['Authorization'], 'Bearer solar-token');
    },
  );

  test(
    'registerPushSubscription puts the device token with the MaidCafe app id',
    () async {
      late RequestOptions request;
      final dio = Dio()
        ..httpClientAdapter = _Adapter((options) async {
          request = options;
          return ResponseBody.fromString('', 204);
        });
      final client = MaidCafeMetoerClient(
        baseUrl: 'https://api.solian.app',
        accessToken: () async => 'solar-token',
        dio: dio,
      );

      await client.registerPushSubscription(
        deviceToken: 'fcm-token-1',
        provider: 1,
        deviceName: 'build-host',
      );

      expect(request.method, 'PUT');
      expect(request.uri.path, '/metoer/notifications/subscription');
      expect(request.headers['Authorization'], 'Bearer solar-token');
      final body = request.data as Map;
      expect(body['device_token'], 'fcm-token-1');
      expect(body['provider'], 1);
      expect(body['device_name'], 'build-host');
      expect(body['app_id'], 'dev.solsynth.maidkit');
    },
  );

  test('missing Solarpass token fails before any network request', () async {
    var requests = 0;
    final dio = Dio()
      ..httpClientAdapter = _Adapter((_) async {
        requests++;
        return _json(const {}, 500);
      });
    final client = MaidCafeMetoerClient(
      baseUrl: 'https://api.solian.app',
      accessToken: () async => null,
      dio: dio,
    );

    expect(() => client.list(), throwsA(isA<MaidCafeMetoerException>()));
    expect(requests, 0);
  });
}
