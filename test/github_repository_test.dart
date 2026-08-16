import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/github/github_models.dart';
import 'package:maid_kit/github/github_repository.dart';
import 'package:maid_kit/github/github_token_store.dart';
import 'package:maid_kit/servers/database_backup_service.dart';
import 'package:maid_kit/servers/vault_service.dart';

/// In-memory stand-in for the OS keychain so vault creation (which caches the
/// sync passphrase) works without a platform implementation.
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

/// drift_flutter resolves its native database directory through
/// path_provider; point it at the system temp directory in tests.
void _mockPathProvider() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        return Directory.systemTemp.path;
      });
}

AppDatabase _database() {
  final directory = Directory.systemTemp.createTempSync('github_test');
  return AppDatabase(filePath: '${directory.path}/test.sqlite');
}

Map<String, Object?> _emptyPayload() => {
  'version': 3,
  'servers': <Object>[],
  'savedCredentials': <Object>[],
  'composeProjectLinks': <Object>[],
  'containerCacheEntries': <Object>[],
  'deploymentProjects': <Object>[],
  'deploymentResources': <Object>[],
  'scriptSnippets': <Object>[],
  'githubConnections': <Object>[],
  'githubRepoPins': <Object>[],
  'githubTokens': <Object>[],
};

void main() {
  _mockPathProvider();

  group('GitHubRepository', () {
    test('saveConnection inserts then updates the same login', () async {
      final database = _database();
      addTearDown(database.close);
      final repository = GitHubRepository(
        database,
        InMemoryGitHubTokenStorage(),
      );

      final first = await repository.saveConnection(
        const GitHubAccount(
          login: 'octocat',
          name: 'Octo Cat',
          avatarUrl: 'https://example.com/a.png',
        ),
      );
      final second = await repository.saveConnection(
        const GitHubAccount(
          login: 'octocat',
          name: 'Octocat',
          avatarUrl: 'https://example.com/b.png',
        ),
      );
      expect(second.id, first.id);
      expect(await repository.watchConnections().first, hasLength(1));
      expect(second.accountName, 'Octocat');
      expect(second.avatarUrl, 'https://example.com/b.png');
    });

    test('pinRepo is idempotent and unpin removes the pin', () async {
      final database = _database();
      addTearDown(database.close);
      final repository = GitHubRepository(
        database,
        InMemoryGitHubTokenStorage(),
      );
      final connection = await repository.saveConnection(
        const GitHubAccount(login: 'octocat', name: '', avatarUrl: ''),
      );

      const repo = GitHubRepoRef(owner: 'octocat', name: 'hello');
      await repository.pinRepo(connection.id, repo);
      await repository.pinRepo(connection.id, repo);
      var pins = await repository.watchRepoPins().first;
      expect(pins, hasLength(1));
      expect(pins.single.name, 'hello');

      await repository.unpinRepo(pins.single);
      pins = await repository.watchRepoPins().first;
      expect(pins, isEmpty);
    });

    test('token round-trips through the token store', () async {
      final database = _database();
      addTearDown(database.close);
      final storage = InMemoryGitHubTokenStorage();
      final repository = GitHubRepository(database, storage);
      await repository.saveToken('octocat', 'secret-token');
      expect(await repository.tokenFor('octocat'), 'secret-token');
      await repository.removeToken('octocat');
      expect(await repository.tokenFor('octocat'), isNull);
    });

    test('removeConnection cascades pins', () async {
      final database = _database();
      addTearDown(database.close);
      final repository = GitHubRepository(
        database,
        InMemoryGitHubTokenStorage(),
      );
      final connection = await repository.saveConnection(
        const GitHubAccount(login: 'octocat', name: '', avatarUrl: ''),
      );
      await repository.pinRepo(
        connection.id,
        const GitHubRepoRef(owner: 'o', name: 'r'),
      );
      await repository.removeConnection(connection);
      expect(await repository.watchRepoPins().first, isEmpty);
      expect(await repository.watchConnections().first, isEmpty);
    });
  });

  group('DatabaseBackupService GitHub sync', () {
    test('exportPayload includes GitHub metadata and tokens', () async {
      final database = _database();
      addTearDown(database.close);
      final vault = VaultService(database, secureStorage: _MemoryStorage());
      await vault.create('password');
      final repository = GitHubRepository(
        database,
        VaultGitHubTokenStorage(database, vault),
      );
      await repository.saveConnection(
        const GitHubAccount(
          login: 'octocat',
          name: 'Octo Cat',
          avatarUrl: 'https://example.com/a.png',
        ),
      );
      await repository.saveToken('octocat', 'gho_secret');
      final service = DatabaseBackupService(database, vault);
      final payload = jsonDecode(await service.exportPayload()) as Map;
      final connections = payload['githubConnections'] as List;
      expect(connections, hasLength(1));
      final connection = connections.single as Map;
      expect(connection['accountLogin'], 'octocat');
      // Tokens never appear on the connection record.
      expect(connection.containsKey('token'), isFalse);
      // The vault-encrypted token is decrypted into the syncable payload.
      final tokens = payload['githubTokens'] as List;
      expect(tokens, hasLength(1));
      final token = tokens.single as Map;
      expect(token['accountLogin'], 'octocat');
      expect(token['token'], 'gho_secret');
    });

    test('importPayload restores and re-encrypts GitHub tokens', () async {
      final database = _database();
      addTearDown(database.close);
      final vault = VaultService(database, secureStorage: _MemoryStorage());
      await vault.create('password');
      final service = DatabaseBackupService(database, vault);
      final payload = {
        ..._emptyPayload(),
        'githubConnections': [
          {
            'id': 1,
            'accountLogin': 'octocat',
            'accountName': 'Octo Cat',
            'avatarUrl': 'https://example.com/a.png',
            'createdAt': '2026-01-01T00:00:00.000Z',
          },
        ],
        'githubTokens': [
          {
            'id': 1,
            'accountLogin': 'octocat',
            'token': 'gho_secret',
            'updatedAt': '2026-01-01T00:00:00.000Z',
          },
        ],
      };
      await service.importPayload(jsonEncode(payload));

      final storage = VaultGitHubTokenStorage(database, vault);
      expect(await storage.read('octocat'), 'gho_secret');
      // The imported token is re-encrypted with this vault's data key, so
      // the plaintext never lands in the database.
      final rows = await database.select(database.gitHubTokens).get();
      expect(rows, hasLength(1));
      expect(rows.single.encryptedToken, isNot(contains('gho_secret')));
    });

    test('importPayload restores connections and pins', () async {
      final database = _database();
      addTearDown(database.close);
      final service = DatabaseBackupService(database, VaultService(database));
      final payload = {
        ..._emptyPayload(),
        'githubConnections': [
          {
            'id': 1,
            'accountLogin': 'octocat',
            'accountName': 'Octo Cat',
            'avatarUrl': 'https://example.com/a.png',
            'createdAt': '2026-01-01T00:00:00.000Z',
          },
        ],
        'githubRepoPins': [
          {
            'id': 1,
            'connectionId': 1,
            'owner': 'octocat',
            'name': 'hello',
            'pinnedAt': '2026-01-01T00:00:00.000Z',
          },
        ],
      };
      await service.importPayload(jsonEncode(payload));

      final repository = GitHubRepository(
        database,
        InMemoryGitHubTokenStorage(),
      );
      final connections = await repository.watchConnections().first;
      expect(connections.single.accountLogin, 'octocat');
      final pins = await repository.watchRepoPins().first;
      expect(pins.single.owner, 'octocat');
    });

    test('importPayload tolerates archives without GitHub keys', () async {
      final database = _database();
      addTearDown(database.close);
      final service = DatabaseBackupService(database, VaultService(database));
      await service.importPayload(jsonEncode(_emptyPayload()));
      final repository = GitHubRepository(
        database,
        InMemoryGitHubTokenStorage(),
      );
      expect(await repository.watchConnections().first, isEmpty);
      expect(await repository.watchRepoPins().first, isEmpty);
      expect(await database.select(database.gitHubTokens).get(), isEmpty);
    });
  });
}
