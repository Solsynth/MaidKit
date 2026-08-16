import 'dart:convert';

enum CredentialType { password, privateKey }

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
    this.connectionType = ServerConnectionType.ssh,
    this.serialConfig,
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

  /// Free-form labels shown on the server card and usable as filters.
  final List<String> tags;

  /// Transport used to reach this server: `ssh` for a remote host, `serial`
  /// for a local serial port.
  final ServerConnectionType connectionType;

  /// Serial-port settings, only used when [connectionType] is serial.
  final SerialConfig? serialConfig;
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

enum ServerConnectionType { ssh, serial, local }

/// Whether serial-port servers are offered in the UI and can be connected.
///
/// On macOS, the unsandboxed Runner opens /dev/cu.* device nodes directly.
/// Windows and Linux need their own transport before this flag can cover them.
const bool serialPortsSupported = true;

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

/// The runtime set the Runtimes tab can render. Wire names equal `.name`
/// ('java', 'dotnet', 'python', ...); the daemon's configured list may carry
/// fewer entries and unknown names are skipped by [RuntimeKindFromWire].
enum RuntimeKind { java, dotnet, python, node, deno, go, ruby, php }

/// Tolerant wire lookup: returns null for unknown runtime names so future
/// daemon additions degrade gracefully instead of throwing.
RuntimeKind? RuntimeKindFromWire(String raw) {
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
