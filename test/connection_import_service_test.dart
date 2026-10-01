import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/connection_export_service.dart';
import 'package:maid_kit/servers/connection_import_service.dart';
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/server_repository.dart';
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

  group('ConnectionImportService', () {
    late AppDatabase database;
    late VaultService vault;
    late ServerRepository repository;
    late ConnectionExportService exportService;
    late ConnectionImportService importService;

    setUp(() async {
      final directory = Directory.systemTemp.createTempSync(
        'connection_import_test',
      );
      final storage = _MemoryStorage();
      database = AppDatabase(filePath: '${directory.path}/test.sqlite');
      vault = VaultService(database, secureStorage: storage);
      await vault.create('vault-password');
      repository = ServerRepository(database, vault);
      exportService = ConnectionExportService(database, vault);
      importService = ConnectionImportService(database, vault);
    });

    tearDown(() => database.close());

    Future<Server> insertPasswordServer() => repository.create(
      ServerDraft(
        name: 'prod-db',
        host: '10.0.0.1',
        port: 2222,
        username: 'root',
        credential: ServerCredential.password('hunter2'),
        credentialName: 'prod-db-cred',
        proxy: const ServerProxy(
          type: ServerProxyType.http,
          host: 'proxy.local',
          port: 8080,
          username: 'proxy-user',
          password: 'proxy-pass',
        ),
        environment: const {'KUBECONFIG': '/etc/kubernetes/admin.conf'},
        tags: const ['prod', 'eu-west'],
      ),
    );

    test(
      'protected JSON round-trips credentials, proxy, and environment',
      () async {
        final original = await insertPasswordServer();
        final export = await exportService.exportJson(
          passphrase: 'export-pass',
        );

        final candidates = await importService.previewJson(
          export,
          passphrase: 'export-pass',
        );
        expect(candidates, hasLength(1));
        expect(candidates.single.isDuplicate, isTrue);

        final connection = candidates.single.connection;
        expect(connection.name, 'prod-db');
        expect(connection.host, '10.0.0.1');
        expect(connection.port, 2222);
        expect(connection.username, 'root');
        expect(connection.tags, ['prod', 'eu-west']);
        expect(connection.credential, isA<ServerCredential>());
        expect(connection.proxy?.password, 'proxy-pass');
        expect(connection.environment, {
          'KUBECONFIG': '/etc/kubernetes/admin.conf',
        });

        final result = await importService.import(candidates);
        expect(result.created, 1);

        final imported = (await repository.all()).firstWhere(
          (server) => server.id != original.id,
        );
        expect(imported.name, 'prod-db');
        expect(imported.port, 2222);
        expect(decodeStringList(imported.tags), ['prod', 'eu-west']);
        expect(decodeEnvironmentMap(imported.environment), {
          'KUBECONFIG': '/etc/kubernetes/admin.conf',
        });
        final credential = await repository.credentialFor(imported);
        expect(credential.type, CredentialType.password);
        expect(credential.password, 'hunter2');
        final proxy = await repository.proxyFor(imported);
        expect(proxy?.host, 'proxy.local');
        expect(proxy?.password, 'proxy-pass');
      },
    );

    test('private key credentials survive a protected round-trip', () async {
      final original = await repository.create(
        ServerDraft(
          name: 'git-deploy',
          host: 'git.internal',
          port: 22,
          username: 'deploy',
          credential: const ServerCredential.privateKey(
            privateKey:
                '-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n'
                '-----END OPENSSH PRIVATE KEY-----\n',
            keyPassphrase: 'key-pass',
          ),
        ),
      );

      final export = await exportService.exportJson(passphrase: 'export-pass');
      final candidates = await importService.previewJson(
        export,
        passphrase: 'export-pass',
      );
      final credential = candidates.single.connection.credential!;
      expect(credential.type, CredentialType.privateKey);
      expect(credential.privateKey, contains('BEGIN OPENSSH PRIVATE KEY'));
      expect(credential.keyPassphrase, 'key-pass');

      await importService.import(candidates);
      final imported = (await repository.all()).firstWhere(
        (server) => server.id != original.id,
      );
      final restored = await repository.credentialFor(imported);
      expect(restored.type, CredentialType.privateKey);
      expect(restored.keyPassphrase, 'key-pass');
    });

    test('redacted JSON imports credential-less servers', () async {
      final original = await insertPasswordServer();
      final export = await exportService.exportJson();

      final candidates = await importService.previewJson(export);
      expect(candidates.single.connection.credential, isNull);
      expect(candidates.single.connection.proxy?.password, isNull);
      expect(candidates.single.connection.environment, isEmpty);

      await importService.import(candidates);
      final imported = (await repository.all()).firstWhere(
        (server) => server.id != original.id,
      );
      expect(imported.credentialId, isNull);
    });

    test('protected JSON without a passphrase is locked', () async {
      await insertPasswordServer();
      final export = await exportService.exportJson(passphrase: 'export-pass');

      expect(
        () => importService.previewJson(export),
        throwsA(isA<ConnectionSecretsLockedException>()),
      );
    });

    test('wrong passphrase is rejected', () async {
      await insertPasswordServer();
      final export = await exportService.exportJson(passphrase: 'export-pass');

      expect(
        () => importService.previewJson(export, passphrase: 'nope'),
        throwsA(isA<ConnectionSecretsPassphraseException>()),
      );
    });

    test('serial servers keep their serial settings', () async {
      await repository.create(
        ServerDraft(
          name: 'router',
          host: '',
          port: 22,
          username: '',
          credential: ServerCredential.password('unused'),
          connectionType: ServerConnectionType.serial,
          serialConfig: const SerialConfig(
            device: '/dev/tty.usbserial',
            baudRate: 9600,
          ),
          tags: const ['hardware'],
        ),
      );

      final export = await exportService.exportJson(passphrase: 'export-pass');
      final candidates = await importService.previewJson(
        export,
        passphrase: 'export-pass',
      );
      final connection = candidates.single.connection;
      expect(connection.connectionType, ServerConnectionType.serial);
      expect(connection.serialConfig?.device, '/dev/tty.usbserial');
      expect(connection.serialConfig?.baudRate, 9600);
    });

    test('CSV round-trips the redacted columns with quoting', () async {
      await repository.create(
        ServerDraft(
          name: 'prod, "east"',
          host: '10.0.0.2',
          port: 22,
          username: 'admin',
          credential: ServerCredential.password('hunter2'),
          tags: const ['a,1', 'b'],
        ),
      );

      final csv = await exportService.exportCsv();
      final candidates = await importService.previewCsv(csv);

      final connection = candidates.single.connection;
      expect(connection.name, 'prod, "east"');
      expect(connection.host, '10.0.0.2');
      expect(connection.port, 22);
      expect(connection.username, 'admin');
      expect(connection.credential, isNull);
      expect(connection.tags, ['a,1', 'b']);
    });

    test('duplicates are flagged against existing servers', () async {
      await insertPasswordServer();
      final export = await exportService.exportJson(passphrase: 'export-pass');

      final candidates = await importService.previewJson(
        export,
        passphrase: 'export-pass',
      );
      expect(candidates.single.isDuplicate, isTrue);
      expect(candidates.single.existing?.name, 'prod-db');
    });

    test(
      'duplicate detection ignores case and excludes soft-deleted servers',
      () async {
        final server = await repository.create(
          ServerDraft(
            name: 'prod-db',
            host: 'github.internal',
            port: 22,
            username: 'root',
            credential: ServerCredential.password('hunter2'),
          ),
        );
        final document = {
          'format': ConnectionExportService.formatName,
          'version': ConnectionExportService.formatVersion,
          'servers': [
            {
              'name': 'prod-db',
              'host': 'GITHUB.Internal',
              'port': 22,
              'username': 'root',
            },
          ],
        };

        var candidates = await importService.previewJson(jsonEncode(document));
        expect(candidates.single.isDuplicate, isTrue);

        // A soft-deleted server must not count as an existing duplicate.
        await repository.delete(server);
        candidates = await importService.previewJson(jsonEncode(document));
        expect(candidates.single.isDuplicate, isFalse);
      },
    );

    test('invalid documents are rejected', () async {
      await expectLater(
        importService.previewJson('{"format":"other","version":1}'),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        importService.previewJson('not json at all'),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        importService.previewCsv('name,host\nonly,two'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('ConnectionImportService previewFiles', () {
    late AppDatabase database;
    late VaultService vault;
    late ServerRepository repository;
    late ConnectionExportService exportService;
    late ConnectionImportService importService;
    late Directory directory;

    setUp(() async {
      directory = Directory.systemTemp.createTempSync('preview_files_test');
      database = AppDatabase(filePath: '${directory.path}/test.sqlite');
      vault = VaultService(database, secureStorage: _MemoryStorage());
      await vault.create('vault-password');
      repository = ServerRepository(database, vault);
      exportService = ConnectionExportService(database, vault);
      importService = ConnectionImportService(database, vault);
    });

    tearDown(() async {
      await database.close();
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    File writeFile(String name, String content) {
      final file = File('${directory.path}/$name');
      file.writeAsStringSync(content);
      return file;
    }

    Future<void> insertServer() => repository.create(
      ServerDraft(
        name: 'prod-db',
        host: '10.0.0.1',
        port: 22,
        username: 'root',
        credential: ServerCredential.password('hunter2'),
      ),
    );

    test('parses multiple files of mixed formats', () async {
      final finalshell = writeFile(
        'conn.json',
        jsonEncode({
          'name': 'fs-host',
          'host': '10.0.0.1',
          'port': 22,
          'user_name': 'root',
          'password': 'plain not base64',
        }),
      );
      final sshConfig = writeFile(
        'config',
        'Host web\n  HostName 10.0.0.2\n  User alice\n',
      );

      final preview = await importService.previewFiles([
        ImportedConnectionFile.fromPath(finalshell.path),
        ImportedConnectionFile.fromPath(sshConfig.path),
      ]);
      expect(preview.aborted, isFalse);
      expect(preview.isEmpty, isFalse);
      expect(preview.candidates, hasLength(2));
      expect(
        preview.candidates.map((c) => c.connection.host),
        containsAll(['10.0.0.1', '10.0.0.2']),
      );
    });

    test('prompts for the passphrase once for a protected export', () async {
      await insertServer();
      final protected = await exportService.exportJson(
        passphrase: 'export-pass',
      );
      final file = writeFile('protected.json', protected);
      var prompts = 0;

      final preview = await importService.previewFiles(
        [ImportedConnectionFile.fromPath(file.path)],
        requestPassphrase: () async {
          prompts += 1;
          return 'export-pass';
        },
      );
      expect(prompts, 1);
      expect(preview.candidates.single.connection.credential, isNotNull);
    });

    test('aborts when the passphrase prompt is cancelled', () async {
      await insertServer();
      final protected = await exportService.exportJson(
        passphrase: 'export-pass',
      );
      final file = writeFile('protected.json', protected);

      final preview = await importService.previewFiles([
        ImportedConnectionFile.fromPath(file.path),
      ], requestPassphrase: () async => null);
      expect(preview.aborted, isTrue);
      expect(preview.candidates, isEmpty);
    });

    test('records a wrong passphrase as the first error', () async {
      await insertServer();
      final protected = await exportService.exportJson(
        passphrase: 'export-pass',
      );
      final file = writeFile('protected.json', protected);

      final preview = await importService.previewFiles([
        ImportedConnectionFile.fromPath(file.path),
      ], requestPassphrase: () async => 'wrong');
      expect(preview.aborted, isFalse);
      expect(preview.candidates, isEmpty);
      expect(preview.firstError, isA<ConnectionSecretsPassphraseException>());
    });

    test('keeps good files despite an unrecognized one', () async {
      final good = writeFile(
        'good.csv',
        'name,host,port,username,authType,tags,connectionType\n'
            'box,10.0.0.9,22,admin,,,ssh\n',
      );
      final bad = writeFile('garbage.txt', 'not a connection file');

      final preview = await importService.previewFiles([
        ImportedConnectionFile.fromPath(bad.path),
        ImportedConnectionFile.fromPath(good.path),
      ]);
      expect(preview.candidates, hasLength(1));
      expect(preview.candidates.single.connection.host, '10.0.0.9');
      expect(preview.firstError, isA<FormatException>());
    });
  });
}
