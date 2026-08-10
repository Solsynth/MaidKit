import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'package:maid_kit/data/local/app_database.dart';

class VaultLockedException implements Exception {
  const VaultLockedException();
}

class BiometricUnlockException implements Exception {
  const BiometricUnlockException(this.message);
  final String message;

  @override
  String toString() => message;
}

class VaultService {
  VaultService(
    this._database, {
    FlutterSecureStorage? secureStorage,
    String vaultId = 'maid_kit',
  }) : _vaultId = vaultId,
       _biometricKey =
           '${_biometricKeyPrefix}_${base64UrlEncode(utf8.encode(vaultId))}',
       _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _biometricKeyPrefix = 'maidkit_vault_data_key';
  static const _syncPassphraseKeyPrefix = 'maidkit_vault_sync_passphrase';
  static const _iterations = 310000;
  static final Map<String, String> _syncPassphrases = {};
  static String _key(String prefix, String vaultId) =>
      '${prefix}_${base64UrlEncode(utf8.encode(vaultId))}';

  /// Moves vault-scoped keychain entries when a database file is relocated.
  static Future<void> relocateStoredKeys({
    required String oldVaultId,
    required String newVaultId,
    FlutterSecureStorage? secureStorage,
  }) async {
    final storage = secureStorage ?? const FlutterSecureStorage();
    for (final prefix in [_biometricKeyPrefix, _syncPassphraseKeyPrefix]) {
      final oldKey = _key(prefix, oldVaultId);
      final newKey = _key(prefix, newVaultId);
      final value = await storage.read(key: oldKey);
      if (value != null) {
        await storage.write(key: newKey, value: value);
        await storage.delete(key: oldKey);
      }
    }
  }

  final AppDatabase _database;
  final FlutterSecureStorage _secureStorage;
  final String _vaultId;
  final String _biometricKey;
  final AesGcm _cipher = AesGcm.with256bits();
  SecretKey? _dataKey;

  bool get isUnlocked => _dataKey != null;
  String get _syncPassphraseKey => _key(_syncPassphraseKeyPrefix, _vaultId);

  Future<String?> syncPassphrase() async {
    final cached = _syncPassphrases[_vaultId];
    if (cached != null) return cached;
    final dataKey = _dataKey;
    if (dataKey == null) return null;

    String? passphrase;
    String? raw;
    try {
      final metadata = await _metadata();
      if (metadata.syncPassphraseCiphertext != null &&
          metadata.syncPassphraseNonce != null) {
        passphrase = await _decryptStoredPassphrase(
          metadata.syncPassphraseCiphertext!,
          metadata.syncPassphraseNonce!,
          dataKey,
        );
      }
    } catch (_) {
      passphrase = null;
    }
    if (passphrase == null) {
      raw = await _secureStorage.read(key: _syncPassphraseKey);
      if (raw == null) return null;
      try {
        final value = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        passphrase = await _decryptStoredPassphrase(
          value['ciphertext'] as String,
          value['nonce'] as String,
          dataKey,
        );
      } catch (_) {
        await _secureStorage.delete(key: _syncPassphraseKey);
        return null;
      }
    }
    _syncPassphrases[_vaultId] = passphrase;
    // Migrate a keychain-only copy into the vault so it can never be lost.
    if (raw != null) await _cacheSyncPassphrase(passphrase);
    return passphrase;
  }

  Future<String> _decryptStoredPassphrase(
    String ciphertext,
    String nonce,
    SecretKey dataKey,
  ) async {
    final clear = await _decryptBytes(
      _decode(ciphertext),
      _decode(nonce),
      dataKey,
      'sync-passphrase',
    );
    return utf8.decode(clear);
  }

  Future<bool> hasVault() async =>
      (await _database.select(_database.vaultMetadata).get()).isNotEmpty;

  Future<bool> isBiometricUnlockEnabled() async =>
      await _secureStorage.containsKey(key: _biometricKey);

  Future<void> create(String password) async {
    final salt = _randomBytes(16);
    final wrappingKey = await _deriveKey(password, salt);
    final dataKey = await _cipher.newSecretKey();
    final dataKeyBytes = await dataKey.extractBytes();
    final wrapped = await _encryptBytes(dataKeyBytes, wrappingKey, 'vault-key');
    final verifier = await _encryptBytes(
      utf8.encode('MaidKit vault v1'),
      dataKey,
      'verifier',
    );
    await _database
        .into(_database.vaultMetadata)
        .insert(
          VaultMetadataCompanion.insert(
            formatVersion: 1,
            salt: _encode(salt),
            wrappedDataKey: _encode(_pack(wrapped)),
            wrappedDataKeyNonce: _encode(wrapped.nonce),
            verifier: _encode(_pack(verifier)),
            verifierNonce: _encode(verifier.nonce),
            createdAt: DateTime.now().toUtc(),
          ),
        );
    _dataKey = dataKey;
    await _cacheSyncPassphrase(password);
  }

  Future<bool> unlockWithPassword(String password) async {
    final metadata = await _metadata();
    try {
      final wrappingKey = await _deriveKey(password, _decode(metadata.salt));
      final bytes = await _decryptBytes(
        _decode(metadata.wrappedDataKey),
        _decode(metadata.wrappedDataKeyNonce),
        wrappingKey,
        'vault-key',
      );
      final candidate = SecretKey(bytes);
      await _decryptBytes(
        _decode(metadata.verifier),
        _decode(metadata.verifierNonce),
        candidate,
        'verifier',
      );
      _dataKey = candidate;
      await _cacheSyncPassphrase(password);
      return true;
    } on SecretBoxAuthenticationError {
      return false;
    } on ArgumentError {
      return false;
    }
  }

  Future<bool> unlockWithBiometrics() async {
    final key = await _secureStorage.read(key: _biometricKey);
    if (key == null) {
      throw const BiometricUnlockException(
        'Biometric unlock is not enabled. Unlock with your vault password, then enable it in Settings.',
      );
    }
    final authentication = LocalAuthentication();
    if (!await authentication.isDeviceSupported() ||
        !await authentication.canCheckBiometrics) {
      throw const BiometricUnlockException(
        'Touch ID is unavailable. Set up Touch ID in macOS System Settings, then try again.',
      );
    }
    try {
      final authenticated = await authentication.authenticate(
        localizedReason: 'Unlock your MaidKit vault',
        biometricOnly: true,
      );
      if (!authenticated) {
        throw const BiometricUnlockException(
          'Biometric authentication was cancelled.',
        );
      }
      _dataKey = SecretKey(_decode(key));
      return true;
    } on BiometricUnlockException {
      rethrow;
    } catch (error) {
      throw BiometricUnlockException('Biometric unlock failed: $error');
    }
  }

  /// Prompts for biometrics once, then stores the data key for future unlocks.
  /// Does not enable on failure (nothing is written).
  Future<void> enableBiometricUnlock() async {
    final key = _requireKey();
    final authentication = LocalAuthentication();
    if (!await authentication.isDeviceSupported() ||
        !await authentication.canCheckBiometrics) {
      throw const BiometricUnlockException(
        'Biometrics are unavailable on this device.',
      );
    }
    try {
      final authenticated = await authentication.authenticate(
        localizedReason: 'Enable biometric unlock for MaidKit',
        biometricOnly: true,
      );
      if (!authenticated) {
        throw const BiometricUnlockException(
          'Biometric authentication was cancelled.',
        );
      }
    } on BiometricUnlockException {
      rethrow;
    } catch (error) {
      throw BiometricUnlockException('Biometric setup failed: $error');
    }
    await _secureStorage.write(
      key: _biometricKey,
      value: _encode(await key.extractBytes()),
    );
  }

  Future<void> disableBiometricUnlock() =>
      _secureStorage.delete(key: _biometricKey);

  Future<void> lock() async {
    _dataKey = null;
    _syncPassphrases.remove(_vaultId);
  }

  /// Rewraps the existing data key with [newPassword]. Stored vault data and
  /// biometric access stay valid because the data key itself does not change.
  Future<void> changePassword(String newPassword) async {
    final dataKey = _requireKey();
    final metadata = await _metadata();
    final salt = _randomBytes(16);
    final wrappingKey = await _deriveKey(newPassword, salt);
    final wrapped = await _encryptBytes(
      await dataKey.extractBytes(),
      wrappingKey,
      'vault-key',
    );
    await (_database.update(
      _database.vaultMetadata,
    )..where((table) => table.id.equals(metadata.id))).write(
      VaultMetadataCompanion(
        salt: Value(_encode(salt)),
        wrappedDataKey: Value(_encode(_pack(wrapped))),
        wrappedDataKeyNonce: Value(_encode(wrapped.nonce)),
      ),
    );
    await _cacheSyncPassphrase(newPassword);
  }

  Future<void> discardNewVault() async {
    await _database.delete(_database.vaultMetadata).go();
    await _secureStorage.delete(key: _syncPassphraseKey);
    await lock();
  }

  Future<void> _cacheSyncPassphrase(String passphrase) async {
    final box = await _encryptBytes(
      utf8.encode(passphrase),
      _requireKey(),
      'sync-passphrase',
    );
    _syncPassphrases[_vaultId] = passphrase;
    final ciphertext = _encode(_pack(box));
    final nonce = _encode(box.nonce);
    await _secureStorage.write(
      key: _syncPassphraseKey,
      value: jsonEncode({'ciphertext': ciphertext, 'nonce': nonce}),
    );
    // Persist with the vault so biometric unlock can always recover it via the
    // data key, independent of the OS keychain.
    final metadata = await _metadata();
    await (_database.update(
      _database.vaultMetadata,
    )..where((table) => table.id.equals(metadata.id))).write(
      VaultMetadataCompanion(
        syncPassphraseCiphertext: Value(ciphertext),
        syncPassphraseNonce: Value(nonce),
      ),
    );
  }

  Future<EncryptedValue> encrypt(
    String value, {
    required String context,
  }) async {
    final box = await _encryptBytes(utf8.encode(value), _requireKey(), context);
    return EncryptedValue(
      bytes: _encode(_pack(box)),
      nonce: _encode(box.nonce),
    );
  }

  Future<String> decrypt(
    EncryptedValue value, {
    required String context,
  }) async {
    final clear = await _decryptBytes(
      _decode(value.bytes),
      _decode(value.nonce),
      _requireKey(),
      context,
    );
    return utf8.decode(clear);
  }

  /// Encrypts a portable archive with the supplied vault password instead of
  /// this device's data key, so another vault can import it.
  Future<String> encryptPortable(String value, String password) async {
    final salt = _randomBytes(16);
    final key = await _deriveKey(password, salt);
    final box = await _encryptBytes(
      utf8.encode(value),
      key,
      'portable-archive',
    );
    return jsonEncode({
      'version': 1,
      'salt': _encode(salt),
      'ciphertext': _encode(_pack(box)),
      'nonce': _encode(box.nonce),
    });
  }

  Future<String> decryptPortable(String archive, String password) async {
    final value = jsonDecode(archive) as Map<String, dynamic>;
    if (value['version'] != 1) {
      throw const FormatException('Unsupported archive version.');
    }
    final key = await _deriveKey(password, _decode(value['salt'] as String));
    final clear = await _decryptBytes(
      _decode(value['ciphertext'] as String),
      _decode(value['nonce'] as String),
      key,
      'portable-archive',
    );
    return utf8.decode(clear);
  }

  Future<VaultMetadataData> _metadata() async =>
      (await _database.select(_database.vaultMetadata).getSingle());

  SecretKey _requireKey() => _dataKey ?? (throw const VaultLockedException());

  Future<SecretKey> _deriveKey(String password, List<int> salt) => Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: 256,
  ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);

  Future<SecretBox> _encryptBytes(
    List<int> bytes,
    SecretKey key,
    String context,
  ) => _cipher.encrypt(bytes, secretKey: key, aad: utf8.encode(context));

  Future<List<int>> _decryptBytes(
    List<int> bytes,
    List<int> nonce,
    SecretKey key,
    String context,
  ) => _cipher.decrypt(
    SecretBox(
      bytes.sublist(0, bytes.length - 16),
      nonce: nonce,
      mac: Mac(bytes.sublist(bytes.length - 16)),
    ),
    secretKey: key,
    aad: utf8.encode(context),
  );

  List<int> _randomBytes(int length) =>
      List<int>.generate(length, (_) => Random.secure().nextInt(256));
  List<int> _pack(SecretBox box) => [...box.cipherText, ...box.mac.bytes];
  String _encode(List<int> bytes) => base64UrlEncode(bytes);
  List<int> _decode(String value) =>
      base64Url.decode(base64Url.normalize(value));
}

class EncryptedValue {
  const EncryptedValue({required this.bytes, required this.nonce});
  final String bytes;
  final String nonce;
}
