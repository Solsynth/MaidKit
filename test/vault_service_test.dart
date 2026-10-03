import 'dart:io';

import 'package:drift/drift.dart' show Value;
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

  @override
  Future<bool> containsKey({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values.containsKey(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => Directory.systemTemp.path,
      );

  test('a browser refuses a second vault in its one database', () async {
    final directory = await Directory.systemTemp.createTemp('vault_web_test');
    final database = AppDatabase(filePath: '${directory.path}/vault.sqlite');
    final vault = VaultService(
      database,
      secureStorage: _MemoryStorage(),
      isWeb: true,
    );
    try {
      await vault.create('first-passphrase');
      expect(await vault.hasVault(), isTrue);

      await expectLater(
        vault.create('second-passphrase'),
        throwsA(isA<VaultAlreadyExistsException>()),
      );

      final metadata = await database.select(database.vaultMetadata).get();
      expect(
        metadata.length,
        1,
        reason: 'a second row would leave the browser vault unopenable',
      );
      expect(vault.isUnlocked, isTrue);
    } finally {
      await database.close();
      await directory.delete(recursive: true);
    }
  });

  test('a duplicated browser vault keeps the first row and opens', () async {
    final directory = await Directory.systemTemp.createTemp(
      'vault_repair_test',
    );
    final database = AppDatabase(filePath: '${directory.path}/vault.sqlite');
    final vault = VaultService(
      database,
      secureStorage: _MemoryStorage(),
      isWeb: true,
    );
    try {
      await vault.create('old-passphrase');
      await vault.lock();
      final original =
          (await database.select(database.vaultMetadata).get()).single;

      // What the old build did when a browser was offered a second vault: it
      // appended a row to the same database instead of making a new vault.
      await database
          .into(database.vaultMetadata)
          .insert(
            original.toCompanion(false).copyWith(id: Value(original.id + 1)),
          );
      expect(
        (await database.select(database.vaultMetadata).get()).length,
        2,
        reason: 'the duplicate has to exist before the repair can be seen',
      );

      expect(
        await vault.unlockWithPassword('old-passphrase'),
        isTrue,
        reason:
            'the password the surviving row was made with must still open it',
      );
      final repaired = await database.select(database.vaultMetadata).get();
      expect(repaired.length, 1);
      expect(repaired.single.id, original.id);
    } finally {
      await database.close();
      await directory.delete(recursive: true);
    }
  });

  test('erasing a vault clears its rows, metadata and stored keys', () async {
    final directory = await Directory.systemTemp.createTemp('vault_erase_test');
    final database = AppDatabase(filePath: '${directory.path}/vault.sqlite');
    final storage = _MemoryStorage();
    final vault = VaultService(database, secureStorage: storage, isWeb: true);
    try {
      await vault.create('erase-me');
      await database
          .into(database.servers)
          .insert(
            ServersCompanion.insert(
              name: 'example',
              host: 'example.com',
              username: 'root',
            ),
          );
      expect(await vault.hasVault(), isTrue);
      expect(storage.values, isNotEmpty);

      await vault.erase();

      expect(await vault.hasVault(), isFalse);
      expect(
        await database.select(database.servers).get(),
        isEmpty,
        reason:
            'a leftover server row would still be encrypted with the old key',
      );
      expect(
        storage.values,
        isEmpty,
        reason: 'keychain entries outlive the database and must go with it',
      );
      expect(vault.isUnlocked, isFalse);
    } finally {
      await database.close();
      await directory.delete(recursive: true);
    }
  });
}
