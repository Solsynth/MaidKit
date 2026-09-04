import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/vault_file_storage.dart';

/// Storage that reproduces the Windows duplicate-vault corruption on any host:
/// resolution and the directory scan return the same vault file under
/// spellings that differ by separator and drive-letter case, so a raw string
/// `contains` dedupe keeps every spelling while `samePath` merges them.
class _SeparatorVariantStorage extends VaultFileStorage {
  @override
  String normalizePath(String path) => path.replaceAll('/', r'\');

  @override
  bool samePath(String a, String b) =>
      normalizePath(a).toLowerCase() == normalizePath(b).toLowerCase();

  @override
  Future<String?> resolvePersistedPath(String value) async =>
      value.toLowerCase().contains('.maidkit') ? value : null;

  @override
  Future<List<String>> managedVaultPaths() async => [
    r'C:\App\Vaults\a.maidkit',
  ];

  @override
  String vaultId(String path) => path;

  @override
  Future<String> persistentPath(String path) async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitUntil(bool Function() predicate) async {
    for (var i = 0; i < 100; i++) {
      if (predicate()) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('condition was never reached');
  }

  test(
    'restore dedupes one vault across separator and case spellings',
    () async {
      SharedPreferences.setMockInitialValues({
        'vault_files': [r'C:\App\Vaults\a.maidkit', 'c:/app/vaults/A.MAIDKIT'],
      });
      final container = ProviderContainer(
        overrides: [
          vaultFileStorageProvider.overrideWithValue(
            _SeparatorVariantStorage(),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(vaultFilesProvider);

      // _restore persisted its deduped list: the raw two-spelling input became
      // one stored reference.
      final preferences = await SharedPreferences.getInstance();
      await waitUntil(
        () => preferences.getStringList('vault_files')?.length == 1,
      );

      // One vault, first-seen spelling wins; no duplicate tile.
      expect(container.read(vaultFilesProvider), [r'C:\App\Vaults\a.maidkit']);
      expect(preferences.getStringList('vault_files'), [
        r'C:\App\Vaults\a.maidkit',
      ]);
    },
  );

  test(
    'remember replaces a path that only differs by separator or case',
    () async {
      SharedPreferences.setMockInitialValues({
        'vault_files': [r'C:\App\Vaults\a.maidkit', 'c:/app/vaults/A.MAIDKIT'],
      });
      final container = ProviderContainer(
        overrides: [
          vaultFileStorageProvider.overrideWithValue(
            _SeparatorVariantStorage(),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(vaultFilesProvider);
      // Restore finished once the duplicate spelling was persisted away.
      final preferences = await SharedPreferences.getInstance();
      await waitUntil(
        () => preferences.getStringList('vault_files')?.length == 1,
      );

      await container
          .read(vaultFilesProvider.notifier)
          .remember('c:/app/vaults/A.MAIDKIT');

      expect(container.read(vaultFilesProvider), ['c:/app/vaults/A.MAIDKIT']);
      expect(preferences.getStringList('vault_files'), [
        'c:/app/vaults/A.MAIDKIT',
      ]);
    },
  );
}
