import 'package:dio/dio.dart';

class AgentModelCatalog {
  AgentModelCatalog({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<List<String>> fetchModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    final endpoint = modelsEndpoint(baseUrl);
    final response = await _dio.get<dynamic>(
      endpoint.toString(),
      options: Options(
        headers: {
          'Accept': 'application/json',
          if (apiKey.trim().isNotEmpty)
            'Authorization': 'Bearer ${apiKey.trim()}',
        },
      ),
    );
    final body = response.data;
    if (body is! Map) {
      throw const FormatException('The models response is not an object.');
    }
    final data = body['data'];
    if (data is! List) {
      throw const FormatException('The models response has no data list.');
    }
    final models = <String>{};
    for (final item in data) {
      if (item is! Map) continue;
      final id = item['id']?.toString().trim();
      if (id != null && id.isNotEmpty) models.add(id);
    }
    if (models.isEmpty) {
      throw const FormatException('The provider returned no model IDs.');
    }
    return models.toList()..sort();
  }
}

Uri modelsEndpoint(String baseUrl) {
  final value = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  final base = Uri.tryParse(value);
  if (base == null || !base.hasScheme || base.host.isEmpty) {
    throw ArgumentError.value(baseUrl, 'baseUrl', 'must be an absolute URL');
  }
  final path = base.path.endsWith('/v1')
      ? '${base.path}/models'
      : '${base.path}/v1/models';
  return base.replace(path: path, query: null, fragment: null);
}
