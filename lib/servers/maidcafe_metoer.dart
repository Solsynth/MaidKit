import 'dart:convert';

import 'package:dio/dio.dart';

/// App id the MaidCafe cloud publishes notifications under
/// (`MaidCafe/internal/ring/client.go`); matches the MaidKit bundle id
/// (`firebase_options.dart`, `dev.solsynth.maid`).
const maidCafeMetoerAppId = 'dev.solsynth.maid';

/// A notification delivered to the signed-in Solar account by Metoer (the
/// Solar Network Ring replacement). Wire shape mirrors
/// `SolarNetwork/Metoer/internal/model/notification.go`: snake_case with
/// nulls included; the body field is `content`.
class MaidCafeMetoerNotification {
  const MaidCafeMetoerNotification({
    required this.id,
    required this.topic,
    required this.createdAt,
    this.title,
    this.subtitle = '',
    this.body = '',
    this.meta = const {},
    this.viewedAt,
    this.appId,
    this.accountId = '',
  });

  final String id;
  final String topic;
  final String? title;
  final String subtitle;
  final String body;
  final Map<String, dynamic> meta;
  final DateTime? viewedAt;
  final String? appId;
  final String accountId;
  final DateTime createdAt;

  bool get unread => viewedAt == null;

  /// Tolerant parse: returns null when a required field is missing or
  /// unparseable so one malformed entry never aborts the whole feed.
  static MaidCafeMetoerNotification? tryParse(Map<String, dynamic> json) {
    final id = json['id'];
    final topic = json['topic'];
    final createdAt = DateTime.tryParse(json['created_at']?.toString() ?? '');
    if (id is! String || id.isEmpty || topic is! String || createdAt == null) {
      return null;
    }
    return MaidCafeMetoerNotification(
      id: id,
      topic: topic,
      title: json['title']?.toString(),
      subtitle: json['subtitle']?.toString() ?? '',
      body: json['content']?.toString() ?? '',
      meta: json['meta'] is Map
          ? Map<String, dynamic>.from(json['meta'] as Map)
          : const {},
      viewedAt: DateTime.tryParse(json['viewed_at']?.toString() ?? ''),
      appId: json['app_id']?.toString(),
      accountId: json['account_id']?.toString() ?? '',
      createdAt: createdAt,
    );
  }
}

/// One page of the Metoer notification feed.
class MaidCafeMetoerPage {
  const MaidCafeMetoerPage({required this.items, required this.total});

  final List<MaidCafeMetoerNotification> items;
  final int total;
}

class MaidCafeMetoerException implements Exception {
  const MaidCafeMetoerException(this.message, {this.statusCode, this.cause});

  final String message;
  final int? statusCode;
  final Object? cause;

  @override
  String toString() => 'MaidCafeMetoerException: $message';
}

/// REST client for the Metoer notification API of the Solar Network gateway
/// (`https://api.solian.app/metoer/**`), mirroring Solian's SDK
/// `NotificationsApi`. Requests are authenticated with the Solarpass bearer
/// token and filtered to the MaidCafe app id.
class MaidCafeMetoerClient {
  MaidCafeMetoerClient({
    required this.baseUrl,
    required this._accessToken,
    Dio? dio,
  }) : _dio = dio ?? Dio()
         ..options.connectTimeout = const Duration(seconds: 10)
         ..options.sendTimeout = const Duration(seconds: 10)
         ..options.receiveTimeout = const Duration(seconds: 15);

  final String baseUrl;
  final Future<String?> Function() _accessToken;
  final Dio _dio;

  /// Fetches one page of MaidCafe notifications, newest first. The endpoint
  /// marks the fetched page viewed server-side unless [unmark] is set.
  Future<MaidCafeMetoerPage> list({
    int offset = 0,
    int take = 50,
    bool unmark = false,
  }) async {
    final response = await _request(
      (token) => _dio.get<dynamic>(
        '$baseUrl/metoer/notifications',
        queryParameters: {
          'app': maidCafeMetoerAppId,
          'offset': offset,
          'take': take,
          if (unmark) 'unmark': 'true',
        },
        options: _options(token),
      ),
    );
    final data = _responseJson(response);
    if (data is! List) {
      throw const MaidCafeMetoerException(
        'Metoer returned an unexpected response.',
      );
    }
    final items = <MaidCafeMetoerNotification>[];
    for (final entry in data) {
      if (entry is! Map) continue;
      final item = MaidCafeMetoerNotification.tryParse(
        Map<String, dynamic>.from(entry),
      );
      if (item != null) items.add(item);
    }
    final total = int.tryParse(response.headers.value('X-Total') ?? '') ?? 0;
    return MaidCafeMetoerPage(items: items, total: total);
  }

  /// Unread notification count for the MaidCafe app. The response body is a
  /// bare integer or `{'count': int}`.
  Future<int> unreadCount() async {
    final response = await _request(
      (token) => _dio.get<dynamic>(
        '$baseUrl/metoer/notifications/count',
        queryParameters: {'app': maidCafeMetoerAppId},
        options: _options(token),
      ),
    );
    final data = response.data;
    if (data is num) return data.toInt();
    if (data is Map) {
      return (data['count'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  /// Marks every MaidCafe notification of this account read.
  Future<void> markAllRead() async {
    await _request(
      (token) => _dio.post<dynamic>(
        '$baseUrl/metoer/notifications/all/read',
        queryParameters: {'app': maidCafeMetoerAppId},
        options: _options(token),
      ),
    );
  }

  /// Registers (or updates) this device's push subscription for the MaidCafe
  /// app, mirroring Solian's `NotificationsApi.registerPushSubscription`
  /// (`PUT /metoer/notifications/subscription`). [deviceId] is a persistent
  /// per-install identifier used by Metoer to keep devices distinct;
  /// [provider] is the `SnNotificationPushSubscription.Provider` wire value
  /// (Apple APNs = 0, Google FCM = 1 — see
  /// `SolarNetwork/Metoer/internal/model/notification.go`).
  Future<void> registerPushSubscription({
    required String deviceId,
    required String deviceToken,
    required int provider,
    required String deviceName,
  }) async {
    await _request(
      (token) => _dio.put<dynamic>(
        '$baseUrl/metoer/notifications/subscription',
        data: {
          'device_id': deviceId,
          'device_token': deviceToken,
          'provider': provider,
          'device_name': deviceName,
          'app_id': maidCafeMetoerAppId,
        },
        options: _options(token),
      ),
    );
  }

  Future<Response<T>> _request<T>(
    Future<Response<T>> Function(String token) request,
  ) async {
    final token = await _accessToken();
    if (token == null || token.trim().isEmpty) {
      throw const MaidCafeMetoerException(
        'Sign in with Solarpass before viewing notifications.',
      );
    }
    try {
      final response = await request(token.trim());
      final status = response.statusCode ?? 0;
      if (!_acceptStatuses.contains(status)) {
        throw _httpError(status, response.data);
      }
      return response;
    } on MaidCafeMetoerException {
      rethrow;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status != null) throw _httpError(status, error.response?.data);
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        throw const MaidCafeMetoerException('Metoer request timed out.');
      }
      throw MaidCafeMetoerException(
        'Could not reach the Solar Network gateway.',
        cause: error,
      );
    } on FormatException {
      throw const MaidCafeMetoerException('Metoer returned invalid JSON.');
    } on TypeError {
      throw const MaidCafeMetoerException(
        'Metoer returned an unexpected response.',
      );
    }
  }

  static const _acceptStatuses = {200, 201, 204};

  Options _options(String token) =>
      Options(headers: {'Authorization': 'Bearer $token'});
}

Object? _responseJson(Response<dynamic> response) {
  final data = response.data;
  if (data is String) return jsonDecode(data);
  if (data is List<int>) return jsonDecode(utf8.decode(data));
  return data;
}

MaidCafeMetoerException _httpError(int status, Object? body) {
  var message = 'Metoer request failed with HTTP $status.';
  try {
    final decoded = body is String ? jsonDecode(body) : body;
    if (decoded is Map) {
      for (final key in const ['error', 'message', 'detail']) {
        final value = decoded[key];
        if (value is String && value.trim().isNotEmpty) {
          message = value;
          break;
        }
      }
    } else if (decoded is String && decoded.trim().isNotEmpty) {
      message = decoded;
    }
  } catch (_) {
    // Keep the actionable status fallback when the error body is not JSON.
  }
  return MaidCafeMetoerException(message, statusCode: status);
}
