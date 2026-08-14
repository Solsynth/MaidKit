import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

/// Newline-delimited JSON protocol used by MaidCafe's stdio daemon mode.
class MaidCafeStreamSession {
  MaidCafeStreamSession._(this._session) {
    _stdoutSubscription = utf8.decoder
        .bind(_session.stdout)
        .transform(const LineSplitter())
        .listen(_handleLine, onError: _handleError, onDone: _handleDone);
    unawaited(
      _session.done.then((_) {
        _markClosed(
          StateError(
            'MaidCafe SSH stream closed before the request completed.',
          ),
          StackTrace.current,
        );
      }),
    );
  }

  static const command =
      '/usr/local/bin/maidcafe-daemon --config /etc/maidcafe/config.stdio.toml';
  final _ready = Completer<void>();
  final SSHSession _session;
  late final StreamSubscription<String> _stdoutSubscription;
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  final _events = StreamController<MaidCafeStreamEvent>.broadcast();
  var _nextId = 0;
  var _closed = false;
  var _closing = false;
  Future<void> _writeTail = Future<void>.value();

  Stream<MaidCafeStreamEvent> get events => _events.stream;

  static Future<MaidCafeStreamSession> open(SSHClient client) async {
    final connection = MaidCafeStreamSession._(await client.execute(command));
    try {
      await connection._ready.future.timeout(const Duration(seconds: 10));
      return connection;
    } catch (_) {
      await connection.close();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> health() => request('health');

  Future<Map<String, dynamic>> metrics() => request('metrics');

  Future<Map<String, dynamic>> invokeAction(String name, {Object? body}) =>
      request('action', name: name, body: body);

  Future<Map<String, dynamic>> request(
    String action, {
    String? name,
    Object? body,
  }) async {
    _throwIfClosed();
    final id = 'maidkit-${_nextId++}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    final payload = <String, dynamic>{
      'type': 'request',
      'id': id,
      'action': action,
      ...?(name == null ? null : {'name': name}),
      ...?(body == null ? null : {'body': body}),
    };
    try {
      await _write(Uint8List.fromList(utf8.encode('${jsonEncode(payload)}\n')));
      return await completer.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      _pending.remove(id);
      rethrow;
    } catch (_) {
      _pending.remove(id);
      rethrow;
    }
  }

  Future<void> _write(Uint8List data) {
    final previous = _writeTail;
    final write = previous.then<void>(
      (_) async {
        _throwIfClosed();
        _session.stdin.add(data);
        await _session.flush();
      },
      onError: (_, _) {
        _throwIfClosed();
      },
    );
    _writeTail = write.catchError((_) {});
    return write;
  }

  void _throwIfClosed() {
    if (_closed || _closing) {
      throw StateError('MaidCafe stream is closed.');
    }
  }

  void _handleLine(String line) {
    if (line.trim().isEmpty) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } catch (error, stackTrace) {
      _handleError(error, stackTrace);
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    if (decoded['type'] == 'event') {
      final event = MaidCafeStreamEvent.fromJson(decoded);
      if (event.event == 'ready' && !_ready.isCompleted) {
        _ready.complete();
      }
      if (!_events.isClosed) _events.add(event);
      return;
    }
    final id = decoded['id'];
    final completer = id is String ? _pending.remove(id) : null;
    if (completer == null || completer.isCompleted) return;
    if (decoded['ok'] != true) {
      completer.completeError(
        StateError(decoded['error']?.toString() ?? 'MaidCafe request failed.'),
      );
      return;
    }
    final result = decoded['result'];
    completer.complete(
      result is Map<String, dynamic> ? result : <String, dynamic>{},
    );
  }

  void _handleError(Object error, StackTrace stackTrace) {
    _markClosed(error, stackTrace);
  }

  void _handleDone() {
    _markClosed(StateError('MaidCafe stream ended.'), StackTrace.current);
  }

  void _markClosed(Object error, StackTrace stackTrace) {
    if (_closed) return;
    _closed = true;
    _failPending(error, stackTrace);
  }

  void _failPending(Object error, StackTrace stackTrace) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    }
    _pending.clear();
  }

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    _closed = true;
    _failPending(StateError('MaidCafe stream closed.'), StackTrace.current);
    try {
      await _writeTail;
    } catch (_) {}
    try {
      await _session.stdin.close();
    } catch (_) {}
    try {
      _session.close();
    } catch (_) {}
    await _stdoutSubscription.cancel();
    await _session.done.timeout(const Duration(seconds: 3), onTimeout: () {});
    await _events.close();
  }
}

class MaidCafeStreamEvent {
  const MaidCafeStreamEvent({required this.event, required this.data});

  final String event;
  final Map<String, dynamic> data;

  factory MaidCafeStreamEvent.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    return MaidCafeStreamEvent(
      event: json['event']?.toString() ?? '',
      data: data is Map<String, dynamic> ? data : const {},
    );
  }
}
