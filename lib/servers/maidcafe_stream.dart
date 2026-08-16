import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/port_forwarding_models.dart';
import 'package:maid_kit/servers/ssh_connection_manager.dart';

import 'maidcafe_install.dart';
import 'maidcafe_service.dart';

const maidCafeDefaultPort = 8747;

/// Raised when the daemon rejects the metrics secret (HTTP 401).
class MaidCafeUnauthorizedException implements Exception {
  const MaidCafeUnauthorizedException();
}

/// Event types the daemon may broadcast on `/api/v1/stream`.
///
/// `hello` is always the first frame, regardless of the requested whitelist.
enum MaidCafeStreamEventType {
  hello,
  metric,
  containers,
  images,
  processes,
  systemd,
}

/// All streamable event types; the default whitelist for [MaidCafeStreamSession.openStream].
const Set<MaidCafeStreamEventType> maidCafeStreamAllEvents = {
  MaidCafeStreamEventType.hello,
  MaidCafeStreamEventType.metric,
  MaidCafeStreamEventType.containers,
  MaidCafeStreamEventType.images,
  MaidCafeStreamEventType.processes,
  MaidCafeStreamEventType.systemd,
};

/// One decoded SSE frame from the daemon stream.
class MaidCafeStreamEvent {
  const MaidCafeStreamEvent({required this.type, required this.data});

  final MaidCafeStreamEventType type;

  /// Decoded JSON payload; already normalized to string keys.
  final Map<String, dynamic> data;
}

/// Parses raw SSE bytes into typed events.
///
/// Standard SSE framing: `event:`/`data:` lines terminated by a blank line;
/// comment lines starting with `:` are ignored. Frames with an unknown event
/// name, missing data, or malformed JSON are skipped so one bad frame never
/// kills the stream.
Stream<MaidCafeStreamEvent> parseMaidCafeSseFrames(
  Stream<List<int>> bytes,
) async* {
  final lines = const LineSplitter().bind(utf8.decoder.bind(bytes));
  String? eventName;
  final data = StringBuffer();
  await for (final line in lines) {
    if (line.isEmpty) {
      final event = _dispatchSseFrame(eventName, data.toString());
      eventName = null;
      data.clear();
      if (event != null) yield event;
    } else if (line.startsWith(':')) {
      // Comment (also used for heartbeats): ignore.
    } else if (line.startsWith('event:')) {
      eventName = line.substring('event:'.length).trim();
    } else if (line.startsWith('data:')) {
      var value = line.substring('data:'.length);
      // Per the SSE spec a single leading space after "data:" is stripped.
      if (value.startsWith(' ')) value = value.substring(1);
      data.writeln(value);
    }
    // Other SSE fields (id:, retry:) are not part of the contract; ignored.
  }
}

MaidCafeStreamEvent? _dispatchSseFrame(String? eventName, String data) {
  final name = eventName?.trim();
  if (name == null || name.isEmpty || data.trim().isEmpty) return null;
  final type = switch (name) {
    'hello' => MaidCafeStreamEventType.hello,
    'metric' => MaidCafeStreamEventType.metric,
    'containers' => MaidCafeStreamEventType.containers,
    'images' => MaidCafeStreamEventType.images,
    'processes' => MaidCafeStreamEventType.processes,
    'systemd' => MaidCafeStreamEventType.systemd,
    _ => null,
  };
  if (type == null) return null;
  try {
    final decoded = jsonDecode(data);
    if (decoded is! Map) return null;
    return MaidCafeStreamEvent(
      type: type,
      data: decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
  } on FormatException {
    return null;
  }
}

/// One execution audit record from the daemon. [name] is the API slug;
/// [displayName] is the configured human-readable label, when present.
class MaidCafeAuditEntry {
  const MaidCafeAuditEntry({
    required this.timestamp,
    required this.name,
    required this.source,
    required this.ok,
    required this.exitCode,
    required this.durationMs,
    this.displayName,
    this.error,
    this.stdout = '',
    this.stderr = '',
    this.invokedBy,
  });

  final DateTime timestamp;
  final String name;
  final String? displayName;
  final String source;
  final bool ok;
  final int exitCode;
  final int durationMs;
  final String? error;

  /// Full captured run output, bounded by the daemon's per-run buffer.
  final String stdout;
  final String stderr;

  /// Who asked for the run: a Solarpass handle, a labeled credential, or
  /// null when the transport carries no identity.
  final String? invokedBy;

  /// Label to show in the UI: the display name when set, else the slug.
  String get label => displayName?.isNotEmpty ?? false ? displayName! : name;

  factory MaidCafeAuditEntry.fromJson(Map<String, dynamic> json) {
    final timestamp = DateTime.tryParse(json['timestamp']?.toString() ?? '');
    return MaidCafeAuditEntry(
      timestamp: timestamp?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
      name: json['name']?.toString() ?? '',
      displayName: json['display_name']?.toString(),
      source: json['source']?.toString() ?? '',
      ok: json['ok'] == true,
      exitCode: (json['exit_code'] as num?)?.toInt() ?? 0,
      durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
      error: json['error']?.toString(),
      stdout: json['stdout']?.toString() ?? '',
      stderr: json['stderr']?.toString() ?? '',
      invokedBy: json['invoked_by']?.toString(),
    );
  }
}

class MaidCafeDaemonAccess {
  const MaidCafeDaemonAccess({
    required this.port,
    required this.apiSecret,
    this.id,
    this.version,
    this.transport,
    this.listenHost,
    this.cloudUrl,
    this.cloudSecret,
    this.metricsInterval,
    this.requestTimeout,
    this.scriptTimeout,
    this.maxBodyBytes,
    this.maxConcurrentRuns,
    this.actions = const [],
    this.alarms = const [],
    this.configText = '',
  });
  final int? port;
  final String? apiSecret;
  final String? id;
  final String? version;
  final String? transport;
  final String? listenHost;
  final String? cloudUrl;
  final String? cloudSecret;
  final String? metricsInterval;
  final String? requestTimeout;
  final String? scriptTimeout;
  final int? maxBodyBytes;
  final int? maxConcurrentRuns;
  final List<MaidCafeActionDefinition> actions;

  /// Alarm thresholds declared in the daemon's `alarmsDir` fragments. Alarms
  /// are evaluated daemon-side; this list is what the config editor edits.
  final List<MaidCafeAlarmDefinition> alarms;

  /// The raw `/etc/maidcafe/config.toml` text, for patch-based updates that
  /// preserve everything the model does not parse.
  final String configText;
}

/// Reads the daemon's HTTP endpoint, API secret, and action scripts over SSH.
///
/// The daemon config is root-only (`0640 root:maidcafe`), so a plain read is
/// tried first and elevated reads fall back to [sudoPassword] when the SSH
/// user cannot open it. The `[daemon]` section (including `[[daemon.actions]]`
/// blocks) is extracted with awk, then every deployed action script is
/// appended after a marker. Script bodies are hex-encoded (`od -tx1`) so
/// arbitrary content — including a trailing newline — round-trips verbatim
/// and can never be confused with the file separators.
const _maidCafeConfigReadBody = r'''awk '
  /^\[daemon\]/{section="daemon"; next}
  /^\[\[/{if (section=="daemon" && $0=="[[daemon.actions]]") {section="actions"; next}}
  /^\[/{section=""; next}
  section!=""{print}
' /etc/maidcafe/config.toml 2>/dev/null || true
printf '\n###MAIDKIT-FULL-CONFIG###\n'
od -An -tx1 -v < /etc/maidcafe/config.toml 2>/dev/null | tr -d ' \n'
printf '\n'
printf '###MAIDKIT-ACTION-CONFIGS###\n'
ls /etc/maidcafe/actions/*.toml 2>/dev/null | while IFS= read -r f; do
  [ -f "$f" ] || continue
  printf '###FILE:%s###\n' "$(basename "$f")"
  od -An -tx1 -v < "$f" 2>/dev/null | tr -d ' \n'
  printf '\n'
done
printf '###MAIDKIT-ALARM-CONFIGS###\n'
ls /etc/maidcafe/alarms/*.toml 2>/dev/null | while IFS= read -r f; do
  [ -f "$f" ] || continue
  printf '###FILE:%s###\n' "$(basename "$f")"
  od -An -tx1 -v < "$f" 2>/dev/null | tr -d ' \n'
  printf '\n'
done
printf '###MAIDKIT-ACTION-SCRIPTS###\n'
ls /etc/maidcafe/actions/*.sh 2>/dev/null | while IFS= read -r f; do
  [ -f "$f" ] || continue
  printf '###FILE:%s###\n' "$(basename "$f")"
  od -An -tx1 -v < "$f" 2>/dev/null | tr -d ' \n'
  printf '\n'
done''';

const _maidCafeFullConfigMarker = '###MAIDKIT-FULL-CONFIG###';
const _maidCafeActionConfigsMarker = '###MAIDKIT-ACTION-CONFIGS###';
const _maidCafeAlarmConfigsMarker = '###MAIDKIT-ALARM-CONFIGS###';
const _maidCafeActionScriptsMarker = '###MAIDKIT-ACTION-SCRIPTS###';

/// Splits the combined read-back payload into the `[daemon]` config section,
/// the raw full config text, the per-action `.toml` fragments and the
/// deployed action-script blob.
(
  String config,
  String fullConfig,
  Map<String, String> actionConfigs,
  Map<String, String> alarmConfigs,
  String scripts,
)
_splitMaidCafeConfigPayload(String output) {
  final fullIndex = output.indexOf(_maidCafeFullConfigMarker);
  final configsIndex = output.indexOf(_maidCafeActionConfigsMarker);
  final alarmsIndex = output.indexOf(_maidCafeAlarmConfigsMarker);
  final scriptsIndex = output.indexOf(_maidCafeActionScriptsMarker);
  String section(int markerIndex, String marker, int end) {
    if (markerIndex == -1 || end == -1 || end <= markerIndex) return '';
    return output.substring(markerIndex + marker.length + 1, end);
  }

  return (
    fullIndex == -1 ? output : output.substring(0, fullIndex),
    _hexDecode(section(fullIndex, _maidCafeFullConfigMarker, configsIndex)),
    parseMaidCafeConfigFiles(
      section(configsIndex, _maidCafeActionConfigsMarker, alarmsIndex),
      '.toml',
    ),
    parseMaidCafeConfigFiles(
      section(alarmsIndex, _maidCafeAlarmConfigsMarker, scriptsIndex),
      '.toml',
    ),
    scriptsIndex == -1
        ? ''
        : output.substring(
            scriptsIndex + _maidCafeActionScriptsMarker.length + 1,
          ),
  );
}

/// Decodes `###FILE:<name><ext>###` + hex pairs from a marker blob.
Map<String, String> parseMaidCafeConfigFiles(String blob, String extension) {
  final result = <String, String>{};
  final pattern = RegExp(
    '###FILE:([A-Za-z0-9._-]+\\$extension)###\\n([0-9a-fA-F]*)\\n',
  );
  for (final match in pattern.allMatches(blob)) {
    final fileName = match.group(1)!;
    final hex = match.group(2)!;
    if (hex.isEmpty) continue;
    result[fileName.substring(0, fileName.length - extension.length)] =
        _hexDecode(hex);
  }
  return result;
}

String _hexDecode(String hex) {
  final bytes = <int>[];
  for (var i = 0; i + 1 < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return utf8.decode(bytes, allowMalformed: true);
}

/// Decodes deployed action scripts from the marker-delimited read-back blob:
/// `###FILE:<name>.sh###` followed by the body hex-encoded with `od -tx1`.
///
/// Keys are action names (file name without `.sh`); bodies are returned
/// verbatim, including any trailing newline. Public so round-trip parsing can
/// be unit-tested.
Map<String, String> parseMaidCafeActionScripts(String blob) =>
    parseMaidCafeConfigFiles(blob, '.sh');

/// Wraps a multi-line [body] for elevation as a single `sh -c` argument.
String _elevatedMaidCafeRead(String prefix, String body) =>
    "$prefix sh -c '${body.replaceAll("'", r"'\''")}'";

Future<MaidCafeDaemonAccess> readMaidCafeConfig({
  required SshConnectionManager manager,
  required Server server,
  String? sudoPassword,
}) => manager.withClient(server.id, (client) async {
  Future<String> read(String command, {String? stdin}) async {
    final session = await client.execute(command);
    final stdout = utf8.decoder.bind(session.stdout).join();
    if (stdin != null) {
      session.stdin.add(utf8.encode('$stdin\n'));
      await session.stdin.close();
    }
    try {
      await session.done.timeout(const Duration(seconds: 8));
    } finally {
      session.close();
    }
    return stdout;
  }

  final plainRead = _maidCafeConfigReadBody;
  final passwordlessRead = _elevatedMaidCafeRead('sudo -n', plainRead);
  final passwordRead = _elevatedMaidCafeRead('sudo -S -p ""', plainRead);

  var output = await read(plainRead);
  if (server.username != 'root') {
    // The scripts section always prints its marker even when the config is
    // unreadable, so the elevation gate must test the config section alone,
    // not the combined payload.
    var configSection = _splitMaidCafeConfigPayload(output).$1;
    if (configSection.trim().isEmpty) {
      output = await read(passwordlessRead);
      configSection = _splitMaidCafeConfigPayload(output).$1;
    }
    final password = sudoPassword?.trim() ?? '';
    if (configSection.trim().isEmpty && password.isNotEmpty) {
      output = await read(passwordRead, stdin: password);
    }
  }
  final (config, fullConfig, actionConfigs, alarmConfigs, scriptsBlob) =
      _splitMaidCafeConfigPayload(output);
  final scripts = parseMaidCafeActionScripts(scriptsBlob);
  // Fragments are the current source of truth; legacy inline [[daemon.actions]]
  // blocks (pre-fragment installs) are kept for migration and overridden by
  // name when a fragment exists.
  final inline = {
    for (final action in parseMaidCafeActionDefinitions(config))
      action.name: action,
  };
  final actions = <MaidCafeActionDefinition>[
    for (final entry in actionConfigs.entries)
      _mergeAction(
        parseMaidCafeActionFragment(entry.value),
        entry.key,
        scripts,
      ),
    for (final entry in inline.entries)
      if (!actionConfigs.containsKey(entry.key))
        _mergeAction(entry.value, entry.key, scripts),
  ];
  final listen = _configValue(config, 'listen');
  final listenUri = listen == null ? null : Uri.tryParse('http://$listen');
  return MaidCafeDaemonAccess(
    port:
        listenUri?.port != null &&
            listenUri!.port >= maidCafeMinimumPort &&
            listenUri.port <= 65535
        ? listenUri.port
        : null,
    apiSecret: _configValue(config, 'metricsSecret'),
    id: _configValue(config, 'id'),
    version: _configValue(config, 'version'),
    transport: _configValue(config, 'transport'),
    listenHost: listenUri?.host,
    cloudUrl: _configValue(config, 'cloudUrl'),
    cloudSecret: _configValue(config, 'cloudSecret'),
    metricsInterval: _configValue(config, 'metricsInterval'),
    requestTimeout: _configValue(config, 'requestTimeout'),
    scriptTimeout: _configValue(config, 'scriptTimeout'),
    maxBodyBytes: int.tryParse(_configValue(config, 'maxBodyBytes') ?? ''),
    maxConcurrentRuns: int.tryParse(
      _configValue(config, 'maxConcurrentRuns') ?? '',
    ),
    configText: fullConfig,
    actions: actions,
    alarms: [
      for (final fragment in alarmConfigs.values)
        parseMaidCafeAlarmFragment(fragment),
    ],
  );
});

/// Merges a parsed action (fragment or legacy inline block) with its deployed
/// script body.
MaidCafeActionDefinition _mergeAction(
  MaidCafeActionDefinition action,
  String name,
  Map<String, String> scripts,
) => scripts[name] == null ? action : action.copyWith(script: scripts[name]);

Future<int?> readMaidCafeListenPort({
  required SshConnectionManager manager,
  required Server server,
  String? sudoPassword,
}) async => (await readMaidCafeConfig(
  manager: manager,
  server: server,
  sudoPassword: sudoPassword,
)).port;

String? _configValue(String config, String key) {
  final pattern =
      r'''^\s*''' +
      RegExp.escape(key) +
      r'''\s*=\s*(?:"([^"]*)"|([^#\s]+))\s*$''';
  final match = RegExp(pattern, multiLine: true).firstMatch(config);
  final value = match?.group(1) ?? match?.group(2);
  return value?.trim().isEmpty ?? true ? null : value!.trim();
}

bool _configBool(String config, String key, {bool fallback = false}) =>
    switch (_configValue(config, key)?.toLowerCase()) {
      'true' => true,
      'false' => false,
      _ => fallback,
    };

/// Parses `[[daemon.actions]]` blocks from the `[daemon]` config section
/// read back over SSH. Public so round-trip parsing can be unit-tested.
///
/// The daemon script bodies are not embedded here; callers merge them from
/// [parseMaidCafeActionScripts]. `env` arrays may span lines (hand-edited
/// configs); [parseMaidCafeTomlStringArray] handles basic strings with the
/// common escapes.
List<MaidCafeActionDefinition> parseMaidCafeActionDefinitions(String config) {
  final blocks = RegExp(
    r'\[\[daemon\.actions\]\](.*?)(?=\n\[\[daemon\.actions\]\]|$)',
    dotAll: true,
  ).allMatches(config);
  return [
    for (final block in blocks)
      if (_configValue(block.group(1)!, 'name') != null &&
          _configValue(block.group(1)!, 'command') != null)
        _actionFromBlock(block.group(1)!),
  ];
}

/// Parses one flat `<slug>.toml` action fragment (the same shape as an entry
/// of `[[daemon.actions]]` without the table header).
MaidCafeActionDefinition parseMaidCafeActionFragment(String fragment) =>
    _actionFromBlock(fragment);

/// Parses one flat `<kind>.toml` alarm fragment (the same shape as an entry
/// of `[[daemon.alarms]]` without the table header). Public so round-trip
/// parsing can be unit-tested.
MaidCafeAlarmDefinition parseMaidCafeAlarmFragment(String fragment) =>
    MaidCafeAlarmDefinition(
      kind: _configValue(fragment, 'kind') ?? '',
      threshold:
          double.tryParse(_configValue(fragment, 'threshold') ?? '') ?? 0,
      enabled: _configBool(fragment, 'enabled', fallback: true),
      cooldownSeconds:
          int.tryParse(_configValue(fragment, 'cooldownSeconds') ?? '') ?? 300,
    );

MaidCafeActionDefinition _actionFromBlock(String block) =>
    MaidCafeActionDefinition(
      name: _configValue(block, 'name')!,
      script: '',
      enabled: _configBool(block, 'enabled', fallback: true),
      notifyOnSuccess: _configBool(block, 'notifyOnSuccess'),
      notifyOnFailure: _configBool(block, 'notifyOnFailure'),
      displayName: _configValue(block, 'displayName'),
      workingDirectory: _configValue(block, 'cwd'),
      user: _configValue(block, 'user'),
      scriptTimeout: _configValue(block, 'timeout'),
      environment: {
        for (final entry in _configList(block, 'env'))
          if (entry.contains('='))
            entry.substring(0, entry.indexOf('=')): entry.substring(
              entry.indexOf('=') + 1,
            ),
      },
    );

List<String> _configList(String config, String key) {
  final match = RegExp(
    r'''^\s*''' + RegExp.escape(key) + r'''\s*=\s*\[(.*?)\]''',
    multiLine: true,
    dotAll: true,
  ).firstMatch(config);
  if (match == null) return const [];
  return parseMaidCafeTomlStringArray(match.group(1)!);
}

/// Parses a TOML array of basic strings (single- or multi-line) into its
/// values, honoring `\"`, `\\`, `\n`, `\t` and `\r` escapes. Values are
/// trimmed; empty entries are dropped.
List<String> parseMaidCafeTomlStringArray(String raw) {
  final result = <String>[];
  final buffer = StringBuffer();
  var inString = false;
  var escaped = false;
  for (final rune in raw.runes) {
    final char = String.fromCharCode(rune);
    if (escaped) {
      buffer.write(switch (char) {
        'n' => '\n',
        't' => '\t',
        'r' => '\r',
        '"' => '"',
        r'\' => r'\',
        _ => char,
      });
      escaped = false;
      continue;
    }
    if (char == r'\') {
      escaped = true;
      continue;
    }
    if (char == '"') {
      inString = !inString;
      continue;
    }
    if (inString) {
      buffer.write(char);
      continue;
    }
    if (char == ',') {
      result.add(buffer.toString().trim());
      buffer.clear();
    }
  }
  if (buffer.isNotEmpty) result.add(buffer.toString().trim());
  return result.where((value) => value.isNotEmpty).toList();
}

/// HTTP client for the systemd-managed MaidCafe daemon.
///
/// The daemon's plaintext HTTP endpoint is never contacted directly: every
/// session goes through a short-lived SSH local TCP forward so requests only
/// travel inside the encrypted SSH channel (or a Tailscale / MaidKit cloud
/// relay path set up by the caller).
class MaidCafeStreamSession {
  MaidCafeStreamSession._(
    this._manager,
    this._forward,
    this._dio,
    this._apiSecret,
  );

  static const _remoteHost = '127.0.0.1';

  final SshConnectionManager _manager;
  final ActivePortForward? _forward;
  final Dio _dio;
  final String? _apiSecret;
  var _closed = false;
  String? _version;
  http.Client? _streamClient;
  final Set<StreamSubscription<MaidCafeStreamEvent>>
  _activeStreamSubscriptions = {};

  String? get apiSecret => _apiSecret;

  /// Whether [close] has been called; a closed session cannot be reused.
  bool get isClosed => _closed;

  static Future<MaidCafeStreamSession> open({
    required SshConnectionManager manager,
    required Server server,
    int? port,
    String? apiSecret,
    String? sudoPassword,
  }) async {
    final access = await readMaidCafeConfig(
      manager: manager,
      server: server,
      sudoPassword: sudoPassword,
    );
    final resolvedPort = port ?? access.port ?? maidCafeDefaultPort;
    final primarySecret = apiSecret ?? access.apiSecret;
    final configSecret = access.apiSecret;
    try {
      return await _openWithSecret(
        manager,
        server,
        resolvedPort,
        primarySecret,
      );
    } on MaidCafeUnauthorizedException {
      if (configSecret == null || configSecret == primarySecret) {
        rethrow;
      }
      // The stored secret is stale; the daemon accepts the one from its own
      // config file, so retry with that. The caller persists the winner.
      return await _openWithSecret(manager, server, resolvedPort, configSecret);
    }
  }

  static Future<MaidCafeStreamSession> _openWithSecret(
    SshConnectionManager manager,
    Server server,
    int resolvedPort,
    String? resolvedSecret,
  ) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      ActivePortForward? forward;
      MaidCafeStreamSession? connection;
      try {
        forward = await manager.startPortForward(
          server: server,
          direction: PortForwardDirection.local,
          kind: PortForwardKind.tcp,
          bindHost: '127.0.0.1',
          bindPort: 0,
          targetHost: _remoteHost,
          targetPort: resolvedPort,
          owner: PortForwardOwner.maidCafe,
        );
        connection = MaidCafeStreamSession._(
          manager,
          forward,
          _newDio(
            'http://${forward.bindHost}:${forward.bindPort}',
            resolvedSecret,
          ),
          resolvedSecret,
        );
        await connection.health();
        return connection;
      } catch (error) {
        lastError = error;
        if (connection != null) {
          await connection.close();
        } else if (forward != null) {
          await manager.stopManagedPortForward(forward.id);
        }
        if (attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 250 * (attempt + 1)),
          );
        }
      }
    }
    Error.throwWithStackTrace(
      lastError ?? StateError('MaidCafe connection failed.'),
      StackTrace.current,
    );
  }

  static Dio _newDio(String baseUrl, String? apiSecret) => Dio(
    BaseOptions(
      baseUrl: baseUrl,
      headers: apiSecret == null
          ? null
          : <String, String>{'Authorization': 'Bearer $apiSecret'},
      connectTimeout: const Duration(seconds: 3),
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  String? get version => _version;

  Future<Map<String, dynamic>> health() async {
    final result = await _get('/health');
    final value = result['version']?.toString().trim();
    _version = value == null || value.isEmpty ? null : value;
    return result;
  }

  Future<Map<String, dynamic>> metrics() => _get('/api/v1/metrics');

  /// One-shot container list from the daemon (same payload as the `containers`
  /// SSE event). Use for first paint; the stream keeps it fresh afterwards.
  Future<Map<String, dynamic>> containers() => _get('/api/v1/containers');

  /// One-shot image list from the daemon (same payload as the `images`
  /// SSE event).
  Future<Map<String, dynamic>> images() => _get('/api/v1/images');

  /// One-shot top-processes snapshot (same payload as the `processes` event).
  Future<Map<String, dynamic>> processes() => _get('/api/v1/processes');

  /// One-shot systemd unit snapshot (same payload as the `systemd` event).
  Future<Map<String, dynamic>> systemd() => _get('/api/v1/systemd');

  Future<List<Map<String, dynamic>>> metricsHistory({
    int limit = 60,
    DateTime? from,
    DateTime? to,
    DateTime? before,
  }) async {
    final query = <String, String>{'limit': '$limit'};
    if (from != null) query['from'] = from.toUtc().toIso8601String();
    if (to != null) query['to'] = to.toUtc().toIso8601String();
    if (before != null) {
      query['before'] = before.toUtc().toIso8601String();
    }
    final result = await _get(
      Uri(path: '/api/v1/metrics/history', queryParameters: query).toString(),
    );
    final metrics = result['metrics'];
    if (metrics is! List) {
      throw StateError('MaidCafe returned an invalid metrics history.');
    }
    return [
      for (final item in metrics)
        if (item is Map)
          item.map((key, value) => MapEntry(key.toString(), value)),
    ];
  }

  /// Recent execution audit entries, newest first, from the daemon's durable
  /// audit log.
  Future<List<MaidCafeAuditEntry>> audit({int limit = 50}) async {
    final result = await _get('/api/v1/audit?limit=$limit');
    final entries = result['entries'];
    if (entries is! List) {
      throw StateError('MaidCafe returned an invalid audit log.');
    }
    return [
      for (final item in entries)
        if (item is Map)
          MaidCafeAuditEntry.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
    ];
  }

  /// Wipes the daemon's audit log (active and rotated files).
  Future<void> clearAudit() async {
    await _delete('/api/v1/audit');
  }

  /// Opens a realtime SSE subscription over the session's port forward.
  ///
  /// Returns a single-subscription stream of decoded frames. The request
  /// header phase is guarded by a 10s timeout; after that, connection errors
  /// and non-200 responses surface through the stream's `onError` (HTTP 401
  /// becomes [MaidCafeUnauthorizedException]). There is no auto-reconnect —
  /// the consumer owns reconnection. The stream ends when the session is
  /// closed.
  Stream<MaidCafeStreamEvent> openStream({
    Set<MaidCafeStreamEventType> events = maidCafeStreamAllEvents,
  }) {
    _throwIfClosed();
    final forward = _forward;
    if (forward == null) {
      throw StateError('MaidCafe session has no active port forward.');
    }
    // `hello` is always sent first regardless of the filter and is not part
    // of the daemon whitelist; omitting the param entirely means "all".
    final requested = events
        .where((event) => event != MaidCafeStreamEventType.hello)
        .toList();
    final uri = Uri(
      scheme: 'http',
      host: forward.bindHost,
      port: forward.bindPort,
      path: '/api/v1/stream',
      queryParameters: requested.isEmpty
          ? null
          : <String, String>{
              'events': requested.map((event) => event.name).join(','),
            },
    );
    final request = http.Request('GET', uri);
    final secret = _apiSecret;
    if (secret != null) request.headers['Authorization'] = 'Bearer $secret';
    request.headers['Accept'] = 'text/event-stream';

    final controller = StreamController<MaidCafeStreamEvent>();
    StreamSubscription<MaidCafeStreamEvent>? frameSubscription;
    var cancelled = false;

    Future<void> connect() async {
      try {
        final client = _streamClient ??= http.Client();
        // Guard only the header phase: an SSE body never completes.
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) {
          // Drain the (small) error body so the connection can be reused.
          unawaited(response.stream.drain<void>().catchError((_) {}));
          throw response.statusCode == 401
              ? const MaidCafeUnauthorizedException()
              : StateError(
                  'MaidCafe stream request failed '
                  '(${response.statusCode}).',
                );
        }
        frameSubscription = parseMaidCafeSseFrames(response.stream).listen(
          controller.add,
          onError: (Object error, StackTrace stackTrace) {
            // Closing the shared HTTP client while a response is mid-read
            // surfaces ClientException on the socket stream. During teardown
            // (session close or consumer cancel) that is expected, not an
            // error: swallow it so it never escapes as an unhandled error.
            if (cancelled || _closed) return;
            controller.addError(error, stackTrace);
          },
          onDone: controller.close,
        );
        if (cancelled) {
          unawaited(frameSubscription!.cancel());
        } else {
          _activeStreamSubscriptions.add(frameSubscription!);
        }
      } catch (error, stackTrace) {
        if (!controller.isClosed) {
          controller.addError(error, stackTrace);
          await controller.close();
        }
      }
    }

    controller.onCancel = () {
      cancelled = true;
      final subscription = frameSubscription;
      if (subscription != null) {
        _activeStreamSubscriptions.remove(subscription);
        unawaited(subscription.cancel());
      }
    };

    unawaited(connect());
    return controller.stream;
  }

  Future<Map<String, dynamic>> invokeAction(
    String name, {
    Object? body,
    String? invokedBy,
  }) async {
    final payload = body == null ? '' : jsonEncode(body);
    final secret = _apiSecret;
    final signature = secret == null
        ? null
        : await maidCafeHmacSignature(secret, utf8.encode(payload));
    return _post(
      '/api/v1/actions/${Uri.encodeComponent(name)}',
      body: payload,
      headers: {
        'X-MaidCafe-Signature': ?signature,
        'X-MaidCafe-Invoked-By': ?invokedBy,
      },
    );
  }

  /// Pushes a test notification through the cloud to Ring/Metoer, verifying
  /// the whole daemon -> cloud -> notification-feed pipeline on demand.
  Future<void> sendTestNotification() =>
      _post('/api/v1/notifications/test').then((_) {});

  Future<Map<String, dynamic>> _get(String path) async {
    _throwIfClosed();
    try {
      final response = await _dio.get<Object?>(path);
      return _responseMap(response);
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        throw const MaidCafeUnauthorizedException();
      }
      throw StateError(_dioError(error));
    }
  }

  Future<Map<String, dynamic>> _post(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    _throwIfClosed();
    try {
      final response = await _dio.post<Object?>(
        path,
        data: body,
        options: Options(
          headers: headers,
          contentType: Headers.jsonContentType,
        ),
      );
      return _responseMap(response);
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        throw const MaidCafeUnauthorizedException();
      }
      throw StateError(_dioError(error));
    }
  }

  Future<Map<String, dynamic>> _delete(String path) async {
    _throwIfClosed();
    try {
      final response = await _dio.delete<Object?>(path);
      return _responseMap(response);
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        throw const MaidCafeUnauthorizedException();
      }
      throw StateError(_dioError(error));
    }
  }

  Map<String, dynamic> _responseMap(Response<Object?> response) {
    final status = response.statusCode ?? 500;
    final data = response.data;
    if (status >= 400) {
      final message = data is Map ? data['error']?.toString() : null;
      throw StateError(message ?? 'MaidCafe HTTP request failed ($status).');
    }
    if (data is! Map) {
      throw StateError('MaidCafe returned an invalid response.');
    }
    return data.map((key, value) => MapEntry(key.toString(), value));
  }

  String _dioError(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['error'] != null) {
      return data['error'].toString();
    }
    return error.message ?? 'MaidCafe HTTP request failed.';
  }

  void _throwIfClosed() {
    if (_closed) throw StateError('MaidCafe session is closed.');
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final subscriptions = _activeStreamSubscriptions.toList();
    _activeStreamSubscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    final streamClient = _streamClient;
    _streamClient = null;
    if (streamClient != null) {
      // Let the cancelled SSE subscriptions detach from their sockets before
      // the shared client destroys them; the swallow above covers any error
      // that still lands mid-read.
      await Future<void>.delayed(Duration.zero);
      streamClient.close();
    }
    _dio.close(force: true);
    final forward = _forward;
    if (forward != null) {
      await _manager.stopManagedPortForward(forward.id);
    }
  }
}
