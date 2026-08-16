import 'package:drift/drift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/vault_service.dart';

/// Storage for GitHub access tokens. Tokens are encrypted with the vault data
/// key and stored inside the vault database, so they sync with the vault and
/// survive vault migration instead of rendering a synced connection as
/// signed-out.
abstract interface class GitHubTokenStorage {
  Future<String?> read(String login);

  Future<void> write(String login, String token);

  Future<void> delete(String login);
}

/// Vault-backed token storage. The token is encrypted with the vault key and
/// kept in [GitHubTokens], mirroring how SSH credentials and agent API keys
/// are stored; only the ciphertext ever touches the database.
///
/// Tokens written before this storage existed (OS keychain entries under
/// `maidkit_github_token_<login>`) are migrated on first read: the legacy
/// value is encrypted into the vault and the keychain copy deleted.
class VaultGitHubTokenStorage implements GitHubTokenStorage {
  VaultGitHubTokenStorage(
    this._database,
    this._vault, {
    GitHubTokenStorage? legacy,
  }) : _legacy = legacy ?? SecureGitHubTokenStorage();

  final AppDatabase _database;
  final VaultService _vault;
  final GitHubTokenStorage _legacy;

  static const _context = 'github-token';

  @override
  Future<String?> read(String login) async {
    final row = await (_database.select(
      _database.gitHubTokens,
    )..where((table) => table.accountLogin.equals(login))).getSingleOrNull();
    if (row != null) {
      return _vault.decrypt(
        EncryptedValue(bytes: row.encryptedToken, nonce: row.tokenNonce),
        context: _context,
      );
    }
    // Migrate a pre-vault keychain token so it syncs like every other secret.
    // The keychain is a migration source only: a read failure there degrades
    // to "no token" instead of breaking the GitHub tab.
    String? legacyToken;
    try {
      legacyToken = await _legacy.read(login);
    } catch (_) {
      return null;
    }
    if (legacyToken == null) return null;
    await write(login, legacyToken);
    return legacyToken;
  }

  @override
  Future<void> write(String login, String token) async {
    final encrypted = await _vault.encrypt(token, context: _context);
    await _database
        .into(_database.gitHubTokens)
        .insert(
          GitHubTokensCompanion.insert(
            accountLogin: login,
            encryptedToken: encrypted.bytes,
            tokenNonce: encrypted.nonce,
            updatedAt: DateTime.now().toUtc(),
          ),
          mode: InsertMode.insertOrReplace,
        );
    await _discardLegacy(login);
  }

  @override
  Future<void> delete(String login) async {
    await (_database.delete(
      _database.gitHubTokens,
    )..where((table) => table.accountLogin.equals(login))).go();
    await _discardLegacy(login);
  }

  /// Best-effort keychain cleanup: a surviving copy is inert because the
  /// vault row wins on read, and it is re-migrated or deleted on a later
  /// sign-out. Failures must not fail a sign-in, sign-out, or token write.
  Future<void> _discardLegacy(String login) async {
    try {
      await _legacy.delete(login);
    } catch (_) {
      // Ignored: stale keychain entry only.
    }
  }
}

/// Legacy keychain-backed token storage through [FlutterSecureStorage]. Kept
/// as the migration source for tokens written before vault-backed storage:
/// [VaultGitHubTokenStorage] reads through it once and then removes the entry.
class SecureGitHubTokenStorage implements GitHubTokenStorage {
  SecureGitHubTokenStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _prefix = 'maidkit_github_token';

  String _key(String login) => '${_prefix}_$login';

  @override
  Future<String?> read(String login) => _storage.read(key: _key(login));

  @override
  Future<void> write(String login, String token) =>
      _storage.write(key: _key(login), value: token);

  @override
  Future<void> delete(String login) => _storage.delete(key: _key(login));
}

/// In-memory token storage for tests.
class InMemoryGitHubTokenStorage implements GitHubTokenStorage {
  final Map<String, String> _tokens = {};

  @override
  Future<String?> read(String login) async => _tokens[login];

  @override
  Future<void> write(String login, String token) async =>
      _tokens[login] = token;

  @override
  Future<void> delete(String login) async => _tokens.remove(login);
}
