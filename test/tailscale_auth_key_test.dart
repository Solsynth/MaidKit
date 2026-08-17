import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/vault_service.dart';

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
    WindowsOptions? wOptions,
    AppleOptions? mOptions,
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
    WindowsOptions? wOptions,
    AppleOptions? mOptions,
  }) async {
    values.remove(key);
  }
}

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

  late Directory directory;
  late AppDatabase database;
  late VaultService vault;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('tailscale_auth_key');
    database = AppDatabase(filePath: '${directory.path}/test.sqlite');
    vault = VaultService(database, secureStorage: _MemoryStorage());
    await vault.create('password');
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test('stores and retrieves the auth key through the vault', () async {
    const authKey = 'tskey-auth-example';

    await vault.storeTailscaleAuthKey(authKey);

    expect(await vault.tailscaleAuthKey(), authKey);
    final metadata = await database.select(database.vaultMetadata).getSingle();
    expect(metadata.encryptedTailscaleAuthKey, isNot(contains(authKey)));
    expect(metadata.tailscaleAuthKeyNonce, isNotEmpty);
  });

  test('clearing the key removes it from the vault', () async {
    await vault.storeTailscaleAuthKey('tskey-auth-example');

    await vault.clearTailscaleAuthKey();

    expect(await vault.tailscaleAuthKey(), isNull);
  });
}
