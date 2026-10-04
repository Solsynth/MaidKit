import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:maid_kit/data/local/app_database.dart';

import 'maidcafe_service.dart';

enum CredentialType { password, privateKey, none }

class SavedCredentialDraft {
  const SavedCredentialDraft({required this.name, required this.credential});

  final String name;
  final ServerCredential credential;
}

class ServerCredential {
  const ServerCredential.password(this.password)
    : type = CredentialType.password,
      privateKey = null,
      keyPassphrase = null;

  const ServerCredential.privateKey({
    required this.privateKey,
    this.keyPassphrase,
  }) : type = CredentialType.privateKey,
       password = null;

  const ServerCredential.none()
    : type = CredentialType.none,
      password = null,
      privateKey = null,
      keyPassphrase = null;

  final CredentialType type;
  final String? password;
  final String? privateKey;
  final String? keyPassphrase;

  Map<String, Object?> toJson() => {
    'type': type.name,
    'password': password,
    'privateKey': privateKey,
    'keyPassphrase': keyPassphrase,
  };

  String encode() => jsonEncode(toJson());

  factory ServerCredential.decode(String value) {
    final json = jsonDecode(value) as Map<String, dynamic>;
    final type = CredentialType.values.byName(json['type'] as String);
    return switch (type) {
      CredentialType.password => ServerCredential.password(
        json['password'] as String,
      ),
      CredentialType.privateKey => ServerCredential.privateKey(
        privateKey: json['privateKey'] as String,
        keyPassphrase: json['keyPassphrase'] as String?,
      ),
      CredentialType.none => const ServerCredential.none(),
    };
  }
}

class ServerDraft {
  const ServerDraft({
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    this.credential,
    this.credentialId,
    this.credentialName,
    this.collectStats = true,
    this.collectSystemInfo = true,
    this.proxy,
    this.jumpHostServerId,
    this.environment = const {},
    this.initialSnippets = const [],
    this.tags = const [],
    this.fileManagementInitialPath,
    this.fileManagementFavorites = const [],
    this.connectionType = ServerConnectionType.ssh,
    this.serialConfig,
    this.maidCafeTerminalUrl,
    this.maidCafeTerminalSecret,
    this.clearMaidCafeTerminalSecret = false,
    this.maidCafeDaemonId,
    this.maidCafeTerminalViaCloud = false,
    this.maidCafeTerminalUser,
  });

  final String name;
  final String host;
  final int port;
  final String username;

  /// A new credential to save, or an existing [credentialId] to reuse.
  final ServerCredential? credential;
  final int? credentialId;
  final String? credentialName;
  final bool collectStats;
  final bool collectSystemInfo;

  /// Optional per-server HTTP CONNECT / SOCKS5 proxy. During an edit, a null
  /// [ServerProxy.password] keeps the stored proxy password unchanged.
  final ServerProxy? proxy;

  /// Another saved SSH server used as the first hop to reach this server.
  ///
  /// The referenced server may itself use a jump host, allowing chains such
  /// as A -> B -> C. Credentials are always taken from the referenced server.
  final int? jumpHostServerId;

  /// Environment variables exported into terminals opened on this server.
  final Map<String, String> environment;

  /// [ScriptSnippets] ids whose scripts run when a terminal opens.
  final List<int> initialSnippets;

  /// Saved directory opened by new file-management sessions.
  final String? fileManagementInitialPath;

  /// User-managed quick-access directories in the file manager.
  final List<String> fileManagementFavorites;

  /// Free-form labels shown on the server card and usable as filters.
  final List<String> tags;

  /// Transport used to reach this server: `ssh` for a remote host, `serial`
  /// for a local serial port, `maidcafe` for the MaidCafe daemon's WebSocket
  /// terminal endpoint.
  final ServerConnectionType connectionType;

  /// Serial-port settings, only used when [connectionType] is serial.
  final SerialConfig? serialConfig;

  /// MaidCafe daemon endpoint this app dials for [ServerConnectionType.maidcafe]
  /// terminals — an http(s) base URL the app itself can reach, such as
  /// `https://host.tailnet.ts.net` (or `http://127.0.0.1:8747` when the page or
  /// app runs on the same machine). Unlike the SSH-forwarded metrics endpoint,
  /// it must be reachable without an SSH session, because that is the whole
  /// point of the transport.
  final String? maidCafeTerminalUrl;

  /// Optional dedicated daemon terminal credential (`daemon.terminal.secret`).
  /// Null/empty keeps the stored value on edit; [clearMaidCafeTerminalSecret]
  /// removes it. The daemon falls back to its metrics secret when this is
  /// unset, so an empty value is a valid configuration, not a missing one.
  final String? maidCafeTerminalSecret;

  /// Whether an edit should delete the stored terminal credential.
  final bool clearMaidCafeTerminalSecret;

  /// The cloud daemon uuid this server is registered as. Set when the app
  /// creates the daemon (or entered by hand); required to route terminals
  /// through the cloud relay.
  final String? maidCafeDaemonId;

  /// Whether terminals go through the MaidCafe cloud relay instead of dialing
  /// the daemon directly. The relay reaches a daemon behind NAT, which is the
  /// only option for a browser build that cannot route to the daemon.
  final bool maidCafeTerminalViaCloud;

  /// The account a daemon terminal opens as, matching the daemon's
  /// `daemon.terminal.users` allowlist. Null/empty opens as the daemon's own
  /// account, which is the daemon's own default; the daemon refuses an account
  /// its allowlist does not name.
  final String? maidCafeTerminalUser;
}

/// JSON-encodes [environment] for storage, or null when it is empty.
String? encodeEnvironmentMap(Map<String, String> environment) =>
    environment.isEmpty ? null : jsonEncode(environment);

/// Decodes a stored environment JSON column.
Map<String, String> decodeEnvironmentMap(String? value) {
  if (value == null || value.isEmpty) return const {};
  final decoded = jsonDecode(value);
  if (decoded is! Map<String, dynamic>) return const {};
  return decoded.map((key, item) => MapEntry(key, item.toString()));
}

/// JSON-encodes [ids] for storage, or null when it is empty.
String? encodeSnippetIdList(List<int> ids) =>
    ids.isEmpty ? null : jsonEncode(ids);

/// Decodes a stored initial-snippets JSON column.
List<int> decodeSnippetIdList(String? value) {
  if (value == null || value.isEmpty) return const [];
  final decoded = jsonDecode(value);
  if (decoded is! List) return const [];
  return [
    for (final item in decoded)
      if (item is int) item,
  ];
}

/// JSON-encodes [values] for storage, or null when it is empty.
String? encodeStringList(List<String> values) =>
    values.isEmpty ? null : jsonEncode(values);

/// Decodes a stored JSON string-list column (tags).
List<String> decodeStringList(String? value) {
  if (value == null || value.isEmpty) return const [];
  final decoded = jsonDecode(value);
  if (decoded is! List) return const [];
  return [
    for (final item in decoded)
      if (item is String && item.isNotEmpty) item,
  ];
}

/// How the app reaches a server's terminal.
///
/// `ssh` and `serial` carry the shell over their own transport. `maidcafe`
/// dials the MaidCafe daemon's WebSocket terminal endpoint directly, which is
/// the only option in a browser build: the web platform has no raw sockets for
/// SSH or a serial device.
enum ServerConnectionType { ssh, serial, maidcafe }

/// Tolerant lookup for a stored `connectionType` value. Unknown or legacy
/// names fall back to SSH, which is what rows written before the column
/// existed mean.
ServerConnectionType serverConnectionTypeFromName(String? raw) =>
    ServerConnectionType.values.asNameMap()[raw] ?? ServerConnectionType.ssh;

/// Whether serial-port servers are offered in the UI and can be connected.
///
/// On macOS, the unsandboxed Runner opens /dev/cu.* device nodes directly.
/// Windows and Linux need their own transport before this flag can cover them.
/// A browser has no device nodes and no platform channel to open one, so
/// serial servers are offered read-only there and cannot be connected.
const bool serialPortsSupported = !kIsWeb;

/// Whether [server] carries a usable MaidCafe daemon terminal route.
///
/// The daemon endpoint is a transport, not a connection type: an SSH server
/// can store one too, and then serves its terminal over the daemon wherever a
/// raw socket is impossible (a browser build), while native builds keep using
/// SSH. See [MaidCafeTerminalTarget].
extension ServerMaidCafeRoute on Server {
  /// A stored endpoint, a cloud relay identity, or a port a native client
  /// learned for the daemon all reach a terminal.
  bool get hasMaidCafeTerminalRoute {
    final url = maidCafeTerminalUrl?.trim();
    if (url != null && url.isNotEmpty) return true;
    final daemonId = maidCafeDaemonId?.trim();
    if (maidCafeTerminalViaCloud && daemonId != null && daemonId.isNotEmpty) {
      return true;
    }
    return maidCafeTerminalPort != null;
  }

  /// The daemon terminal endpoint a browser should dial, or null when the row
  /// carries none.
  ///
  /// A native client reaches the daemon through its own SSH tunnel, so the
  /// endpoint it stores is a loopback address (`http://127.0.0.1:<port>`). A
  /// browser has no tunnel and would dial its own machine, so when only such an
  /// address (or none at all) is stored the endpoint is rebuilt against
  /// [Server.host] on [Server.maidCafeTerminalPort], the port the daemon itself
  /// reported. A stored endpoint that already names a non-loopback host is
  /// returned unchanged.
  ///
  /// The rebuilt endpoint keeps the stored scheme — plain `http` for a tunnel
  /// address — so a page served over https blocks that socket as mixed content;
  /// reaching a plain-http daemon from one needs a TLS front, the same rule the
  /// endpoint editor enforces for non-loopback addresses.
  /// The stored daemon endpoint when it is one a client can dial without a
  /// tunnel, or null when only a loopback address (or nothing) is stored.
  ///
  /// This is the per-server override: an address the user pointed at the
  /// daemon, typically an HTTPS reverse proxy that terminates TLS in front of
  /// it. Loopback addresses are what a native client's own SSH forward uses,
  /// so they are not an override — they are the route the app builds for
  /// itself.
  String? get maidCafeEndpointOverride {
    final stored = maidCafeTerminalUrl?.trim();
    if (stored == null || stored.isEmpty) return null;
    final uri = Uri.tryParse(stored);
    if (uri == null || uri.host.isEmpty) return null;
    if (_maidCafeHostIsLoopback(uri.host)) return null;
    return stored;
  }

  /// The accounts a daemon terminal may open as: the daemon's
  /// `daemon.terminal.users` allowlist as last read from its configuration.
  /// Empty means the daemon names none, so its own account is the only account
  /// a session can be.
  List<String> get maidCafeTerminalUserChoices =>
      decodeStringList(maidCafeTerminalUsers);

  String? get maidCafeBrowserTerminalUrl {
    final stored = maidCafeTerminalUrl?.trim();
    final storedUrl = (stored == null || stored.isEmpty)
        ? null
        : Uri.tryParse(stored);
    if (storedUrl != null && !_maidCafeHostIsLoopback(storedUrl.host)) {
      return stored;
    }
    final host = this.host.trim();
    final port =
        maidCafeTerminalPort ??
        (storedUrl != null && storedUrl.hasPort ? storedUrl.port : null);
    if (port == null || host.isEmpty) {
      return storedUrl == null ? null : stored;
    }
    return Uri(
      scheme: storedUrl?.scheme ?? 'http',
      host: host,
      port: port,
      path: storedUrl?.path ?? '',
    ).toString();
  }
}

/// The address this app dials for a daemon terminal when the daemon announces
/// [listenHost] and [port].
///
/// Loopback is used when the daemon only listens locally or on every interface:
/// a native client reaches that through its SSH forward, and a browser client
/// re-points the stored address at the server host (see
/// [ServerMaidCafeRoute.maidCafeBrowserTerminalUrl]). An announced host is kept
/// as-is, because that is the address the daemon itself is reachable at.
String maidCafeDialUrl(String? listenHost, int port) {
  final host = (listenHost ?? '').trim();
  final announced =
      host.isNotEmpty && host != '0.0.0.0' && host != '::' && host != '[::]';
  return 'http://${announced ? host : '127.0.0.1'}:$port';
}

bool _maidCafeHostIsLoopback(String host) =>
    host == 'localhost' || host == '127.0.0.1' || host == '::1';

/// Subprotocol token prefix that carries a terminal credential. A browser
/// cannot set an `Authorization` header on a WebSocket handshake, so the
/// daemon (direct) and the MaidCafe cloud (relayed) accept
/// `maidcafe.terminal.<base64url-unpadded credential>` as an offered
/// subprotocol. Native builds use the same token so both paths share one code
/// path and one credential format.
const String maidCafeTerminalSubprotocolPrefix = 'maidcafe.terminal.';

/// Builds the subprotocol token that carries [credential].
///
/// The peer decodes with unpadded base64url, so padding is stripped; a padded
/// token would not be a valid subprotocol value either (RFC 6455 tokens are
/// restricted).
String maidCafeTerminalToken(String credential) {
  final encoded = base64Url.encode(utf8.encode(credential)).replaceAll('=', '');
  return '$maidCafeTerminalSubprotocolPrefix$encoded';
}

/// Mints a one-time cloud ticket for a relayed session with the requested PTY
/// geometry and run-as [user] (null/empty for the daemon's own account).
/// Sampled by [MaidCafeTerminalTarget.ticketProvider].
typedef MaidCafeTerminalTicketProvider =
    Future<MaidCafeTerminalTicket> Function(
      int columns,
      int rows,
      String? user,
    );

/// A resolved MaidCafe daemon terminal endpoint and its credential.
///
/// [baseUrl] is the root the app dials: the daemon itself (e.g.
/// `https://host.tailnet.ts.net`, authorized by [secret]) or the MaidCafe cloud
/// for a relayed session (e.g. `https://mkc.solsynth.dev`, with
/// [relayDaemonId] and [ticketProvider] set). The transport appends
/// `/api/v1/terminal`, or `/api/daemons/{id}/terminal` for a relayed session.
/// [secret] is the dedicated terminal secret when one is stored and the daemon
/// metrics secret otherwise, matching the daemon's own `daemon.terminal.secret`
/// fallback.
class MaidCafeTerminalTarget {
  const MaidCafeTerminalTarget({
    required this.baseUrl,
    required this.secret,
    this.user,
    this.relayDaemonId,
    this.ticketProvider,
  });

  final String baseUrl;
  final String secret;

  /// The account the shell should open as, matching the daemon's
  /// `daemon.terminal.users` allowlist. Null/empty opens as the daemon's own
  /// account, which is the daemon's own default. Sent as the `user` query
  /// parameter on a direct handshake and in the ticket request body on a
  /// relayed one.
  ///
  /// The daemon is the authority: an account its allowlist does not name is
  /// refused, so this asks rather than grants.
  final String? user;

  /// Cloud daemon uuid for a cloud-relayed session. When set, [endpoint]
  /// addresses the relay (`{baseUrl}/api/daemons/{id}/terminal`) and the
  /// session is authorized by [ticketProvider] instead of [secret]; when null
  /// the target is the daemon's own directly reachable endpoint.
  final String? relayDaemonId;

  /// Mints the one-time ticket a relayed handshake carries, with the geometry
  /// the daemon should start the shell at. Set together with [relayDaemonId];
  /// the daemon never sees the ticket, it authenticates its outbound dial with
  /// its own cloud secret.
  final MaidCafeTerminalTicketProvider? ticketProvider;

  /// Whether this target goes through the MaidCafe cloud relay.
  bool get isRelayed => relayDaemonId != null;

  /// The `ws`/`wss` endpoint for the terminal session, keeping the configured
  /// scheme's security: `https` becomes `wss` so a TLS-fronted host is never
  /// downgraded to a cleartext socket.
  ///
  /// A base path is preserved, so a daemon behind a path-prefixed reverse
  /// proxy (`https://host/maidcafe`) is addressed at
  /// `wss://host/maidcafe/api/v1/terminal`.
  Uri get endpoint {
    final base = Uri.parse(baseUrl);
    final scheme = switch (base.scheme) {
      'https' => 'wss',
      'http' => 'ws',
      _ => throw ArgumentError('Unsupported daemon endpoint: $baseUrl'),
    };
    final prefix = base.path.replaceFirst(RegExp(r'/+$'), '');
    final daemonId = relayDaemonId;
    // Built explicitly: Uri.replace(query: '') would leave a trailing '?'.
    return Uri(
      scheme: scheme,
      userInfo: base.userInfo,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: daemonId == null
          ? '$prefix/api/v1/terminal'
          : '$prefix/api/daemons/$daemonId/terminal',
    );
  }

  /// Builds the subprotocol credential for a cloud-relayed session, reusing
  /// [maidCafeTerminalToken] so a direct and a relayed handshake carry the
  /// same encoding. The cloud splits the decoded payload on the first `.` into
  /// the session id and the ticket ([sessionId] is a uuid, so it holds none).
  String sessionToken(String sessionId, String ticket) =>
      maidCafeTerminalToken('$sessionId.$ticket');

  /// The same target with a different run-as account, for a session that
  /// picked one after the route was resolved.
  MaidCafeTerminalTarget withUser(String? user) => MaidCafeTerminalTarget(
    baseUrl: baseUrl,
    secret: secret,
    user: user,
    relayDaemonId: relayDaemonId,
    ticketProvider: ticketProvider,
  );

  /// The handshake URL for one session: [endpoint] with the PTY geometry and
  /// the run-as account the daemon should apply.
  ///
  /// A relayed target returns [endpoint] unchanged — the cloud takes both in
  /// the ticket request body, and the browser socket carries no query
  /// parameters there. Also what the diagnostic probe requests, so a refusal
  /// it has to explain is the one the session itself would have met.
  Uri sessionEndpoint({int? columns, int? rows}) {
    if (isRelayed) return endpoint;
    final user = this.user?.trim();
    return endpoint.replace(
      queryParameters: {
        if (columns != null) 'cols': '$columns',
        if (rows != null) 'rows': '$rows',
        // Absent when no account is selected, which the daemon reads as its
        // own account — the same value an empty parameter means.
        if (user != null && user.isNotEmpty) 'user': user,
      },
    );
  }
}

enum SerialParity { none, even, odd }

enum SerialFlowControl { none, hardware, software }

/// Serial sessions are owned by the native platform implementation and expose
/// their raw byte stream to the terminal.
class SerialConfig {
  const SerialConfig({
    required this.device,
    this.baudRate = 115200,
    this.dataBits = 8,
    this.parity = SerialParity.none,
    this.stopBits = 1,
    this.flowControl = SerialFlowControl.none,
  });

  final String device;
  final int baudRate;
  final int dataBits;
  final SerialParity parity;
  final int stopBits;
  final SerialFlowControl flowControl;

  Map<String, Object?> toJson() => {
    'device': device,
    'baudRate': baudRate,
    'dataBits': dataBits,
    'parity': parity.name,
    'stopBits': stopBits,
    'flowControl': flowControl.name,
  };

  factory SerialConfig.decode(String value) {
    final json = jsonDecode(value) as Map<String, dynamic>;
    final device = json['device'];
    return SerialConfig(
      device: device is String ? device : '',
      baudRate: json['baudRate'] is int ? json['baudRate'] as int : 115200,
      dataBits: json['dataBits'] is int ? json['dataBits'] as int : 8,
      parity: _parseSerialParity(json['parity']),
      stopBits: json['stopBits'] is int ? json['stopBits'] as int : 1,
      flowControl: _parseSerialFlowControl(json['flowControl']),
    );
  }
}

SerialParity _parseSerialParity(Object? value) {
  if (value is! String) return SerialParity.none;
  for (final parity in SerialParity.values) {
    if (parity.name == value) return parity;
  }
  return SerialParity.none;
}

SerialFlowControl _parseSerialFlowControl(Object? value) {
  if (value is! String) return SerialFlowControl.none;
  for (final control in SerialFlowControl.values) {
    if (control.name == value) return control;
  }
  return SerialFlowControl.none;
}

/// JSON-encodes [config] for storage, or null when it is null.
String? encodeSerialConfig(SerialConfig? config) =>
    config == null ? null : jsonEncode(config.toJson());

/// Decodes a stored serial-config JSON column. Null, empty, or malformed
/// values decode to null; unknown enum names fall back to their defaults.
SerialConfig? decodeSerialConfig(String? value) {
  if (value == null || value.isEmpty) return null;
  try {
    return SerialConfig.decode(value);
  } on FormatException {
    return null;
  }
}

enum ServerProxyType { none, http, socks5 }

/// A per-server HTTP CONNECT or SOCKS5 proxy used to reach the SSH host.
///
/// The proxy establishes the underlying TCP connection, so DNS resolution
/// happens at the proxy rather than on this device.
class ServerProxy {
  const ServerProxy({
    required this.type,
    required this.host,
    required this.port,
    this.username,
    this.password,
  });

  final ServerProxyType type;
  final String host;
  final int port;
  final String? username;
  final String? password;
}

enum SessionStatus { connecting, connected, failed, closed }

/// Raised when an operation needs the server's retained SSH connection.
class ServerConnectionRequiredException implements Exception {
  const ServerConnectionRequiredException();

  @override
  String toString() => 'Connect to this server before running an operation.';
}

/// Raised when a configured jump host is not connected yet.
class JumpHostConnectionRequiredException implements Exception {
  const JumpHostConnectionRequiredException(this.jumpHostServerId);

  final int jumpHostServerId;

  @override
  String toString() =>
      'Connect to jump host $jumpHostServerId before connecting this server.';
}

class ServerGpuStats {
  const ServerGpuStats({
    required this.index,
    required this.name,
    this.utilizationPercent,
    this.memoryUsedKb,
    this.memoryTotalKb,
    this.temperatureC,
  });

  final int index;
  final String name;
  final double? utilizationPercent;
  final int? memoryUsedKb;
  final int? memoryTotalKb;
  final double? temperatureC;
}

/// One mounted filesystem's capacity snapshot (root, data volumes, network
/// mounts). Mirrors the `df -Pk` "available" semantics: used = total −
/// available, so the numbers match what `df` prints.
class DiskUsage {
  const DiskUsage({
    required this.mount,
    this.filesystem,
    this.totalKb,
    this.availableKb,
  });

  /// Mount point ('/', '/data', 'C:').
  final String mount;

  /// Device or filesystem identifier ('/dev/vda1', 'C:').
  final String? filesystem;
  final int? totalKb;
  final int? availableKb;

  int? get usedKb {
    final total = totalKb;
    final available = availableKb;
    if (total == null || available == null) return null;
    return total - available;
  }

  double? get percent {
    final used = usedKb;
    final total = totalKb;
    if (used == null || total == null || total == 0) return null;
    return (used / total * 100).clamp(0, 100);
  }
}

/// The band the MaidCafe daemon's host health score falls into. The daemon
/// bands its weighted score at 90 (`healthy`) and 70 (`degraded`); everything
/// below is `critical`.
enum ServerHealthStatus {
  healthy,
  degraded,
  critical;

  /// Tolerant wire lookup for a health band. A band this build does not know —
  /// a newer daemon, or a sample ingested before health reporting existed,
  /// which the cloud calls `unknown` — parses to null so a surface shows no
  /// band rather than a wrong one.
  static ServerHealthStatus? fromWire(Object? raw) {
    final value = raw?.toString().trim().toLowerCase();
    if (value == null || value.isEmpty) return null;
    for (final status in values) {
      if (status.name == value) return status;
    }
    return null;
  }
}

/// The daemon's summary of host health: the weighted score it computed for one
/// metric sample and the band that score falls into.
///
/// Health is all-or-nothing. A score is meaningless without its band, so
/// [serverHealthFromWire] yields null unless both halves are present and
/// trustworthy, and no surface ever renders a bare number or a band on its
/// own.
class ServerHealth {
  const ServerHealth({required this.score, required this.status});

  /// 0..100, where 100 is every scored dimension at or below its warning
  /// threshold.
  final int score;

  final ServerHealthStatus status;
}

/// Builds [ServerHealth] from a wire score and band, or null when either half
/// is missing, the band is unknown, or the score is outside 0..100.
ServerHealth? serverHealthFromWire(Object? score, Object? status) {
  final band = ServerHealthStatus.fromWire(status);
  final value = switch (score) {
    final int value => value,
    final num value => value.toInt(),
    final String value => int.tryParse(value.trim()),
    _ => null,
  };
  if (band == null || value == null || value < 0 || value > 100) return null;
  return ServerHealth(score: value, status: band);
}

class ServerStats {
  const ServerStats({
    required this.collectorId,
    required this.updatedAt,
    this.loadAverage,
    this.loadAverage5,
    this.loadAverage15,
    this.cpuCount,
    this.memoryTotalKb,
    this.memoryAvailableKb,
    this.swapTotalKb,
    this.swapFreeKb,
    this.diskTotalKb,
    this.diskAvailableKb,
    this.uptime,
    this.gpus = const [],
    this.disks = const [],
    this.health,
  });

  final String collectorId;
  final DateTime updatedAt;
  final double? loadAverage;
  final double? loadAverage5;
  final double? loadAverage15;
  final int? cpuCount;
  final int? memoryTotalKb;
  final int? memoryAvailableKb;
  final int? swapTotalKb;
  final int? swapFreeKb;
  final int? diskTotalKb;
  final int? diskAvailableKb;
  final Duration? uptime;
  final List<ServerGpuStats> gpus;

  /// Every reportable mounted filesystem (physical partitions and network
  /// mounts), root first. Empty when the collector only exposes the root
  /// aggregate.
  final List<DiskUsage> disks;

  /// The daemon's own health score for this sample, or null when the route
  /// cannot report one: the SSH collectors do not score health, and a daemon
  /// older than the health feature sends neither half.
  final ServerHealth? health;
}

class ServerProcess {
  const ServerProcess({
    required this.pid,
    required this.user,
    required this.cpuPercent,
    required this.memoryPercent,
    required this.rssKb,
    required this.command,
  });

  final int pid;
  final String user;
  final double cpuPercent;
  final double memoryPercent;
  final int rssKb;
  final String command;
}

/// The fixed runtime set the Runtimes tab can render. Wire names equal `.name`
/// ('java', 'dotnet', 'python', ...); the daemon's configured list may carry
/// fewer entries and unknown names are skipped by [runtimeKindFromWire].
enum RuntimeKind { java, dotnet, python, node, deno, go, ruby, php }

/// Which channel produced a runtime snapshot.
enum RuntimeDataSource { daemon, ssh }

/// Tolerant wire lookup: returns null for unknown runtime names so future
/// daemon additions degrade gracefully instead of throwing.
RuntimeKind? runtimeKindFromWire(String raw) {
  for (final kind in RuntimeKind.values) {
    if (kind.name == raw) {
      return kind;
    }
  }
  return null;
}

class RuntimeProcessInfo {
  const RuntimeProcessInfo({
    required this.pid,
    required this.user,
    required this.cpuPercent,
    required this.memoryPercent,
    required this.rssKb,
    required this.command,
    this.threads,
  });

  final int pid;
  final String user;
  final double cpuPercent;
  final double memoryPercent;
  final int rssKb;

  /// Null on BSD/macOS hosts where ps has no nlwp column.
  final int? threads;
  final String command;
}

class JavaJvmInfo {
  const JavaJvmInfo({
    required this.pid,
    this.mainClass,
    this.oldPercent,
    this.ygc,
    this.fgc,
    this.gctSeconds,
    this.error,
  });

  final int pid;
  final String? mainClass;
  final double? oldPercent;
  final int? ygc;
  final int? fgc;
  final double? gctSeconds;

  /// Per-JVM collection failure; the process row itself is still valid.
  final String? error;
}

class JavaRuntimeInfo {
  const JavaRuntimeInfo({
    required this.jdkAvailable,
    required this.jvms,
    this.jdkError,
  });

  final bool jdkAvailable;
  final String? jdkError;
  final List<JavaJvmInfo> jvms;
}

class RuntimeGroup {
  const RuntimeGroup({
    required this.kind,
    required this.available,
    required this.processes,
    this.error,
    this.java,
  });

  final RuntimeKind kind;
  final bool available;
  final String? error;
  final List<RuntimeProcessInfo> processes;

  /// Present only in the java group when at least one java process exists.
  final JavaRuntimeInfo? java;
}

/// One user-defined process watcher (daemon-side `watched` list). Processes
/// match by comm-token prefix; only the MaidCafe channel provides these, the
/// SSH fallback has no watched list.
class WatchedProcessGroup {
  const WatchedProcessGroup({
    required this.name,
    required this.available,
    required this.processes,
    this.error,
  });

  final String name;
  final bool available;
  final String? error;
  final List<RuntimeProcessInfo> processes;
}

class RuntimeSnapshot {
  const RuntimeSnapshot({
    required this.groups,
    required this.collectedAt,
    this.watched = const [],
  });

  final List<RuntimeGroup> groups;
  final DateTime collectedAt;

  /// Watched-process groups from the daemon; empty on the SSH fallback.
  final List<WatchedProcessGroup> watched;
}

/// One daemon-recorded usage sample for a watched process.
class ProcessHistorySample {
  const ProcessHistorySample({
    required this.name,
    required this.timestamp,
    required this.cpuPercent,
    required this.rssKb,
    required this.processCount,
    this.threads,
  });

  final String name;
  final DateTime timestamp;
  final double cpuPercent;
  final int rssKb;
  final int processCount;
  final int? threads;
}

class ProcessHistory {
  const ProcessHistory({required this.name, required this.samples});

  final String name;
  final List<ProcessHistorySample> samples;
}

class ServerSystemInfo {
  const ServerSystemInfo({this.distribution, this.kernel});

  final String? distribution;
  final String? kernel;
}

class SshSessionInfo {
  const SshSessionInfo({
    required this.serverId,
    required this.serverName,
    required this.connectedAt,
    required this.status,
    this.error,
    this.stats,
    this.systemInfo,
    this.networkLatency,
  });

  final int serverId;
  final String serverName;
  final DateTime connectedAt;
  final SessionStatus status;
  final String? error;
  final ServerStats? stats;
  final ServerSystemInfo? systemInfo;

  /// Direct network ping latency used by server cards.
  final Duration? networkLatency;

  SshSessionInfo copyWith({
    SessionStatus? status,
    String? error,
    ServerStats? stats,
    ServerSystemInfo? systemInfo,
    Duration? networkLatency,
  }) => SshSessionInfo(
    serverId: serverId,
    serverName: serverName,
    connectedAt: connectedAt,
    status: status ?? this.status,
    error: error ?? this.error,
    stats: stats ?? this.stats,
    systemInfo: systemInfo ?? this.systemInfo,
    networkLatency: networkLatency ?? this.networkLatency,
  );
}

class HostKeyPrompt {
  const HostKeyPrompt({
    required this.algorithm,
    required this.fingerprint,
    this.replacesExisting = false,
  });

  final String algorithm;
  final String fingerprint;
  final bool replacesExisting;
}

/// One keyboard-interactive challenge issued by an SSH server while
/// authenticating, for example a bastion that asks for the account password
/// and then for a verification code.
class AuthChallenge {
  const AuthChallenge({
    required this.serverName,
    required this.name,
    required this.instruction,
    required this.prompts,
  });

  final String serverName;

  /// Server-supplied challenge name, for example "Two-factor authentication".
  final String name;

  /// Server-supplied instructions shown above the prompts.
  final String instruction;

  final List<AuthChallengePrompt> prompts;
}

class AuthChallengePrompt {
  const AuthChallengePrompt({
    required this.text,
    required this.obscure,
    this.initialValue,
  });

  final String text;

  /// Whether the response must be hidden while typing, matching the server's
  /// echo flag.
  final bool obscure;

  /// Answer detected from the saved credential. The user may still correct it.
  final String? initialValue;
}

final _passwordPromptPattern = RegExp(
  r'pass(word|phrase)?',
  caseSensitive: false,
);

/// Wording that asks for a second factor, a one-time code, or another secret
/// that is not the stored account password.
///
/// Checked before [_passwordPromptPattern] so that prompts such as
/// "One-time password" or "Verification code" are never answered with the
/// saved password. Input the user would otherwise have to supply by hand only
/// costs a dialog, while a wrong automatic answer fails the whole login.
final _secondFactorPromptPattern = RegExp(
  r'one[\s-]?time|otp|passcode|verification|verify|authenticator'
  r'|two[\s-]?factor|2fa|mfa|token|\bcode\b|动态|验证码|驗證碼|令牌|一次性',
  caseSensitive: false,
);

/// Whether [prompt] asks for the account password rather than a one-time code
/// or a menu choice.
bool isPasswordPrompt(String prompt) {
  if (_secondFactorPromptPattern.hasMatch(prompt)) return false;
  return _passwordPromptPattern.hasMatch(prompt) ||
      prompt.contains('密码') ||
      prompt.contains('密碼');
}

/// Answers for a keyboard-interactive challenge that can be resolved without
/// asking the user.
///
/// Password prompts are filled from [password]. Every other prompt, including
/// verification codes and bastion menus, stays null so the caller knows it
/// must ask the user. The result always matches [prompts] in length and order.
List<String?> detectedAuthAnswers(List<String> prompts, String? password) => [
  for (final prompt in prompts)
    if (password != null && password.isNotEmpty && isPasswordPrompt(prompt))
      password
    else
      null,
];
