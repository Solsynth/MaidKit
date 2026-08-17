import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:tailscale/tailscale.dart';

import 'ssh_proxy_connect.dart' show proxyHandshakeTimeout;
import 'tailscale_service.dart';

/// Raised when a tailnet address cannot be dialed.
class TailscaleConnectException implements Exception {
  const TailscaleConnectException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// Whether [host] can only be reached through the tailnet: an address in
/// Tailscale's CGNAT range (100.64.0.0/10), its IPv6 ULA prefix
/// (fd7a:115c:a1e0::/48), or a MagicDNS `.ts.net` name.
bool isTailnetAddress(String host) {
  final ip = InternetAddress.tryParse(host);
  if (ip == null) return host.endsWith('.ts.net');
  final bytes = ip.rawAddress;
  return switch (ip.type) {
    InternetAddressType.IPv4 => bytes[0] == 100 && (bytes[1] & 0xc0) == 0x40,
    InternetAddressType.IPv6 =>
      bytes[0] == 0xfd &&
          bytes[1] == 0x7a &&
          bytes[2] == 0x11 &&
          bytes[3] == 0x5c &&
          bytes[4] == 0xa1 &&
          bytes[5] == 0xe0,
    _ => false,
  };
}

/// An [SSHSocket] that carries SSH over the embedded Tailscale node's TCP
/// tunnel to a tailnet peer.
class TailscaleSshSocket implements SSHSocket {
  TailscaleSshSocket(this._connection);

  final TailscaleConnection _connection;

  /// ([Tailscale.up]); DNS for MagicDNS names is resolved by the tailnet.
  static Future<TailscaleSshSocket> connect(String host, int port) async {
    try {
      await ensureTailscaleInitialized();
      final status = await Tailscale.instance.status();
      if (!status.isRunning) {
        throw const TailscaleConnectException(
          'Embedded Tailscale is not running.',
        );
      }
      final connection = await Tailscale.instance.tcp.dial(
        host,
        port,
        timeout: proxyHandshakeTimeout,
      );
      return TailscaleSshSocket(connection);
    } on TailscaleTcpException catch (error) {
      throw TailscaleConnectException(
        error.cause?.toString() ??
            'Could not reach $host:$port over embedded Tailscale.',
        error,
      );
    } on TailscaleException catch (error) {
      throw TailscaleConnectException(
        'Could not connect to $host:$port through embedded Tailscale.',
        error,
      );
    }
  }

  @override
  Stream<Uint8List> get stream => _connection.input;

  @override
  StreamSink<List<int>> get sink => _TailscaleSink(_connection.output);

  @override
  Future<void> get done => _connection.done;

  @override
  Future<void> close() => _connection.close();

  @override
  void destroy() {
    // Graceful close rather than an immediate reset: dartssh2 calls destroy()
    // on handshake failures, and an abrupt abort while the fd reactor is
    // polling can race the package's native teardown (pre-1.0 runtime).
    unawaited(_connection.close());
  }

  @override
  Future<void> flush() async {}

  @override
  String toString() => 'TailscaleSshSocket(${_connection.remote})';
}

/// Adapts the tailnet write half to the [StreamSink] contract dartssh2 uses.
/// dartssh2 only calls [add] and [close] on the sink.
class _TailscaleSink implements StreamSink<List<int>> {
  _TailscaleSink(this._output);

  final TailscaleConnectionOutput _output;

  @override
  void add(List<int> data) {
    unawaited(_output.write(data));
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) => _output.writeAll(stream);

  @override
  Future<void> close() => _output.close();

  @override
  Future<void> get done => _output.done;

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
}
