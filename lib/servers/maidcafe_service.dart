import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../containers/container_list_tile.dart';
import '../containers/container_models.dart';
import 'cloud_sync_service.dart';
import 'server_models.dart';
import 'systemd_models.dart';

const maidCafeMinimumPort = 1024;
const maidCafeDefaultCloudUrl = 'https://mk.solsynth.dev';
const maidCafeDefaultLocalDaemonUrl = 'http://127.0.0.1:8747';

/// HMAC-SHA256 signature over [data] keyed by [secret], lowercase hex.
///
/// Webhook and action invocations are authenticated with this signature; the
/// transport (SSH tunnel, Tailscale or the MaidKit cloud relay) provides
/// confidentiality.
Future<String> maidCafeHmacSignature(String secret, List<int> data) async {
  final mac = await Hmac.sha256().calculateMac(
    data,
    secretKey: SecretKey(utf8.encode(secret)),
  );
  return mac.bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

class MaidCafeException implements Exception {
  const MaidCafeException(
    this.message, {
    this.kind = MaidCafeErrorKind.unknown,
    this.statusCode,
    this.cause,
  });

  final String message;
  final MaidCafeErrorKind kind;
  final int? statusCode;
  final Object? cause;

  @override
  String toString() => 'MaidCafeException: $message';
}

enum MaidCafeErrorKind {
  signInRequired,
  http,
  invalidResponse,
  timeout,
  network,
  validation,
  unknown,
}

class MaidCafeDaemon {
  const MaidCafeDaemon({
    required this.id,
    required this.name,
    required this.enabled,
    required this.lastSeenAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final bool enabled;
  final DateTime? lastSeenAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory MaidCafeDaemon.fromJson(Map<String, dynamic> json) => MaidCafeDaemon(
    id: _requiredString(json, 'id'),
    name: _requiredString(json, 'name'),
    enabled: _requiredBool(json, 'enabled'),
    lastSeenAt: _optionalDate(json, 'last_seen_at'),
    createdAt: _requiredDate(json, 'created_at'),
    updatedAt: _requiredDate(json, 'updated_at'),
  );
}

class MaidCafeDaemonCredential extends MaidCafeDaemon {
  const MaidCafeDaemonCredential({
    required super.id,
    required super.name,
    required super.enabled,
    required super.lastSeenAt,
    required super.createdAt,
    required super.updatedAt,
    required this.secret,
  });

  final String secret;

  factory MaidCafeDaemonCredential.fromJson(Map<String, dynamic> json) {
    final daemon = MaidCafeDaemon.fromJson(json);
    final secret = _requiredString(json, 'secret');
    return MaidCafeDaemonCredential(
      id: daemon.id,
      name: daemon.name,
      enabled: daemon.enabled,
      lastSeenAt: daemon.lastSeenAt,
      createdAt: daemon.createdAt,
      updatedAt: daemon.updatedAt,
      secret: secret,
    );
  }
}

class MaidCafeNotification {
  const MaidCafeNotification({
    required this.id,
    required this.accountId,
    required this.daemonId,
    required this.kind,
    required this.title,
    required this.body,
    required this.metadata,
    required this.readAt,
    required this.createdAt,
  });

  final String id;
  final String accountId;
  final String daemonId;
  final String kind;
  final String title;
  final String body;
  final Map<String, dynamic> metadata;
  final DateTime? readAt;
  final DateTime createdAt;

  factory MaidCafeNotification.fromJson(Map<String, dynamic> json) =>
      MaidCafeNotification(
        id: _requiredString(json, 'id'),
        accountId: _requiredString(json, 'account_id'),
        daemonId: _requiredString(json, 'daemon_id'),
        kind: _requiredString(json, 'kind'),
        title: _requiredString(json, 'title'),
        body: _requiredString(json, 'body'),
        metadata: _metadata(json['metadata']),
        readAt: _optionalDate(json, 'read_at'),
        createdAt: _requiredDate(json, 'created_at'),
      );

  bool get unread => readAt == null;
}

/// One action the daemon reported to the cloud for listing. The script body
/// and any secret stay on the host; the cloud page invokes it through the
/// webhook relay by name.
class MaidCafeCloudAction {
  const MaidCafeCloudAction({
    required this.name,
    required this.displayName,
    required this.enabled,
    required this.notifyOnSuccess,
    required this.notifyOnFailure,
    required this.timeout,
    required this.cwd,
    required this.user,
    required this.updatedAt,
  });

  final String name;
  final String displayName;
  final bool enabled;
  final bool notifyOnSuccess;
  final bool notifyOnFailure;
  final String timeout;
  final String cwd;
  final String user;
  final DateTime? updatedAt;

  String get label => displayName.isNotEmpty ? displayName : name;

  factory MaidCafeCloudAction.fromJson(Map<String, dynamic> json) =>
      MaidCafeCloudAction(
        name: _requiredString(json, 'name'),
        displayName: json['display_name']?.toString() ?? '',
        enabled: json['enabled'] == true,
        notifyOnSuccess: json['notify_on_success'] == true,
        notifyOnFailure: json['notify_on_failure'] == true,
        timeout: json['timeout']?.toString() ?? '',
        cwd: json['cwd']?.toString() ?? '',
        user: json['user']?.toString() ?? '',
        updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
      );
}

/// A user-level API credential for CI/CD: a labeled token scoped to a
/// subset of daemons, hosts and action names. The plain token is returned
/// once at creation ([token] is empty on list responses).
class MaidCafeCredential {
  const MaidCafeCredential({
    required this.id,
    required this.label,
    required this.daemonIds,
    required this.hostIds,
    required this.actionNames,
    required this.createdAt,
    this.lastUsedAt,
    this.token = '',
  });

  final String id;
  final String label;
  final List<String> daemonIds;
  final List<String> hostIds;
  final List<String> actionNames;
  final DateTime createdAt;
  final DateTime? lastUsedAt;

  /// One-time plain token, present only on the create response.
  final String token;

  factory MaidCafeCredential.fromJson(Map<String, dynamic> json) =>
      MaidCafeCredential(
        id: _requiredString(json, 'id'),
        label: json['label']?.toString() ?? '',
        daemonIds: _stringList(json['daemon_ids']),
        hostIds: _stringList(json['host_ids']),
        actionNames: _stringList(json['action_names']),
        createdAt:
            _optionalDate(json, 'created_at') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        lastUsedAt: _optionalDate(json, 'last_used_at'),
        token: json['token']?.toString() ?? '',
      );
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return [for (final entry in value) entry.toString()];
}

class MaidCafeMetric {
  const MaidCafeMetric({
    required this.id,
    required this.daemonId,
    required this.sentAt,
    required this.receivedAt,
    required this.uptimeSeconds,
    required this.processMemoryBytes,
    required this.cpuPercent,
    this.cpuCount = 0,
    this.load1 = 0,
    this.load5 = 0,
    this.load15 = 0,
    required this.memoryUsedPercent,
    required this.memoryUsedBytes,
    required this.memoryTotalBytes,
    this.swapTotalKb = 0,
    this.swapFreeKb = 0,
    this.diskTotalKb = 0,
    this.diskAvailableKb = 0,
    this.netRxBytes = 0,
    this.netTxBytes = 0,
    required this.webhookExecutions,
    required this.webhookFailures,
  });

  final String id;
  final String daemonId;
  final DateTime sentAt;
  final DateTime receivedAt;
  final int uptimeSeconds;
  final int processMemoryBytes;
  final double cpuPercent;
  final int cpuCount;
  final double load1;
  final double load5;
  final double load15;
  final double memoryUsedPercent;
  final int memoryUsedBytes;
  final int memoryTotalBytes;
  final int swapTotalKb;
  final int swapFreeKb;
  final int diskTotalKb;
  final int diskAvailableKb;
  final int netRxBytes;
  final int netTxBytes;
  final int webhookExecutions;
  final int webhookFailures;

  factory MaidCafeMetric.fromJson(Map<String, dynamic> json) => MaidCafeMetric(
    id: _requiredString(json, 'id'),
    daemonId: _requiredString(json, 'daemon_id'),
    sentAt: _requiredDate(json, 'sent_at'),
    receivedAt: _requiredDate(json, 'received_at'),
    uptimeSeconds: _requiredInt(json, 'uptime_seconds'),
    processMemoryBytes: _requiredInt(json, 'process_memory_bytes'),
    cpuPercent: _requiredNum(json, 'cpu_percent').toDouble(),
    cpuCount: _optionalInt(json, 'cpu_count'),
    load1: _optionalNum(json, 'load1')?.toDouble() ?? 0,
    load5: _optionalNum(json, 'load5')?.toDouble() ?? 0,
    load15: _optionalNum(json, 'load15')?.toDouble() ?? 0,
    memoryUsedPercent: _requiredNum(json, 'memory_used_percent').toDouble(),
    memoryUsedBytes: _requiredInt(json, 'memory_used_bytes'),
    memoryTotalBytes: _requiredInt(json, 'memory_total_bytes'),
    swapTotalKb: _optionalInt(json, 'swap_total_kb'),
    swapFreeKb: _optionalInt(json, 'swap_free_kb'),
    diskTotalKb: _optionalInt(json, 'disk_total_kb'),
    diskAvailableKb: _optionalInt(json, 'disk_available_kb'),
    netRxBytes: _optionalInt(json, 'net_rx_bytes'),
    netTxBytes: _optionalInt(json, 'net_tx_bytes'),
    webhookExecutions: _requiredInt(json, 'webhook_executions'),
    webhookFailures: _requiredInt(json, 'webhook_failures'),
  );
}

class MaidCafeDaemonHealth {
  const MaidCafeDaemonHealth({
    required this.ok,
    required this.mode,
    required this.id,
    required this.raw,
  });

  final bool ok;
  final String? mode;
  final String? id;
  final Map<String, dynamic> raw;

  factory MaidCafeDaemonHealth.fromJson(Map<String, dynamic> json) =>
      MaidCafeDaemonHealth(
        ok: _requiredBool(json, 'ok'),
        mode: json['mode'] as String?,
        id: json['id'] as String?,
        raw: Map<String, dynamic>.unmodifiable(json),
      );
}

class MaidCafeWebhookResult {
  const MaidCafeWebhookResult({
    required this.statusCode,
    required this.body,
    required this.headers,
    this.error,
  });

  final int statusCode;
  final Uint8List body;
  final Map<String, List<String>> headers;

  /// Remote execution error, e.g. a failed script or rejected signature.
  final String? error;

  bool get isSuccess => statusCode == 200;
  String get text => utf8.decode(body, allowMalformed: true);
}

class MaidCafeService {
  MaidCafeService({
    required String baseUrl,
    required this._cloudSync,
    Dio? dio,
    FlutterSecureStorage? secureStorage,
    this._accessToken,
  }) : baseUrl = normalizeMaidCafeUrl(baseUrl),
       _dio = dio ?? Dio(),
       _secureStorage = secureStorage ?? const FlutterSecureStorage() {
    _dio.options.connectTimeout ??= const Duration(seconds: 10);
    _dio.options.sendTimeout ??= const Duration(seconds: 10);
    _dio.options.receiveTimeout ??= const Duration(seconds: 15);
  }

  final String baseUrl;
  final CloudSyncService _cloudSync;
  final Future<String?> Function()? _accessToken;
  final Dio _dio;
  final FlutterSecureStorage _secureStorage;

  String get _apiBase => '$baseUrl/api';
  Future<MaidCafeDaemonHealth> checkCloudHealth() async {
    final response = await _localRequest(
      () => _dio.get<dynamic>('$baseUrl/health'),
    );
    return MaidCafeDaemonHealth.fromJson(_responseMap(response));
  }

  Future<MaidCafeDaemonCredential> createDaemon({
    required String name,
    required String workspaceId,
  }) async {
    final response = await _cloudRequest(
      (token) => _dio.post<dynamic>(
        '$_apiBase/daemons',
        data: {'workspace_id': workspaceId, 'name': name},
        options: _cloudOptions(token),
      ),
    );
    final credential = MaidCafeDaemonCredential.fromJson(
      _responseMap(response),
    );
    await _writeCloudSecret(credential.id, credential.secret);
    return credential;
  }

  Future<List<MaidCafeDaemon>> listDaemons({
    required String workspaceId,
  }) async {
    final response = await _cloudRequest(
      (token) => _dio.get<dynamic>(
        '$_apiBase/daemons',
        queryParameters: {'workspace_id': workspaceId},
        options: _cloudOptions(token),
      ),
    );
    final data = _responseJson(response);
    if (data is! List) {
      throw _invalidResponse('Expected a daemon list.');
    }
    return data
        .map((item) => MaidCafeDaemon.fromJson(_map(item)))
        .toList(growable: false);
  }

  Future<List<MaidCafeMetric>> listMetrics(
    String daemonId, {
    int limit = 100,
    DateTime? before,
  }) async {
    if (limit < 1 || limit > 100) {
      throw const MaidCafeException(
        'Metric limit must be between 1 and 100.',
        kind: MaidCafeErrorKind.validation,
      );
    }
    final response = await _cloudRequest(
      (token) => _dio.get<dynamic>(
        '$_apiBase/daemons/${_pathPart(daemonId)}/metrics',
        queryParameters: {
          'limit': limit,
          if (before != null) 'before': before.toUtc().toIso8601String(),
        },
        options: _cloudOptions(token),
      ),
    );
    final data = _responseJson(response);
    if (data is! List) throw _invalidResponse('Expected a metric list.');
    return data
        .map((item) => MaidCafeMetric.fromJson(_map(item)))
        .toList(growable: false);
  }

  Future<MaidCafeNotification> requestPushNotification(
    String daemonId, {
    required String kind,
    required String title,
    required String body,
    Map<String, dynamic> metadata = const {},
  }) async {
    final response = await _cloudRequest(
      (token) => _dio.post<dynamic>(
        '$_apiBase/daemons/${_pathPart(daemonId)}/push-notification',
        data: {
          'kind': kind,
          'title': title,
          'body': body,
          'metadata': metadata,
        },
        options: _cloudOptions(token),
      ),
    );
    return MaidCafeNotification.fromJson(_responseMap(response));
  }

  Future<MaidCafeDaemon> getDaemon(String daemonId) async {
    final response = await _cloudRequest(
      (token) => _dio.get<dynamic>(
        '$_apiBase/daemons/${_pathPart(daemonId)}',
        options: _cloudOptions(token),
      ),
    );
    return MaidCafeDaemon.fromJson(_responseMap(response));
  }

  Future<MaidCafeDaemon> updateDaemon(
    String daemonId, {
    String? name,
    bool? enabled,
  }) async {
    if (name == null && enabled == null) {
      throw const MaidCafeException(
        'At least one daemon field must be provided.',
        kind: MaidCafeErrorKind.validation,
      );
    }
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (enabled != null) data['enabled'] = enabled;
    final response = await _cloudRequest(
      (token) => _dio.patch<dynamic>(
        '$_apiBase/daemons/${_pathPart(daemonId)}',
        data: data,
        options: _cloudOptions(token),
      ),
    );
    final daemon = MaidCafeDaemon.fromJson(_responseMap(response));
    if (enabled == false) await _deleteCloudSecret(daemon.id);
    return daemon;
  }

  Future<String> rotateDaemonSecret(String daemonId) async {
    final response = await _cloudRequest(
      (token) => _dio.post<dynamic>(
        '$_apiBase/daemons/${_pathPart(daemonId)}/rotate-secret',
        options: _cloudOptions(token),
      ),
    );
    final secret = _requiredString(_responseMap(response), 'secret');
    await _writeCloudSecret(daemonId, secret);
    return secret;
  }

  Future<void> disableDaemon(String daemonId) async {
    await _cloudRequest(
      (token) => _dio.delete<dynamic>(
        '$_apiBase/daemons/${_pathPart(daemonId)}',
        options: _cloudOptions(token),
      ),
    );
    await _deleteCloudSecret(daemonId);
  }

  Future<MaidCafeDaemonHealth> checkDaemonHealth({
    String daemonBaseUrl = maidCafeDefaultLocalDaemonUrl,
  }) async {
    final response = await _localRequest(
      () => _dio.get<dynamic>(
        '${normalizeMaidCafeLocalDaemonUrl(daemonBaseUrl)}/health',
      ),
    );
    return MaidCafeDaemonHealth.fromJson(_responseMap(response));
  }

  Future<MaidCafeWebhookResult> invokeWebhook({
    required String daemonBaseUrl,
    required String webhookName,
    required String localWebhookSecret,
    required List<int> payload,
  }) async {
    if (webhookName.trim().isEmpty) {
      throw const MaidCafeException(
        'Webhook name is required.',
        kind: MaidCafeErrorKind.validation,
      );
    }
    if (localWebhookSecret.trim().isEmpty) {
      throw const MaidCafeException(
        'Local webhook secret is required.',
        kind: MaidCafeErrorKind.validation,
      );
    }
    final signature = await maidCafeHmacSignature(
      localWebhookSecret.trim(),
      payload,
    );
    final response = await _localRequest(
      () => _dio.post<List<int>>(
        '${normalizeMaidCafeLocalDaemonUrl(daemonBaseUrl)}/api/v1/webhooks/${_pathPart(webhookName)}',
        data: Uint8List.fromList(payload),
        options: Options(
          headers: {
            'X-MaidCafe-Signature': signature,
            'Content-Type': 'application/octet-stream',
          },
          responseType: ResponseType.bytes,
        ),
      ),
      acceptStatuses: const {200},
    );
    final body = response.data;
    return MaidCafeWebhookResult(
      statusCode: response.statusCode ?? 200,
      body: Uint8List.fromList(body is List<int> ? body : const <int>[]),
      headers: response.headers.map.map(
        (key, values) => MapEntry(key, List<String>.from(values)),
      ),
    );
  }

  /// Enqueues a signed webhook invocation on the MaidKit cloud relay; the
  /// daemon polls the cloud (every 60s) and executes the webhook locally.
  /// Returns the relay request id to poll with [waitForWebhookResult].
  Future<String> enqueueWebhookRequest({
    required String daemonId,
    required String webhookName,
    required String webhookSecret,
    required List<int> payload,
  }) async {
    if (webhookName.trim().isEmpty) {
      throw const MaidCafeException(
        'Webhook name is required.',
        kind: MaidCafeErrorKind.validation,
      );
    }
    if (webhookSecret.trim().isEmpty) {
      throw const MaidCafeException(
        'Webhook secret is required.',
        kind: MaidCafeErrorKind.validation,
      );
    }
    final signature = await maidCafeHmacSignature(
      webhookSecret.trim(),
      payload,
    );
    final response = await _cloudRequest(
      (token) => _dio.post<dynamic>(
        '$_apiBase/daemons/${_pathPart(daemonId)}/webhook-requests',
        data: {
          'name': webhookName.trim(),
          'body': base64Encode(payload),
          'signature': signature,
        },
        options: _cloudOptions(token),
      ),
    );
    final data = _responseMap(response);
    final id = data['id']?.toString();
    if (id == null || id.isEmpty) {
      throw const MaidCafeException(
        'The cloud did not return a webhook request id.',
        kind: MaidCafeErrorKind.invalidResponse,
      );
    }
    return id;
  }

  /// Creates a labeled API credential with optional scope lists; the
  /// one-time plain token is returned in [MaidCafeCredential.token].
  Future<MaidCafeCredential> createCredential({
    required String label,
    List<String> daemonIds = const [],
    List<String> hostIds = const [],
    List<String> actionNames = const [],
  }) async {
    final response = await _cloudRequest(
      (token) => _dio.post<dynamic>(
        '$_apiBase/credentials',
        data: {
          'label': label,
          'daemon_ids': daemonIds,
          'host_ids': hostIds,
          'action_names': actionNames,
        },
        options: _cloudOptions(token),
      ),
    );
    return MaidCafeCredential.fromJson(_responseMap(response));
  }

  Future<List<MaidCafeCredential>> listCredentials() async {
    final response = await _cloudRequest(
      (token) => _dio.get<dynamic>(
        '$_apiBase/credentials',
        options: _cloudOptions(token),
      ),
    );
    final data = _responseJson(response);
    if (data is! List) {
      throw _invalidResponse('Expected a credential list.');
    }
    return data
        .map((item) => MaidCafeCredential.fromJson(_map(item)))
        .toList(growable: false);
  }

  Future<void> deleteCredential(String credentialId) async {
    await _cloudRequest(
      (token) => _dio.delete<dynamic>(
        '$_apiBase/credentials/${_pathPart(credentialId)}',
        options: _cloudOptions(token),
      ),
    );
  }

  /// Lists the actions the daemon reported to the cloud (see the daemon's
  /// action report on every metrics tick).
  Future<List<MaidCafeCloudAction>> listActions(String daemonId) async {
    final response = await _cloudRequest(
      (token) => _dio.get<dynamic>(
        '$_apiBase/daemons/${_pathPart(daemonId)}/actions',
        options: _cloudOptions(token),
      ),
    );
    final data = _responseJson(response);
    if (data is! List) {
      throw _invalidResponse('Expected an action list.');
    }
    return data
        .map((item) => MaidCafeCloudAction.fromJson(_map(item)))
        .toList(growable: false);
  }

  /// Invokes an action on the daemon through the cloud relay and waits for
  /// the result. Actions carry no secret, so the relay request is
  /// signature-less: the daemon runs it because it arrived through its own
  /// cloud-authenticated poll.
  Future<MaidCafeWebhookResult> invokeActionViaCloud({
    required String daemonId,
    required String actionName,
    Map<String, dynamic> body = const {},
  }) async {
    final name = actionName.trim();
    if (name.isEmpty) {
      throw const MaidCafeException(
        'Action name is required.',
        kind: MaidCafeErrorKind.validation,
      );
    }
    final payload = utf8.encode(jsonEncode(body));
    final response = await _cloudRequest(
      (token) => _dio.post<dynamic>(
        '$_apiBase/daemons/${_pathPart(daemonId)}/webhook-requests',
        data: {'name': name, 'body': base64Encode(payload), 'signature': ''},
        options: _cloudOptions(token),
      ),
    );
    final data = _responseMap(response);
    final id = data['id']?.toString();
    if (id == null || id.isEmpty) {
      throw const MaidCafeException(
        'The cloud did not return a webhook request id.',
        kind: MaidCafeErrorKind.invalidResponse,
      );
    }
    return waitForWebhookResult(daemonId: daemonId, requestId: id);
  }

  /// Polls the cloud until the relayed webhook reaches a terminal state or
  /// [timeout] elapses. The daemon polls for requests every 60s, so results
  /// typically appear within one interval.
  Future<MaidCafeWebhookResult> waitForWebhookResult({
    required String daemonId,
    required String requestId,
    Duration timeout = const Duration(minutes: 5),
    Duration interval = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final data = await _cloudRequest(
        (token) => _dio.get<dynamic>(
          '$_apiBase/daemons/${_pathPart(daemonId)}/webhook-requests/${_pathPart(requestId)}',
          options: _cloudOptions(token),
        ),
      );
      final result = _responseMap(data);
      if (result['status'] == 'done') {
        return MaidCafeWebhookResult(
          statusCode: (result['result_code'] as num?)?.toInt() ?? 0,
          body: Uint8List.fromList(
            base64Decode(result['result_body']?.toString() ?? ''),
          ),
          headers: const {},
          error: result['result_error']?.toString(),
        );
      }
      if (DateTime.now().isAfter(deadline)) {
        throw const MaidCafeException(
          'Timed out waiting for the relayed webhook.',
          kind: MaidCafeErrorKind.http,
        );
      }
      await Future<void>.delayed(interval);
    }
  }

  Future<String?> storedCloudSecret(String daemonId) =>
      _secureStorage.read(key: _cloudSecretKey(daemonId));

  Future<Response<T>> _cloudRequest<T>(
    Future<Response<T>> Function(String token) request,
  ) async {
    final token = await (_accessToken ?? _cloudSync.accessToken)();
    if (token == null || token.trim().isEmpty) {
      throw const MaidCafeException(
        'Sign in with Solarpass before managing MaidCafe.',
        kind: MaidCafeErrorKind.signInRequired,
      );
    }
    return _runRequest(() => request(token.trim()));
  }

  Options _cloudOptions(String token) =>
      Options(headers: {'Authorization': 'Bearer $token'});

  Future<Response<T>> _localRequest<T>(
    Future<Response<T>> Function() request, {
    Set<int> acceptStatuses = const {200},
  }) => _runRequest(request, acceptStatuses: acceptStatuses);

  Future<Response<T>> _runRequest<T>(
    Future<Response<T>> Function() request, {
    Set<int> acceptStatuses = const {200, 201, 204},
  }) async {
    try {
      final response = await request();
      final status = response.statusCode ?? 0;
      if (!acceptStatuses.contains(status)) {
        throw _httpError(status, response.data);
      }
      return response;
    } on MaidCafeException {
      rethrow;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status != null) throw _httpError(status, error.response?.data);
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        throw MaidCafeException(
          'MaidCafe request timed out.',
          kind: MaidCafeErrorKind.timeout,
          cause: error,
        );
      }
      throw MaidCafeException(
        'Could not reach MaidCafe.',
        kind: MaidCafeErrorKind.network,
        cause: error,
      );
    } on FormatException catch (error) {
      throw MaidCafeException(
        'MaidCafe returned invalid JSON.',
        kind: MaidCafeErrorKind.invalidResponse,
        cause: error,
      );
    } on TypeError catch (error) {
      throw MaidCafeException(
        'MaidCafe returned an unexpected response.',
        kind: MaidCafeErrorKind.invalidResponse,
        cause: error,
      );
    }
  }

  Future<void> _writeCloudSecret(String daemonId, String secret) =>
      _secureStorage.write(key: _cloudSecretKey(daemonId), value: secret);

  Future<void> _deleteCloudSecret(String daemonId) =>
      _secureStorage.delete(key: _cloudSecretKey(daemonId));

  String _cloudSecretKey(String daemonId) => 'maidcafe_cloud_secret_$daemonId';

  static String _pathPart(String value) => Uri.encodeComponent(value);
}

String normalizeMaidCafeUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw const MaidCafeException(
      'MaidCafe URL must not be empty.',
      kind: MaidCafeErrorKind.validation,
    );
  }
  final parsed = Uri.tryParse(trimmed);
  if (parsed == null ||
      parsed.host.isEmpty ||
      (parsed.scheme != 'http' && parsed.scheme != 'https') ||
      parsed.userInfo.isNotEmpty ||
      parsed.query.isNotEmpty ||
      parsed.fragment.isNotEmpty) {
    throw const MaidCafeException(
      'MaidCafe URL must be an absolute HTTP(S) URL without credentials or query parameters.',
      kind: MaidCafeErrorKind.validation,
    );
  }
  return trimmed.replaceFirst(RegExp(r'/+$'), '');
}

String normalizeMaidCafeCloudUrl(String value) {
  final normalized = normalizeMaidCafeUrl(value);
  final uri = Uri.parse(normalized);
  if (uri.scheme == 'http' && !_isLoopbackHost(uri.host)) {
    throw const MaidCafeException(
      'MaidCafe cloud hosts must use HTTPS.',
      kind: MaidCafeErrorKind.validation,
    );
  }
  return normalized;
}

String normalizeMaidCafeLocalDaemonUrl(String value) {
  final normalized = normalizeMaidCafeUrl(value);
  final uri = Uri.parse(normalized);
  if (uri.scheme == 'http' && !_isLoopbackHost(uri.host)) {
    throw const MaidCafeException(
      'Non-loopback local daemon targets must use HTTPS.',
      kind: MaidCafeErrorKind.validation,
    );
  }
  return normalized;
}

bool _isLoopbackHost(String host) =>
    host == 'localhost' || host == '127.0.0.1' || host == '::1';

Map<String, dynamic> _responseMap(Response<dynamic> response) =>
    _map(_responseJson(response));

Object? _responseJson(Response<dynamic> response) {
  final data = response.data;
  if (data is String) return jsonDecode(data);
  if (data is List<int>) return jsonDecode(utf8.decode(data));
  return data;
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, value) => MapEntry('$key', value));
  throw _invalidResponse('Expected a JSON object.');
}

MaidCafeException _invalidResponse(String message) =>
    MaidCafeException(message, kind: MaidCafeErrorKind.invalidResponse);

MaidCafeException _httpError(int status, Object? body) {
  var message = 'MaidCafe request failed with HTTP $status.';
  try {
    final decoded = body is String ? jsonDecode(body) : body;
    if (decoded is Map && decoded['error'] is String) {
      message = decoded['error'] as String;
    } else if (decoded is String && decoded.trim().isNotEmpty) {
      message = decoded;
    }
  } catch (_) {
    // Keep the actionable status fallback when the error body is not JSON.
  }
  return MaidCafeException(
    message,
    kind: MaidCafeErrorKind.http,
    statusCode: status,
  );
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw _invalidResponse('MaidCafe response field "$key" is missing.');
}

bool _requiredBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw _invalidResponse('MaidCafe response field "$key" is missing.');
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  throw _invalidResponse('MaidCafe response field "$key" is missing.');
}

num _requiredNum(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num) return value;
  throw _invalidResponse('MaidCafe response field "$key" is missing.');
}

/// Numeric field that older clouds or stored rows may omit; defaults to 0.
int _optionalInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is num ? value.toInt() : 0;
}

DateTime _requiredDate(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.toUtc();
  }
  throw _invalidResponse('MaidCafe response field "$key" is invalid.');
}

DateTime? _optionalDate(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) return DateTime.tryParse(value)?.toUtc();
  throw _invalidResponse('MaidCafe response field "$key" is invalid.');
}

Map<String, dynamic> _metadata(Object? value) {
  if (value == null) return <String, dynamic>{};
  if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
  if (value is Map) return value.map((key, value) => MapEntry('$key', value));
  throw _invalidResponse('MaidCafe notification metadata is invalid.');
}

/// Containers for one runtime from a `containers` event or endpoint.
class MaidCafeRuntimeContainers {
  const MaidCafeRuntimeContainers({
    required this.runtime,
    required this.available,
    this.error,
    this.containers = const [],
  });

  /// `"podman"` or `"docker"`.
  final String runtime;
  final bool available;

  /// Collection failure message when the runtime exists but could not be
  /// listed; null when the list is current.
  final String? error;
  final List<ServerContainer> containers;
}

/// Typed containers from a `containers` SSE event or `/api/v1/containers`.
///
/// [runtimes] covers every runtime found on the host (podman first); an empty
/// list means the daemon found no container runtime at all.
class MaidCafeContainersSnapshot {
  const MaidCafeContainersSnapshot({this.runtimes = const []});

  final List<MaidCafeRuntimeContainers> runtimes;

  bool get hasRuntimes => runtimes.isNotEmpty;
}

/// Typed processes from a `processes` SSE event.
class MaidCafeProcessesSnapshot {
  const MaidCafeProcessesSnapshot({this.processes = const []});

  final List<ServerProcess> processes;
}

/// Typed systemd units from a `systemd` SSE event.
class MaidCafeSystemdSnapshot {
  const MaidCafeSystemdSnapshot({
    required this.available,
    this.error,
    this.units = const [],
  });

  final bool available;
  final String? error;
  final List<SystemdUnit> units;
}

/// Tolerant parse of a `containers` SSE event or `/api/v1/containers` payload.
///
/// Malformed or incomplete container entries are skipped; missing scalar
/// fields fall back to null/empty values so one bad entry never aborts the
/// whole snapshot.
MaidCafeContainersSnapshot parseMaidCafeContainers(Map<String, dynamic> json) {
  final runtimes = <MaidCafeRuntimeContainers>[];
  final rawRuntimes = json['runtimes'];
  if (rawRuntimes is List) {
    for (final raw in rawRuntimes) {
      if (raw is! Map) continue;
      final entry = Map<String, dynamic>.from(raw);
      final runtime = _optionalString(entry, 'runtime');
      if (runtime == null) continue;
      final containers = <ServerContainer>[];
      final rawContainers = entry['containers'];
      if (rawContainers is List) {
        for (final rawContainer in rawContainers) {
          if (rawContainer is! Map) continue;
          final container = _parseSseContainer(
            Map<String, dynamic>.from(rawContainer),
          );
          if (container != null) containers.add(container);
        }
      }
      runtimes.add(
        MaidCafeRuntimeContainers(
          runtime: runtime,
          available: entry['available'] is bool
              ? entry['available'] as bool
              : true,
          error: _optionalString(entry, 'error'),
          containers: containers,
        ),
      );
    }
  }
  return MaidCafeContainersSnapshot(runtimes: runtimes);
}

ServerContainer? _parseSseContainer(Map<String, dynamic> json) {
  final id = _optionalString(json, 'id');
  final name = _optionalString(json, 'name');
  if (id == null || name == null) return null;
  return ServerContainer(
    id: id,
    name: name,
    image: _optionalString(json, 'image') ?? '',
    state: _optionalString(json, 'state') ?? '',
    status: _optionalString(json, 'status') ?? '',
    composeProject: _optionalString(json, 'compose_project'),
  );
}

/// Images for one runtime from an `images` event or endpoint.
class MaidCafeRuntimeImages {
  const MaidCafeRuntimeImages({
    required this.runtime,
    required this.available,
    this.error,
    this.images = const [],
  });

  /// `"podman"` or `"docker"`.
  final String runtime;
  final bool available;

  /// Collection failure message when the runtime exists but could not be
  /// listed; null when the list is current.
  final String? error;
  final List<ServerContainerImage> images;
}

/// Typed images from an `images` SSE event or `/api/v1/images`.
///
/// [runtimes] covers every runtime found on the host (podman first); an empty
/// list means the daemon found no container runtime at all.
class MaidCafeImagesSnapshot {
  const MaidCafeImagesSnapshot({this.runtimes = const []});

  final List<MaidCafeRuntimeImages> runtimes;

  bool get hasRuntimes => runtimes.isNotEmpty;
}

/// Tolerant parse of an `images` SSE event or `/api/v1/images` payload.
///
/// The daemon emits one entry per image with a `tags` array; the entry is
/// expanded into one [ServerContainerImage] per tag so the rows match the
/// runtime's own `images` output (one row per repository:tag pair). Dangling
/// images (no tags) stay a single row via the `<none>` fallback.
MaidCafeImagesSnapshot parseMaidCafeImages(Map<String, dynamic> json) {
  final runtimes = <MaidCafeRuntimeImages>[];
  final rawRuntimes = json['runtimes'];
  if (rawRuntimes is List) {
    for (final raw in rawRuntimes) {
      if (raw is! Map) continue;
      final entry = Map<String, dynamic>.from(raw);
      final runtime = _optionalString(entry, 'runtime');
      if (runtime == null) continue;
      final images = <ServerContainerImage>[];
      final rawImages = entry['images'];
      if (rawImages is List) {
        for (final rawImage in rawImages) {
          if (rawImage is! Map) continue;
          images.addAll(_parseSseImage(Map<String, dynamic>.from(rawImage)));
        }
      }
      runtimes.add(
        MaidCafeRuntimeImages(
          runtime: runtime,
          available: entry['available'] is bool
              ? entry['available'] as bool
              : true,
          error: _optionalString(entry, 'error'),
          images: images,
        ),
      );
    }
  }
  return MaidCafeImagesSnapshot(runtimes: runtimes);
}

List<ServerContainerImage> _parseSseImage(Map<String, dynamic> json) {
  final id = _optionalString(json, 'id');
  if (id == null || id.isEmpty) return const [];
  final rawTags = json['tags'];
  final tags = rawTags is List
      ? [
          for (final tag in rawTags)
            if (tag is String && tag.trim().isNotEmpty) tag.trim(),
        ]
      : <String>[];
  final size = formatContainerBytes(_optionalNum(json, 'size')?.toInt() ?? 0);
  final created = _formatImageAge(_optionalNum(json, 'created')?.toInt());
  if (tags.isEmpty) {
    // Dangling image: reference falls back to the id.
    return [
      ServerContainerImage(
        id: id,
        repository: '<none>',
        tag: '<none>',
        size: size,
        created: created,
      ),
    ];
  }
  return [
    for (final tag in tags)
      ServerContainerImage(
        id: id,
        repository: _imageRepository(tag),
        tag: _imageTag(tag),
        size: size,
        created: created,
      ),
  ];
}

/// Repository part of a `repository:tag` reference. The last `:` after the
/// final `/` separates the tag, so registry hosts with ports
/// (`localhost:5000/nginx`) do not split incorrectly.
String _imageRepository(String reference) {
  final slash = reference.lastIndexOf('/');
  final colon = reference.lastIndexOf(':');
  if (colon > slash) return reference.substring(0, colon);
  return reference;
}

String _imageTag(String reference) {
  final slash = reference.lastIndexOf('/');
  final colon = reference.lastIndexOf(':');
  if (colon > slash) return reference.substring(colon + 1);
  return '<none>';
}

/// Relative age for a unix-seconds created timestamp (e.g. `2w ago`,
/// `5h ago`); empty for missing or future timestamps.
String _formatImageAge(int? unixSeconds) {
  if (unixSeconds == null || unixSeconds <= 0) return '';
  final age = DateTime.now().toUtc().difference(
    DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true),
  );
  if (age.isNegative) return '';
  if (age.inSeconds < 60) return '${age.inSeconds}s ago';
  if (age.inMinutes < 60) return '${age.inMinutes}m ago';
  if (age.inHours < 24) return '${age.inHours}h ago';
  if (age.inDays < 7) return '${age.inDays}d ago';
  if (age.inDays < 30) return '${age.inDays ~/ 7}w ago';
  if (age.inDays < 365) return '${age.inDays ~/ 30}mo ago';
  return '${age.inDays ~/ 365}y ago';
}

/// Tolerant parse of a `processes` SSE event payload.
MaidCafeProcessesSnapshot parseMaidCafeProcesses(Map<String, dynamic> json) {
  final processes = <ServerProcess>[];
  final rawProcesses = json['processes'];
  if (rawProcesses is List) {
    for (final raw in rawProcesses) {
      if (raw is! Map) continue;
      final process = _parseSseProcess(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (process != null) processes.add(process);
    }
  }
  return MaidCafeProcessesSnapshot(processes: processes);
}

ServerProcess? _parseSseProcess(Map<String, dynamic> json) {
  final pid = json['pid'];
  final user = _optionalString(json, 'user');
  if (pid is! num || user == null) return null;
  return ServerProcess(
    pid: pid.toInt(),
    user: user,
    cpuPercent: _optionalNum(json, 'cpu_percent')?.toDouble() ?? 0,
    memoryPercent: _optionalNum(json, 'memory_percent')?.toDouble() ?? 0,
    rssKb: _optionalNum(json, 'rss_kb')?.toInt() ?? 0,
    command: _optionalString(json, 'command') ?? '',
  );
}

/// Tolerant parse of a `runtimes` SSE event payload / one-shot snapshot.
/// Malformed groups are skipped, unknown runtime names are ignored, `available`
/// defaults to true, and a missing `java` key leaves the java info null.
RuntimeSnapshot parseMaidCafeRuntimes(Map<String, dynamic> json) {
  final groups = <RuntimeGroup>[];
  final rawGroups = json['runtimes'];
  if (rawGroups is List) {
    for (final raw in rawGroups) {
      if (raw is! Map) continue;
      final group = _parseSseRuntimeGroup(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (group != null) groups.add(group);
    }
  }
  final watched = <WatchedProcessGroup>[];
  final rawWatched = json['watched'];
  if (rawWatched is List) {
    for (final raw in rawWatched) {
      if (raw is! Map) continue;
      final group = _parseSseWatchedGroup(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (group != null) watched.add(group);
    }
  }
  return RuntimeSnapshot(
    groups: groups,
    watched: watched,
    collectedAt: DateTime.now(),
  );
}

WatchedProcessGroup? _parseSseWatchedGroup(Map<String, dynamic> json) {
  final name = _optionalString(json, 'name');
  if (name == null || name.isEmpty) return null;
  final processes = <RuntimeProcessInfo>[];
  final rawProcesses = json['processes'];
  if (rawProcesses is List) {
    for (final raw in rawProcesses) {
      if (raw is! Map) continue;
      final process = _parseSseRuntimeProcess(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (process != null) processes.add(process);
    }
  }
  return WatchedProcessGroup(
    name: name,
    available: json['available'] is bool ? json['available'] as bool : true,
    error: _optionalString(json, 'error'),
    processes: processes,
  );
}

/// Tolerant parse of a `process-history` response: `{name, samples:[...]}`.
/// Malformed samples are skipped; unknown fields ignored.
ProcessHistory parseMaidCafeProcessHistory(Map<String, dynamic> json) {
  final name = _optionalString(json, 'name') ?? '';
  final samples = <ProcessHistorySample>[];
  final rawSamples = json['samples'];
  if (rawSamples is List) {
    for (final raw in rawSamples) {
      if (raw is! Map) continue;
      final sample = _parseProcessHistorySample(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (sample != null) samples.add(sample);
    }
  }
  return ProcessHistory(name: name, samples: samples);
}

ProcessHistorySample? _parseProcessHistorySample(Map<String, dynamic> json) {
  final rawTs = json['ts'];
  final cpu = _optionalNum(json, 'cpu_percent');
  final rss = _optionalNum(json, 'rss_kb');
  final count = _optionalNum(json, 'process_count');
  final ts = rawTs is String ? DateTime.tryParse(rawTs) : null;
  if (ts == null || cpu == null || rss == null || count == null) return null;
  final threads = _optionalNum(json, 'threads');
  return ProcessHistorySample(
    name: _optionalString(json, 'name') ?? '',
    timestamp: ts,
    cpuPercent: cpu.toDouble(),
    rssKb: rss.toInt(),
    processCount: count.toInt(),
    threads: threads?.toInt(),
  );
}

RuntimeGroup? _parseSseRuntimeGroup(Map<String, dynamic> json) {
  final rawKind = _optionalString(json, 'runtime');
  final kind = rawKind == null ? null : RuntimeKindFromWire(rawKind);
  if (kind == null) return null;
  final processes = <RuntimeProcessInfo>[];
  final rawProcesses = json['processes'];
  if (rawProcesses is List) {
    for (final raw in rawProcesses) {
      if (raw is! Map) continue;
      final process = _parseSseRuntimeProcess(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (process != null) processes.add(process);
    }
  }
  JavaRuntimeInfo? java;
  final rawJava = json['java'];
  if (rawJava is Map) {
    final javaMap = rawJava.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final jdk = javaMap['jdk'];
    final jvms = <JavaJvmInfo>[];
    final rawJvms = javaMap['jvms'];
    if (rawJvms is List) {
      for (final raw in rawJvms) {
        if (raw is! Map) continue;
        final jvm = _parseSseJavaJvm(
          raw.map((key, value) => MapEntry(key.toString(), value)),
        );
        if (jvm != null) jvms.add(jvm);
      }
    }
    java = JavaRuntimeInfo(
      jdkAvailable: jdk is Map && jdk['available'] is bool
          ? jdk['available'] as bool
          : true,
      jdkError: jdk is Map && jdk['error'] is String
          ? jdk['error'] as String
          : null,
      jvms: jvms,
    );
  }
  return RuntimeGroup(
    kind: kind,
    available: json['available'] is bool ? json['available'] as bool : true,
    error: _optionalString(json, 'error'),
    processes: processes,
    java: java,
  );
}

RuntimeProcessInfo? _parseSseRuntimeProcess(Map<String, dynamic> json) {
  final pid = json['pid'];
  final user = _optionalString(json, 'user');
  if (pid is! num || user == null) return null;
  final threads = _optionalNum(json, 'threads');
  return RuntimeProcessInfo(
    pid: pid.toInt(),
    user: user,
    cpuPercent: _optionalNum(json, 'cpu_percent')?.toDouble() ?? 0,
    memoryPercent: _optionalNum(json, 'memory_percent')?.toDouble() ?? 0,
    rssKb: _optionalNum(json, 'rss_kb')?.toInt() ?? 0,
    threads: threads?.toInt(),
    command: _optionalString(json, 'command') ?? '',
  );
}

JavaJvmInfo? _parseSseJavaJvm(Map<String, dynamic> json) {
  final pid = json['pid'];
  if (pid is! num) return null;
  final oldPercent = _optionalNum(json, 'old_percent');
  final ygc = _optionalNum(json, 'ygc');
  final fgc = _optionalNum(json, 'fgc');
  final gctSeconds = _optionalNum(json, 'gct_seconds');
  return JavaJvmInfo(
    pid: pid.toInt(),
    mainClass: _optionalString(json, 'main_class'),
    oldPercent: oldPercent?.toDouble(),
    ygc: ygc?.toInt(),
    fgc: fgc?.toInt(),
    gctSeconds: gctSeconds?.toDouble(),
    error: _optionalString(json, 'error'),
  );
}

/// Tolerant parse of a `systemd` SSE event payload.
MaidCafeSystemdSnapshot parseMaidCafeSystemd(Map<String, dynamic> json) {
  final units = <SystemdUnit>[];
  final rawUnits = json['units'];
  if (rawUnits is List) {
    for (final raw in rawUnits) {
      if (raw is! Map) continue;
      final unit = _parseSseSystemdUnit(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (unit != null) units.add(unit);
    }
  }
  return MaidCafeSystemdSnapshot(
    available: json['available'] is bool ? json['available'] as bool : true,
    error: _optionalString(json, 'error'),
    units: units,
  );
}

SystemdUnit? _parseSseSystemdUnit(Map<String, dynamic> json) {
  final name = _optionalString(json, 'name');
  if (name == null) return null;
  return SystemdUnit(
    name: name,
    loadState: _optionalString(json, 'load_state') ?? '',
    activeState: _optionalString(json, 'active_state') ?? '',
    subState: _optionalString(json, 'sub_state') ?? '',
    description: _optionalString(json, 'description') ?? '',
    unitFileState: _optionalString(json, 'unit_file_state') ?? '',
  );
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is String ? value : null;
}

num? _optionalNum(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is num ? value : null;
}
