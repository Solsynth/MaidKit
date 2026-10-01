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

/// What the user has to approve before a device-flow sign-in can finish: the
/// code, and the page that takes it. [verificationUriComplete] carries the
/// code in the URL, so opening it saves typing it.
@immutable
class SolarpassDeviceAuthorization {
  const SolarpassDeviceAuthorization({
    required this.userCode,
    required this.verificationUri,
    required this.verificationUriComplete,
    required this.expiresAt,
  });

  final String userCode;
  final Uri verificationUri;
  final Uri verificationUriComplete;
  final DateTime expiresAt;
}

/// Tells the caller what a device-flow sign-in is waiting on. The web build
/// has no callback to bounce through, so it puts the code on screen; every
/// other platform opens a browser window and never calls it.
typedef CloudDeviceCodeCallback =
    void Function(SolarpassDeviceAuthorization authorization);

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
  final data = _decodeErrorBody(error.response?.data);
  if (data is Map) {
    final values = Map<String, dynamic>.from(data);
    final message = values['detail'] ?? values['message'] ?? values['error'];
    if (message != null && message.toString().isNotEmpty) {
      return message.toString();
    }
  }
  final status = error.response?.statusCode;
  if (status == null) {
    return 'Unable to reach Solarpass. Check your connection and try again.';
  }
  // A body-less 404 means the request never reached a handler: no route
  // matched, usually because a path segment is not the GUID the route
  // requires. Naming the request keeps that from surfacing as an opaque
  // status code.
  final request = error.requestOptions;
  return 'Solarpass request failed (HTTP $status · '
      '${request.method} ${request.uri.path}).';
}

/// The dashed 8-4-4-4-12 form (`Guid`'s "D" format) the Flywheel routes
/// usually carry.
final _dashedGuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// The undashed 32-hexadecimal form (`Guid`'s "N" format).
final _compactGuidPattern = RegExp(r'^[0-9a-fA-F]{32}$');

/// Whether [value] is a GUID in any of the forms ASP.NET's `:guid` route
/// constraint accepts. That constraint delegates to `Guid.TryParse`, so it
/// takes the dashed ("D"), undashed ("N"), brace-wrapped ("B"), and
/// parenthesized ("P") layouts. Mirroring it exactly keeps this pre-flight
/// check from refusing an id the server would happily route, while still
/// catching a stale slug or a truncated value that would miss the route and
/// answer a body-less 404.
bool _isGuid(String value) {
  if (_dashedGuidPattern.hasMatch(value)) return true;
  if (_compactGuidPattern.hasMatch(value)) return true;
  if (value.length >= 2) {
    final braced = value.startsWith('{') && value.endsWith('}');
    final parenthesized = value.startsWith('(') && value.endsWith(')');
    if (braced || parenthesized) {
      return _dashedGuidPattern.hasMatch(value.substring(1, value.length - 1));
    }
  }
  return false;
}

/// Recovers the JSON error body Dio leaves as raw bytes.
///
/// Requests made with `ResponseType.bytes` (the vault content download) get a
/// `Uint8List` even when the server answered with a JSON error object, which
/// would otherwise drop the real reason and surface only the status code. The
/// original value is returned unchanged when it is not a UTF-8 JSON body.
Object? _decodeErrorBody(Object? data) {
  if (data is! List<int>) return data;
  try {
    final text = utf8.decode(data).trim();
    if (text.isEmpty) return null;
    return jsonDecode(text);
  } on Object {
    return null;
  }
}

/// Solarpass authorization and Flywheel encrypted-blob transport.
class CloudSyncService {
  CloudSyncService({
    required String vaultId,
    FlutterSecureStorage? secureStorage,
    Dio? dio,
    bool? isWeb,
  }) : _vaultKey = base64UrlEncode(utf8.encode(vaultId)),
       _storage = secureStorage ?? const FlutterSecureStorage(),
       _dio = dio ?? Dio(),
       _isWeb = isWeb ?? kIsWeb;

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

  /// The grant the web build signs in with: RFC 8628's device flow, which
  /// needs no callback at all. A browser cannot hand a custom scheme back to
  /// the page, and the loopback listener is unreachable from one too, so the
  /// browser platform uses neither redirect.
  static const _deviceCodeGrant =
      'urn:ietf:params:oauth:grant-type:device_code';

  final String _vaultKey;
  final FlutterSecureStorage _storage;
  final Dio _dio;

  /// Whether this build signs in with the device flow. Injected rather than
  /// read from [kIsWeb] so tests can run either flow.
  final bool _isWeb;

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

  /// Signs in, returning the account.
  ///
  /// [onDeviceCode] is how the web build tells the user what to approve: the
  /// device flow has no callback to bounce through, so the provider hands out
  /// a code and the app polls until the user has entered it in a browser. The
  /// other platforms open a browser window and never call it.
  Future<CloudUser> signIn({CloudDeviceCodeCallback? onDeviceCode}) async {
    try {
      await _signIn(onDeviceCode: onDeviceCode);
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

  /// Signs in when no usable session is stored, then lists the workspaces the
  /// account can link a vault to. [onDeviceCode] carries the web build's
  /// device-flow code the same way [signIn] does.
  Future<List<CloudWorkspace>> signInAndListWorkspaces({
    CloudDeviceCodeCallback? onDeviceCode,
  }) async {
    try {
      final session = await _validSession();
      if (session == null) {
        return await _listWorkspaces(await _signIn(onDeviceCode: onDeviceCode));
      }
      try {
        return await _listWorkspaces(session);
      } on DioException catch (error) {
        if (error.response?.statusCode != 401) rethrow;
        // The stored session was rejected (revoked or rotated server-side).
        // Drop it and authorize again so the user can sign in interactively.
        await signOut();
        return await _listWorkspaces(await _signIn(onDeviceCode: onDeviceCode));
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
    // Reject a bad identifier before anything is stored or sent. The Flywheel
    // routes bind the workspace and blob ids as GUIDs, so a workspace or blob
    // list that hands back a slug would persist a binding whose every request
    // misses its route and answers a body-less 404 on both upload and
    // download. Failing here names the real cause instead.
    if (!_isGuid(workspace.id)) {
      throw const CloudSyncException(
        'Solarpass returned an invalid workspace id for this workspace. '
        'Sign in again and retry; if it persists, the workspace list on the '
        'server needs attention.',
      );
    }
    if (existingBlob != null && !_isGuid(existingBlob.id)) {
      throw const CloudSyncException(
        'The selected cloud vault has an invalid id. Choose another cloud '
        'vault, or upload this vault from a device that still has it.',
      );
    }
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
  ///
  /// Calls run one at a time through a per-service queue. The five-minute
  /// auto-sync and a manual sync can both be in flight against the same vault;
  /// two overlapping uploads read the same remote revision and race for the
  /// next one, which is the race that let an uploader's cleanup delete
  /// committed blob content. The server now keys each attempt separately, but
  /// running one sync at a time keeps the client from provoking the race at
  /// all. Each queued sync fails on its own, so one rejected sync never stalls
  /// the ones behind it.
  Future<CloudSyncConfiguration> sync({
    required String archive,
    required Future<void> Function(String archive) applyArchive,
    Future<String> Function()? contentFingerprint,
    CloudSyncArchiveComparator? compareAndMergeArchive,
    CloudSyncConflictResolution? conflictResolution,
    int conflictRetryCount = 0,
  }) {
    final result = _syncQueue.then(
      (_) => _sync(
        archive: archive,
        applyArchive: applyArchive,
        contentFingerprint: contentFingerprint,
        compareAndMergeArchive: compareAndMergeArchive,
        conflictResolution: conflictResolution,
        conflictRetryCount: conflictRetryCount,
      ),
    );
    // Keep the queue tail non-failing so the next sync is not blocked by this
    // one's error.
    _syncQueue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> _syncQueue = Future<void>.value();

  Future<CloudSyncConfiguration> _sync({
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
    // The Flywheel routes bind the workspace and blob ids as GUIDs. A stored
    // value that is not one makes every blob request miss its route and come
    // back as a body-less 404, so name the cause before sending anything.
    if (!_isGuid(configuration.workspaceId) || !_isGuid(configuration.blobId)) {
      throw const CloudSyncException(
        'This vault is linked to an invalid cloud workspace. Unlink the vault '
        'from its cloud workspace and link it again.',
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
      var blobMissing = false;
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
        blobMissing = true;
      }
      // Onboarding is downloading a blob the user just picked from the list.
      // If it has vanished since, fail loudly instead of "restoring" an empty
      // vault and recreating the blob under the same id.
      if (blobMissing && configuration.pendingDownload) {
        throw const CloudSyncException(
          'The cloud copy could not be found. It may have been deleted; try '
          'again, or upload it from a device that still has this vault.',
        );
      }
      // The blob is gone but this device still holds the vault. Treat the
      // local copy as authoritative and recreate the blob from revision zero
      // rather than uploading against a revision the server no longer has,
      // which it would reject as a conflict and loop on.
      if (blobMissing) revision = 0;
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
      final response = await _authorizedRequest(
        session,
        (accessToken) => _dio.put<Map<String, dynamic>>(
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
          options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
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
        return _sync(
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
    try {
      final content = await _authorizedRequest(
        session,
        (accessToken) => _dio.get<List<int>>(
          '$apiBase${_flywheelAppPath(configuration.workspaceId)}/blobs/'
          '${configuration.blobId}/content',
          options: Options(
            headers: {'Authorization': 'Bearer $accessToken'},
            responseType: ResponseType.bytes,
          ),
        ),
      );
      return utf8.decode(content.data ?? const []);
    } on DioException catch (error) {
      // The metadata reported a newer revision, but its bytes do not exist.
      // Flywheel answers 404 ("Revision not found." / "Blob content is
      // unavailable.") when an upload's cleanup deleted the object out from
      // under the committed revision.
      if (error.response?.statusCode == 404) {
        throw const CloudSyncException(
          'The cloud copy is unavailable on the server. It may have been '
          'damaged by an interrupted upload; upload it again from a device '
          'that still has this vault.',
        );
      }
      rethrow;
    }
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

  /// Runs the flow this platform signs in with and stores the session.
  ///
  /// The web build has to use the device flow: nothing in a browser can hand
  /// the provider's callback back into the page, which both the custom scheme
  /// and the loopback listener assume. Everywhere else the browser flow runs
  /// unchanged.
  Future<_Session> _signIn({CloudDeviceCodeCallback? onDeviceCode}) async {
    final session = _isWeb
        ? await _authorizeDevice(onDeviceCode)
        : await _authorizeBrowserFlow();
    await _saveSession(session);
    return session;
  }

  /// The browser sign-in: open the authorization page, take the code back
  /// through the platform's redirect, exchange it for a session.
  Future<_Session> _authorizeBrowserFlow() async {
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
    return _exchange(configuration.tokenEndpoint, {
      'grant_type': 'authorization_code',
      'client_id': _clientId,
      'code': code,
      'redirect_uri': redirectUri,
      'code_verifier': verifier,
    });
  }

  /// Signs in with RFC 8628's device flow: ask for a code, hand it to the
  /// user, then poll the token endpoint until they have approved it in a
  /// browser. This is the web's flow; it needs no redirect at all.
  Future<_Session> _authorizeDevice(
    CloudDeviceCodeCallback? onDeviceCode,
  ) async {
    final configuration = await _discover();
    final endpoint = configuration.deviceAuthorizationEndpoint;
    if (!endpoint.hasScheme) {
      throw const CloudSyncException(
        'This Solar Network deployment does not offer device sign-in.',
      );
    }
    final response = await _dio.post<Map<String, dynamic>>(
      endpoint.toString(),
      data: {'client_id': _clientId, 'scope': '*'},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final data = response.data;
    if (data == null) {
      throw const CloudSyncException('Invalid device authorization response.');
    }
    final deviceCode = data['device_code']?.toString() ?? '';
    final userCode = data['user_code']?.toString() ?? '';
    final verificationUri = Uri.tryParse(
      data['verification_uri']?.toString() ?? '',
    );
    if (deviceCode.isEmpty ||
        userCode.isEmpty ||
        verificationUri == null ||
        !verificationUri.hasScheme) {
      throw const CloudSyncException('Invalid device authorization response.');
    }
    // The provider may send a URI that carries the code, which saves the user
    // typing it. Where it does not, the code itself is the whole instruction.
    final completeUri = Uri.tryParse(
      data['verification_uri_complete']?.toString() ?? '',
    );
    final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 600;
    onDeviceCode?.call(
      SolarpassDeviceAuthorization(
        userCode: userCode,
        verificationUri: verificationUri,
        verificationUriComplete: completeUri != null && completeUri.hasScheme
            ? completeUri
            : verificationUri,
        expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      ),
    );
    return _awaitDeviceApproval(
      configuration.tokenEndpoint,
      deviceCode,
      interval: (data['interval'] as num?)?.toInt() ?? 5,
      deadline: DateTime.now().add(Duration(seconds: expiresIn)),
    );
  }

  /// Polls [tokenEndpoint] until the user has approved [deviceCode].
  ///
  /// RFC 8628's two "not yet" answers are not failures: `authorization_pending`
  /// means the user has not got there yet, `slow_down` means the provider
  /// wants the next poll further out. Anything else — approval, refusal, an
  /// expired code — is the answer, and the loop ends either way.
  Future<_Session> _awaitDeviceApproval(
    Uri tokenEndpoint,
    String deviceCode, {
    required int interval,
    required DateTime deadline,
  }) async {
    var wait = interval;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(Duration(seconds: wait));
      final response = await _dio.post<dynamic>(
        tokenEndpoint.toString(),
        data: {
          'grant_type': _deviceCodeGrant,
          'device_code': deviceCode,
          'client_id': _clientId,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          // The pending answers arrive with 400; they are part of the flow,
          // so read them instead of letting Dio throw on them.
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final status = response.statusCode ?? 0;
      final body = response.data;
      if (status >= 200 && status < 300) return _sessionFrom(body);
      final error = body is Map ? body['error']?.toString() : null;
      if (error == 'authorization_pending') continue;
      if (error == 'slow_down') {
        wait += 5;
        continue;
      }
      if (error == 'expired_token') {
        throw const CloudSyncException(
          'The sign-in code expired before it was approved. Try again.',
        );
      }
      if (error == 'access_denied') {
        throw const CloudSyncException('The sign-in was declined.');
      }
      throw CloudSyncException(_deviceFlowFailure(body, status));
    }
    throw const CloudSyncException(
      'The sign-in code expired before it was approved. Try again.',
    );
  }

  String _deviceFlowFailure(Object? body, int status) {
    if (body is Map) {
      final detail =
          body['error_description'] ?? body['detail'] ?? body['message'];
      if (detail != null && detail.toString().isNotEmpty) {
        return detail.toString();
      }
    }
    return 'Solarpass sign-in failed (HTTP $status).';
  }

  Future<_Session?> _validSession() async {
    final session = await _readSession();
    if (session == null || !session.needsRefresh) return session;
    debugPrint('[Solarpass] Access token is nearing expiry; refreshing.');
    return _refreshSessionFor(session);
  }

  // The account session is shared by every vault-specific service instance.
  // Keep refresh-token rotation single-use within this process.
  static Future<_Session?>? _refreshFuture;

  Future<_Session?> _refreshSessionFor(_Session session) async {
    if (session.refreshToken == null || session.refreshToken!.isEmpty) {
      debugPrint('[Solarpass] Cannot refresh: no refresh token is stored.');
      return null;
    }
    final current = await _readSession();
    if (current == null) {
      debugPrint('[Solarpass] Cannot refresh: session was removed.');
      return null;
    }
    if (!current.matches(session)) {
      debugPrint('[Solarpass] Using a session refreshed by another request.');
      return current;
    }
    final inFlight = _refreshFuture;
    if (inFlight != null) {
      debugPrint('[Solarpass] Waiting for an in-flight token refresh.');
      return inFlight;
    }
    debugPrint('[Solarpass] Requesting a rotated token pair.');
    final refresh = _refreshSession(session);
    _refreshFuture = refresh;
    try {
      return await refresh;
    } finally {
      if (identical(_refreshFuture, refresh)) _refreshFuture = null;
    }
  }

  Future<_Session?> _refreshSession(_Session session) async {
    try {
      final refreshed = await _exchange((await _discover()).tokenEndpoint, {
        'grant_type': 'refresh_token',
        'client_id': _clientId,
        'refresh_token': session.refreshToken!,
      }, previous: session);
      await _saveSession(refreshed);
      debugPrint('[Solarpass] Token refresh succeeded; rotated pair saved.');
      return refreshed;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      debugPrint(
        '[Solarpass] Token refresh failed (HTTP ${status ?? 'network'}).',
      );
      if (_isInvalidRefreshResponse(error)) {
        debugPrint(
          '[Solarpass] Refresh grant is invalid; clearing stored session.',
        );
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
    debugPrint('[Solarpass] Cleared the invalid stored session.');
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
      _authorizedRequest(
        session,
        (accessToken) => _dio.get<dynamic>(
          '$apiBase$path',
          options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
        ),
      );

  Future<T> _authorizedRequest<T>(
    _Session session,
    Future<T> Function(String accessToken) request,
  ) async {
    try {
      return await request(session.accessToken);
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) rethrow;
      debugPrint('[Solarpass] Bearer request returned 401; refreshing once.');
      final refreshed = await _refreshSessionFor(session);
      if (refreshed == null) {
        debugPrint(
          '[Solarpass] Bearer request cannot be retried: refresh failed.',
        );
        rethrow;
      }
      debugPrint('[Solarpass] Retrying bearer request with the rotated token.');
      return request(refreshed.accessToken);
    }
  }

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
    return _sessionFrom(response.data, previous: previous);
  }

  /// The session a token response describes.
  _Session _sessionFrom(Object? body, {_Session? previous}) {
    final data = body is Map
        ? Map<String, dynamic>.from(body)
        : const <String, dynamic>{};
    // Some deployments answer with `token` rather than `access_token`.
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
  const _OidcConfiguration(
    this.authorizationEndpoint,
    this.tokenEndpoint,
    this.deviceAuthorizationEndpoint,
  );
  final Uri authorizationEndpoint;
  final Uri tokenEndpoint;

  /// Where a device-flow sign-in asks for its code. Empty when the deployment
  /// does not offer one.
  final Uri deviceAuthorizationEndpoint;

  factory _OidcConfiguration.fromJson(Map<String, dynamic> json) =>
      _OidcConfiguration(
        Uri.parse(json['authorization_endpoint'] as String),
        Uri.parse(json['token_endpoint'] as String),
        Uri.parse(json['device_authorization_endpoint']?.toString() ?? ''),
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

  bool matches(_Session other) =>
      accessToken == other.accessToken && refreshToken == other.refreshToken;
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
