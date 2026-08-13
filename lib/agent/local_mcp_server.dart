import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_openai/dart_openai.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:maid_kit/agent/mcp_client.dart' show mcpProtocolVersion;
import 'package:maid_kit/agent/mcp_review_mode.dart';
import 'package:maid_kit/agent/ssh_agent_service.dart';
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/shared/presentation/maidkit_alert.dart';
import 'package:maid_kit/github/github_mcp_tools.dart';
import 'package:maid_kit/github/github_providers.dart';
import 'package:maid_kit/snippets/snippet_repository.dart';

/// Lifecycle of the in-app MCP server exposed to other local agents.
enum LocalMcpServerStatus { stopped, running, failed }

/// Observable state of the local MCP server. [enabled] reflects the user's
/// preference even when binding failed, so the settings UI can surface the
/// error and let the user pick a different port.
class LocalMcpServerState {
  const LocalMcpServerState({
    required this.enabled,
    required this.port,
    required this.status,
    this.error,
  });

  final bool enabled;
  final int port;
  final LocalMcpServerStatus status;
  final String? error;

  /// The MCP SSE endpoint other agents configure as their server URL.
  String get url => 'http://127.0.0.1:$port/sse';

  LocalMcpServerState copyWith({
    bool? enabled,
    int? port,
    LocalMcpServerStatus? status,
    String? error,
  }) => LocalMcpServerState(
    enabled: enabled ?? this.enabled,
    port: port ?? this.port,
    status: status ?? this.status,
    error: error ?? this.error,
  );
}

/// Persisted preference for the local MCP server. Plain app preferences, not
/// vault data: the port and a boolean carry no secrets.
class LocalMcpServerPreferences {
  LocalMcpServerPreferences(this._preferences, this.enabled, this.port);

  static const _enabledKey = 'local_mcp_server_enabled';
  static const _portKey = 'local_mcp_server_port';

  /// Port picked to avoid common dev-server ranges.
  static const int defaultPort = 8746;

  final SharedPreferencesAsync _preferences;
  final bool enabled;
  final int port;

  static Future<LocalMcpServerPreferences> load({
    SharedPreferencesAsync? preferences,
  }) async {
    final store = preferences ?? SharedPreferencesAsync();
    final enabled = await store.getBool(_enabledKey) ?? false;
    final port = await store.getInt(_portKey) ?? defaultPort;
    return LocalMcpServerPreferences(store, enabled, port);
  }

  Future<void> saveEnabled(bool value) =>
      _preferences.setBool(_enabledKey, value);

  Future<void> savePort(int value) => _preferences.setInt(_portKey, value);
}

/// The tool surface the protocol serves. Split from the HTTP/JSON-RPC layer
/// so tests can drive the protocol with a fake tool set. Resolves
/// asynchronously because the surface can depend on runtime state (e.g. the
/// GitHub tools are hidden until a GitHub account is signed in).
abstract interface class LocalMcpToolInvoker {
  Future<List<Map<String, dynamic>>> get toolDefinitions;

  /// Executes [name] with [arguments] and returns an MCP `tools/call` result
  /// map (`content` + `isError`). Throws [ArgumentError] or
  /// [McpActionDeclinedException] for failures the caller should see as a
  /// tool error rather than a protocol error. [callerLabel] identifies the
  /// MCP client that sent the request (from the handshake), for the user's
  /// review UI.
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> arguments, {
    String? callerLabel,
  });
}

/// Raised when the user declines a proposed action in the approval dialog.
class McpActionDeclinedException implements Exception {
  const McpActionDeclinedException();

  @override
  String toString() => 'Action declined by the user.';
}

/// JSON-RPC request handling for one MCP session. Transport-agnostic: the
/// session feeds decoded messages in and emits response maps out.
class LocalMcpProtocolHandler {
  LocalMcpProtocolHandler(this.invoker);

  final LocalMcpToolInvoker invoker;

  /// Human-readable label of the client that initialized this session,
  /// e.g. `Claude Desktop 1.2.3`. Set once from the `initialize` handshake
  /// and surfaced in approval reviews.
  String? _callerLabel;

  /// Handles one incoming JSON-RPC message. Returns the response to send
  /// back, or null when the message is a notification or otherwise
  /// unanswered.
  Future<Map<String, dynamic>?> handle(Map<String, dynamic> message) async {
    final id = message['id'];
    final method = message['method'];
    if (method is! String) {
      return id == null ? null : _error(id, -32600, 'Invalid Request');
    }
    if (id == null) {
      // Notifications (initialized, cancelled, …) need no reply.
      return null;
    }
    switch (method) {
      case 'initialize':
        _callerLabel = _clientLabel(message['params']);
        return _result(id, {
          'protocolVersion': mcpProtocolVersion,
          'capabilities': const {
            'tools': {'listChanged': false},
          },
          'serverInfo': const {'name': 'MaidKit', 'version': '1.0.0'},
        });
      case 'ping':
        return _result(id, const <String, Object?>{});
      case 'tools/list':
        return _result(id, {'tools': await invoker.toolDefinitions});
      case 'tools/call':
        return _handleCall(id, message['params']);
      default:
        return _error(id, -32601, 'Method not found: $method');
    }
  }

  Future<Map<String, dynamic>> _handleCall(
    Object? id,
    Object? rawParams,
  ) async {
    final params = rawParams is Map<String, dynamic> ? rawParams : null;
    final name = params?['name'];
    if (name is! String || name.isEmpty) {
      return _error(id, -32602, 'tools/call requires a tool name.');
    }
    final rawArguments = params?['arguments'];
    final arguments = rawArguments is Map<String, dynamic>
        ? rawArguments
        : <String, dynamic>{};
    try {
      return _result(
        id,
        await invoker.call(name, arguments, callerLabel: _callerLabel),
      );
    } on ArgumentError catch (error) {
      return _result(id, _toolError(error.toString()));
    } on McpActionDeclinedException {
      return _result(id, _toolError('Action declined by the user.'));
    } catch (error) {
      debugPrint('[local mcp] tool "$name" failed: $error');
      return _error(id, -32603, 'Internal error: $error');
    }
  }

  Map<String, dynamic> _toolError(String message) => {
    'content': [
      {'type': 'text', 'text': message},
    ],
    'isError': true,
  };

  /// Builds a display label from the `initialize` clientInfo: `name` plus
  /// `version` when present, null when the client sent none.
  String? _clientLabel(Object? rawParams) {
    final params = rawParams is Map<String, dynamic> ? rawParams : null;
    final info = params?['clientInfo'];
    if (info is! Map<String, dynamic>) return null;
    final name = info['name'];
    if (name is! String || name.isEmpty) return null;
    final version = info['version'];
    return version is String && version.isNotEmpty ? '$name $version' : name;
  }

  Map<String, dynamic> _result(Object? id, Map<String, Object?> result) => {
    'jsonrpc': '2.0',
    'id': id,
    'result': result,
  };

  Map<String, dynamic> _error(Object? id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };
}

/// A local Model Context Protocol server exposing MaidKit's resources to
/// other agents on this machine. Speaks the MCP HTTP+SSE transport: `GET
/// /sse` opens a session event stream, `POST /message` delivers JSON-RPC
/// requests whose replies come back over that stream. Bound to loopback only.
class LocalMcpServer {
  LocalMcpServer({required this.executor, required this.port});

  final LocalMcpToolInvoker executor;
  final int port;

  final _sessions = <String, _LocalMcpSession>{};
  String? _latestSessionId;
  HttpServer? _server;

  bool get isRunning => _server != null;

  /// The port actually bound. Differs from [port] when 0 was requested
  /// (ephemeral), which tests use.
  int get boundPort => _server?.port ?? port;

  Future<void> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server = server;
    server.listen(
      _handleRequest,
      onError: (Object error) => debugPrint('[local mcp] server error: $error'),
    );
  }

  Future<void> stop() async {
    final sessions = _sessions.values.toList();
    _sessions.clear();
    _latestSessionId = null;
    for (final session in sessions) {
      await session.close();
    }
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  void _handleRequest(HttpRequest request) {
    final path = request.uri.path;
    if (request.method == 'GET' && path == '/sse') {
      _handleSse(request);
      return;
    }
    if (request.method == 'POST' && path == '/message') {
      unawaited(_handleMessage(request));
      return;
    }
    if (request.method == 'GET' && (path == '/' || path.isEmpty)) {
      unawaited(_handleStatus(request));
      return;
    }
    request.response.statusCode = HttpStatus.notFound;
    unawaited(request.response.close());
  }

  void _handleSse(HttpRequest request) {
    // Each session gets its own protocol handler so the caller identity from
    // its `initialize` handshake never mixes with another client's.
    final session = _LocalMcpSession(LocalMcpProtocolHandler(executor));
    _sessions[session.id] = session;
    _latestSessionId = session.id;
    final response = request.response;
    response
      ..statusCode = HttpStatus.ok
      // dart:io buffers response bodies by default and `flush()` alone does
      // not push buffered bytes to the client before the response closes.
      // Unbuffered writes are what keep SSE events flowing incrementally.
      ..bufferOutput = false
      ..headers.set('Content-Type', 'text/event-stream')
      ..headers.set('Cache-Control', 'no-cache')
      ..headers.set('Connection', 'keep-alive')
      ..headers.set('Access-Control-Allow-Origin', '*')
      ..headers.set('Mcp-Session-Id', session.id);
    // Legacy SSE handshake: announce the message endpoint, then stream
    // replies as `message` events.
    response.write(
      'event: endpoint\ndata: /message?sessionId=${session.id}\n\n',
    );
    session.outgoing.listen((payload) {
      response.write('event: message\ndata: $payload\n\n');
    }, onDone: () => unawaited(response.close()));
    // The client hung up or the server closed the stream; drop the session.
    unawaited(
      response.done
          .then((_) {
            if (_sessions.remove(session.id) != null &&
                session.id == _latestSessionId) {
              _latestSessionId = null;
            }
            unawaited(session.close());
          })
          .catchError((_) {}),
    );
  }

  Future<void> _handleMessage(HttpRequest request) async {
    final session = _sessionFor(request);
    if (session == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final body = await utf8.decoder.bind(request).join();
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    if (decoded is! Map<String, dynamic>) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    // The reply arrives over the SSE stream; 202 is the spec's acknowledgement.
    request.response.statusCode = HttpStatus.accepted;
    await request.response.close();
    await session.enqueue(decoded);
  }

  Future<void> _handleStatus(HttpRequest request) async {
    final response = request.response
      ..statusCode = HttpStatus.ok
      ..headers.set('Content-Type', 'application/json');
    response.write(
      jsonEncode({
        'name': 'MaidKit',
        'status': 'running',
        'tools': [
          for (final tool in await executor.toolDefinitions) tool['name'],
        ],
      }),
    );
    await response.close();
  }

  _LocalMcpSession? _sessionFor(HttpRequest request) {
    final header = request.headers.value('Mcp-Session-Id');
    final query = request.uri.queryParameters['sessionId'];
    final id = header ?? query ?? _latestSessionId;
    if (id == null) return null;
    return _sessions[id];
  }
}

class _LocalMcpSession {
  _LocalMcpSession(this._handler) : id = _newSessionId();

  static String _newSessionId() {
    final random = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return 'maidkit-$random';
  }

  final String id;
  final LocalMcpProtocolHandler _handler;
  final _outgoing = StreamController<String>();
  Future<void> _tail = Future.value();

  Stream<String> get outgoing => _outgoing.stream;

  /// Processes [message] after every earlier message on this session has
  /// finished. Tool calls can wait on user approval, so interleaving requests
  /// would reorder replies and stack dialogs.
  Future<void> enqueue(Map<String, dynamic> message) {
    final completer = Completer<void>();
    _tail = _tail
        .then((_) => _handle(message))
        .catchError((Object error) {
          debugPrint('[local mcp] request failed: $error');
        })
        .whenComplete(completer.complete);
    return completer.future;
  }

  Future<void> _handle(Map<String, dynamic> message) async {
    final response = await _handler.handle(message);
    if (response != null) _emit(response);
  }

  void _emit(Map<String, dynamic> message) {
    if (_outgoing.isClosed) return;
    _outgoing.add(jsonEncode(message));
  }

  Future<void> close() async {
    if (!_outgoing.isClosed) await _outgoing.close();
  }
}

/// Executes MCP tool calls against MaidKit's own resources — the saved SSH
/// servers, snippets, and skills. Mutating actions go through the same
/// run policy and approval dialogs as the chat agent.
class LocalMcpToolExecutor implements LocalMcpToolInvoker {
  LocalMcpToolExecutor(this.ref);

  final Ref ref;

  @override
  Future<List<Map<String, dynamic>>> get toolDefinitions async {
    // GitHub tools are hidden from other agents until this device has a
    // signed-in GitHub account with a device token; otherwise they would
    // advertise tools that always fail.
    final cwt = await ref.read(githubTokenForConnectionProvider.future);
    if (cwt != null) return _toolDefinitions;
    return [
      for (final tool in _toolDefinitions)
        if (!GitHubMcpToolHandlers.isGitHubTool(tool['name'] as String? ?? ''))
          tool,
    ];
  }

  /// The tool surface this executor serves, kept static so tests can inspect
  /// it without constructing a Riverpod-backed instance.
  static List<Map<String, dynamic>> get definitions => _toolDefinitions;

  static final List<Map<String, dynamic>> _toolDefinitions = [
    {
      'name': 'list_servers',
      'description':
          'List the SSH servers configured in MaidKit. Returns id, name, '
          'host, port, and username for each server. Use the returned id as '
          'server_id for other tools.',
      'inputSchema': {'type': 'object', 'properties': <String, dynamic>{}},
    },
    {
      'name': 'run_command',
      'description':
          'Run one shell command on a server through its saved SSH '
          'connection. Mutating commands are shown to the user for approval '
          'before they run.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'server_id': {
            'type': 'integer',
            'description': 'Id of the target server, from list_servers.',
          },
          'command': {'type': 'string', 'description': 'Shell command to run.'},
        },
        'required': ['server_id', 'command'],
      },
    },
    {
      'name': 'read_file',
      'description': 'Read a UTF-8 text file from a server over SFTP.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'server_id': {
            'type': 'integer',
            'description': 'Id of the target server, from list_servers.',
          },
          'path': {
            'type': 'string',
            'description': 'Absolute path of the file to read.',
          },
        },
        'required': ['server_id', 'path'],
      },
    },
    {
      'name': 'write_file',
      'description':
          'Create or replace a UTF-8 text file on a server over SFTP. '
          'Requires user approval.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'server_id': {
            'type': 'integer',
            'description': 'Id of the target server, from list_servers.',
          },
          'path': {
            'type': 'string',
            'description': 'Absolute path of the file to write.',
          },
          'content': {
            'type': 'string',
            'description': 'UTF-8 content to write.',
          },
        },
        'required': ['server_id', 'path', 'content'],
      },
    },
    {
      'name': 'delete_file',
      'description':
          'Permanently delete a file from a server over SFTP. '
          'Requires user approval.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'server_id': {
            'type': 'integer',
            'description': 'Id of the target server, from list_servers.',
          },
          'path': {
            'type': 'string',
            'description': 'Absolute path of the file to delete.',
          },
        },
        'required': ['server_id', 'path'],
      },
    },
    {
      'name': 'list_snippets',
      'description':
          'List the reusable shell snippets saved in MaidKit. Returns id and '
          'name for each snippet; read the full script with get_snippet.',
      'inputSchema': {'type': 'object', 'properties': <String, dynamic>{}},
    },
    {
      'name': 'get_snippet',
      'description': 'Read the full script of a saved MaidKit snippet.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'snippet_id': {
            'type': 'integer',
            'description': 'Id of the snippet, from list_snippets.',
          },
        },
        'required': ['snippet_id'],
      },
    },
    {
      'name': 'create_snippet',
      'description':
          'Save a reusable POSIX shell snippet in MaidKit. '
          'Requires user approval.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description': 'Short name for the snippet.',
          },
          'script': {
            'type': 'string',
            'description': 'POSIX shell script body.',
          },
        },
        'required': ['name', 'script'],
      },
    },
    {
      'name': 'run_snippet',
      'description':
          'Run a saved MaidKit snippet on a server. Requires user approval.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'server_id': {
            'type': 'integer',
            'description': 'Id of the target server, from list_servers.',
          },
          'snippet_id': {
            'type': 'integer',
            'description': 'Id of the snippet, from list_snippets.',
          },
        },
        'required': ['server_id', 'snippet_id'],
      },
    },
    {
      'name': 'list_skills',
      'description':
          'List the reusable expertise packs (skills) saved in MaidKit. '
          'Returns id, name, description, and enabled for each skill.',
      'inputSchema': {'type': 'object', 'properties': <String, dynamic>{}},
    },
    {
      'name': 'get_skill',
      'description':
          'Read the full instructions of a saved skill by its skill_id.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'skill_id': {
            'type': 'integer',
            'description': 'Id of the skill, from list_skills.',
          },
        },
        'required': ['skill_id'],
      },
    },
    {
      'name': 'get_review_mode',
      'description':
          'Read the current approval review mode for actions requested '
          'through this MCP server. Returns the mode as a string: '
          'always_ask, auto_review, or always_approve.',
      'inputSchema': {'type': 'object', 'properties': <String, dynamic>{}},
    },
    {
      'name': 'set_review_mode',
      'description':
          'Change the approval review mode for actions requested through '
          'this MCP server: always_ask (every action needs approval), '
          'auto_review (read-only actions run automatically, everything '
          'else asks), or always_approve (actions run without asking). '
          'This setting is independent of the in-app agent run policy and '
          'always requires explicit user approval, whatever the current '
          'mode is.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'mode': {
            'type': 'string',
            'enum': ['always_ask', 'auto_review', 'always_approve'],
            'description': 'Review mode to switch to.',
          },
        },
        'required': ['mode'],
      },
    },
    ...GitHubMcpToolHandlers.definitions,
  ];

  /// Largest tool result handed to the calling agent. Mirrors the chat
  /// agent's truncation so replies stay small enough for model context.
  static const int maxResultLength = 12000;

  @override
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> arguments, {
    String? callerLabel,
  }) async {
    final String text;
    switch (name) {
      case 'list_servers':
        text = jsonEncode(await _listServers());
      case 'run_command':
        text = await _runRemoteAction(
          AgentActionKind.command,
          arguments,
          toolName: name,
          callerLabel: callerLabel,
        );
      case 'read_file':
        text = await _runRemoteAction(
          AgentActionKind.readFile,
          arguments,
          toolName: name,
          callerLabel: callerLabel,
        );
      case 'write_file':
        text = await _runRemoteAction(
          AgentActionKind.writeFile,
          arguments,
          toolName: name,
          callerLabel: callerLabel,
        );
      case 'delete_file':
        text = await _runRemoteAction(
          AgentActionKind.deleteFile,
          arguments,
          toolName: name,
          callerLabel: callerLabel,
        );
      case 'list_snippets':
        text = jsonEncode(await _listSnippets());
      case 'get_snippet':
        text = await _getSnippet(arguments);
      case 'create_snippet':
        text = await _createSnippet(arguments, callerLabel: callerLabel);
      case 'run_snippet':
        text = await _runSnippet(arguments, callerLabel: callerLabel);
      case 'list_skills':
        text = jsonEncode(await _listSkills());
      case 'get_skill':
        text = await _getSkill(arguments);
      case 'get_review_mode':
        text = jsonEncode({'mode': _currentReviewMode().wireName});
      case 'set_review_mode':
        text = await _setReviewMode(arguments, callerLabel: callerLabel);
      case 'github_list_runs':
      case 'github_get_run':
      case 'github_list_jobs':
        text = jsonEncode(
          await GitHubMcpToolHandlers(ref).call(name, arguments),
        );
      default:
        throw ArgumentError('Unknown tool: $name');
    }
    return {
      'content': [
        {
          'type': 'text',
          'text': text.length <= maxResultLength
              ? text
              : '${text.substring(0, maxResultLength)}\n[output truncated]',
        },
      ],
      'isError': false,
    };
  }

  Future<List<Map<String, dynamic>>> _listServers() async {
    final servers = await ref.read(serverRepositoryProvider).all();
    return [
      for (final server in servers)
        {
          'id': server.id,
          'name': server.name,
          'host': server.host,
          'port': server.port,
          'username': server.username,
        },
    ];
  }

  Future<List<Map<String, dynamic>>> _listSnippets() async {
    final snippets = await ref.read(snippetRepositoryProvider).all();
    return [
      for (final snippet in snippets) {'id': snippet.id, 'name': snippet.name},
    ];
  }

  Future<String> _getSnippet(Map<String, dynamic> arguments) async {
    final snippet = await ref
        .read(snippetRepositoryProvider)
        .snippet(_int(arguments, 'snippet_id'));
    if (snippet == null) throw ArgumentError('Unknown snippet_id.');
    return 'Snippet #${snippet.id}: ${snippet.name}\n\n${snippet.script}';
  }

  Future<String> _createSnippet(
    Map<String, dynamic> arguments, {
    String? callerLabel,
  }) async {
    final name = _string(arguments, 'name');
    final script = _string(arguments, 'script');
    if (name.trim().isEmpty || script.trim().isEmpty) {
      throw ArgumentError('name and script are required.');
    }
    if (!await _approve(
      _proposal(AgentActionKind.createSnippet, arguments, 'create_snippet'),
      callerLabel: callerLabel,
    )) {
      throw const McpActionDeclinedException();
    }
    final id = await ref
        .read(snippetRepositoryProvider)
        .save(name: name, script: script);
    return 'Created saved snippet #$id: $name';
  }

  Future<String> _runSnippet(
    Map<String, dynamic> arguments, {
    String? callerLabel,
  }) async {
    final serverId = _int(arguments, 'server_id');
    final snippet = await ref
        .read(snippetRepositoryProvider)
        .snippet(_int(arguments, 'snippet_id'));
    if (snippet == null) throw ArgumentError('Unknown snippet_id.');
    final proposal = _proposal(
      AgentActionKind.runSnippet,
      arguments,
      'run_snippet',
    );
    if (!await _approve(proposal, callerLabel: callerLabel)) {
      throw const McpActionDeclinedException();
    }
    final client = await _clientForServer(serverId);
    return SshAgentService.executeProposal(
      client,
      proposal,
      snippetScript: snippet.script,
    );
  }

  Future<List<Map<String, dynamic>>> _listSkills() async {
    final skills = await ref.read(skillRepositoryProvider).all();
    return [
      for (final skill in skills)
        {
          'id': skill.id,
          'name': skill.name,
          'description': skill.description,
          'enabled': skill.enabled,
        },
    ];
  }

  Future<String> _getSkill(Map<String, dynamic> arguments) async {
    final skill = await ref
        .read(skillRepositoryProvider)
        .skill(_int(arguments, 'skill_id'));
    if (skill == null) throw ArgumentError('Unknown skill_id.');
    return 'Skill "${skill.name}":\n\n${skill.content}';
  }

  /// Current review mode without loading it twice across the async boundary.
  McpReviewMode _currentReviewMode() =>
      ref.read(mcpReviewModeProvider).value ?? McpReviewMode.alwaysAsk;

  Future<String> _setReviewMode(
    Map<String, dynamic> arguments, {
    String? callerLabel,
  }) async {
    final rawMode = _string(arguments, 'mode');
    final mode = McpReviewMode.fromWireName(rawMode);
    final proposal = AgentProposal(
      kind: AgentActionKind.mcpToolCall,
      arguments: {'mode': mode.wireName},
      toolCall: OpenAIResponseToolCall.fromMap({
        'id': 'local-mcp-${DateTime.now().microsecondsSinceEpoch}',
        'type': 'function',
        'function': {
          'name': 'set_review_mode',
          'arguments': jsonEncode(arguments),
        },
      }),
      assistantMessage: OpenAIChatCompletionChoiceMessageModel(
        role: OpenAIChatMessageRole.assistant,
        content: null,
      ),
    );
    // Changing the review mode can widen what runs without approval, so it is
    // never auto-approved — not even under always_approve.
    if (!await _approve(
      proposal,
      requireApproval: true,
      callerLabel: callerLabel,
    )) {
      throw const McpActionDeclinedException();
    }
    await ref.read(mcpReviewModeProvider.notifier).setMode(mode);
    return 'Review mode set to ${mode.wireName}.';
  }

  /// Runs a proposal that targets a server. The approval check happens before
  /// any connection work so a declined action never touches the network.
  Future<String> _runRemoteAction(
    AgentActionKind kind,
    Map<String, dynamic> arguments, {
    required String toolName,
    String? callerLabel,
  }) async {
    final serverId = _int(arguments, 'server_id');
    switch (kind) {
      case AgentActionKind.command:
        _string(arguments, 'command');
      case AgentActionKind.readFile:
      case AgentActionKind.deleteFile:
        _string(arguments, 'path');
      case AgentActionKind.writeFile:
        _string(arguments, 'path');
        _string(arguments, 'content');
      default:
        break;
    }
    final proposal = _proposal(kind, arguments, toolName);
    if (!await _approve(proposal, callerLabel: callerLabel)) {
      throw const McpActionDeclinedException();
    }
    return SshAgentService.executeProposal(
      await _clientForServer(serverId),
      proposal,
    );
  }

  /// Mirrors the chat page's run policy shape but reads the MCP server's own
  /// review mode, which is independent of the in-app agent run policy:
  /// read-only actions auto-run under auto-review, everything else is shown
  /// to the user unless the mode approves it outright. [requireApproval]
  /// forces the dialog even when the current mode would auto-approve.
  /// [callerLabel] and the proposal's target server are surfaced in the
  /// review card so the user sees who asked and where the action would run.
  Future<bool> _approve(
    AgentProposal proposal, {
    bool requireApproval = false,
    String? callerLabel,
  }) async {
    final mode = await ref.read(mcpReviewModeProvider.future);
    final shouldAutoRun = requireApproval
        ? false
        : switch (mode) {
            McpReviewMode.alwaysApprove => true,
            McpReviewMode.autoReview => proposal.safeToRun,
            McpReviewMode.alwaysAsk => false,
          };
    if (shouldAutoRun) return true;
    await _notifyIfWindowBackgrounded(proposal);
    final targetServerLabel = await _targetServerLabel(proposal);
    return await showMaidKitOverlayDialog<bool>(
          barrierDismissible: false,
          builder: (context, close) => _McpApprovalCard(
            proposal: proposal,
            callerLabel: callerLabel,
            targetServerLabel: targetServerLabel,
            onResult: close,
          ),
        ) ??
        false;
  }

  /// Resolves the server a proposal targets into a display label for the
  /// review card. Null for actions that do not run on a server.
  Future<String?> _targetServerLabel(AgentProposal proposal) async {
    final serverId = proposal.serverId;
    if (serverId == null) return null;
    final servers = await ref.read(serverRepositoryProvider).all();
    final server = servers.where((server) => server.id == serverId).firstOrNull;
    if (server == null) return null;
    final hideAddresses = ref.read(hideServerAddressesProvider);
    return hideAddresses
        ? server.name
        : '${server.name} (${server.username}@${server.host}:${server.port})';
  }

  /// Posts a macOS Notification Center alert when an agent's access request
  /// arrives while the MaidKit window is in the background, so the pending
  /// approval dialog is not missed. The in-app dialog is the only surface
  /// when the window is focused or on non-desktop platforms.
  Future<void> _notifyIfWindowBackgrounded(AgentProposal proposal) async {
    final bool focused;
    try {
      focused = await windowManager.isFocused();
    } catch (_) {
      return; // No window manager (tests, non-desktop): dialog-only.
    }
    if (focused || !Platform.isMacOS) return;
    final detail = proposal.detail.replaceAll('\n', ' ');
    try {
      await Process.run('osascript', [
        '-e',
        'display notification ${_osascriptQuoted(detail)} '
            'with title ${_osascriptQuoted('MaidKit — ${proposal.title}')}',
      ]);
    } catch (_) {
      // A failed notification must never block or fail the approval flow.
    }
  }

  /// Quotes [value] for embedding in an AppleScript string literal.
  static String _osascriptQuoted(String value) =>
      '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

  Future<SSHClient> _clientForServer(int serverId) async {
    final repository = ref.read(serverRepositoryProvider);
    final servers = await repository.all();
    final server = servers.where((server) => server.id == serverId).firstOrNull;
    if (server == null) throw ArgumentError('Unknown server_id: $serverId');
    final manager = ref.read(connectionManagerProvider);
    final existing = manager.clientFor(serverId);
    if (existing != null) return existing;
    final credential = await repository.credentialFor(server);
    final proxy = await repository.proxyFor(server);
    HostKeyPrompt? approvedHostKey;
    await manager.connect(
      server,
      credential,
      (prompt) async {
        final approved = await _approveHostKey(prompt);
        if (approved) approvedHostKey = prompt;
        return approved;
      },
      knownHostKeyFingerprint: server.hostKeyFingerprint,
      proxy: proxy,
    );
    if (approvedHostKey != null) {
      await repository.rememberHostKey(server.id, approvedHostKey!);
    }
    await repository.markConnected(server.id);
    return manager.clientFor(serverId) ??
        (throw StateError('The SSH connection was lost.'));
  }

  Future<bool> _approveHostKey(HostKeyPrompt prompt) async {
    return await showMaidKitOverlayDialog<bool>(
          barrierDismissible: false,
          builder: (context, close) => ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kMaidKitDialogMaxWidth),
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Symbols.verified_user,
                      color: Theme.of(context).colorScheme.primary,
                      size: 36,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'serverVerifyHostKey'.tr(),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      prompt.replacesExisting
                          ? 'serverHostKeyChanged'.tr()
                          : 'serverHostKeyNew'.tr(),
                    ),
                    const SizedBox(height: 16),
                    SelectableText(
                      '${prompt.algorithm}\n${prompt.fingerprint}',
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => close(false),
                          child: const Text('serverReject').tr(),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => close(true),
                          child: const Text('serverApprove').tr(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ) ??
        false;
  }

  AgentProposal _proposal(
    AgentActionKind kind,
    Map<String, dynamic> arguments,
    String toolName,
  ) => AgentProposal(
    kind: kind,
    arguments: arguments,
    toolCall: OpenAIResponseToolCall.fromMap({
      'id': 'local-mcp-${DateTime.now().microsecondsSinceEpoch}',
      'type': 'function',
      'function': {'name': toolName, 'arguments': jsonEncode(arguments)},
    }),
    assistantMessage: OpenAIChatCompletionChoiceMessageModel(
      role: OpenAIChatMessageRole.assistant,
      content: null,
    ),
  );

  int _int(Map<String, dynamic> arguments, String name) {
    final value = arguments[name];
    if (value is int) return value;
    throw ArgumentError('$name must be an integer.');
  }

  String _string(Map<String, dynamic> arguments, String name) {
    final value = arguments[name];
    if (value is String) return value;
    throw ArgumentError('$name must be a string.');
  }
}

/// Approval card for actions requested through the local MCP server. Mirrors
/// the chat agent's proposal presentation but as a modal overlay, and names
/// the client that asked ([callerLabel]) plus the server the action targets
/// ([targetServer]) when one applies.
class _McpApprovalCard extends StatelessWidget {
  const _McpApprovalCard({
    required this.proposal,
    required this.onResult,
    this.callerLabel,
    this.targetServerLabel,
  });

  final AgentProposal proposal;
  final void Function(bool approved) onResult;
  final String? callerLabel;
  final String? targetServerLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final targetLabel = targetServerLabel;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kMaidKitDialogMaxWidth),
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Symbols.rule, color: scheme.primary, size: 36),
              const SizedBox(height: 16),
              Text(
                'mcpApprovalTitle'.tr(),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'mcpApprovalHint'.tr(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              _ReviewInfoRow(
                icon: Symbols.smart_toy,
                label: 'mcpApprovalCaller'.tr(),
                value: callerLabel ?? 'mcpApprovalCallerUnknown'.tr(),
              ),
              if (targetLabel != null) ...[
                const SizedBox(height: 8),
                _ReviewInfoRow(
                  icon: Symbols.dns,
                  label: 'mcpApprovalTarget'.tr(),
                  value: targetLabel,
                ),
              ],
              const SizedBox(height: 16),
              Text(
                proposal.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: SelectableText(
                    proposal.detail,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFamily: 'IBM Plex Mono',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => onResult(false),
                    child: Text('agentDecline'.tr()),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => onResult(true),
                    child: Text('agentApproveRun'.tr()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One labelled line of context in an approval card: who asked, and where the
/// action would run.
class _ReviewInfoRow extends StatelessWidget {
  const _ReviewInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

final localMcpServerProvider =
    AsyncNotifierProvider<LocalMcpServerNotifier, LocalMcpServerState>(
      LocalMcpServerNotifier.new,
    );

/// The approval review mode for actions requested through the local MCP
/// server. Kept separate from the in-app agent run policy so remote agents
/// can be held to a different standard.
final mcpReviewModeProvider =
    AsyncNotifierProvider<McpReviewModeNotifier, McpReviewMode>(
      McpReviewModeNotifier.new,
    );

class McpReviewModeNotifier extends AsyncNotifier<McpReviewMode> {
  @override
  Future<McpReviewMode> build() async {
    return (await McpReviewModePreferences.load()).mode;
  }

  Future<void> setMode(McpReviewMode mode) async {
    await McpReviewModePreferences.load().then((settings) {
      return settings.saveMode(mode);
    });
    state = AsyncData(mode);
  }
}

class LocalMcpServerNotifier extends AsyncNotifier<LocalMcpServerState> {
  LocalMcpServer? _server;

  @override
  Future<LocalMcpServerState> build() async {
    final settings = await LocalMcpServerPreferences.load();
    await _server?.stop();
    _server = LocalMcpServer(
      executor: LocalMcpToolExecutor(ref),
      port: settings.port,
    );
    if (!settings.enabled) {
      return LocalMcpServerState(
        enabled: false,
        port: settings.port,
        status: LocalMcpServerStatus.stopped,
      );
    }
    return _start(settings.port);
  }

  Future<void> setEnabled(bool enabled) async {
    final current = state.value;
    await LocalMcpServerPreferences.load().then(
      (settings) => settings.saveEnabled(enabled),
    );
    if (!enabled) {
      await _server?.stop();
      state = AsyncData(
        (current ??
                const LocalMcpServerState(
                  enabled: false,
                  port: LocalMcpServerPreferences.defaultPort,
                  status: LocalMcpServerStatus.stopped,
                ))
            .copyWith(
              enabled: false,
              status: LocalMcpServerStatus.stopped,
              error: null,
            ),
      );
      return;
    }
    final port = current?.port ?? LocalMcpServerPreferences.defaultPort;
    // The port may have changed while disabled; bind what the state reports.
    await _server?.stop();
    _server = LocalMcpServer(executor: LocalMcpToolExecutor(ref), port: port);
    state = AsyncData(await _start(port));
  }

  Future<void> setPort(int port) async {
    await LocalMcpServerPreferences.load().then(
      (settings) => settings.savePort(port),
    );
    final current = state.value;
    if (current == null || !current.enabled) {
      state = AsyncData(
        LocalMcpServerState(
          enabled: current?.enabled ?? false,
          port: port,
          status: LocalMcpServerStatus.stopped,
        ),
      );
      return;
    }
    await _server?.stop();
    _server = LocalMcpServer(executor: LocalMcpToolExecutor(ref), port: port);
    state = AsyncData(await _start(port));
  }

  Future<LocalMcpServerState> _start(int port) async {
    try {
      await _server!.start();
      return LocalMcpServerState(
        enabled: true,
        port: port,
        status: LocalMcpServerStatus.running,
      );
    } catch (error) {
      return LocalMcpServerState(
        enabled: true,
        port: port,
        status: LocalMcpServerStatus.failed,
        error: '$error',
      );
    }
  }
}
