import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/cloud_sync_service.dart';

const _sessionKey = 'maidkit_solar_network_oauth_session';
String _configurationKey(String vaultId) =>
    'maidkit_cloud_sync_${base64UrlEncode(utf8.encode(vaultId))}';

// Flywheel binds the workspace and blob path segments as GUIDs, so the stored
// configuration has to carry GUIDs too.
const _workspaceId = '11111111-1111-1111-1111-111111111111';
const _blobId = '22222222-2222-2222-2222-222222222222';

Map<String, dynamic> _syncConfiguration({
  required int revision,
  String? lastContentFingerprint,
  bool pendingDownload = false,
}) => {
  'workspaceId': _workspaceId,
  'workspaceName': 'Test workspace',
  'workspaceSlug': 'test',
  'blobId': _blobId,
  'revision': revision,
  'pendingDownload': pendingDownload,
  'lastContentFingerprint': lastContentFingerprint,
};

class _MemoryStorage extends FlutterSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}

class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.handle);

  final Future<ResponseBody> Function(RequestOptions options) handle;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handle(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, int status) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Stub the native OIDC browser flow: echo the state back in a callback
    // URL so the PKCE state check inside the service passes.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_web_auth_2'), (
          call,
        ) async {
          if (call.method != 'authenticate') return null;
          final arguments = Map<String, dynamic>.from(call.arguments as Map);
          final url = Uri.parse(arguments['url'] as String);
          final state = url.queryParameters['state']!;
          return 'maidkit://oauth/callback?code=test-code&state=$state';
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_web_auth_2'),
          null,
        );
  });

  test('re-signs in when the stored session is rejected with 401', () async {
    final storage = _MemoryStorage();
    // A session that is not yet expired (no refresh is attempted) but whose
    // access token the server rejects: the stale-session failure mode.
    storage.values[_sessionKey] = jsonEncode({
      'access_token': 'stale-token',
      'refresh_token': 'stale-refresh',
      'expires_at': DateTime.now()
          .add(const Duration(days: 1))
          .toUtc()
          .toIso8601String(),
    });
    var workspaceCalls = 0;
    var tokenExchanges = 0;
    final dio = Dio()
      ..httpClientAdapter = _CannedAdapter((options) async {
        switch (options.uri.path) {
          case '/.well-known/openid-configuration':
            return _json({
              'authorization_endpoint': 'https://id.solian.app/authorize',
              'token_endpoint': 'https://id.solian.app/token',
            }, 200);
          case '/valve/workspaces':
            workspaceCalls++;
            if (workspaceCalls == 1) {
              return _json({'error': 'unauthorized'}, 401);
            }
            return _json([
              {'id': 'workspace-1', 'slug': 'test', 'name': 'Test workspace'},
            ], 200);
          case '/token':
            tokenExchanges++;
            return _json({
              'access_token': 'fresh-token',
              'expires_in': 3600,
            }, 200);
          default:
            return _json({}, 404);
        }
      });

    final service = CloudSyncService(
      vaultId: 'test-vault',
      secureStorage: storage,
      dio: dio,
    );

    final workspaces = await service.signInAndListWorkspaces();

    expect(workspaces.single.id, 'workspace-1');
    expect(workspaces.single.name, 'Test workspace');
    expect(
      tokenExchanges,
      1,
      reason: 'a fresh authorization must follow the rejected session',
    );
    expect(
      storage.values[_sessionKey],
      contains('fresh-token'),
      reason: 'the fresh session replaces the stale one',
    );
  });

  test('signs in directly when no session is stored', () async {
    final storage = _MemoryStorage();
    var tokenExchanges = 0;
    final dio = Dio()
      ..httpClientAdapter = _CannedAdapter((options) async {
        switch (options.uri.path) {
          case '/.well-known/openid-configuration':
            return _json({
              'authorization_endpoint': 'https://id.solian.app/authorize',
              'token_endpoint': 'https://id.solian.app/token',
            }, 200);
          case '/valve/workspaces':
            return _json([
              {'id': 'workspace-2', 'slug': 'two', 'name': 'Second'},
            ], 200);
          case '/token':
            tokenExchanges++;
            return _json({
              'access_token': 'fresh-token',
              'expires_in': 3600,
            }, 200);
          default:
            return _json({}, 404);
        }
      });

    final service = CloudSyncService(
      vaultId: 'test-vault',
      secureStorage: storage,
      dio: dio,
    );

    final workspaces = await service.signInAndListWorkspaces();

    expect(workspaces.single.id, 'workspace-2');
    expect(tokenExchanges, 1);
  });

  test('surfaces a non-401 failure as CloudSyncException', () async {
    final storage = _MemoryStorage();
    final dio = Dio()
      ..httpClientAdapter = _CannedAdapter((options) async {
        switch (options.uri.path) {
          case '/.well-known/openid-configuration':
            return _json({
              'authorization_endpoint': 'https://id.solian.app/authorize',
              'token_endpoint': 'https://id.solian.app/token',
            }, 200);
          case '/valve/workspaces':
            return _json({'error': 'server error'}, 500);
          case '/token':
            return _json({
              'access_token': 'fresh-token',
              'expires_in': 3600,
            }, 200);
          default:
            return _json({}, 404);
        }
      });

    final service = CloudSyncService(
      vaultId: 'test-vault',
      secureStorage: storage,
      dio: dio,
    );
    storage.values[_sessionKey] = jsonEncode({
      'access_token': 'stale-token',
      'expires_at': DateTime.now()
          .add(const Duration(days: 1))
          .toUtc()
          .toIso8601String(),
    });

    await expectLater(
      service.signInAndListWorkspaces(),
      throwsA(
        isA<CloudSyncException>().having(
          (error) => error.toString(),
          'message',
          contains('server error'),
        ),
      ),
    );
  });

  test('loads the current account from the Stargate route', () async {
    final storage = _MemoryStorage();
    final requestedPaths = <String>[];
    final dio = Dio()
      ..httpClientAdapter = _CannedAdapter((options) async {
        requestedPaths.add(options.uri.path);
        switch (options.uri.path) {
          case '/stargate/accounts/me':
            return _json({
              'name': 'littlesheep',
              'nick': 'Little Sheep',
              'profile': {
                'picture': {'id': 'pic-1'},
              },
            }, 200);
          default:
            return _json({}, 404);
        }
      });
    // A session that is not yet expired so no refresh or re-auth is attempted.
    storage.values[_sessionKey] = jsonEncode({
      'access_token': 'valid-token',
      'expires_at': DateTime.now()
          .add(const Duration(days: 1))
          .toUtc()
          .toIso8601String(),
    });

    final service = CloudSyncService(
      vaultId: 'test-vault',
      secureStorage: storage,
      dio: dio,
    );

    final user = await service.currentUser();

    expect(user?.name, 'Little Sheep');
    expect(requestedPaths, ['/stargate/accounts/me']);
  });

  test(
    'refreshes and retries a bearer request rejected before local expiry',
    () async {
      final storage = _MemoryStorage()
        ..values[_sessionKey] = jsonEncode({
          'access_token': 'rejected-token',
          'refresh_token': 'refresh-token',
          'expires_at': DateTime.now()
              .add(const Duration(minutes: 5))
              .toUtc()
              .toIso8601String(),
        });
      final bearerTokens = <String?>[];
      var refreshes = 0;
      final dio = Dio()
        ..httpClientAdapter = _CannedAdapter((options) async {
          switch (options.uri.path) {
            case '/stargate/accounts/me':
              bearerTokens.add(options.headers['Authorization'] as String?);
              return bearerTokens.last == 'Bearer rejected-token'
                  ? _json({'error': 'unauthorized'}, 401)
                  : _json({'name': 'littlesheep', 'nick': 'Little Sheep'}, 200);
            case '/.well-known/openid-configuration':
              return _json({
                'authorization_endpoint': 'https://id.solian.app/authorize',
                'token_endpoint': 'https://id.solian.app/token',
              }, 200);
            case '/token':
              refreshes++;
              expect(options.data, {
                'grant_type': 'refresh_token',
                'client_id': 'maidkit',
                'refresh_token': 'refresh-token',
              });
              return _json({
                'access_token': 'rotated-token',
                'refresh_token': 'rotated-refresh-token',
                'expires_in': 3600,
              }, 200);
            default:
              return _json({}, 404);
          }
        });
      final service = CloudSyncService(
        vaultId: 'test-vault',
        secureStorage: storage,
        dio: dio,
      );

      final user = await service.currentUser();

      expect(user?.name, 'Little Sheep');
      expect(refreshes, 1);
      expect(bearerTokens, ['Bearer rejected-token', 'Bearer rotated-token']);
      expect(storage.values[_sessionKey], contains('rotated-refresh-token'));
    },
  );

  test('shares one in-flight refresh across service instances', () async {
    final storage = _MemoryStorage();
    var tokenExchanges = 0;
    final tokenStarted = Completer<void>();
    final releaseToken = Completer<void>();
    final dio = Dio()
      ..httpClientAdapter = _CannedAdapter((options) async {
        switch (options.uri.path) {
          case '/.well-known/openid-configuration':
            return _json({
              'authorization_endpoint': 'https://id.solian.app/authorize',
              'token_endpoint': 'https://id.solian.app/token',
            }, 200);
          case '/token':
            tokenExchanges++;
            if (tokenExchanges == 1) {
              tokenStarted.complete();
              await releaseToken.future;
              return _json({
                'access_token': 'fresh-token',
                'refresh_token': 'rotated-refresh',
                'expires_in': 3600,
              }, 200);
            }
            return _json({'error': 'invalid_grant'}, 400);
          default:
            return _json({}, 404);
        }
      });
    storage.values[_sessionKey] = jsonEncode({
      'access_token': 'stale-token',
      'refresh_token': 'stale-refresh',
      'expires_at': DateTime.now()
          .subtract(const Duration(minutes: 1))
          .toUtc()
          .toIso8601String(),
    });
    final firstService = CloudSyncService(
      vaultId: 'first-vault',
      secureStorage: storage,
      dio: dio,
    );
    final secondService = CloudSyncService(
      vaultId: 'second-vault',
      secureStorage: storage,
      dio: dio,
    );

    final first = firstService.accessToken();
    await tokenStarted.future;
    final second = secondService.accessToken();
    releaseToken.complete();

    expect(await Future.wait([first, second]), ['fresh-token', 'fresh-token']);
    expect(tokenExchanges, 1);
    expect(
      storage.values[_sessionKey],
      contains('rotated-refresh'),
      reason: 'the rotated refresh token must be persisted',
    );
  });

  test('drops a session after an invalid refresh grant', () async {
    final storage = _MemoryStorage();
    var tokenExchanges = 0;
    final dio = Dio()
      ..httpClientAdapter = _CannedAdapter((options) async {
        switch (options.uri.path) {
          case '/.well-known/openid-configuration':
            return _json({
              'authorization_endpoint': 'https://id.solian.app/authorize',
              'token_endpoint': 'https://id.solian.app/token',
            }, 200);
          case '/token':
            tokenExchanges++;
            return _json({
              'error': 'invalid_grant',
              'error_description': 'Refresh token has been invalidated',
            }, 400);
          default:
            return _json({}, 404);
        }
      });
    storage.values[_sessionKey] = jsonEncode({
      'access_token': 'stale-token',
      'refresh_token': 'invalid-refresh',
      'expires_at': DateTime.now()
          .subtract(const Duration(minutes: 1))
          .toUtc()
          .toIso8601String(),
    });
    final service = CloudSyncService(
      vaultId: 'test-vault',
      secureStorage: storage,
      dio: dio,
    );

    expect(await service.accessToken(), isNull);
    expect(storage.values.containsKey(_sessionKey), isFalse);
    expect(await service.accessToken(), isNull);
    expect(tokenExchanges, 1);
  });
  test('adopts a newer identical remote archive without uploading', () async {
    final storage = _MemoryStorage()
      ..values[_sessionKey] = jsonEncode({
        'access_token': 'valid-token',
        'expires_at': DateTime.now()
            .add(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
      })
      ..values[_configurationKey('sync-vault')] = jsonEncode(
        _syncConfiguration(
          revision: 1,
          lastContentFingerprint: 'local-fingerprint',
        ),
      );
    var uploads = 0;
    var applied = 0;
    final dio = Dio()
      ..httpClientAdapter = _CannedAdapter((options) async {
        switch (options.uri.path) {
          case '/flywheel/workspaces/$_workspaceId/apps/'
              'dev.solsynth.maidkit/blobs/$_blobId':
            return _json({'current_revision': 2}, 200);
          case '/flywheel/workspaces/$_workspaceId/apps/'
              'dev.solsynth.maidkit/blobs/$_blobId/content':
            return ResponseBody.fromString('remote-archive', 200);
          default:
            if (options.method == 'PUT') uploads++;
            return _json({'revision': 3}, 200);
        }
      });
    final service = CloudSyncService(
      vaultId: 'sync-vault',
      secureStorage: storage,
      dio: dio,
    );

    final configuration = await service.sync(
      archive: 'local-archive',
      applyArchive: (_) async => applied++,
      contentFingerprint: () async => 'local-fingerprint',
      compareAndMergeArchive:
          ({required localArchive, required remoteArchive}) async {
            expect(localArchive, 'local-archive');
            expect(remoteArchive, 'remote-archive');
            return const CloudSyncArchiveMergeResult.identical();
          },
    );

    expect(configuration.revision, 2);
    expect(configuration.lastContentFingerprint, 'local-fingerprint');
    expect(uploads, 0);
    expect(applied, 0);
  });

  test('silently applies and uploads an auto-merged archive', () async {
    final storage = _MemoryStorage()
      ..values[_sessionKey] = jsonEncode({
        'access_token': 'valid-token',
        'expires_at': DateTime.now()
            .add(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
      })
      ..values[_configurationKey('merge-vault')] = jsonEncode(
        _syncConfiguration(revision: 1),
      );
    var uploads = 0;
    String? appliedArchive;
    final dio = Dio()
      ..httpClientAdapter = _CannedAdapter((options) async {
        if (options.method == 'PUT') {
          uploads++;
          return _json({'revision': 3}, 200);
        }
        switch (options.uri.path) {
          case '/flywheel/workspaces/$_workspaceId/apps/'
              'dev.solsynth.maidkit/blobs/$_blobId':
            return _json({'current_revision': 2}, 200);
          case '/flywheel/workspaces/$_workspaceId/apps/'
              'dev.solsynth.maidkit/blobs/$_blobId/content':
            return ResponseBody.fromString('remote-archive', 200);
          default:
            return _json({}, 404);
        }
      });
    final service = CloudSyncService(
      vaultId: 'merge-vault',
      secureStorage: storage,
      dio: dio,
    );

    final configuration = await service.sync(
      archive: 'local-archive',
      applyArchive: (archive) async => appliedArchive = archive,
      contentFingerprint: () async => 'merged-fingerprint',
      compareAndMergeArchive:
          ({required localArchive, required remoteArchive}) async =>
              const CloudSyncArchiveMergeResult.merged('merged-archive'),
    );

    expect(appliedArchive, 'merged-archive');
    expect(uploads, 1);
    expect(configuration.revision, 3);
    expect(configuration.lastContentFingerprint, 'merged-fingerprint');
  });

  test('web signs in with the device flow and reports the code', () async {
    final storage = _MemoryStorage();
    SolarpassDeviceAuthorization? reported;
    var tokenPolls = 0;
    final dio = Dio()
      ..httpClientAdapter = _CannedAdapter((options) async {
        switch (options.uri.path) {
          case '/.well-known/openid-configuration':
            return _json({
              'authorization_endpoint': 'https://id.solian.app/authorize',
              'token_endpoint': 'https://id.solian.app/token',
              'device_authorization_endpoint': 'https://id.solian.app/device',
            }, 200);
          case '/device':
            return _json({
              'device_code': 'device-code-1',
              'user_code': 'ABCD-1234',
              'verification_uri': 'https://id.solian.app/activate',
              'verification_uri_complete':
                  'https://id.solian.app/activate?code=ABCD-1234',
              'expires_in': 600,
              'interval': 0,
            }, 200);
          case '/token':
            tokenPolls++;
            if (tokenPolls == 1) {
              return _json({'error': 'authorization_pending'}, 400);
            }
            return _json({
              'access_token': 'device-token',
              'refresh_token': 'device-refresh',
              'expires_in': 3600,
            }, 200);
          case '/stargate/accounts/me':
            return _json({'name': 'littlesheep', 'nick': 'Little Sheep'}, 200);
          default:
            return _json({}, 404);
        }
      });
    final service = CloudSyncService(
      vaultId: 'test-vault',
      secureStorage: storage,
      dio: dio,
      isWeb: true,
    );

    final user = await service.signIn(
      onDeviceCode: (authorization) => reported = authorization,
    );

    expect(user.handle, '@littlesheep');
    expect(user.name, 'Little Sheep');
    expect(reported?.userCode, 'ABCD-1234');
    expect(
      reported?.verificationUriComplete.toString(),
      'https://id.solian.app/activate?code=ABCD-1234',
    );
    expect(
      tokenPolls,
      2,
      reason: 'a pending answer is not the token and must be polled again',
    );
    expect(storage.values[_sessionKey], contains('device-token'));
  });

  test('web device flow surfaces a refused or expired code', () async {
    final storage = _MemoryStorage();
    final dio = Dio()
      ..httpClientAdapter = _CannedAdapter((options) async {
        switch (options.uri.path) {
          case '/.well-known/openid-configuration':
            return _json({
              'authorization_endpoint': 'https://id.solian.app/authorize',
              'token_endpoint': 'https://id.solian.app/token',
              'device_authorization_endpoint': 'https://id.solian.app/device',
            }, 200);
          case '/device':
            return _json({
              'device_code': 'device-code-1',
              'user_code': 'ABCD-1234',
              'verification_uri': 'https://id.solian.app/activate',
              'expires_in': 600,
              'interval': 0,
            }, 200);
          case '/token':
            return _json({'error': 'access_denied'}, 400);
          default:
            return _json({}, 404);
        }
      });
    final service = CloudSyncService(
      vaultId: 'test-vault',
      secureStorage: storage,
      dio: dio,
      isWeb: true,
    );

    await expectLater(
      service.signIn(onDeviceCode: (_) {}),
      throwsA(
        isA<CloudSyncException>().having(
          (error) => error.toString(),
          'message',
          contains('declined'),
        ),
      ),
    );
    expect(storage.values.containsKey(_sessionKey), isFalse);
  });

  test('web sign-in reports a deployment without device sign-in', () async {
    final storage = _MemoryStorage();
    final dio = Dio()
      ..httpClientAdapter = _CannedAdapter((options) async {
        switch (options.uri.path) {
          case '/.well-known/openid-configuration':
            return _json({
              'authorization_endpoint': 'https://id.solian.app/authorize',
              'token_endpoint': 'https://id.solian.app/token',
            }, 200);
          default:
            return _json({}, 404);
        }
      });
    final service = CloudSyncService(
      vaultId: 'test-vault',
      secureStorage: storage,
      dio: dio,
      isWeb: true,
    );

    await expectLater(
      service.signIn(onDeviceCode: (_) {}),
      throwsA(
        isA<CloudSyncException>().having(
          (error) => error.toString(),
          'message',
          contains('device sign-in'),
        ),
      ),
    );
  });

  test('runs concurrent syncs against one vault one at a time', () async {
    final storage = _MemoryStorage()
      ..values[_sessionKey] = jsonEncode({
        'access_token': 'valid-token',
        'expires_at': DateTime.now()
            .add(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
      })
      ..values[_configurationKey('race-vault')] = jsonEncode(
        _syncConfiguration(revision: 1),
      );
    var uploads = 0;
    var inFlight = 0;
    var maxInFlight = 0;
    final dio = Dio()
      ..httpClientAdapter = _CannedAdapter((options) async {
        if (options.method == 'PUT') {
          uploads++;
          inFlight++;
          if (inFlight > maxInFlight) maxInFlight = inFlight;
          // Hold the request open so an unserialized second upload would
          // overlap it.
          await Future<void>.delayed(const Duration(milliseconds: 20));
          inFlight--;
          return _json({'revision': 1 + uploads}, 200);
        }
        return _json({'current_revision': 1}, 200);
      });
    final service = CloudSyncService(
      vaultId: 'race-vault',
      secureStorage: storage,
      dio: dio,
    );

    await Future.wait([
      service.sync(archive: 'first', applyArchive: (_) async {}),
      service.sync(archive: 'second', applyArchive: (_) async {}),
    ]);

    expect(uploads, 2);
    expect(
      maxInFlight,
      1,
      reason: 'overlapping uploads for one blob are what triggered the race',
    );
  });

  test('reports an undownloadable cloud copy instead of a bare 404', () async {
    final storage = _MemoryStorage()
      ..values[_sessionKey] = jsonEncode({
        'access_token': 'valid-token',
        'expires_at': DateTime.now()
            .add(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
      })
      ..values[_configurationKey('damaged-vault')] = jsonEncode(
        _syncConfiguration(revision: 0, pendingDownload: true),
      );
    var applied = 0;
    final dio = Dio()
      ..httpClientAdapter = _CannedAdapter((options) async {
        if (options.uri.path.endsWith('/content')) {
          return _json({'error': 'Blob content is unavailable.'}, 404);
        }
        return _json({'current_revision': 3}, 200);
      });
    final service = CloudSyncService(
      vaultId: 'damaged-vault',
      secureStorage: storage,
      dio: dio,
    );

    await expectLater(
      service.sync(
        archive: 'local-archive',
        applyArchive: (_) async => applied++,
        conflictResolution: CloudSyncConflictResolution.downloadRemote,
      ),
      throwsA(
        isA<CloudSyncException>().having(
          (error) => error.toString(),
          'message',
          contains('unavailable on the server'),
        ),
      ),
    );
    expect(applied, 0);
  });

  test('overwrites a damaged cloud copy when the user asks to', () async {
    // The server still lists a newer revision but its bytes are gone. With an
    // explicit overwrite resolution (the path the 409 retry and the damaged
    // remote prompt take), the local copy must be published over the damaged
    // revision instead of failing the sync.
    final storage = _MemoryStorage()
      ..values[_sessionKey] = jsonEncode({
        'access_token': 'valid-token',
        'expires_at': DateTime.now()
            .add(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
      })
      ..values[_configurationKey('damaged-vault-overwrite')] = jsonEncode(
        _syncConfiguration(revision: 0),
      );
    int? expectedRevision;
    final dio = Dio()
      ..httpClientAdapter = _CannedAdapter((options) async {
        if (options.uri.path.endsWith('/content')) {
          return _json({'error': 'Blob content is unavailable.'}, 404);
        }
        if (options.method == 'PUT') {
          final data = options.data;
          if (data is FormData) {
            expectedRevision = int.tryParse(
              data.fields
                  .firstWhere((field) => field.key == 'ExpectedRevision')
                  .value,
            );
          }
          return _json({'revision': 4}, 200);
        }
        return _json({'current_revision': 3}, 200);
      });
    final service = CloudSyncService(
      vaultId: 'damaged-vault-overwrite',
      secureStorage: storage,
      dio: dio,
    );

    final configuration = await service.sync(
      archive: 'local-archive',
      applyArchive: (_) async {},
      conflictResolution: CloudSyncConflictResolution.overwriteRemote,
    );

    expect(expectedRevision, 3, reason: 'must replace the live revision');
    expect(configuration.revision, 4);
  });

  test('leaves a damaged cloud copy alone without confirmation', () async {
    // Without an app overlay the overwrite prompt cannot be answered, which
    // must not be read as consent: the sync fails and the cloud copy stays.
    final storage = _MemoryStorage()
      ..values[_sessionKey] = jsonEncode({
        'access_token': 'valid-token',
        'expires_at': DateTime.now()
            .add(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
      })
      ..values[_configurationKey('damaged-vault-unconfirmed')] = jsonEncode(
        _syncConfiguration(revision: 0),
      );
    var uploads = 0;
    final dio = Dio()
      ..httpClientAdapter = _CannedAdapter((options) async {
        if (options.uri.path.endsWith('/content')) {
          return _json({'error': 'Blob content is unavailable.'}, 404);
        }
        if (options.method == 'PUT') {
          uploads++;
          return _json({'revision': 4}, 200);
        }
        return _json({'current_revision': 3}, 200);
      });
    final service = CloudSyncService(
      vaultId: 'damaged-vault-unconfirmed',
      secureStorage: storage,
      dio: dio,
    );

    await expectLater(
      service.sync(archive: 'local-archive', applyArchive: (_) async {}),
      throwsA(
        isA<CloudSyncException>().having(
          (error) => error.toString(),
          'message',
          contains('unavailable on the server'),
        ),
      ),
    );
    expect(uploads, 0, reason: 'an unanswered prompt must not overwrite');
  });

  test('surfaces a byte-encoded server error body', () async {
    // The content route answers with raw bytes, so Dio hands the error body to
    // the service as a Uint8List. The JSON it contains must still be read.
    final storage = _MemoryStorage()
      ..values[_sessionKey] = jsonEncode({
        'access_token': 'valid-token',
        'expires_at': DateTime.now()
            .add(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
      })
      ..values[_configurationKey('byte-error-vault')] = jsonEncode(
        _syncConfiguration(revision: 0),
      );
    final dio = Dio()
      ..httpClientAdapter = _CannedAdapter((options) async {
        if (options.uri.path.endsWith('/content')) {
          return _json({'error': 'Flywheel exploded.'}, 500);
        }
        return _json({'current_revision': 3}, 200);
      });
    final service = CloudSyncService(
      vaultId: 'byte-error-vault',
      secureStorage: storage,
      dio: dio,
    );

    await expectLater(
      service.sync(
        archive: 'local-archive',
        applyArchive: (_) async {},
        conflictResolution: CloudSyncConflictResolution.downloadRemote,
      ),
      throwsA(
        isA<CloudSyncException>().having(
          (error) => error.toString(),
          'message',
          contains('Flywheel exploded.'),
        ),
      ),
    );
  });

  test('fails a pending download whose cloud blob has vanished', () async {
    final storage = _MemoryStorage()
      ..values[_sessionKey] = jsonEncode({
        'access_token': 'valid-token',
        'expires_at': DateTime.now()
            .add(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
      })
      ..values[_configurationKey('gone-vault')] = jsonEncode(
        _syncConfiguration(revision: 0, pendingDownload: true),
      );
    var uploads = 0;
    final dio = Dio()
      ..httpClientAdapter = _CannedAdapter((options) async {
        if (options.method == 'PUT') {
          uploads++;
          return _json({'revision': 1}, 200);
        }
        return _json({'error': 'Blob not found.'}, 404);
      });
    final service = CloudSyncService(
      vaultId: 'gone-vault',
      secureStorage: storage,
      dio: dio,
    );

    await expectLater(
      service.sync(
        archive: 'local-archive',
        applyArchive: (_) async {},
        conflictResolution: CloudSyncConflictResolution.downloadRemote,
      ),
      throwsA(
        isA<CloudSyncException>().having(
          (error) => error.toString(),
          'message',
          contains('could not be found'),
        ),
      ),
    );
    expect(uploads, 0, reason: 'a vanished cloud copy must not be recreated');
  });

  test('refuses to sync a configuration whose ids are not GUIDs', () async {
    // A stale config with a non-GUID workspace/blob id makes every Flywheel
    // request miss its route and answer a body-less 404. The service must
    // catch that before it sends anything.
    final storage = _MemoryStorage()
      ..values[_sessionKey] = jsonEncode({
        'access_token': 'valid-token',
        'expires_at': DateTime.now()
            .add(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
      })
      ..values[_configurationKey('bad-config-vault')] = jsonEncode({
        'workspaceId': 'workspace-1',
        'workspaceName': 'Test workspace',
        'workspaceSlug': 'test',
        'blobId': 'blob-1',
        'revision': 0,
        'pendingDownload': false,
      });
    var requests = 0;
    final dio = Dio()
      ..httpClientAdapter = _CannedAdapter((options) async {
        requests++;
        return _json({}, 404);
      });
    final service = CloudSyncService(
      vaultId: 'bad-config-vault',
      secureStorage: storage,
      dio: dio,
    );

    await expectLater(
      service.sync(archive: 'local-archive', applyArchive: (_) async {}),
      throwsA(
        isA<CloudSyncException>().having(
          (error) => error.toString(),
          'message',
          contains('invalid cloud workspace'),
        ),
      ),
    );
    expect(requests, 0, reason: 'an invalid config must not reach the network');
  });

  test('accepts an undashed GUID on both path segments', () async {
    // ASP.NET's `:guid` constraint is `Guid.TryParse`, which also takes the
    // undashed "N" form. The pre-flight check must not be stricter than the
    // route, or it would refuse a binding the server would route fine.
    const compactWorkspaceId = '11111111111111111111111111111111';
    const compactBlobId = '22222222222222222222222222222222';
    final storage = _MemoryStorage()
      ..values[_sessionKey] = jsonEncode({
        'access_token': 'valid-token',
        'expires_at': DateTime.now()
            .add(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
      })
      ..values[_configurationKey('compact-vault')] = jsonEncode({
        'workspaceId': compactWorkspaceId,
        'workspaceName': 'Test workspace',
        'workspaceSlug': 'test',
        'blobId': compactBlobId,
        'revision': 0,
        'pendingDownload': false,
      });
    var uploads = 0;
    final dio = Dio()
      ..httpClientAdapter = _CannedAdapter((options) async {
        if (options.method == 'PUT') {
          uploads++;
          return _json({'revision': 1}, 200);
        }
        return _json({'current_revision': 0}, 200);
      });
    final service = CloudSyncService(
      vaultId: 'compact-vault',
      secureStorage: storage,
      dio: dio,
    );

    final configuration = await service.sync(
      archive: 'local-archive',
      applyArchive: (_) async {},
    );

    expect(uploads, 1, reason: 'an undashed GUID is valid for the route');
    expect(configuration.revision, 1);
  });

  test('refuses to enable a workspace whose id is not a GUID', () async {
    // A workspace list that returns a slug (as the pre-GUID API did) must not
    // be persisted: it would make every Flywheel request miss its route and
    // answer a body-less 404 on both upload and download.
    var requests = 0;
    final dio = Dio()
      ..httpClientAdapter = _CannedAdapter((options) async {
        requests++;
        return _json({}, 404);
      });
    final service = CloudSyncService(
      vaultId: 'link-vault',
      secureStorage: _MemoryStorage(),
      dio: dio,
    );

    await expectLater(
      service.enable(
        const CloudWorkspace(
          id: 'personal',
          slug: 'personal',
          name: 'Personal',
        ),
      ),
      throwsA(
        isA<CloudSyncException>().having(
          (error) => error.toString(),
          'message',
          contains('invalid workspace id'),
        ),
      ),
    );
    expect(
      requests,
      0,
      reason: 'a bad workspace id must not reach the network',
    );
  });

  test('refuses to enable a cloud vault whose blob id is not a GUID', () async {
    final service = CloudSyncService(
      vaultId: 'link-blob-vault',
      secureStorage: _MemoryStorage(),
      dio: Dio(),
    );

    await expectLater(
      service.enable(
        const CloudWorkspace(
          id: _workspaceId,
          slug: 'test',
          name: 'Test workspace',
        ),
        existingBlob: const CloudVaultBlob(
          id: 'legacy-blob',
          revision: 3,
          updatedAt: null,
        ),
      ),
      throwsA(
        isA<CloudSyncException>().having(
          (error) => error.toString(),
          'message',
          contains('invalid id'),
        ),
      ),
    );
  });

  test('recreates a vanished cloud blob from revision zero', () async {
    // The blob is gone (deleted, or orphaned by an app-id rename) but this
    // device still holds the vault. Uploading against the stale revision
    // would 409 forever, so the local copy is republished from scratch.
    final storage = _MemoryStorage()
      ..values[_sessionKey] = jsonEncode({
        'access_token': 'valid-token',
        'expires_at': DateTime.now()
            .add(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
      })
      ..values[_configurationKey('orphaned-vault')] = jsonEncode(
        _syncConfiguration(revision: 4),
      );
    int? expectedRevision;
    var uploads = 0;
    final dio = Dio()
      ..httpClientAdapter = _CannedAdapter((options) async {
        if (options.method == 'PUT') {
          uploads++;
          final data = options.data;
          if (data is FormData) {
            expectedRevision = int.tryParse(
              data.fields
                  .firstWhere((field) => field.key == 'ExpectedRevision')
                  .value,
            );
          }
          return _json({'revision': 1}, 200);
        }
        return _json({'error': 'Blob not found.'}, 404);
      });
    final service = CloudSyncService(
      vaultId: 'orphaned-vault',
      secureStorage: storage,
      dio: dio,
    );

    final configuration = await service.sync(
      archive: 'local-archive',
      applyArchive: (_) async {},
    );

    expect(uploads, 1);
    expect(
      expectedRevision,
      0,
      reason:
          'a missing blob must be recreated, not uploaded against a '
          'revision the server no longer has',
    );
    expect(configuration.revision, 1);
  });

  test('names the request when the server answers a body-less 404', () async {
    final storage = _MemoryStorage()
      ..values[_sessionKey] = jsonEncode({
        'access_token': 'valid-token',
        'expires_at': DateTime.now()
            .add(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
      })
      ..values[_configurationKey('route-miss-vault')] = jsonEncode(
        _syncConfiguration(revision: 0),
      );
    final dio = Dio()
      ..httpClientAdapter = _CannedAdapter((options) async {
        if (options.method == 'PUT') {
          return ResponseBody.fromString(
            '',
            404,
            headers: {
              Headers.contentTypeHeader: ['text/plain'],
            },
          );
        }
        return _json({'current_revision': 0}, 200);
      });
    final service = CloudSyncService(
      vaultId: 'route-miss-vault',
      secureStorage: storage,
      dio: dio,
    );

    await expectLater(
      service.sync(archive: 'local-archive', applyArchive: (_) async {}),
      throwsA(
        isA<CloudSyncException>().having(
          (error) => error.toString(),
          'message',
          allOf(
            contains('HTTP 404'),
            contains('/flywheel/workspaces/$_workspaceId'),
          ),
        ),
      ),
    );
  });
}
