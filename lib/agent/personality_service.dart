import 'dart:convert';

import 'package:http/http.dart' as http;
import '../shared/services/user_agent.dart';

class PersonalityAgent {
  const PersonalityAgent({
    required this.id,
    required this.name,
    required this.description,
  });

  final String id;
  final String name;
  final String description;

  String get displayName => name.isEmpty ? 'Unnamed agent' : name;

  factory PersonalityAgent.fromJson(Map<String, dynamic> json) =>
      PersonalityAgent(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
      );
}

/// Discovers enabled agents from a PersonalityCore deployment.
class PersonalityService {
  const PersonalityService({this.client});

  static const productionBaseUrl = 'https://api.solian.app/personality';

  final http.Client? client;

  Future<List<PersonalityAgent>> listAgents({
    required String baseUrl,
    required String accessToken,
  }) async {
    final requestClient = client ?? http.Client();
    try {
      final root = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
      final response = await requestClient.get(
        Uri.parse('$root/agents'),
        headers: {
          'Authorization': 'Bearer ${accessToken.trim()}',
          ...await maidKitUserAgentHeader(),
        },
      );
      final Object? body;
      try {
        body = jsonDecode(response.body);
      } catch (_) {
        throw PersonalityServiceException('Invalid agent-list response.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw PersonalityServiceException(
          _errorMessage(body, response.statusCode),
        );
      }
      if (body is! List) {
        throw PersonalityServiceException('Invalid agent-list response.');
      }
      return [
        for (final item in body)
          if (item is Map<String, dynamic>)
            PersonalityAgent.fromJson(item)
          else if (item is Map)
            PersonalityAgent.fromJson(Map<String, dynamic>.from(item)),
      ].where((agent) => agent.id.isNotEmpty).toList();
    } finally {
      if (client == null) requestClient.close();
    }
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
    return 'Unable to load Personality agents (HTTP $statusCode).';
  }
}

class PersonalityServiceException implements Exception {
  const PersonalityServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
