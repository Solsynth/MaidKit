import 'dart:convert';

import 'package:http/http.dart' as http;
import '../shared/services/user_agent.dart';

import 'personality_service.dart';

class BillingUsage {
  const BillingUsage({required this.used, this.max});

  final double used;
  final double? max;

  factory BillingUsage.fromJson(Object? json) {
    if (json is! Map) return const BillingUsage(used: 0);
    final values = Map<String, dynamic>.from(json);
    return BillingUsage(
      used: double.tryParse(values['used']?.toString() ?? '') ?? 0,
      max: double.tryParse(values['max']?.toString() ?? ''),
    );
  }
}

class BillingPolicy {
  const BillingPolicy({
    this.hourlyGolds,
    this.hourlyPoints,
    this.dailyGolds,
    this.dailyPoints,
    required this.blacklisted,
  });

  final BillingUsage? hourlyGolds;
  final BillingUsage? hourlyPoints;
  final BillingUsage? dailyGolds;
  final BillingUsage? dailyPoints;
  final bool blacklisted;

  factory BillingPolicy.fromJson(Map<String, dynamic> json) {
    final usage = json['usage'] is Map
        ? Map<String, dynamic>.from(json['usage'] as Map)
        : const <String, dynamic>{};
    final hourly = usage['hourly_usage'] is Map
        ? Map<String, dynamic>.from(usage['hourly_usage'] as Map)
        : const <String, dynamic>{};
    final daily = usage['daily_usage'] is Map
        ? Map<String, dynamic>.from(usage['daily_usage'] as Map)
        : const <String, dynamic>{};
    return BillingPolicy(
      hourlyGolds: BillingUsage.fromJson(hourly['golds']),
      hourlyPoints: BillingUsage.fromJson(hourly['points']),
      dailyGolds: BillingUsage.fromJson(daily['golds']),
      dailyPoints: BillingUsage.fromJson(daily['points']),
      blacklisted: json['blacklisted'] == true,
    );
  }
}

class PersonalityBillingException implements Exception {
  const PersonalityBillingException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads the signed-in account's PersonalityCore usage and billing policy.
class PersonalityBillingService {
  const PersonalityBillingService({this.client});

  static const productionBaseUrl = PersonalityService.productionBaseUrl;

  final http.Client? client;

  Future<BillingPolicy> getMyBilling({
    required String baseUrl,
    required String accessToken,
  }) async {
    final requestClient = client ?? http.Client();
    try {
      final response = await requestClient.get(
        _endpoint(baseUrl, 'billing/me'),
        headers: {
          'Authorization': 'Bearer ${accessToken.trim()}',
          ...await maidKitUserAgentHeader(),
        },
      );
      final Object? body;
      try {
        body = jsonDecode(response.body);
      } catch (_) {
        throw const PersonalityBillingException('Invalid billing response.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw PersonalityBillingException(
          _errorMessage(body, response.statusCode),
        );
      }
      if (body is! Map) {
        throw const PersonalityBillingException('Invalid billing response.');
      }
      return BillingPolicy.fromJson(Map<String, dynamic>.from(body));
    } finally {
      if (client == null) requestClient.close();
    }
  }

  Future<void> settle({
    required String baseUrl,
    required String accessToken,
  }) async {
    final requestClient = client ?? http.Client();
    try {
      final response = await requestClient.post(
        _endpoint(baseUrl, 'billing/me/settle'),
        headers: {
          'Authorization': 'Bearer ${accessToken.trim()}',
          ...await maidKitUserAgentHeader(),
        },
      );
      Object? body;
      try {
        body = jsonDecode(response.body);
      } catch (_) {
        body = null;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw PersonalityBillingException(
          _errorMessage(body, response.statusCode),
        );
      }
    } finally {
      if (client == null) requestClient.close();
    }
  }

  Uri _endpoint(String baseUrl, String path) {
    final root = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$root/$path');
  }

  String _errorMessage(Object? body, int statusCode) {
    if (body is Map) {
      final message = body['detail'] ?? body['message'];
      if (message != null && message.toString().isNotEmpty) {
        return message.toString();
      }
      if (body['error'] case final Map error) {
        final message = error['message'];
        if (message != null && message.toString().isNotEmpty) {
          return message.toString();
        }
      }
    }
    return 'Unable to load Personality billing (HTTP $statusCode).';
  }
}
