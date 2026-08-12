import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/vault_file_storage.dart';
import 'package:maid_kit/servers/vault_service.dart';

class _HangingVaultService extends VaultService {
  _HangingVaultService(super.database);

  @override
  Future<bool> hasVault() => Completer<bool>().future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        return Directory.systemTemp.path;
      });

  test('vault existence resolves for a fresh database', () async {
    final directory = await Directory.systemTemp.createTemp('vault_gate_test');
    final database = AppDatabase(filePath: '${directory.path}/vault.sqlite');
    addTearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);

    expect(await container.read(vaultExistsProvider.future), isFalse);
  });
  test(
    'vault existence reports a timeout instead of loading forever',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'vault_gate_test',
      );
      final database = AppDatabase(filePath: '${directory.path}/vault.sqlite');
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });

      final container = ProviderContainer(
        overrides: [
          vaultServiceProvider.overrideWithValue(
            _HangingVaultService(database),
          ),
          vaultOpenTimeoutProvider.overrideWithValue(
            const Duration(milliseconds: 1),
          ),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen(vaultExistsProvider, (_, _) {});
      addTearDown(subscription.close);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container.read(vaultExistsProvider), isA<AsyncError<bool>>());
    },
  );
  test(
    'external vault selection is disabled on restricted platforms',
    () async {
      if (externalVaultsSupported) return;

      final directory = await Directory.systemTemp.createTemp(
        'vault_gate_test',
      );
      final path = '${directory.path}/external.maidkit';
      await File(path).writeAsBytes(const <int>[]);
      addTearDown(() => directory.delete(recursive: true));

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await expectLater(
        container.read(activeVaultFileProvider.notifier).select(path),
        throwsA(isA<FileSystemException>()),
      );
      final preferences = await SharedPreferences.getInstance();
      expect(container.read(activeVaultFileProvider), isNull);
      expect(preferences.getString('active_vault_file'), isNull);
      expect(preferences.getStringList('vault_files'), isNull);
    },
  );
}
