/// Web stand-ins for `package:tailscale`.
///
/// `package:tailscale` links a native Go runtime through `dart:ffi`, so the
/// embedded node cannot exist in a browser. This file keeps the same names and
/// signatures the app uses, reports [tailscaleRuntimeSupported] as `false`, and
/// throws [UnsupportedError] from every entry point that would otherwise need
/// the native runtime. Data holders and exceptions stay usable so callers can
/// still name and catch them without branching on the platform.
library;

import 'dart:async';
import 'dart:typed_data';

/// Whether the embedded Tailscale runtime is available on this platform.
///
/// Always false on the web: the runtime needs `dart:ffi`. Every caller must
/// stay behind this flag.
bool get tailscaleRuntimeSupported => false;

/// The node's position in the connection lifecycle.
///
/// Mirrors the native [NodeState]; the values never occur on web because no
/// runtime reports them.
enum NodeState {
  noState,
  needsLogin,
  needsMachineAuth,
  starting,
  running,
  stopped,
  unknown,
}

/// High-level category for asynchronous runtime errors.
enum TailscaleRuntimeErrorCode {
  localClient,
  watcher,
  node,
  worker,
  publicationBootstrapFailure,
  publicationDeliveryFailure,
  unknown,
}

/// Native log verbosity for the embedded Tailscale runtime.
enum TailscaleLogLevel { silent, info }

/// Base type for library-level Tailscale failures.
sealed class TailscaleException implements Exception {
  const TailscaleException(this.message, {this.cause});

  /// Human-readable error message.
  final String message;

  /// Optional underlying cause.
  final Object? cause;

  @override
  String toString() {
    if (cause == null) {
      return '$runtimeType: $message';
    }
    return '$runtimeType: $message (cause: $cause)';
  }
}

/// Thrown when the API is used in an invalid lifecycle state.
final class TailscaleUsageException extends TailscaleException {
  const TailscaleUsageException(super.message, {super.cause});
}

/// Thrown when a `tcp.*` call fails on the native runtime.
final class TailscaleTcpException extends TailscaleException {
  const TailscaleTcpException(super.message, {super.cause});
}

/// Asynchronous background error reported by the embedded runtime.
final class TailscaleRuntimeError {
  const TailscaleRuntimeError({required this.message, required this.code});

  /// Human-readable error string from the native runtime.
  final String message;

  /// High-level category for the background error.
  final TailscaleRuntimeErrorCode code;

  @override
  String toString() => '$runtimeType(${code.name}): $message';
}

/// A snapshot of the local node's current state.
class TailscaleStatus {
  const TailscaleStatus({
    required this.state,
    this.authUrl,
    this.stableNodeId,
    this.tailscaleIPs = const [],
    this.health = const [],
    this.magicDNSSuffix,
  });

  /// Where the node is in the connection lifecycle.
  final NodeState state;

  /// Login URL from the control plane, if authentication is required.
  final Uri? authUrl;

  /// Stable identifier for this node.
  final String? stableNodeId;

  /// This node's assigned Tailscale IP addresses.
  final List<String> tailscaleIPs;

  /// Health check warnings from the embedded runtime.
  final List<String> health;

  /// The MagicDNS suffix for the tailnet, if known.
  final String? magicDNSSuffix;

  /// Whether the node is connected and ready for traffic.
  bool get isRunning => state == NodeState.running;

  /// Whether the node needs authentication credentials.
  bool get needsLogin => state == NodeState.needsLogin;

  /// This node's first IPv4 address, or null.
  String? get ipv4 {
    for (final ip in tailscaleIPs) {
      if (!ip.contains(':')) return ip;
    }
    return null;
  }
}

/// One peer reported by the node inventory.
class TailscaleNode {
  const TailscaleNode({
    this.publicKey = '',
    this.stableNodeId = '',
    this.hostName = '',
    this.tailscaleIPs = const [],
    this.online = false,
  });

  /// The node's public key.
  final String publicKey;

  /// Stable identifier for the node.
  final String stableNodeId;

  /// The node's hostname.
  final String hostName;

  /// The node's Tailscale IP addresses.
  final List<String> tailscaleIPs;

  /// Whether the node is currently reachable on the tailnet.
  final bool online;

  /// This node's first IPv4 address, or null.
  String? get ipv4 {
    for (final ip in tailscaleIPs) {
      if (!ip.contains(':')) return ip;
    }
    return null;
  }
}

/// A tailnet endpoint attached to a transport object.
class TailscaleEndpoint {
  const TailscaleEndpoint({required this.address, required this.port});

  /// Endpoint address.
  final String address;

  /// TCP or UDP port.
  final int port;

  @override
  String toString() => address.isEmpty ? ':$port' : '$address:$port';
}

/// Write half of a [TailscaleConnection].
abstract interface class TailscaleConnectionOutput {
  Future<void> write(List<int> bytes);

  Future<void> writeAll(Stream<List<int>> chunks, {bool close = false});

  Future<void> close();

  Future<void> get done;
}

/// One full-duplex byte stream over the tailnet.
abstract interface class TailscaleConnection {
  TailscaleEndpoint get local;
  TailscaleEndpoint get remote;
  Stream<Uint8List> get input;
  TailscaleConnectionOutput get output;
  Future<void> get done;
  Future<void> close();
}

/// Raw TCP primitives between tailnet nodes.
abstract interface class Tcp {
  /// Opens a TCP connection to a node on the tailnet.
  Future<TailscaleConnection> dial(String host, int port, {Duration? timeout});
}

/// Testable app-facing contract for an embedded Tailscale node.
///
/// Mirrors the members the app uses from the native interface; the web
/// implementation has no node behind it.
abstract interface class TailscaleClient {
  Tcp get tcp;
  Stream<NodeState> get onStateChange;
  Stream<TailscaleRuntimeError> get onError;

  Future<TailscaleStatus> up({
    String hostname = '',
    String? authKey,
    bool ephemeral = false,
    Uri? controlUrl,
    Duration timeout = const Duration(seconds: 30),
  });

  Future<TailscaleStatus> status();
  Future<List<TailscaleNode>> nodes();
  Future<void> logout();
}

/// Singleton embedded Tailscale node for the current Dart process.
///
/// On web there is no native runtime to embed, so every entry point reports
/// the unsupported platform instead.
final class Tailscale implements TailscaleClient {
  Tailscale._();

  /// The embedded node does not exist on web; reading it is a programming
  /// error, so the getter reports the unsupported platform.
  static TailscaleClient get instance {
    throw UnsupportedError('Tailscale.instance is unavailable on web');
  }

  /// Configures the embedded node. Unsupported on web.
  static void init({
    required String stateDir,
    required String appId,
    TailscaleLogLevel logLevel = TailscaleLogLevel.silent,
    bool noLogsNoSupport = false,
  }) {
    throw UnsupportedError('Tailscale.init is unavailable on web');
  }

  @override
  Tcp get tcp {
    throw UnsupportedError('Tailscale.instance.tcp is unavailable on web');
  }

  @override
  Stream<NodeState> get onStateChange {
    throw UnsupportedError(
      'Tailscale.instance.onStateChange is unavailable on web',
    );
  }

  @override
  Stream<TailscaleRuntimeError> get onError {
    throw UnsupportedError('Tailscale.instance.onError is unavailable on web');
  }

  @override
  Future<TailscaleStatus> up({
    String hostname = '',
    String? authKey,
    bool ephemeral = false,
    Uri? controlUrl,
    Duration timeout = const Duration(seconds: 30),
  }) {
    throw UnsupportedError('Tailscale.instance.up is unavailable on web');
  }

  @override
  Future<TailscaleStatus> status() {
    throw UnsupportedError('Tailscale.instance.status is unavailable on web');
  }

  @override
  Future<List<TailscaleNode>> nodes() {
    throw UnsupportedError('Tailscale.instance.nodes is unavailable on web');
  }

  @override
  Future<void> logout() {
    throw UnsupportedError('Tailscale.instance.logout is unavailable on web');
  }
}
