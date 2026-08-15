import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/port_forwarding_models.dart';
import 'package:maid_kit/servers/ssh_connection_manager.dart';

import 'maidcafe_install.dart';
import 'maidcafe_service.dart';

const maidCafeDefaultPort = 8747;

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
}

/// Reads the daemon's HTTP endpoint and API secret over SSH.
Future<MaidCafeDaemonAccess> readMaidCafeConfig({
  required SshConnectionManager manager,
  required Server server,
}) => manager.withClient(server.id, (client) async {
  final session = await client.execute(
    r'''sed -n '/^\[daemon\]/,/^\[/p' /etc/maidcafe/config.toml /etc/maidcafe/config.stdio.toml 2>/dev/null || true''',
  );
  try {
    final config = await utf8.decoder.bind(session.stdout).join();
    await session.done.timeout(const Duration(seconds: 5));
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
      actions: _configActions(config),
    );
  } finally {
    session.close();
  }
});

Future<int?> readMaidCafeListenPort({
  required SshConnectionManager manager,
  required Server server,
}) async => (await readMaidCafeConfig(manager: manager, server: server)).port;

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

List<String> _configArray(String config, String key) {
  final match = RegExp(
    r'^\s*' + RegExp.escape(key) + r'\s*=\s*\[(.*?)\]\s*$',
    multiLine: true,
    dotAll: true,
  ).firstMatch(config);
  if (match == null) return const [];
  return RegExp(r'"((?:\\.|[^"])*)"')
      .allMatches(match.group(1)!)
      .map((match) => match.group(1)!.replaceAll(r'\"', '"'))
      .toList();
}

List<MaidCafeActionDefinition> _configActions(String config) {
  final blocks = RegExp(
    r'\[\[daemon\.actions\]\](.*?)(?=\n\[\[daemon\.actions\]\]|$)',
    dotAll: true,
  ).allMatches(config);
  return [
    for (final block in blocks)
      if (_configValue(block.group(1)!, 'name') != null &&
          _configValue(block.group(1)!, 'command') != null)
        MaidCafeActionDefinition(
          name: _configValue(block.group(1)!, 'name')!,
          command: _configValue(block.group(1)!, 'command')!,
          arguments: _configArray(block.group(1)!, 'args'),
          enabled: _configBool(block.group(1)!, 'enabled', fallback: true),
          notifyOnSuccess: _configBool(block.group(1)!, 'notifyOnSuccess'),
          notifyOnFailure: _configBool(block.group(1)!, 'notifyOnFailure'),
        ),
  ];
}

/// HTTP client for the systemd-managed MaidCafe daemon.
///
/// MaidKit first tries the configured server address directly. If the daemon
/// is loopback-only or the host is not reachable from this computer, it falls
/// back to a short-lived SSH local TCP forward.
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

  String? get apiSecret => _apiSecret;

  static Future<MaidCafeStreamSession> open({
    required SshConnectionManager manager,
    required Server server,
    int? port,
    String? apiSecret,
  }) async {
    final access = await readMaidCafeConfig(manager: manager, server: server);
    final resolvedPort = port ?? access.port ?? maidCafeDefaultPort;
    final resolvedSecret = apiSecret ?? access.apiSecret;
    final direct = await _tryDirect(
      manager,
      server,
      resolvedPort,
      resolvedSecret,
    );
    if (direct != null) return direct;

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

  static Future<MaidCafeStreamSession?> _tryDirect(
    SshConnectionManager manager,
    Server server,
    int port,
    String? apiSecret,
  ) async {
    final host = server.host.contains(':') && !server.host.startsWith('[')
        ? '[${server.host}]'
        : server.host;
    final connection = MaidCafeStreamSession._(
      manager,
      null,
      _newDio('http://$host:$port', apiSecret),
      apiSecret,
    );
    try {
      await connection.health();
      return connection;
    } catch (_) {
      await connection.close();
      return null;
    }
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

  Future<List<Map<String, dynamic>>> metricsHistory({int limit = 60}) async {
    final result = await _get('/api/v1/metrics/history?limit=$limit');
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

  Future<Map<String, dynamic>> invokeAction(String name, {Object? body}) =>
      _post('/api/v1/actions/${Uri.encodeComponent(name)}', body: body);

  Future<Map<String, dynamic>> _get(String path) async {
    _throwIfClosed();
    try {
      final response = await _dio.get<Object?>(path);
      return _responseMap(response);
    } on DioException catch (error) {
      throw StateError(_dioError(error));
    }
  }

  Future<Map<String, dynamic>> _post(String path, {Object? body}) async {
    _throwIfClosed();
    try {
      final response = await _dio.post<Object?>(path, data: body);
      return _responseMap(response);
    } on DioException catch (error) {
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
    _dio.close(force: true);
    final forward = _forward;
    if (forward != null) {
      await _manager.stopManagedPortForward(forward.id);
    }
  }
}
