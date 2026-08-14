import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/agent/agent_model_catalog.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.body);

  final String body;
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      body,
      200,
      headers: const {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('builds model endpoints with or without an existing v1 path', () {
    expect(
      modelsEndpoint('https://api.openai.com').toString(),
      'https://api.openai.com/v1/models',
    );
    expect(
      modelsEndpoint('https://openrouter.ai/api/v1/').toString(),
      'https://openrouter.ai/api/v1/models',
    );
  });

  test('fetches, deduplicates, and sorts OpenAI-compatible models', () async {
    final adapter = _FakeAdapter(
      jsonEncode({
        'data': [
          {'id': 'z-model'},
          {'id': 'a-model'},
          {'id': 'z-model'},
        ],
      }),
    );
    final dio = Dio()..httpClientAdapter = adapter;

    final models = await AgentModelCatalog(
      dio: dio,
    ).fetchModels(baseUrl: 'https://api.example.com', apiKey: 'secret');

    expect(models, ['a-model', 'z-model']);
    expect(
      adapter.request!.uri.toString(),
      'https://api.example.com/v1/models',
    );
    expect(adapter.request!.headers['Authorization'], 'Bearer secret');
  });
}
