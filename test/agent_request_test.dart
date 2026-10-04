import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/agent/agent_attachment.dart';
import 'package:maid_kit/agent/agent_reasoning.dart';
import 'package:maid_kit/agent/agent_repository.dart';
import 'package:maid_kit/agent/ssh_agent_service.dart';

/// A stand-in for an OpenAI-compatible endpoint: it records the JSON body of
/// every chat completion and answers with one streamed token, so the request
/// the service actually puts on the wire can be read back.
class _FakeEndpoint {
  HttpServer? _server;

  /// The decoded body of every request, in order.
  final bodies = <Map<String, dynamic>>[];

  String get baseUrl => 'http://127.0.0.1:${_server!.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((request) async {
      bodies.add(
        jsonDecode(await utf8.decodeStream(request)) as Map<String, dynamic>,
      );
      request.response
        ..statusCode = 200
        ..write('data: {"choices":[{"delta":{"content":"ok"}}]}\n\n')
        ..write('data: [DONE]\n\n');
      await request.response.close();
    });
  }

  Future<void> stop() async => _server?.close(force: true);
}

void main() {
  late _FakeEndpoint endpoint;

  setUp(() async {
    endpoint = _FakeEndpoint();
    await endpoint.start();
  });

  tearDown(() => endpoint.stop());

  SshAgentService service(AgentReasoning reasoning) => SshAgentService(
    AgentConfiguration(
      providerId: 1,
      providerName: 'Test',
      apiKey: 'test-key',
      baseUrl: endpoint.baseUrl,
      model: 'test-model',
    ),
    reasoningEffort: reasoning.effort,
  );

  test('no chosen level leaves reasoning_effort off the request', () async {
    final turn = await service(
      AgentReasoning.modelDefault,
    ).request(servers: const [], prompt: 'hello');

    expect(turn.text, 'ok');
    expect(endpoint.bodies.single.containsKey('reasoning_effort'), isFalse);
  });

  test('a chosen level rides every request as reasoning_effort', () async {
    await service(
      AgentReasoning.high,
    ).request(servers: const [], prompt: 'hello');

    expect(endpoint.bodies.single['reasoning_effort'], 'high');
    expect(endpoint.bodies.single['model'], 'test-model');
  });

  test('attachments ride the user message as multimodal content', () async {
    const image = AgentAttachment(
      name: 'shot.png',
      content: 'data:image/png;base64,cG5n',
      isImage: true,
    );
    await service(AgentReasoning.modelDefault).request(
      servers: const [],
      prompt: agentUserContent('look', const [image]),
    );

    final messages = endpoint.bodies.single['messages'] as List;
    final content = (messages.last as Map)['content'] as List;
    expect(content, hasLength(2));
    expect(content.first, isA<Map<dynamic, dynamic>>());
    expect((content.last as Map)['image_url'], {
      'url': 'data:image/png;base64,cG5n',
    });
  });
}
