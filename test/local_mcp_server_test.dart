import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/agent/local_mcp_server.dart';
import 'package:maid_kit/agent/mcp_client.dart' show mcpProtocolVersion;
import 'package:maid_kit/agent/mcp_review_mode.dart';

/// Fake tool set for protocol tests: one echo tool that records calls.
class _FakeInvoker implements LocalMcpToolInvoker {
  _FakeInvoker({this.decline = false});

  final bool decline;
  final calls = <String>[];
  final callers = <String?>[];

  @override
  Future<List<Map<String, dynamic>>> get toolDefinitions async => const [
    {
      'name': 'echo',
      'description': 'Echoes the input text.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'text': {'type': 'string'},
        },
        'required': ['text'],
      },
    },
  ];

  @override
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> arguments, {
    String? callerLabel,
  }) async {
    calls.add(name);
    callers.add(callerLabel);
    if (decline) throw const McpActionDeclinedException();
    if (name != 'echo') throw ArgumentError('Unknown tool: $name');
    return {
      'content': [
        {'type': 'text', 'text': 'echo: ${arguments['text']}'},
      ],
      'isError': false,
    };
  }
}

Map<String, dynamic> _request(Object? id, String method, [Object? params]) => {
  'jsonrpc': '2.0',
  'id': ?id,
  'method': method,
  'params': ?params,
};

void main() {
  group('LocalMcpProtocolHandler', () {
    late _FakeInvoker invoker;
    late LocalMcpProtocolHandler handler;

    setUp(() {
      invoker = _FakeInvoker();
      handler = LocalMcpProtocolHandler(invoker);
    });

    test(
      'initialize advertises the protocol version and capabilities',
      () async {
        final response = await handler.handle(
          _request(1, 'initialize', {
            'protocolVersion': mcpProtocolVersion,
            'capabilities': <String, Object?>{},
            'clientInfo': {'name': 'test-agent', 'version': '0'},
          }),
        );
        expect(response!['id'], 1);
        final result = response['result'] as Map<String, dynamic>;
        expect(result['protocolVersion'], mcpProtocolVersion);
        expect((result['capabilities'] as Map<String, dynamic>)['tools'], {
          'listChanged': false,
        });
        final serverInfo = result['serverInfo'] as Map<String, dynamic>;
        expect(serverInfo['name'], 'MaidKit');
      },
    );

    test('ping answers with an empty result', () async {
      final response = await handler.handle(_request(2, 'ping'));
      expect(response, {
        'jsonrpc': '2.0',
        'id': 2,
        'result': <String, Object?>{},
      });
    });

    test('notifications receive no reply', () async {
      expect(
        await handler.handle(_request(null, 'notifications/initialized')),
        isNull,
      );
      expect(
        await handler.handle(
          _request(null, 'notifications/cancelled', {'requestId': 1}),
        ),
        isNull,
      );
    });

    test('tools/list returns the invoker tool definitions', () async {
      final response = await handler.handle(_request(3, 'tools/list'));
      final result = response!['result'] as Map<String, dynamic>;
      expect(result['tools'], await invoker.toolDefinitions);
    });

    test('tools/call invokes the tool and returns its result', () async {
      final response = await handler.handle(
        _request(4, 'tools/call', {
          'name': 'echo',
          'arguments': {'text': 'hi'},
        }),
      );
      expect(invoker.calls, ['echo']);
      final result = response!['result'] as Map<String, dynamic>;
      expect(result['isError'], false);
      final content = result['content'] as List<dynamic>;
      expect(content.first['text'], 'echo: hi');
    });

    test('tools/call without a name is an invalid-params error', () async {
      final response = await handler.handle(_request(5, 'tools/call', {}));
      final error = response!['error'] as Map<String, dynamic>;
      expect(error['code'], -32602);
    });

    test('tools/call tool failure is returned as an isError result', () async {
      final response = await handler.handle(
        _request(6, 'tools/call', {
          'name': 'nope',
          'arguments': <String, dynamic>{},
        }),
      );
      final result = response!['result'] as Map<String, dynamic>;
      expect(result['isError'], true);
      final content = result['content'] as List<dynamic>;
      expect(content.first['text'], contains('Unknown tool'));
    });

    test('tools/call carries the client label from initialize', () async {
      await handler.handle(
        _request(1, 'initialize', {
          'protocolVersion': mcpProtocolVersion,
          'capabilities': <String, Object?>{},
          'clientInfo': {'name': 'test-agent', 'version': '2.1'},
        }),
      );
      await handler.handle(
        _request(2, 'tools/call', {
          'name': 'echo',
          'arguments': {'text': 'hi'},
        }),
      );
      expect(invoker.callers, ['test-agent 2.1']);
    });

    test('tools/call without initialize has no caller label', () async {
      await handler.handle(
        _request(1, 'tools/call', {
          'name': 'echo',
          'arguments': {'text': 'hi'},
        }),
      );
      expect(invoker.callers, [null]);
    });

    test('tools/call declined by the user is an isError result', () async {
      final declining = LocalMcpProtocolHandler(_FakeInvoker(decline: true));
      final response = await declining.handle(
        _request(7, 'tools/call', {
          'name': 'echo',
          'arguments': {'text': 'hi'},
        }),
      );
      final result = response!['result'] as Map<String, dynamic>;
      expect(result['isError'], true);
      final content = result['content'] as List<dynamic>;
      expect(content.first['text'], 'Action declined by the user.');
    });

    test('unknown methods answer with method-not-found', () async {
      final response = await handler.handle(_request(8, 'bogus'));
      final error = response!['error'] as Map<String, dynamic>;
      expect(error['code'], -32601);
    });

    test('requests without a method are invalid requests', () async {
      final response = await handler.handle({'jsonrpc': '2.0', 'id': 9});
      final error = response!['error'] as Map<String, dynamic>;
      expect(error['code'], -32600);
    });
  });

  group('LocalMcpToolExecutor tool surface', () {
    test('exposes the sixteen MaidKit resource tools', () {
      final definitions = LocalMcpToolExecutor.definitions;
      final names = [for (final tool in definitions) tool['name']];
      expect(names, [
        'list_servers',
        'run_command',
        'read_file',
        'write_file',
        'delete_file',
        'list_snippets',
        'get_snippet',
        'create_snippet',
        'run_snippet',
        'list_skills',
        'get_skill',
        'get_review_mode',
        'set_review_mode',
        'github_list_runs',
        'github_get_run',
        'github_list_jobs',
      ]);
      final runCommand = definitions.firstWhere(
        (tool) => tool['name'] == 'run_command',
      );
      final schema = runCommand['inputSchema'] as Map<String, dynamic>;
      expect(schema['required'], ['server_id', 'command']);
      final properties = schema['properties'] as Map<String, dynamic>;
      expect(properties['server_id']['type'], 'integer');
      expect(properties['command']['type'], 'string');

      final listRuns = definitions.firstWhere(
        (tool) => tool['name'] == 'github_list_runs',
      );
      final listRunsSchema = listRuns['inputSchema'] as Map<String, dynamic>;
      expect(listRunsSchema['required'], ['owner', 'name']);
    });
  });

  group('McpReviewMode', () {
    test('wire names round-trip for every mode', () {
      for (final mode in McpReviewMode.values) {
        expect(McpReviewMode.fromWireName(mode.wireName), mode);
      }
    });

    test('unknown wire names throw', () {
      expect(
        () => McpReviewMode.fromWireName('sometimes'),
        throwsArgumentError,
      );
    });
  });

  group('LocalMcpServer HTTP+SSE transport', () {
    late LocalMcpServer server;
    late HttpClient http;
    static const token = 'test-bearer-token';

    setUp(() async {
      server = LocalMcpServer(
        executor: _FakeInvoker(),
        port: 0,
        authToken: token,
      );
      await server.start();
      addTearDown(server.stop);
      http = HttpClient();
      addTearDown(http.close);
    });

    void authorize(HttpClientRequest request) {
      request.headers.set('Authorization', 'Bearer $token');
    }

    test('GET / reports the running server and its tools', () async {
      final request = await http.getUrl(
        Uri.parse('http://127.0.0.1:${server.boundPort}/'),
      );
      final response = await request.close();
      expect(response.statusCode, 200);
      final body =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      expect(body['name'], 'MaidKit');
      expect(body['status'], 'running');
      expect(body['tools'], contains('echo'));
    });

    test('rejects /sse and /message without the bearer token', () async {
      final sseRequest = await http.getUrl(
        Uri.parse('http://127.0.0.1:${server.boundPort}/sse'),
      );
      final sseResponse = await sseRequest.close();
      expect(sseResponse.statusCode, 401);
      await sseResponse.drain<void>();

      final messageRequest = await http.postUrl(
        Uri.parse('http://127.0.0.1:${server.boundPort}/message'),
      );
      messageRequest.write('{}');
      final messageResponse = await messageRequest.close();
      expect(messageResponse.statusCode, 401);
      await messageResponse.drain<void>();
    });

    test('serves the MCP handshake and tools/list over SSE', () async {
      final sseRequest = await http.getUrl(
        Uri.parse('http://127.0.0.1:${server.boundPort}/sse'),
      );
      authorize(sseRequest);
      final sseResponse = await sseRequest.close();
      expect(sseResponse.statusCode, 200);
      expect(sseResponse.headers.value('Mcp-Session-Id'), isNotNull);
      final reader = _SseReader(
        sseResponse.transform(utf8.decoder).transform(const LineSplitter()),
      );

      // The legacy handshake announces the message endpoint with a session id.
      final endpoint = await reader.nextData();
      expect(endpoint, startsWith('/message?sessionId='));
      final sessionId = endpoint!.split('sessionId=').last;
      expect(sessionId, isNotEmpty);

      Future<Map<String, dynamic>> post(Object message) async {
        final request = await http.postUrl(
          Uri.parse(
            'http://127.0.0.1:${server.boundPort}/message?sessionId=$sessionId',
          ),
        );
        authorize(request);
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(message));
        final response = await request.close();
        expect(response.statusCode, 202);
        await response.drain<void>();
        final data = await reader.nextData();
        return jsonDecode(data!) as Map<String, dynamic>;
      }

      final initialize = await post(
        _request(1, 'initialize', {
          'protocolVersion': mcpProtocolVersion,
          'capabilities': <String, Object?>{},
          'clientInfo': {'name': 'test-agent', 'version': '0'},
        }),
      );
      expect(
        (initialize['result'] as Map<String, dynamic>)['protocolVersion'],
        mcpProtocolVersion,
      );

      final tools = await post(_request(2, 'tools/list'));
      final toolsResult = tools['result'] as Map<String, dynamic>;
      final listed = toolsResult['tools'] as List<dynamic>;
      expect(listed.single['name'], 'echo');
    });

    test('POST /message without a session answers 404', () async {
      final request = await http.postUrl(
        Uri.parse('http://127.0.0.1:${server.boundPort}/message'),
      );
      authorize(request);
      request.write('{}');
      final response = await request.close();
      expect(response.statusCode, 404);
      await response.drain<void>();
    });
  });
}

/// Reads complete SSE events from a line stream: `data:` lines are joined
/// until a blank line terminates the event.
class _SseReader {
  _SseReader(Stream<String> lines) : _iterator = StreamIterator(lines);

  final StreamIterator<String> _iterator;

  Future<String?> nextData() async {
    final data = StringBuffer();
    while (await _iterator.moveNext()) {
      final line = _iterator.current;
      if (line.isEmpty) {
        if (data.isNotEmpty) return data.toString();
        data.clear();
        continue;
      }
      if (line.startsWith('data: ')) data.write(line.substring(6));
    }
    return data.isEmpty ? null : data.toString();
  }
}
