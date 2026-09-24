import 'dart:async';

import 'package:maid_kit/data/local/app_database.dart';

import 'serial_port_client.dart';
import 'server_models.dart';
import 'ssh_connection_manager.dart';
import 'terminal_session_adapter.dart';

/// Manages terminal sessions opened over local serial ports.
///
/// Mirrors [SshConnectionManager]'s terminal lifecycle, but each terminal owns
/// a [SerialPortSession] instead of an SSH channel.
class SerialConnectionManager {
  SerialConnectionManager(
    this._terminalAdapterFactory, {
    SerialPortClient? serialClient,
  }) : _serialClient = serialClient ?? SerialPortClient();

  final TerminalSessionAdapterFactory Function() _terminalAdapterFactory;
  final SerialPortClient _serialClient;

  final _terminals = <String, _SerialTerminalConnection>{};
  final _states = <int, SshSessionInfo>{};
  final _controller = StreamController<List<SshSessionInfo>>.broadcast();
  var _nextTerminalId = 0;

  Stream<List<SshSessionInfo>> get sessions => _controller.stream;
  List<SshSessionInfo> get current => _states.values.toList();

  /// Opens a terminal over [server]'s serial port.
  ///
  /// Throws [ArgumentError] when [server] is not a serial connection or has no
  /// serial configuration.
  Future<TerminalSessionHandle> openTerminal(
    Server server, {
    String? initialOutput,
  }) async {
    if (server.connectionType != 'serial') {
      throw ArgumentError('Server ${server.id} is not a serial connection.');
    }
    final config = decodeSerialConfig(server.serialConfig);
    if (config == null) {
      throw ArgumentError('Server ${server.id} has no serial configuration.');
    }
    final session = await _serialClient.open(config);
    final terminal = _terminalAdapterFactory().create();
    if (initialOutput != null && initialOutput.isNotEmpty) {
      terminal.replayHistory(initialOutput);
    }
    final terminalId = 'serial-${_nextTerminalId++}';
    final binding = TerminalSessionBinding(
      adapter: terminal,
      stdout: session.bytes,
      stderr: const Stream.empty(),
      send: session.write,
      resize: (_) {},
    );
    _terminals[terminalId] = _SerialTerminalConnection(
      serverId: server.id,
      session: session,
      binding: binding,
    );
    // The native app closing the file descriptor ends the session like
    // `exit` would end an SSH shell. Do not use `whenComplete` here: its
    // returned future re-emits a transport error and, because this is
    // fire-and-forget cleanup, would become an unhandled application error.
    session.done.then<void>(
      (_) => _closeTerminalAfterSessionEnds(terminalId, session),
      onError: (_, _) => _closeTerminalAfterSessionEnds(terminalId, session),
    );
    _set(
      SshSessionInfo(
        serverId: server.id,
        serverName: server.name,
        connectedAt: DateTime.now(),
        status: SessionStatus.connected,
      ),
    );
    return TerminalSessionHandle(
      id: terminalId,
      adapter: terminal,
      done: session.done,
    );
  }

  /// Closes the terminal with [terminalId]. Idempotent: unknown ids are
  /// ignored, so it is safe to call for both SSH and serial tab ids.
  Future<void> closeTerminal(String terminalId) async {
    final terminal = _terminals.remove(terminalId);
    if (terminal == null) return;
    // The device side may already have closed the connection by the time this
    // runs. Treat those close races as successful cleanup rather than letting
    // a transport error escape as an unhandled error.
    try {
      await terminal.binding.close();
    } catch (_) {}
    try {
      await terminal.session.close();
    } catch (_) {}
    final state = _states[terminal.serverId];
    if (state != null) _set(state.copyWith(status: SessionStatus.closed));
  }

  void _closeTerminalAfterSessionEnds(
    String terminalId,
    SerialPortSession session,
  ) {
    if (!identical(_terminals[terminalId]?.session, session)) return;
    unawaited(closeTerminal(terminalId).catchError((_) {}));
  }

  void _set(SshSessionInfo value) {
    _states[value.serverId] = value;
    _controller.add(current);
  }

  void dispose() {
    unawaited(_closeAll());
  }

  Future<void> _closeAll() async {
    for (final terminalId in _terminals.keys.toList()) {
      await closeTerminal(terminalId);
    }
    await _controller.close();
  }
}

class _SerialTerminalConnection {
  const _SerialTerminalConnection({
    required this.serverId,
    required this.session,
    required this.binding,
  });

  final int serverId;
  final SerialPortSession session;
  final TerminalSessionBinding binding;
}
