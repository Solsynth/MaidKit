import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:maid_kit/servers/vault_file_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storage = VaultFileStorage();

  group('VaultFileStorage.createVaultPath', () {
    test('stores new vaults under application support', () async {
      final support = await Directory.systemTemp.createTemp(
        'maidkit-vault-storage-',
      );
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProvider(support);
      addTearDown(() async {
        PathProviderPlatform.instance = previous;
        await support.delete(recursive: true);
      });

      final path = await storage.createVaultPath(name: 'Primary Vault');

      expect(
        storage.isInDirectory(
          path,
          '${support.path}${Platform.pathSeparator}vaults',
        ),
        isTrue,
      );
      expect(storage.fileName(path), startsWith('Primary Vault-'));
      expect(path, endsWith('.maidkit'));
    });

    test(
      'resolves an old absolute path after the app container changes',
      () async {
        final support = await Directory.systemTemp.createTemp(
          'maidkit-vault-update-',
        );
        final previous = PathProviderPlatform.instance;
        PathProviderPlatform.instance = _FakePathProvider(support);
        addTearDown(() async {
          PathProviderPlatform.instance = previous;
          await support.delete(recursive: true);
        });

        final directory = await Directory('${support.path}/vaults').create();
        final current = File('${directory.path}/primary.maidkit');
        await current.writeAsString('vault');

        final resolved = await storage.resolvePersistedPath(
          '/var/mobile/Containers/Data/Application/old-id/Library/'
          'Application Support/vaults/primary.maidkit',
        );

        expect(resolved, current.absolute.path);
        expect(await storage.persistentPath(resolved!), 'primary.maidkit');
        expect(storage.vaultId(resolved), 'primary.maidkit');
        expect(await storage.managedVaultPaths(), [current.absolute.path]);
      },
    );
  });
  group('VaultFileStorage external paths', () {
    test('imports vaults only when external storage is supported', () async {
      final root = await Directory.systemTemp.createTemp(
        'maidkit-external-vault-',
      );
      addTearDown(() => root.delete(recursive: true));
      final source = File('${root.path}/shared.sqlite');
      await source.writeAsString('vault');
      final support = await Directory.systemTemp.createTemp(
        'maidkit-vault-support-',
      );
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProvider(support);
      addTearDown(() async {
        PathProviderPlatform.instance = previous;
        await support.delete(recursive: true);
      });

      if (externalVaultsSupported) {
        final resolved = await storage.importVault(source.path);
        expect(resolved, source.absolute.path);
        expect(await source.exists(), isTrue);
      } else {
        await expectLater(
          storage.importVault(source.path),
          throwsA(isA<FileSystemException>()),
        );
      }
    });

    test('moves vaults only when external storage is supported', () async {
      final root = await Directory.systemTemp.createTemp('maidkit-move-vault-');
      final destination = await Directory('${root.path}/sync').create();
      addTearDown(() => root.delete(recursive: true));
      final source = File('${root.path}/old.sqlite');
      await source.writeAsString('vault');
      await File('${source.path}-wal').writeAsString('wal');
      await File('${source.path}-shm').writeAsString('shm');

      if (!externalVaultsSupported) {
        await expectLater(
          storage.moveVault(source.path, directoryPath: destination.path),
          throwsA(isA<FileSystemException>()),
        );
        return;
      }
      final moved = await storage.moveVault(
        source.path,
        directoryPath: destination.path,
      );

      expect(await source.exists(), isFalse);
      expect(await File(moved).readAsString(), 'vault');
      expect(await File('$moved-wal').readAsString(), 'wal');
      expect(await File('$moved-shm').readAsString(), 'shm');
    });
    test('classifies application-support vaults as internal', () async {
      final support = await Directory.systemTemp.createTemp(
        'maidkit-vault-location-',
      );
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProvider(support);
      addTearDown(() async {
        PathProviderPlatform.instance = previous;
        await support.delete(recursive: true);
      });

      expect(
        await storage.isExternalPath(
          '${support.path}${Platform.pathSeparator}vaults/internal.maidkit',
        ),
        isFalse,
      );
      expect(
        await storage.isExternalPath(
          '${support.path}${Platform.pathSeparator}Sync/external.maidkit',
        ),
        isTrue,
      );
    });
  });

  group('VaultFileStorage.fileName', () {
    test('returns the basename for native Windows separators', () {
      expect(
        storage.fileName(r'C:\Users\Me\Documents\vaults\a.maidkit'),
        'a.maidkit',
      );
    });

    test('returns the basename for forward-slash managed paths', () {
      expect(
        storage.fileName('C:/Users/Me/Documents/vaults/a.maidkit'),
        'a.maidkit',
      );
    });

    test('returns the path itself when it has no separators', () {
      expect(storage.fileName('a.maidkit'), 'a.maidkit');
    });
  });

  group('VaultFileStorage.isInDirectory', () {
    test('recognizes a managed vault when separators differ', () {
      // path_provider reports Application Support with '\' on Windows while
      // managed vault paths are built with '/'; both must count as in-directory.
      expect(
        storage.isInDirectory(
          'C:/Users/Me/Application Support/vaults/a.maidkit',
          r'C:\Users\Me\Application Support',
        ),
        isTrue,
      );
    });

    test('recognizes a managed vault with matching separators', () {
      expect(
        storage.isInDirectory(
          r'C:\Users\Me\Application Support\vaults\a.maidkit',
          r'C:\Users\Me\Application Support',
        ),
        isTrue,
      );
      expect(
        storage.isInDirectory(
          'C:/Users/Me/Application Support/vaults/a.maidkit',
          'C:/Users/Me/Application Support',
        ),
        isTrue,
      );
    });

    test('tolerates a trailing separator on the directory', () {
      expect(
        storage.isInDirectory(
          'C:/Users/Me/Application Support/vaults/a.maidkit',
          r'C:\Users\Me\Application Support\',
        ),
        isTrue,
      );
    });

    test('rejects files outside the directory', () {
      expect(
        storage.isInDirectory(
          'C:/Users/Me/Other/a.maidkit',
          'C:/Users/Me/Application Support',
        ),
        isFalse,
      );
    });

    test('rejects sibling paths that merely share a prefix', () {
      expect(
        storage.isInDirectory(
          'C:/Users/Me/Application SupportVaults/a.maidkit',
          'C:/Users/Me/Application Support',
        ),
        isFalse,
      );
    });
  });

  group('VaultFileStorage.samePath', () {
    test('treats a path as equal to itself', () {
      final path = '${Directory.systemTemp.path}/a.maidkit';
      expect(storage.samePath(path, path), isTrue);
    });

    test('treats different files as unequal', () {
      expect(
        storage.samePath(
          '${Directory.systemTemp.path}/a.maidkit',
          '${Directory.systemTemp.path}/b.maidkit',
        ),
        isFalse,
      );
    });
  });

  group('VaultFileStorage.normalizePath', () {
    test('returns an absolute form of a relative path', () {
      final absolute = storage.normalizePath('a.maidkit');
      expect(absolute, File('a.maidkit').absolute.path);
    });
  });
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this._support);

  final Directory _support;

  @override
  Future<String?> getApplicationSupportPath() async => _support.path;
}
