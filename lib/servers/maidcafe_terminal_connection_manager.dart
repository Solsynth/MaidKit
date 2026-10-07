import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:maid_kit/data/local/app_database.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'maidcafe_debug.dart';
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

/// The message for a direct daemon route that did not open.
///
/// Only the cases the probe could not classify fall back to listing the likely
/// causes, and then by platform: a browser handshake carries an Origin, a native
/// one does not.
String _maidCafeDaemonHandshakeMessage(
  MaidCafeTerminalTarget target,
  Object error,
  MaidCafeTerminalHandshakeFailure? failure,
) {
  final at = 'Cannot open the MaidCafe daemon terminal at ${target.baseUrl}';
  return switch (failure) {
    MaidCafeTerminalHandshakeFailure.disabled =>
      '$at: the daemon is serving with its terminal endpoint switched off, so '
          'it refuses every session. If it was just enabled, the daemon is '
          'still running an older configuration — restart it and check its '
          'log. Otherwise enable it in the MaidCafe tab.',
    MaidCafeTerminalHandshakeFailure.credential =>
      '$at: the daemon rejected this credential. It accepts its terminal '
          'secret, or its metrics secret when no terminal secret is set; '
          're-read the daemon configuration or enter the credential in the '
          'server settings.',
    MaidCafeTerminalHandshakeFailure.remote =>
      '$at: the daemon only accepts terminal sessions from local or private '
          'addresses. Reach it over SSH or the local network, or allow remote '
          'sessions on the daemon.',
    MaidCafeTerminalHandshakeFailure.origin =>
      '$at: the daemon refused this browser origin. Add it to the allowed '
          'origins in the MaidCafe tab.',
    MaidCafeTerminalHandshakeFailure.user =>
      '$at: the daemon refused the account this session asked for. Its '
          'daemon.terminal.users allowlist has to name it; clear the terminal '
          'user to open as the daemon\'s own account.',
    MaidCafeTerminalHandshakeFailure.unsupported =>
      '$at: the daemon cannot serve a terminal on its platform.',
    MaidCafeTerminalHandshakeFailure.busy =>
      '$at: the daemon is already at its terminal session limit. Close a '
          'session and try again.',
    MaidCafeTerminalHandshakeFailure.unknown =>
      '$at: the daemon refused the handshake without saying why: $error',
    // Not diagnosed: nothing answered, or this build cannot ask. List what to
    // check for the client that is running.
    null =>
      kIsWeb
          ? '$at: no answer from the endpoint, or the handshake was refused. '
                'Check the daemon endpoint and that this origin is among the '
                'allowed origins.'
          : '$at: $error. Check the daemon endpoint, the terminal credential, '
                'and that the daemon answers on this address.',
  };
}

/// Which part of the daemon's terminal policy refused a handshake.
///
/// The daemon checks its policy in a fixed order before it upgrades the socket,
/// so the refusal is a policy answer, not a transport problem: the port is
/// reachable and something said no. [unknown] means the endpoint answered in a
/// way the probe does not classify — past the checks, the socket itself was
/// refused.
enum MaidCafeTerminalHandshakeFailure {
  /// The daemon's terminal endpoint is switched off.
  disabled,

  /// The credential this client sent was not accepted.
  credential,

  /// The daemon only accepts sessions from local or private addresses.
  remote,

  /// A browser origin the daemon does not allow (browser builds only).
  origin,

  /// The account the session asked to run as is not in the daemon's
  /// `daemon.terminal.users` allowlist.
  user,

  /// The daemon cannot serve a terminal on its platform.
  unsupported,

  /// The daemon is already at its concurrent session limit.
  busy,

  /// Answered, but not by any check the probe knows.
  unknown,
}

/// Maps the daemon's answer to one plain HTTP GET on the terminal endpoint onto
/// the policy that refused the handshake.
///
/// The daemon validates enabled → platform → peer address → credential before
/// it upgrades, and reports each failure as JSON with its own status, so the
/// answer names the cause instead of leaving the client to guess. Pure so the
/// mapping is unit-tested without a daemon.
MaidCafeTerminalHandshakeFailure maidCafeHandshakeFailureFrom(
  int status,
  Object? body,
) {
  final text = body is Map
      ? '${body['error'] ?? ''}'.toLowerCase()
      : '$body'.toLowerCase();
  if (status == 401) return MaidCafeTerminalHandshakeFailure.credential;
  if (status == 501) return MaidCafeTerminalHandshakeFailure.unsupported;
  if (status == 429) return MaidCafeTerminalHandshakeFailure.busy;
  if (status == 403) {
    // Order matters: the remote-access message is worded "disabled" too, so the
    // more specific causes are matched before the generic disabled one.
    if (text.contains('remote')) return MaidCafeTerminalHandshakeFailure.remote;
    // "terminal user not allowed" and "terminal shell not allowed" are the
    // allowlist refusals; only the user one is actionable from this client.
    if (text.contains('user')) return MaidCafeTerminalHandshakeFailure.user;
    if (text.contains('disabl')) {
      return MaidCafeTerminalHandshakeFailure.disabled;
    }
    // A rejected Origin is written by the WebSocket library, not the daemon,
    // so it arrives with no JSON body at all.
    return MaidCafeTerminalHandshakeFailure.origin;
  }
  return MaidCafeTerminalHandshakeFailure.unknown;
}

/// Asks the daemon which policy refused a failed handshake, or null when it
/// cannot be asked.
///
/// [secret] is the daemon credential itself — not the subprotocol token the
/// socket carries. A plain request can send a bearer, and the daemon reads that
/// as the same secret, so the probe asks with the credential the socket would
/// have presented rather than with an encoding of it.
///
/// A relayed route authenticates at the cloud and keeps the generic report. A
/// browser can ask now that the daemon answers CORS for the origins its
/// terminal allowlist names; an origin the daemon does not answer for fails the
/// request here, which is reported as the probe having no answer.
Future<MaidCafeTerminalHandshakeFailure?> diagnoseMaidCafeTerminalHandshake(
  MaidCafeTerminalTarget target,
  String secret,
) async {
  if (target.isRelayed || secret.isEmpty) return null;
  // The endpoint is the WebSocket URL; the same host answers a plain request,
  // and the policy checks run before the upgrade either way. The session's own
  // request is repeated — geometry and run-as account included — so a refusal
  // only a session can provoke (a user outside the allowlist) is the one the
  // probe meets too.
  final socket = target.sessionEndpoint();
  final uri = socket.replace(scheme: socket.scheme == 'wss' ? 'https' : 'http');
  final dio = Dio(
    BaseOptions(
      headers: <String, String>{'Authorization': 'Bearer $secret'},
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 4),
      // The refusal *is* the answer, so every status is a success here.
      validateStatus: (_) => true,
    ),
  );
  try {
    maidCafeLog(
      'asking $uri why the handshake failed; credential '
      '${maidCafeDescribeCredential(secret)}',
    );
    final response = await dio.getUri<dynamic>(uri);
    final failure = maidCafeHandshakeFailureFrom(
      response.statusCode ?? 0,
      response.data,
    );
    maidCafeLog(
      'the daemon answered HTTP ${response.statusCode} → $failure '
      '(body: ${response.data})',
    );
    return failure;
  } catch (error) {
    // Nothing answered: a different problem, reported as such.
    maidCafeLog('the diagnostic request itself failed', error: error);
    return null;
  } finally {
    dio.close(force: true);
  }
}

/// Raised when a daemon terminal cannot be opened or ends abnormally.
class MaidCafeTerminalException implements Exception {
  const MaidCafeTerminalException(
    this.message, {
    this.exitCode,
    this.reason,
    this.handshake,
  });

  /// The policy that refused the handshake, when it was diagnosed. Callers use
  /// it to give advice that matches the cause — a daemon that answered is not a
  /// port or firewall problem.
  final MaidCafeTerminalHandshakeFailure? handshake;

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
  /// [target] identifies the route and credential, so any server that resolved
  /// one can be served here — an SSH server whose host also runs the daemon
  /// uses this transport where a raw socket is unavailable (a browser build).
  /// Each call owns one socket and one PTY, so several sessions on the same
  /// server run at the same time.
  ///
  /// Throws [MaidCafeTerminalException] when the handshake is refused (a wrong
  /// credential, a disabled endpoint, a rejected origin, or an unreachable
  /// daemon), or when the daemon cannot start the shell.
  ///
  /// [onOutput] receives every PTY chunk and [onExit] the session's exit code,
  /// for a caller that drives the session without a terminal view — an agent
  /// action running a command over the daemon. The emulator still renders the
  /// same bytes; these are taps, not a replacement.
  Future<TerminalSessionHandle> openTerminal(
    Server server,
    MaidCafeTerminalTarget target, {
    String? initialOutput,
    void Function(Uint8List chunk)? onOutput,
    void Function(int? exitCode)? onExit,
  }) async {
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
    final user = target.user?.trim();
    final endpoint = target.sessionEndpoint(
      columns: maidCafeTerminalInitialColumns,
      rows: maidCafeTerminalInitialRows,
    );
    maidCafeLog(
      'opening "${server.name}" (id=${server.id}) at $endpoint\n'
      '  relayed=${target.isRelayed} storedEndpoint=${target.baseUrl}\n'
      '  user=${user == null || user.isEmpty ? 'the daemon account' : user}\n'
      '  credential=${maidCafeDescribeCredential(credential)}, '
      'subprotocol token carries ${credential.length} chars encoded',
    );
    final channel = _socketFactory(endpoint, [credential]);
    final connection = _MaidCafeTerminalConnection(
      serverId: server.id,
      channel: channel,
      output: StreamController<Uint8List>(),
      onOutput: onOutput,
      onExit: onExit,
    );
    try {
      await channel.ready;
    } catch (error) {
      // Nothing listens to the output stream yet, and an unlistened
      // single-subscription close never completes, so it is fire and forget.
      unawaited(connection.output.close());
      if (target.isRelayed) {
        throw MaidCafeTerminalException(
          'Cannot open the cloud-relayed MaidCafe terminal at '
          '${target.baseUrl}: $error. Check that you are signed in '
          'with Solarpass and that this workspace still owns the '
          'daemon.',
        );
      }
      // A refused handshake is a policy answer: ask which policy, so the
      // message names it rather than sending the user after the port, the
      // credential and the origin list all at once.
      maidCafeLog('the socket to $endpoint never upgraded', error: error);
      final failure = await diagnoseMaidCafeTerminalHandshake(
        target,
        target.secret,
      );
      if (failure == null) {
        maidCafeLog(
          'nothing answered the diagnostic request: the endpoint is '
          'unreachable, or this build cannot ask it',
        );
      }
      throw MaidCafeTerminalException(
        _maidCafeDaemonHandshakeMessage(target, error, failure),
        handshake: failure,
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
        target.user,
      );
    } on MaidCafeException catch (error) {
      // The cloud mints the session, so a refusal here is about the daemon
      // record and the account, never about a port or a firewall. A relayed
      // session needs the host to opt in twice: daemon.terminal.relay.enabled
      // in its configuration and terminal_relay_enabled on its cloud record.
      throw MaidCafeTerminalException(
        'The cloud refused the relay session (${error.message}). Check that '
        'the daemon serves relayed terminals (daemon.terminal.relay.enabled and '
        'its cloud daemon record) and that this device is signed in with the '
        'account that owns the workspace.',
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

  /// Sends [text] to the terminal with [terminalId] as if it had been typed.
  ///
  /// A caller that drives a session without a view — an agent action feeding a
  /// command, or answering a prompt — writes through here rather than through
  /// an emulator it never built. Unknown ids are ignored, like [closeTerminal].
  void writeToTerminal(String terminalId, String text) {
    final connection = _terminals[terminalId];
    if (connection == null || text.isEmpty) return;
    _sendBytes(connection, Uint8List.fromList(utf8.encode(text)));
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
    connection.onOutput?.call(bytes);
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
    // A caller that drives this session reports the end to whoever asked for
    // the run; it happens after the socket is closed and the last chunk queued,
    // so a command's output is never cut short by its own exit.
    connection.onExit?.call(exitCode);
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
    this.onOutput,
    this.onExit,
  });

  final int serverId;
  final WebSocketChannel channel;

  /// Client-bound PTY chunks. The binding owns the listener; the frame pump
  /// feeds it and the daemon's backpressure is the socket itself.
  final StreamController<Uint8List> output;

  /// Optional taps for a caller that drives this session without a view (see
  /// [MaidCafeTerminalConnectionManager.openTerminal]).
  final void Function(Uint8List chunk)? onOutput;
  final void Function(int? exitCode)? onExit;

  late final TerminalSessionBinding binding;
  StreamSubscription<Object?>? frames;
  final done = Completer<void>();

  bool closed = false;
  int? exitCode;
  String? reason;
  String? error;
}
