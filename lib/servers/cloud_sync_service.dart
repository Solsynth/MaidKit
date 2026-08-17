import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:uuid/uuid.dart';

import '../shared/presentation/maidkit_alert.dart';

/// Configuration is deliberately opt-in and scoped to one local vault.
class CloudSyncConfiguration {
  const CloudSyncConfiguration({
    required this.workspaceId,
    required this.workspaceName,
    required this.workspaceSlug,
    required this.blobId,
    required this.revision,
    this.pendingDownload = false,
    this.lastSyncedAt,
    this.lastContentFingerprint,
  });

  final String workspaceId;
  final String workspaceName;
  final String workspaceSlug;
  final String blobId;
  final int revision;
  final bool pendingDownload;
  final DateTime? lastSyncedAt;

  /// SHA-256 of the syncable content at the last successful sync. A matching
  /// fingerprint means the local database is unchanged and no upload is needed.
  final String? lastContentFingerprint;

  Map<String, Object?> toJson() => {
    'workspaceId': workspaceId,
    'workspaceName': workspaceName,
    'workspaceSlug': workspaceSlug,
    'blobId': blobId,
    'revision': revision,
    'pendingDownload': pendingDownload,
    'lastSyncedAt': lastSyncedAt?.toUtc().toIso8601String(),
    'lastContentFingerprint': lastContentFingerprint,
  };

  factory CloudSyncConfiguration.fromJson(Map<String, dynamic> json) =>
      CloudSyncConfiguration(
        workspaceId: json['workspaceId'] as String,
        workspaceName: json['workspaceName'] as String,
        workspaceSlug: json['workspaceSlug'] as String,
        blobId: json['blobId'] as String? ?? const Uuid().v4(),
        revision: (json['revision'] as num?)?.toInt() ?? 0,
        pendingDownload: json['pendingDownload'] == true,
        lastSyncedAt: DateTime.tryParse(
          json['lastSyncedAt'] as String? ?? '',
        )?.toLocal(),
        lastContentFingerprint: json['lastContentFingerprint'] as String?,
      );
}

class CloudWorkspace {
  const CloudWorkspace({
    required this.id,
    required this.slug,
    required this.name,
  });

  final String id;
  final String slug;
  final String name;

  factory CloudWorkspace.fromJson(Map<String, dynamic> json) => CloudWorkspace(
    id: json['id']?.toString() ?? '',
    slug: json['slug']?.toString() ?? '',
    name: json['name']?.toString() ?? 'Untitled workspace',
  );
}

class CloudVaultBlob {
  const CloudVaultBlob({
    required this.id,
    required this.revision,
    required this.updatedAt,
  });

  final String id;
  final int revision;
  final DateTime? updatedAt;

  factory CloudVaultBlob.fromJson(Map<String, dynamic> json) => CloudVaultBlob(
    id: json['blob_id']?.toString() ?? json['blobId']?.toString() ?? '',
    revision:
        (json['current_revision'] as num?)?.toInt() ??
        (json['currentRevision'] as num?)?.toInt() ??
        0,
    updatedAt: DateTime.tryParse(
      json['updated_at']?.toString() ?? json['updatedAt']?.toString() ?? '',
    )?.toLocal(),
  );
}

class CloudUser {
  const CloudUser({required this.name, required this.handle, this.avatarUrl});

  final String name;
  final String handle;
  final String? avatarUrl;

  String get initials {
    final value = name.trim();
    return value.isEmpty ? '?' : value.substring(0, 1).toUpperCase();
  }

  factory CloudUser.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'] is Map
        ? Map<String, dynamic>.from(json['profile'] as Map)
        : const <String, dynamic>{};
    final picture = profile['picture'] ?? json['picture'];
    final pictureData = picture is Map
        ? Map<String, dynamic>.from(picture)
        : const <String, dynamic>{};
    final storageUrl =
        pictureData['storage_url']?.toString() ??
        pictureData['storageUrl']?.toString() ??
        pictureData['url']?.toString();
    final id = pictureData['id']?.toString();
    final handle = json['name']?.toString() ?? '';
    final displayName = json['nick']?.toString();
    return CloudUser(
      name: displayName?.isNotEmpty == true
          ? displayName!
          : handle.isNotEmpty
          ? '@$handle'
          : 'Solar Network user',
      handle: handle.isEmpty ? '' : '@$handle',
      avatarUrl:
          storageUrl ??
          (id == null ? null : '${CloudSyncService.apiBase}/drive/files/$id'),
    );
  }
}

class CloudSyncException implements Exception {
  const CloudSyncException(this.message);
  final String message;

  @override
  String toString() => message;
}

enum CloudSyncConflictResolution { downloadRemote, overwriteRemote }

enum CloudSyncArchiveMergeStatus { identical, merged, conflict }

/// Result of comparing a local encrypted archive with a newer remote archive.
///
/// The comparison callback owns decryption and merge policy. A merged archive
/// must contain the local and remote changes and remain encrypted with the
/// current vault passphrase.
class CloudSyncArchiveMergeResult {
  const CloudSyncArchiveMergeResult._(this.status, this.archive);

  const CloudSyncArchiveMergeResult.identical()
    : this._(CloudSyncArchiveMergeStatus.identical, null);

  const CloudSyncArchiveMergeResult.merged(String archive)
    : this._(CloudSyncArchiveMergeStatus.merged, archive);

  const CloudSyncArchiveMergeResult.conflict()
    : this._(CloudSyncArchiveMergeStatus.conflict, null);

  final CloudSyncArchiveMergeStatus status;
  final String? archive;
}

typedef CloudSyncArchiveComparator =
    Future<CloudSyncArchiveMergeResult> Function({
      required String localArchive,
      required String remoteArchive,
    });

/// Raised before either copy is changed when Flywheel has a newer revision.
class CloudSyncConflictException extends CloudSyncException {
  const CloudSyncConflictException({this.remoteRevision})
    : super('This vault has a newer cloud version.');

  final int? remoteRevision;
}

String _apiErrorMessage(DioException error) {
  final data = error.response?.data;
  if (data is Map) {
    final values = Map<String, dynamic>.from(data);
    final message = values['detail'] ?? values['message'] ?? values['error'];
    if (message != null && message.toString().isNotEmpty) {
      return message.toString();
    }
  }
  final status = error.response?.statusCode;
  return status == null
      ? 'Unable to reach Solarpass. Check your connection and try again.'
      : 'Solarpass request failed (HTTP $status).';
}

/// Solarpass authorization and Flywheel encrypted-blob transport.
class CloudSyncService {
  CloudSyncService({
    required String vaultId,
    FlutterSecureStorage? secureStorage,
    Dio? dio,
  }) : _vaultKey = base64UrlEncode(utf8.encode(vaultId)),
       _storage = secureStorage ?? const FlutterSecureStorage(),
       _dio = dio ?? Dio();

  static const apiBase = 'https://api.solian.app';
  // Flywheel app namespace for vault blobs. Keep stable: changing it orphans
  // every existing blob and makes syncs 409 against the old revision. The
  // MaidCafe Metoer notifications use their own maidCafeMetoerAppId.
  static const appId = 'dev.solsynth.maidkit';
  static const _clientId = 'maidkit';
  static const _callbackScheme = 'maidkit';
  static const _redirectUri = '$_callbackScheme://oauth/callback';
  // On Windows/Linux flutter_web_auth_2's default in-app WebView2 window runs
  // a second Flutter engine that crashes the app; the browser + loopback
  // callback flow is used instead there. The port must stay fixed so the
  // redirect URI can be registered with the Solarpass OIDC client.
  static const _loopbackPort = 42871;
  static const _loopbackCallbackScheme = 'http://127.0.0.1:$_loopbackPort';
  static const _loopbackRedirectUri = '$_loopbackCallbackScheme/oauth/callback';
  static const _sessionKey = 'maidkit_solar_network_oauth_session';
  static const _schemeVersion = 1;

  final String _vaultKey;
  final FlutterSecureStorage _storage;
  final Dio _dio;

  String get _configurationKey => 'maidkit_cloud_sync_$_vaultKey';

  Future<void> relocateVault(String newVaultId) async {
    final value = await _storage.read(key: _configurationKey);
    if (value == null) return;
    final newKey =
        'maidkit_cloud_sync_${base64UrlEncode(utf8.encode(newVaultId))}';
    await _storage.write(key: newKey, value: value);
    await _storage.delete(key: _configurationKey);
  }

  String _flywheelAppPath(String workspaceId) =>
      '/flywheel/workspaces/$workspaceId/apps/$appId';

  Future<CloudSyncConfiguration?> configuration() async {
    final raw = await _storage.read(key: _configurationKey);
    if (raw == null) return null;
    try {
      return CloudSyncConfiguration.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      await disable();
      return null;
    }
  }

  Future<void> disable() => _storage.delete(key: _configurationKey);

  Future<CloudUser?> currentUser() async {
    final session = await _validSession();
    if (session == null) return null;
    // The accounts profile domain moved from Passport to Stargate; Blade
    // converts the /stargate service prefix to /api at the gateway.
    final response = await _authorizedGet('/stargate/accounts/me', session);
    final data = response.data;
    return data is Map
        ? CloudUser.fromJson(Map<String, dynamic>.from(data))
        : null;
  }

  /// Returns a current Solarpass access token for first-party services.
  /// The token remains in secure storage and is refreshed when necessary.
  Future<String?> accessToken() async => (await _validSession())?.accessToken;

  Future<CloudUser> signIn() async {
    try {
      await _signIn();
      final user = await currentUser();
      if (user == null) {
        throw const CloudSyncException('Unable to load the signed-in account.');
      }
      return user;
    } on DioException catch (error) {
      throw CloudSyncException(_apiErrorMessage(error));
    }
  }

  Future<void> signOut() async {
    await _storage.delete(key: _sessionKey);
  }

  Future<List<CloudWorkspace>> listWorkspaces() async {
    final session = await _validSession();
    return session == null ? const [] : _listWorkspaces(session);
  }

  Future<List<CloudWorkspace>> signInAndListWorkspaces() async {
    try {
      final session = await _validSession();
      if (session == null) {
        return await _listWorkspaces(await _signIn());
      }
      try {
        return await _listWorkspaces(session);
      } on DioException catch (error) {
        if (error.response?.statusCode != 401) rethrow;
        // The stored session was rejected (revoked or rotated server-side).
        // Drop it and authorize again so the user can sign in interactively.
        await signOut();
        return await _listWorkspaces(await _signIn());
      }
    } on DioException catch (error) {
      throw CloudSyncException(_apiErrorMessage(error));
    }
  }

  Future<List<CloudWorkspace>> _listWorkspaces(_Session session) async {
    final response = await _authorizedGet('/valve/workspaces', session);
    final entries = response.data;
    if (entries is! List) {
      throw const CloudSyncException('Invalid workspace response.');
    }
    return entries
        .whereType<Map>()
        .map(
          (entry) => CloudWorkspace.fromJson(Map<String, dynamic>.from(entry)),
        )
        .where((workspace) => workspace.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<CloudVaultBlob>> listVaultBlobs(CloudWorkspace workspace) async {
    try {
      final session = await _validSession();
      if (session == null) {
        throw const CloudSyncException(
          'Sign in is required to list cloud vaults.',
        );
      }
      final response = await _authorizedGet(
        '${_flywheelAppPath(workspace.id)}/blobs',
        session,
      );
      final entries = response.data;
      if (entries is! List) {
        throw const CloudSyncException('Invalid cloud vault response.');
      }
      return entries
          .whereType<Map>()
          .map(
            (value) =>
                CloudVaultBlob.fromJson(Map<String, dynamic>.from(value)),
          )
          .where((blob) => blob.id.isNotEmpty && blob.revision > 0)
          .toList(growable: false);
    } on DioException catch (error) {
      throw CloudSyncException(_apiErrorMessage(error));
    }
  }

  Future<CloudSyncConfiguration> enable(
    CloudWorkspace workspace, {
    CloudVaultBlob? existingBlob,
  }) async {
    try {
      final session = await _validSession();
      if (session == null) {
        throw const CloudSyncException(
          'Sign in is required to enable cloud sync.',
        );
      }
      await _authorizedGet(
        '/valve/workspaces/${workspace.id}/plan/status',
        session,
      );
      final previous = await this.configuration();
      final reuseCurrentBlob =
          existingBlob == null && previous?.workspaceId == workspace.id;
      final configuration = CloudSyncConfiguration(
        workspaceId: workspace.id,
        workspaceName: workspace.name,
        workspaceSlug: workspace.slug,
        blobId:
            existingBlob?.id ??
            (reuseCurrentBlob ? previous!.blobId : const Uuid().v4()),
        revision: reuseCurrentBlob ? previous!.revision : 0,
        pendingDownload: existingBlob != null,
        lastContentFingerprint: reuseCurrentBlob
            ? previous!.lastContentFingerprint
            : null,
      );
      await _storage.write(
        key: _configurationKey,
        value: jsonEncode(configuration.toJson()),
      );
      return configuration;
    } on DioException catch (error) {
      throw CloudSyncException(_apiErrorMessage(error));
    }
  }

  Future<void> completePendingDownload() async {
    final configuration = await this.configuration();
    if (configuration == null || !configuration.pendingDownload) return;
    await _saveConfiguration(
      CloudSyncConfiguration(
        workspaceId: configuration.workspaceId,
        workspaceName: configuration.workspaceName,
        workspaceSlug: configuration.workspaceSlug,
        blobId: configuration.blobId,
        revision: configuration.revision,
        lastSyncedAt: configuration.lastSyncedAt,
        lastContentFingerprint: configuration.lastContentFingerprint,
      ),
    );
  }

  /// Uploads/downloads a client-encrypted archive. Flywheel never decrypts it.
  ///
  /// When a newer remote revision exists, [compareAndMergeArchive] receives
  /// both encrypted copies after the remote copy has been downloaded. The
  /// callback decrypts them with the active vault passphrase and can report
  /// identical content or return an encrypted merged archive. Only an
  /// unmergeable difference reaches the conflict prompt.
  ///
  /// [conflictResolution] remains an explicit override for onboarding and
  /// other callers that must deterministically choose one side.
  ///
  /// When [contentFingerprint] is provided, the upload is skipped if it
  /// matches the fingerprint stored at the last successful sync and the local
  /// revision was not superseded.
  Future<CloudSyncConfiguration> sync({
    required String archive,
    required Future<void> Function(String archive) applyArchive,
    Future<String> Function()? contentFingerprint,
    CloudSyncArchiveComparator? compareAndMergeArchive,
    CloudSyncConflictResolution? conflictResolution,
    int conflictRetryCount = 0,
  }) async {
    final configuration = await this.configuration();
    if (configuration == null) {
      throw const CloudSyncException(
        'Link this vault to a cloud workspace first.',
      );
    }
    try {
      final session = await _validSession();
      if (session == null) {
        throw const CloudSyncException(
          'Sign in is required to sync this vault.',
        );
      }
      var revision = configuration.revision;
      var uploadArchive = archive;
      var remoteRevision = 0;
      try {
        final metadata = await _authorizedGet(
          '${_flywheelAppPath(configuration.workspaceId)}/blobs/'
          '${configuration.blobId}',
          session,
        );
        final data = metadata.data as Map?;
        remoteRevision =
            ((data?['current_revision'] ?? data?['currentRevision']) as num?)
                ?.toInt() ??
            0;
      } on DioException catch (error) {
        if (error.response?.statusCode != 404) rethrow;
      }
      if (remoteRevision > revision) {
        final remoteArchive = await _downloadRemoteArchive(
          configuration,
          session,
        );
        final comparison = conflictResolution == null
            ? await compareAndMergeArchive?.call(
                localArchive: archive,
                remoteArchive: remoteArchive,
              )
            : null;
        if (comparison?.status == CloudSyncArchiveMergeStatus.identical) {
          final updated = _updatedConfiguration(
            configuration,
            revision: remoteRevision,
            contentFingerprint: await contentFingerprint?.call(),
          );
          await _saveConfiguration(updated);
          return updated;
        }
        if (comparison?.status == CloudSyncArchiveMergeStatus.merged) {
          uploadArchive = comparison!.archive!;
          // The merged result becomes the local database before it is
          // published. If the upload fails, the unchanged configuration causes
          // the next sync to retry this merged local state.
          await applyArchive(uploadArchive);
          revision = remoteRevision;
        } else {
          final resolution =
              conflictResolution ?? await _resolveConflict(remoteRevision);
          if (resolution == CloudSyncConflictResolution.downloadRemote) {
            await applyArchive(remoteArchive);
            final updated = _updatedConfiguration(
              configuration,
              revision: remoteRevision,
              contentFingerprint: await contentFingerprint?.call(),
            );
            await _saveConfiguration(updated);
            return updated;
          }
          // Local-authoritative sync keeps this vault's stable blob ID and
          // creates the next revision from the latest remote one.
          revision = remoteRevision;
        }
      }
      final fingerprint = await contentFingerprint?.call();
      if (fingerprint != null &&
          fingerprint == configuration.lastContentFingerprint &&
          revision == configuration.revision) {
        return configuration;
      }
      final response = await _dio.put<Map<String, dynamic>>(
        '$apiBase${_flywheelAppPath(configuration.workspaceId)}/blobs/'
        '${configuration.blobId}',
        data: FormData.fromMap({
          // Flywheel binds these multipart fields to its C# [FromForm]
          // properties. JSON's snake_case convention does not apply here.
          'File': MultipartFile.fromBytes(
            utf8.encode(uploadArchive),
            filename: 'vault.mkb',
          ),
          'SchemeVersion': _schemeVersion,
          'ExpectedRevision': revision,
        }),
        options: Options(
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ),
      );
      revision =
          (response.data?['revision'] as num?)?.toInt() ?? (revision + 1);
      final updated = _updatedConfiguration(
        configuration,
        revision: revision,
        contentFingerprint: fingerprint,
      );
      await _saveConfiguration(updated);
      return updated;
    } on DioException catch (error) {
      if (error.response?.statusCode == 409 && conflictRetryCount < 1) {
        return sync(
          archive: archive,
          applyArchive: applyArchive,
          contentFingerprint: contentFingerprint,
          compareAndMergeArchive: compareAndMergeArchive,
          conflictResolution: CloudSyncConflictResolution.overwriteRemote,
          conflictRetryCount: conflictRetryCount + 1,
        );
      }
      if (error.response?.statusCode == 409) {
        throw const CloudSyncException(
          'This cloud vault changed again while syncing. Try once more.',
        );
      }
      throw CloudSyncException(_apiErrorMessage(error));
    }
  }

  Future<String> _downloadRemoteArchive(
    CloudSyncConfiguration configuration,
    _Session session,
  ) async {
    final content = await _dio.get<List<int>>(
      '$apiBase${_flywheelAppPath(configuration.workspaceId)}/blobs/'
      '${configuration.blobId}/content',
      options: Options(
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
        responseType: ResponseType.bytes,
      ),
    );
    return utf8.decode(content.data ?? const []);
  }

  /// Asks the user whether to adopt the newer cloud revision or keep the
  /// local copy. Without an app overlay (headless), the local copy wins.
  Future<CloudSyncConflictResolution> _resolveConflict(
    int remoteRevision,
  ) async {
    final useCloud = await showMaidKitCloudSyncConflictAlert(
      remoteRevision: remoteRevision,
    );
    return useCloud
        ? CloudSyncConflictResolution.downloadRemote
        : CloudSyncConflictResolution.overwriteRemote;
  }

  CloudSyncConfiguration _updatedConfiguration(
    CloudSyncConfiguration configuration, {
    required int revision,
    String? contentFingerprint,
  }) => CloudSyncConfiguration(
    workspaceId: configuration.workspaceId,
    workspaceName: configuration.workspaceName,
    workspaceSlug: configuration.workspaceSlug,
    blobId: configuration.blobId,
    revision: revision,
    pendingDownload: configuration.pendingDownload,
    lastSyncedAt: DateTime.now(),
    lastContentFingerprint:
        contentFingerprint ?? configuration.lastContentFingerprint,
  );

  Future<void> _saveConfiguration(CloudSyncConfiguration configuration) =>
      _storage.write(
        key: _configurationKey,
        value: jsonEncode(configuration.toJson()),
      );

  Future<_Session> _signIn() async {
    final configuration = await _discover();
    final verifier = _randomUrlSafe(64);
    final state = _randomUrlSafe(32);
    final challenge = base64UrlEncode(
      sha256.convert(utf8.encode(verifier)).bytes,
    ).replaceAll('=', '');
    // Windows/Linux: use the system browser with a loopback callback instead
    // of the in-app WebView2 window, which crashes the app (its title bar
    // runs a second Flutter engine without the window_manager plugin).
    final useLoopback =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);
    final redirectUri = useLoopback ? _loopbackRedirectUri : _redirectUri;
    final url = configuration.authorizationEndpoint.replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': _clientId,
        'redirect_uri': redirectUri,
        'scope': '*',
        'state': state,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
      },
    );
    final callback = Uri.parse(
      await FlutterWebAuth2.authenticate(
        url: url.toString(),
        callbackUrlScheme: useLoopback
            ? _loopbackCallbackScheme
            : _callbackScheme,
        options: useLoopback
            ? const FlutterWebAuth2Options(useWebview: false)
            : const FlutterWebAuth2Options(),
      ),
    );
    if (callback.queryParameters['state'] != state) {
      throw const CloudSyncException(
        'The authorization response could not be verified.',
      );
    }
    final error = callback.queryParameters['error'];
    if (error != null) {
      throw CloudSyncException(
        callback.queryParameters['error_description'] ?? error,
      );
    }
    final code = callback.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw const CloudSyncException(
        'The authorization server did not return an authorization code.',
      );
    }
    final session = await _exchange(configuration.tokenEndpoint, {
      'grant_type': 'authorization_code',
      'client_id': _clientId,
      'code': code,
      'redirect_uri': redirectUri,
      'code_verifier': verifier,
    });
    await _saveSession(session);
    return session;
  }

  Future<_Session?> _validSession() async {
    final session = await _readSession();
    if (session == null || !session.needsRefresh) return session;
    if (session.refreshToken == null || session.refreshToken!.isEmpty) {
      return null;
    }
    final inFlight = _refreshFuture;
    if (inFlight != null) return inFlight;
    final refresh = _refreshSession(session);
    _refreshFuture = refresh;
    try {
      return await refresh;
    } finally {
      if (identical(_refreshFuture, refresh)) _refreshFuture = null;
    }
  }

  // The account session is shared by every vault-specific service instance.
  // Keep refresh-token rotation single-use within this process.
  static Future<_Session?>? _refreshFuture;

  Future<_Session?> _refreshSession(_Session session) async {
    try {
      final refreshed = await _exchange((await _discover()).tokenEndpoint, {
        'grant_type': 'refresh_token',
        'client_id': _clientId,
        'refresh_token': session.refreshToken!,
      }, previous: session);
      await _saveSession(refreshed);
      return refreshed;
    } on DioException catch (error) {
      if (_isInvalidRefreshResponse(error)) {
        await _clearSessionIfUnchanged(session);
      }
      return null;
    }
  }

  bool _isInvalidRefreshResponse(DioException error) {
    final status = error.response?.statusCode;
    // OAuth token endpoints use 400 (invalid_grant) for an expired, rotated,
    // or otherwise invalid refresh token. A 401 is likewise unrecoverable.
    return status == 400 || status == 401;
  }

  Future<void> _clearSessionIfUnchanged(_Session session) async {
    final current = await _readSession();
    if (current == null ||
        current.accessToken != session.accessToken ||
        current.refreshToken != session.refreshToken) {
      return;
    }
    await _storage.delete(key: _sessionKey);
  }

  Future<_OidcConfiguration> _discover() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '$apiBase/.well-known/openid-configuration',
    );
    final data = response.data;
    if (data == null) {
      throw const CloudSyncException('Unable to load sign-in configuration.');
    }
    return _OidcConfiguration.fromJson(data);
  }

  Future<Response<dynamic>> _authorizedGet(String path, _Session session) =>
      _dio.get<dynamic>(
        '$apiBase$path',
        options: Options(
          headers: {'Authorization': 'Bearer ${session.accessToken}'},
        ),
      );

  Future<_Session> _exchange(
    Uri endpoint,
    Map<String, String> fields, {
    _Session? previous,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      endpoint.toString(),
      data: fields,
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final data = response.data ?? const <String, dynamic>{};
    final accessToken = (data['access_token'] ?? data['token']) as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw const CloudSyncException(
        'The token response did not include an access token.',
      );
    }
    return _Session(
      accessToken: accessToken,
      refreshToken: data['refresh_token'] as String? ?? previous?.refreshToken,
      expiresAt: data['expires_in'] is num
          ? DateTime.now().add(
              Duration(seconds: (data['expires_in'] as num).toInt()),
            )
          : null,
    );
  }

  Future<_Session?> _readSession() async {
    final raw = await _storage.read(key: _sessionKey);
    if (raw == null) return null;
    try {
      return _Session.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      await _storage.delete(key: _sessionKey);
      return null;
    }
  }

  Future<void> _saveSession(_Session session) =>
      _storage.write(key: _sessionKey, value: jsonEncode(session.toJson()));

  String _randomUrlSafe(int length) => base64UrlEncode(
    List<int>.generate(length, (_) => Random.secure().nextInt(256)),
  ).replaceAll('=', '');
}

class _OidcConfiguration {
  const _OidcConfiguration(this.authorizationEndpoint, this.tokenEndpoint);
  final Uri authorizationEndpoint;
  final Uri tokenEndpoint;
  factory _OidcConfiguration.fromJson(Map<String, dynamic> json) =>
      _OidcConfiguration(
        Uri.parse(json['authorization_endpoint'] as String),
        Uri.parse(json['token_endpoint'] as String),
      );
}

class _Session {
  const _Session({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
  });
  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  bool get needsRefresh =>
      expiresAt != null &&
      DateTime.now().isAfter(expiresAt!.subtract(const Duration(seconds: 30)));
  Map<String, Object?> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'expires_at': expiresAt?.toUtc().toIso8601String(),
  };
  factory _Session.fromJson(Map<String, dynamic> json) => _Session(
    accessToken: json['access_token'] as String,
    refreshToken: json['refresh_token'] as String?,
    expiresAt: DateTime.tryParse(
      json['expires_at'] as String? ?? '',
    )?.toLocal(),
  );
}
