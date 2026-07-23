import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
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
  VaultService(this._database, {FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _biometricKey = 'maidkit_vault_data_key';
  static const _iterations = 310000;
  final AppDatabase _database;
  final FlutterSecureStorage _secureStorage;
  final AesGcm _cipher = AesGcm.with256bits();
  SecretKey? _dataKey;

  bool get isUnlocked => _dataKey != null;

  Future<bool> hasVault() async =>
      (await _database.select(_database.vaultMetadata).get()).isNotEmpty;

  Future<bool> isBiometricUnlockEnabled() async =>
      await _secureStorage.containsKey(key: _biometricKey);

  Future<void> create(String password) async {
    if (password.length < 8) {
      throw ArgumentError('Use a vault password with at least 8 characters.');
    }
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

  Future<void> lock() async => _dataKey = null;

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
