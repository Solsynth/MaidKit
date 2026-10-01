import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:maid_kit/data/local/app_database.dart';

import 'agent_cancel_token.dart';
import 'mcp_repository.dart';

/// Model Context Protocol protocol version advertised during initialization.
/// The server negotiates its own supported version in the reply.
const String mcpProtocolVersion = '2025-06-18';

/// Error raised when an MCP server cannot be reached, initialized, or fails
/// to answer a request.
class McpException implements Exception {
  const McpException(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() => cause == null ? message : '$message ($cause)';
}

/// One tool exposed by an MCP server. [inputSchema] is a JSON Schema object
/// describing the tool's arguments.
class McpToolDefinition {
  const McpToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
}

class McpToolResult {
  const McpToolResult({required this.content, required this.isError});

  /// Rendered content items as they were returned by the server. Text items
  /// are plain strings; anything else is the raw JSON-encodable payload.
  final List<Object?> content;
  final bool isError;

  String get text => [
    for (final item in content)
      if (item is String) item,
  ].join('\n');
}

/// Adds a `safe_to_run` property to an MCP tool's JSON Schema so the existing
/// agent run policy (auto-approve read-only calls) applies uniformly. Only
/// plain `{type: object, properties: ...}` schemas can be extended safely;
/// anything else returns null and the tool always requires approval.
Map<String, dynamic>? withSafeToRunProperty(Map<String, dynamic> schema) {
  if (schema['type'] != 'object') return null;
  final properties = schema['properties'];
  if (properties is! Map<String, dynamic>) return null;
  final copy = Map<String, dynamic>.from(schema);
  final props = Map<String, dynamic>.from(properties);
  props['safe_to_run'] = const {
    'type': 'boolean',
    'description':
        'Set to true only when calling this tool now is safe: it is '
        'read-only, idempotent, or otherwise carries no risk of losing data. '
        'When in doubt, set false so the user can review it.',
  };
  copy['properties'] = props;
  return copy;
}

/// Byte transport for MCP JSON-RPC messages. Implementations deliver
/// newline-delimited JSON and accept one outgoing message at a time.
abstract interface class McpTransport {
  Stream<String> get incoming;

  void send(String message);

  Future<void> close();
}

/// Transport over a child process's stdio, as used by locally launched MCP
/// servers. Stderr is forwarded to debug logs for diagnostics.
class StdioMcpTransport implements McpTransport {
  StdioMcpTransport(Process process) : _process = process {
    _stderrSubscription = _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => debugPrint('[mcp] stderr: $line'),
          onError: (Object error) => debugPrint('[mcp] stderr error: $error'),
        );
    _process.exitCode.then(
      (_) => _alive = false,
      onError: (_) => _alive = false,
    );
  }

  final Process _process;
  StreamSubscription<String>? _stderrSubscription;
  var _alive = true;

  @override
  late final Stream<String> incoming = _process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter());

  @override
  void send(String message) {
    if (!_alive) {
      throw const McpException('MCP server process is not running.');
    }
    _process.stdin.writeln(message);
  }

  @override
  Future<void> close() async {
    await _stderrSubscription?.cancel();
    _process.kill();
    await _process.exitCode.catchError((_) => -1);
  }
}

/// A minimal Model Context Protocol client over [McpTransport]. Implements
/// just enough of the protocol for tool use: initialize, tools/list,
/// tools/call, and the notifications the client must tolerate. Requests are
/// serialized per server — MCP tool use is driven one call at a time by the
/// agent loop, and several servers mishandle concurrent JSON-RPC requests.
class McpClient {
  McpClient(this._transport, [this._serverName = 'MCP']) {
    _incomingSubscription = _transport.incoming.listen(
      _handleIncoming,
      onError: (Object error, StackTrace stack) =>
          _failPending(McpException('MCP server connection dropped.', error)),
      onDone: () {
        _streamClosed = true;
        _failPending(const McpException('MCP server closed.'));
      },
    );
  }

  static const Duration initializeTimeout = Duration(seconds: 15);
  static const Duration listToolsTimeout = Duration(seconds: 30);
  static const Duration callToolTimeout = Duration(minutes: 3);

  final McpTransport _transport;
  final String _serverName;
  StreamSubscription<String>? _incomingSubscription;
  final _pending = <int, Completer<Object?>>{};
  final _sendQueue = <String>[];
  bool _sending = false;
  bool _initialized = false;
  bool _closed = false;
  bool _streamClosed = false;
  int _nextId = 1;
  List<McpToolDefinition>? _cachedTools;

  /// Whether the underlying connection is still alive. The manager uses this
  /// to decide whether to relaunch a server.
  bool get isAlive => !_closed && !_streamClosed;

  /// Launches [server] as a child process and returns a connected client.
  /// The process inherits the app environment with [environment] merged over
  /// it. Launching is separate from [initialize] so tests can drive the
  /// client with an in-memory transport.
  static Future<McpClient> launch(
    McpServer server, {
    String? workingDirectory,
  }) async {
    // A browser cannot spawn child processes, so stdio MCP servers are
    // unavailable there.
    if (kIsWeb) {
      throw const McpException('MCP servers cannot be launched in a browser.');
    }
    final arguments = decodeMcpArguments(server.arguments);
    final environment = decodeMcpEnvironment(server.environment);
    final Process process;
    try {
      process = await Process.start(
        server.command,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        includeParentEnvironment: true,
      );
    } on Object catch (error) {
      throw McpException('Could not launch "${server.command}".', error);
    }
    return McpClient(StdioMcpTransport(process), server.name);
  }

  Future<void> initialize() async {
    if (_initialized) return;
    await _request('initialize', const {
      'protocolVersion': mcpProtocolVersion,
      'capabilities': <String, Object?>{},
      'clientInfo': {'name': 'MaidKit', 'version': '1.0.0'},
    }, timeout: initializeTimeout);
    _initialized = true;
    // No reply is expected; the notification is the spec's handshake end.
    _send({
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
      'params': const <String, Object?>{},
    });
  }

  /// Lists the tools this server exposes. Results are cached until the
  /// server announces `tools/list_changed` or [refresh] is requested.
  Future<List<McpToolDefinition>> listTools({bool refresh = false}) async {
    await initialize();
    if (!refresh && _cachedTools != null) return _cachedTools!;
    final result =
        await _request(
              'tools/list',
              const <String, Object?>{},
              timeout: listToolsTimeout,
            )
            as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final tools = result['tools'];
    if (tools is! List) {
      throw const McpException('MCP server returned an invalid tools list.');
    }
    final definitions = <McpToolDefinition>[];
    for (final tool in tools) {
      if (tool is! Map<String, dynamic>) continue;
      final name = tool['name'];
      final schema = tool['inputSchema'];
      if (name is! String || name.isEmpty) continue;
      definitions.add(
        McpToolDefinition(
          name: name,
          description: tool['description'] as String? ?? '',
          inputSchema: schema is Map<String, dynamic>
              ? schema
              : const <String, dynamic>{},
        ),
      );
    }
    _cachedTools = definitions;
    return definitions;
  }

  /// Invokes a tool and returns its rendered result. [cancelToken] aborts the
  /// call and notifies the server when the user stops the agent.
  Future<McpToolResult> callTool(
    String name,
    Map<String, dynamic> arguments, {
    AgentCancelToken? cancelToken,
  }) async {
    await initialize();
    final completer = _request(
      'tools/call',
      {'name': name, 'arguments': arguments},
      timeout: callToolTimeout,
      cancelToken: cancelToken,
    );
    final Object? result;
    try {
      result = await completer;
    } on AgentCancelledException {
      rethrow;
    } on McpException {
      rethrow;
    } catch (error) {
      throw McpException('MCP tool "$name" failed.', error);
    }
    final map = result as Map<String, dynamic>? ?? const <String, dynamic>{};
    final content = map['content'];
    final items = content is List ? content : const <Object?>[];
    final rendered = <Object?>[];
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      switch (item['type']) {
        case 'text':
          rendered.add(item['text'] as String? ?? '');
        case 'image':
          rendered.add(
            '[image${item['mimeType'] == null ? '' : ' (${item['mimeType']})'}]',
          );
        default:
          rendered.add(jsonEncode(item));
      }
    }
    return McpToolResult(content: rendered, isError: map['isError'] == true);
  }

  /// Disposes the connection and kills the child process if any.
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    await _incomingSubscription?.cancel();
    _failPending(McpException('MCP server "$_serverName" closed.'));
    await _transport.close();
  }

  void _handleIncoming(String line) {
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } catch (_) {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    if (decoded['method'] is String) {
      // Server-initiated notifications. tools/list_changed invalidates the
      // cached tool list; everything else (logs, progress) is informational.
      if (decoded['method'] == 'notifications/tools/list_changed') {
        _cachedTools = null;
      }
      return;
    }
    final id = decoded['id'];
    if (id is! int) return;
    final error = decoded['error'];
    final completer = _pending.remove(id);
    if (completer == null) return;
    if (error is Map<String, dynamic>) {
      completer.completeError(
        McpException(
          error['message'] as String? ?? 'MCP request failed.',
          error['code'],
        ),
      );
      return;
    }
    completer.complete(decoded['result']);
  }

  Future<Object?> _request(
    String method,
    Map<String, dynamic> params, {
    required Duration timeout,
    AgentCancelToken? cancelToken,
  }) {
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    cancelToken?.register(() {
      if (!_pending.containsKey(id)) return;
      _pending.remove(id);
      if (!completer.isCompleted) {
        completer.completeError(const AgentCancelledException());
      }
      try {
        _send({
          'jsonrpc': '2.0',
          'method': 'notifications/cancelled',
          'params': {'requestId': id, 'reason': 'Cancelled by user'},
        });
      } catch (_) {
        // The connection may already be gone; the abort stands either way.
      }
    });
    final result = completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw McpException('MCP request "$method" timed out.');
      },
    );
    try {
      _send({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});
    } catch (error) {
      _pending.remove(id);
      if (!completer.isCompleted) {
        completer.completeError(
          McpException('Could not send "$method" to $_serverName.', error),
        );
      }
    }
    return result;
  }

  void _send(Map<String, Object?> message) {
    final serialized = jsonEncode(message);
    if (_closed) {
      throw const McpException('MCP server is closed.');
    }
    _writeLine(serialized);
  }

  void _writeLine(String serialized) {
    if (_sending) {
      _sendQueue.add(serialized);
      return;
    }
    // Serialize writes: the stdin sink is not thread-safe against concurrent
    // writes, and servers must not see interleaved messages mid-line.
    _sending = true;
    try {
      while (true) {
        _transport.send(serialized);
        if (_sendQueue.isEmpty) break;
        serialized = _sendQueue.removeAt(0);
      }
    } finally {
      _sending = false;
    }
  }

  void _failPending(McpException error) {
    final pending = _pending.values.toList();
    _pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) completer.completeError(error);
    }
  }
}

/// Owns the live [McpClient] instances for configured MCP servers, keyed by
/// server id. Clients are created lazily, survive across chat turns, and are
/// killed when the server is deleted, disabled, edited, or on app exit.
class McpClientManager {
  McpClientManager({String? workingDirectory})
    : _workingDirectory =
          workingDirectory ?? (kIsWeb ? '' : Directory.current.path);

  final String _workingDirectory;
  final _clients = <int, McpClient>{};
  final _failures = <int, _LaunchFailure>{};

  static const Duration retryCooldown = Duration(seconds: 30);

  /// Returns the connected client for [server], launching it on first use.
  /// A recently failed launch is rethrown until the cooldown passes so a
  /// broken server cannot stall every request.
  Future<McpClient> clientFor(McpServer server) async {
    final existing = _clients[server.id];
    if (existing != null && existing.isAlive) return existing;
    _clients.remove(server.id);
    final failure = _failures[server.id];
    if (failure != null &&
        DateTime.now().difference(failure.time) < retryCooldown) {
      throw McpException(failure.message);
    }
    try {
      final client = await McpClient.launch(
        server,
        workingDirectory: _workingDirectory,
      );
      await client.initialize();
      _clients[server.id] = client;
      _failures.remove(server.id);
      return client;
    } on Object catch (error) {
      final message = error is McpException ? error.message : '$error';
      _failures[server.id] = _LaunchFailure(DateTime.now(), message);
      rethrow;
    }
  }

  /// Kills the client for [server.id] so the next use relaunches it, e.g.
  /// after the server was edited or the user asks to restart it.
  Future<void> dispose(int id) async {
    final client = _clients.remove(id);
    _failures.remove(id);
    if (client != null) {
      try {
        await client.dispose();
      } catch (_) {
        // The process may already be gone; nothing left to do.
      }
    }
  }

  /// Kills every live client. Called when the app shuts down so no server
  /// process outlives MaidKit.
  Future<void> disposeAll() async {
    final clients = _clients.values.toList();
    _clients.clear();
    for (final client in clients) {
      try {
        await client.dispose();
      } catch (_) {
        // Best effort teardown.
      }
    }
  }
}

class _LaunchFailure {
  const _LaunchFailure(this.time, this.message);
  final DateTime time;
  final String message;
}
