import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/github/github_token_store.dart';
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

void main() {
  _mockPathProvider();

  late AppDatabase database;
  late VaultService vault;

  setUp(() async {
    final directory = Directory.systemTemp.createTempSync('github_token_test');
    database = AppDatabase(filePath: '${directory.path}/test.sqlite');
    vault = VaultService(database, secureStorage: _MemoryStorage());
    await vault.create('password');
  });

  tearDown(() async => database.close());

  test('write then read round-trips the token', () async {
    final storage = VaultGitHubTokenStorage(database, vault);
    await storage.write('octocat', 'gho_secret');
    expect(await storage.read('octocat'), 'gho_secret');
  });

  test('write replaces an existing token for the same login', () async {
    final storage = VaultGitHubTokenStorage(database, vault);
    await storage.write('octocat', 'first');
    await storage.write('octocat', 'second');
    expect(await storage.read('octocat'), 'second');
    expect(await database.select(database.gitHubTokens).get(), hasLength(1));
  });

  test('the database only ever holds ciphertext', () async {
    final storage = VaultGitHubTokenStorage(database, vault);
    await storage.write('octocat', 'gho_secret');
    final rows = await database.select(database.gitHubTokens).get();
    expect(rows, hasLength(1));
    expect(rows.single.accountLogin, 'octocat');
    expect(rows.single.encryptedToken, isNot(contains('gho_secret')));
    expect(rows.single.tokenNonce, isNotEmpty);
  });

  test('delete removes the vault row', () async {
    final storage = VaultGitHubTokenStorage(database, vault);
    await storage.write('octocat', 'gho_secret');
    await storage.delete('octocat');
    expect(await storage.read('octocat'), isNull);
    expect(await database.select(database.gitHubTokens).get(), isEmpty);
  });

  test('read migrates a legacy keychain token into the vault', () async {
    final legacy = InMemoryGitHubTokenStorage();
    await legacy.write('octocat', 'gho_legacy');
    final storage = VaultGitHubTokenStorage(database, vault, legacy: legacy);

    expect(await storage.read('octocat'), 'gho_legacy');
    // The vault now holds it and the keychain copy is consumed.
    expect(await database.select(database.gitHubTokens).get(), hasLength(1));
    expect(await legacy.read('octocat'), isNull);
  });

  test('delete clears legacy keychain copies too', () async {
    final legacy = InMemoryGitHubTokenStorage();
    await legacy.write('octocat', 'gho_legacy');
    final storage = VaultGitHubTokenStorage(database, vault, legacy: legacy);

    await storage.delete('octocat');
    expect(await legacy.read('octocat'), isNull);
    expect(await database.select(database.gitHubTokens).get(), isEmpty);
  });

  test('read returns null when no token exists anywhere', () async {
    final storage = VaultGitHubTokenStorage(database, vault);
    expect(await storage.read('nobody'), isNull);
  });

  test('read while the vault is locked throws VaultLockedException', () async {
    final storage = VaultGitHubTokenStorage(database, vault);
    await storage.write('octocat', 'gho_secret');
    await vault.lock();

    await expectLater(
      storage.read('octocat'),
      throwsA(isA<VaultLockedException>()),
    );
  });
}
