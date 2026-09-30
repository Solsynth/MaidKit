import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'maidcafe_service.dart';
import 'server_models.dart';
import 'ssh_connection_manager.dart';
import 'terminal_session_adapter.dart';

// The credential encoder lives with the target it authorizes; re-exported here
// so the manager's importers keep seeing it.
export 'server_models.dart'
    show maidCafeTerminalSubprotocolPrefix, maidCafeTerminalToken;

/// Wire protocol version this transport speaks. The daemon announces it in the
/// hello frame, so an older daemon is detected instead of misread.
const String maidCafeTerminalProtocolVersion = 'v1';

/// Initial PTY geometry requested at open. The daemon applies its own defaults
/// only when no size is sent; the terminal renderer pushes the real size as
/// soon as it is laid out. These values mirror the SSH path's `SSHPtyConfig`.
const int maidCafeTerminalInitialColumns = 120;
const int maidCafeTerminalInitialRows = 36;

/// Opens the socket for [endpoint], offering [protocols]. Injectable so tests
/// can drive frame handling without a live daemon.
typedef MaidCafeTerminalSocketFactory =
    WebSocketChannel Function(Uri endpoint, List<String> protocols);

WebSocketChannel _connectMaidCafeTerminal(
  Uri endpoint,
  List<String> protocols,
) => WebSocketChannel.connect(endpoint, protocols: protocols);

/// Raised when a daemon terminal cannot be opened or ends abnormally.
class MaidCafeTerminalException implements Exception {
  const MaidCafeTerminalException(this.message, {this.exitCode, this.reason});

  final String message;

  /// Shell exit code reported by the daemon, when it ended the session.
  final int? exitCode;

  /// Daemon close reason (`idle timeout`, `terminal shell not allowed`, ...).
  final String? reason;

  @override
  String toString() => message;
}

/// Manages terminal sessions served by a MaidCafe daemon over WebSocket.
///
/// Mirrors [SerialConnectionManager]'s lifecycle: each terminal owns one socket
/// and one [TerminalSessionBinding], and closing the tab closes the socket. The
/// transport is the only one that works in a browser build, because it needs no
/// raw socket and no platform channel.
class MaidCafeTerminalConnectionManager {
  MaidCafeTerminalConnectionManager(
    this._terminalAdapterFactory, {
    MaidCafeTerminalSocketFactory? socketFactory,
  }) : _socketFactory = socketFactory ?? _connectMaidCafeTerminal;

  final TerminalSessionAdapterFactory Function() _terminalAdapterFactory;
  final MaidCafeTerminalSocketFactory _socketFactory;

  final _terminals = <String, _MaidCafeTerminalConnection>{};
  final _states = <int, SshSessionInfo>{};
  final _controller = StreamController<List<SshSessionInfo>>.broadcast();
  var _nextTerminalId = 0;

  Stream<List<SshSessionInfo>> get sessions => _controller.stream;
  List<SshSessionInfo> get current => _states.values.toList();

  /// Opens a terminal on [server]'s daemon [target].
  ///
  /// Throws [MaidCafeTerminalException] when the server is not a daemon
  /// terminal, when the handshake is refused (a wrong credential, a disabled
  /// endpoint, a rejected origin, or an unreachable daemon), or when the daemon
  /// cannot start the shell.
  Future<TerminalSessionHandle> openTerminal(
    Server server,
    MaidCafeTerminalTarget target, {
    String? initialOutput,
  }) async {
    if (server.connectionType != ServerConnectionType.maidcafe.name) {
      throw ArgumentError(
        'Server ${server.id} is not a MaidCafe daemon terminal connection.',
      );
    }
    final terminal = _terminalAdapterFactory().create();
    if (initialOutput != null && initialOutput.isNotEmpty) {
      terminal.replayHistory(initialOutput);
    }
    final terminalId = 'maidcafe-${_nextTerminalId++}';
    // A cloud-relayed target mints its one-time ticket before the socket is
    // dialed, so a refused ticket fails the open without opening anything. The
    // ticket POST carries the PTY geometry; the cloud ignores query parameters
    // on the browser socket.
    final credential = await _credentialFor(target);
    final endpoint = target.isRelayed
        ? target.endpoint
        : target.endpoint.replace(
            queryParameters: {
              'cols': '$maidCafeTerminalInitialColumns',
              'rows': '$maidCafeTerminalInitialRows',
            },
          );
    final channel = _socketFactory(endpoint, [credential]);
    final connection = _MaidCafeTerminalConnection(
      serverId: server.id,
      channel: channel,
      output: StreamController<Uint8List>(),
    );
    try {
      await channel.ready;
    } catch (error) {
      // Nothing listens to the output stream yet, and an unlistened
      // single-subscription close never completes, so it is fire and forget.
      unawaited(connection.output.close());
      throw MaidCafeTerminalException(
        target.isRelayed
            ? 'Cannot open the cloud-relayed MaidCafe terminal at '
                  '${target.baseUrl}: $error. Check that you are signed in '
                  'with Solarpass and that this workspace still owns the '
                  'daemon.'
            : 'Cannot open the MaidCafe daemon terminal at ${target.baseUrl}: '
                  '$error. Check the daemon endpoint, the terminal credential, '
                  'and that this origin is listed in '
                  'daemon.terminal.allowedOrigins.',
      );
    }
    final binding = TerminalSessionBinding(
      adapter: terminal,
      stdout: connection.output.stream,
      stderr: const Stream.empty(),
      send: (bytes) => _sendBytes(connection, bytes),
      resize: (event) => _sendResize(connection, event),
    );
    connection
      ..binding = binding
      ..frames = channel.stream.listen(
        (frame) => _handleFrame(connection, frame),
        onError: (Object error) =>
            _finish(connection, error: 'Terminal transport failed: $error'),
        onDone: () => _finish(connection),
      );
    _terminals[terminalId] = connection;
    _set(
      SshSessionInfo(
        serverId: server.id,
        serverName: server.name,
        connectedAt: DateTime.now(),
        status: SessionStatus.connected,
      ),
    );
    // Do not use `whenComplete` here: its returned future re-emits a transport
    // error and, because this is fire-and-forget cleanup, would become an
    // unhandled application error.
    connection.done.future.then<void>(
      (_) => _closeTerminalAfterSessionEnds(terminalId, connection),
      onError: (_, _) => _closeTerminalAfterSessionEnds(terminalId, connection),
    );
    return TerminalSessionHandle(
      id: terminalId,
      adapter: terminal,
      done: connection.done.future,
    );
  }

  /// Resolves the subprotocol credential for [target]: a freshly minted cloud
  /// ticket for a relayed target, or the daemon secret for a direct one.
  ///
  /// A ticket failure surfaces as [MaidCafeTerminalException] before any socket
  /// is opened, so callers can treat it like a refused handshake.
  Future<String> _credentialFor(MaidCafeTerminalTarget target) async {
    final provider = target.ticketProvider;
    if (provider == null) return maidCafeTerminalToken(target.secret);
    final MaidCafeTerminalTicket ticket;
    try {
      ticket = await provider(
        maidCafeTerminalInitialColumns,
        maidCafeTerminalInitialRows,
      );
    } on MaidCafeException catch (error) {
      throw MaidCafeTerminalException(
        'Cannot open the cloud-relayed MaidCafe terminal: ${error.message}',
      );
    } catch (error) {
      throw MaidCafeTerminalException(
        'Cannot open the cloud-relayed MaidCafe terminal: $error',
      );
    }
    return target.sessionToken(ticket.sessionId, ticket.ticket);
  }

  /// Closes the terminal with [terminalId]. Idempotent: unknown ids are
  /// ignored, so it is safe to call for SSH, serial and daemon tab ids alike.
  Future<void> closeTerminal(String terminalId) async {
    final connection = _terminals.remove(terminalId);
    if (connection == null) return;
    // The peer may already have closed the socket; treat close races as
    // successful cleanup instead of letting a transport error escape.
    try {
      await connection.binding.close();
    } catch (_) {}
    await _finish(connection);
  }

  void dispose() {
    unawaited(_closeAll());
  }

  /// Sends keystrokes as a binary frame. On web the frame type is decided by
  /// the value's Dart type, so the bytes must stay a [Uint8List]: a plain
  /// `List<int>` would be delivered as text and read as a control frame.
  void _sendBytes(_MaidCafeTerminalConnection connection, Uint8List bytes) {
    if (connection.closed) return;
    try {
      connection.channel.sink.add(bytes);
    } catch (_) {
      // The socket can close between delivering input and teardown.
    }
  }

  void _sendResize(
    _MaidCafeTerminalConnection connection,
    TerminalResize resize,
  ) {
    if (connection.closed) return;
    try {
      connection.channel.sink.add(
        jsonEncode({
          'type': 'resize',
          'cols': resize.columns,
          'rows': resize.rows,
        }),
      );
    } catch (_) {
      // See [_sendBytes].
    }
  }

  /// Dispatches one incoming frame. Binary frames are PTY output; text frames
  /// are the daemon's control frames and never reach the emulator.
  void _handleFrame(_MaidCafeTerminalConnection connection, Object? frame) {
    if (connection.closed) return;
    if (frame is String) {
      _handleControlFrame(connection, frame);
      return;
    }
    final bytes = switch (frame) {
      Uint8List value => value,
      List<int> value => Uint8List.fromList(value),
      _ => null,
    };
    if (bytes == null || bytes.isEmpty) return;
    connection.output.add(bytes);
  }

  void _handleControlFrame(
    _MaidCafeTerminalConnection connection,
    String frame,
  ) {
    final Object? decoded;
    try {
      decoded = jsonDecode(frame);
    } catch (_) {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    switch (decoded['type']) {
      case 'hello':
        final version = decoded['version'];
        if (version != maidCafeTerminalProtocolVersion) {
          unawaited(
            _finish(
              connection,
              error:
                  'The MaidCafe daemon speaks terminal protocol $version, '
                  'but this app expects $maidCafeTerminalProtocolVersion. '
                  'Update the daemon or the app.',
            ),
          );
        }
      case 'exit':
        final code = decoded['code'];
        final reason = decoded['reason'];
        unawaited(
          _finish(
            connection,
            exitCode: code is int ? code : null,
            reason: reason is String && reason.isNotEmpty ? reason : null,
          ),
        );
      case 'error':
        final message = decoded['message'];
        unawaited(
          _finish(
            connection,
            error: message is String && message.isNotEmpty
                ? message
                : 'The MaidCafe daemon rejected the terminal session.',
          ),
        );
    }
  }

  /// Ends [connection] exactly once: closes the socket, drains the output
  /// stream, records why, and completes [done].
  ///
  /// A daemon-reported `error` marks the session failed; a plain close (a
  /// shell `exit`, `idle timeout`, `lifetime exceeded`) ends it normally and
  /// keeps the reason as the last-session detail.
  Future<void> _finish(
    _MaidCafeTerminalConnection connection, {
    int? exitCode,
    String? reason,
    String? error,
  }) async {
    if (connection.closed) return;
    connection.closed = true;
    connection.exitCode = exitCode;
    connection.reason = reason;
    connection.error = error;
    try {
      await connection.channel.sink.close();
    } catch (_) {}
    await connection.frames?.cancel();
    connection.frames = null;
    // A canceled subscription (the binding closing first) can leave the close
    // future pending, so it is fire and forget.
    unawaited(connection.output.close());
    final state = _states[connection.serverId];
    if (state != null) {
      _set(
        state.copyWith(
          status: error == null ? SessionStatus.closed : SessionStatus.failed,
          error: error ?? reason,
        ),
      );
    }
    if (!connection.done.isCompleted) connection.done.complete();
  }

  void _closeTerminalAfterSessionEnds(
    String terminalId,
    _MaidCafeTerminalConnection connection,
  ) {
    if (!identical(_terminals[terminalId], connection)) return;
    unawaited(closeTerminal(terminalId).catchError((_) {}));
  }

  void _set(SshSessionInfo value) {
    _states[value.serverId] = value;
    _controller.add(current);
  }

  Future<void> _closeAll() async {
    for (final terminalId in _terminals.keys.toList()) {
      await closeTerminal(terminalId);
    }
    await _controller.close();
  }
}

class _MaidCafeTerminalConnection {
  _MaidCafeTerminalConnection({
    required this.serverId,
    required this.channel,
    required this.output,
  });

  final int serverId;
  final WebSocketChannel channel;

  /// Client-bound PTY chunks. The binding owns the listener; the frame pump
  /// feeds it and the daemon's backpressure is the socket itself.
  final StreamController<Uint8List> output;

  late final TerminalSessionBinding binding;
  StreamSubscription<Object?>? frames;
  final done = Completer<void>();

  bool closed = false;
  int? exitCode;
  String? reason;
  String? error;
}
