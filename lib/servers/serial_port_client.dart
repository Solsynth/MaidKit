import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import 'server_models.dart';

/// A failure opening or communicating with a local serial port.
class SerialPortException implements Exception {
  const SerialPortException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A raw duplex byte session with a local serial device.
class SerialPortSession {
  SerialPortSession._(this._client, this.id);

  final SerialPortClient _client;
  final int id;
  final StreamController<Uint8List> _data =
      StreamController<Uint8List>.broadcast();
  final Completer<void> _done = Completer<void>();
  var _closed = false;

  Stream<Uint8List> get bytes => _data.stream;

  Future<void> get done => _done.future;

  /// Sends [data] directly to the native serial file descriptor.
  void write(List<int> data) {
    if (_closed || data.isEmpty) return;
    unawaited(_writeAndHandleError(Uint8List.fromList(data)));
  }

  Future<void> _writeAndHandleError(Uint8List data) async {
    try {
      await _client._write(id, data);
    } catch (error) {
      _finish(error);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _client._close(id);
    } finally {
      _finish();
    }
  }

  void _add(Uint8List data) {
    if (!_closed && !_data.isClosed) _data.add(data);
  }

  void _finish([Object? error]) {
    if (_done.isCompleted) return;
    _closed = true;
    if (error != null && !_data.isClosed) {
      _data.addError(error);
    }
    if (!_data.isClosed) unawaited(_data.close());
    _done.complete();
  }
}

/// Client for the serial-port implementation hosted by the macOS app.
///
/// The app is not sandboxed, so the native Runner opens `/dev/cu.*` directly.
/// Dart communicates with it over a method channel; serial bytes are delivered
/// back on the same channel as native `data` calls.
class SerialPortClient {
  static const channelName = 'dev.solsynth.maidKit/serial_port';

  final MethodChannel _channel = const MethodChannel(channelName);
  final _sessions = <int, SerialPortSession>{};

  SerialPortClient() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  Future<List<String>> listDevices() async {
    // The native serial bridge does not exist in a browser.
    if (kIsWeb) return const [];
    try {
      final result = await _channel.invokeMethod<List<Object?>>('listDevices');
      return result?.whereType<String>().toList(growable: false) ?? const [];
    } on PlatformException catch (error) {
      throw SerialPortException(
        error.message ?? 'Unable to list serial ports.',
      );
    } on MissingPluginException {
      throw const SerialPortException(
        'Serial ports are unavailable on this platform.',
      );
    }
  }

  Future<SerialPortSession> open(SerialConfig config) async {
    if (kIsWeb) {
      throw const SerialPortException(
        'Serial ports are unavailable on this platform.',
      );
    }
    try {
      final id = await _channel.invokeMethod<int>('open', config.toJson());
      if (id == null) {
        throw const SerialPortException(
          'The native serial session was not created.',
        );
      }
      final session = SerialPortSession._(this, id);
      _sessions[id] = session;
      return session;
    } on SerialPortException {
      rethrow;
    } on PlatformException catch (error) {
      throw SerialPortException(
        error.message ?? 'Unable to open ${config.device}.',
      );
    } on MissingPluginException {
      throw const SerialPortException(
        'Serial ports are unavailable on this platform.',
      );
    }
  }

  Future<void> _write(int id, Uint8List data) async {
    try {
      await _channel.invokeMethod<void>('write', {
        'sessionId': id,
        'data': data,
      });
    } on PlatformException catch (error) {
      throw SerialPortException(
        error.message ?? 'Unable to write to serial port.',
      );
    }
  }

  Future<void> _close(int id) async {
    try {
      await _channel.invokeMethod<void>('close', {'sessionId': id});
    } on PlatformException catch (error) {
      throw SerialPortException(
        error.message ?? 'Unable to close serial port.',
      );
    } finally {
      _sessions.remove(id);
    }
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    final rawArguments = call.arguments;
    if (rawArguments is! Map) return null;
    final arguments = Map<Object?, Object?>.from(rawArguments);
    final id = arguments['sessionId'];
    if (id is! int) return null;
    final session = _sessions[id];
    if (session == null) return null;

    switch (call.method) {
      case 'data':
        final rawData = arguments['data'];
        if (rawData is Uint8List) {
          session._add(rawData);
        } else if (rawData is List) {
          session._add(Uint8List.fromList(rawData.whereType<int>().toList()));
        }
        return null;
      case 'done':
        _sessions.remove(id);
        session._finish();
        return null;
    }
    return null;
  }
}
