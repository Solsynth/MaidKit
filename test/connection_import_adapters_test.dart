import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/connection_import_adapters.dart';
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

/// Reference vectors generated with the public Python translation of
/// FinalShell's Java `FinalShellDecodePass` (pycryptodome), so the Dart port
/// is cross-validated against the original algorithm.
const _finalshellNewVector1 = 'AQIDBAUGBwhnHHgRpf4t0w=='; // 'hunter2'
const _finalshellNewVector2 =
    '/iyBAHr/EZvIZqMetqEnN4vUnHn+RBGk'; // 'P@ss wörd!9'
const _finalshellClassic1 = 'kmqLQBYj0vs='; // 'hunter2'
const _finalshellClassic2 =
    'k83h1BscUyg/DxUW2cxV6PTkBVAIcbSZJXQ/3chSK2U='; // 'correct horse battery staple'

String _finalshellJson({
  required String password,
  String authMode = 'password',
  Map<String, dynamic>? extra,
}) => jsonEncode({
  'id': '1',
  'name': 'prod',
  'host': '10.0.0.1',
  'port': 22,
  'user_name': 'root',
  'authMode': authMode,
  'password': password,
  ...?extra,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        return Directory.systemTemp.path;
      });

  group('FinalShellAdapter', () {
    test('decrypts the modern head-seeded scheme', () {
      final connections = FinalShellAdapter().parse(
        _finalshellJson(password: _finalshellNewVector1),
      );
      expect(connections, hasLength(1));
      expect(connections.single.credential, isA<ServerCredential>());
      expect(connections.single.credential!.password, 'hunter2');
    });

    test('decrypts the modern scheme with unicode passwords', () {
      final connections = FinalShellAdapter().parse(
        _finalshellJson(password: _finalshellNewVector2),
      );
      expect(connections.single.credential!.password, 'P@ss wörd!9');
    });

    test('decrypts the classic hardcoded-key scheme', () {
      final adapter = FinalShellAdapter();
      expect(
        adapter
            .parse(_finalshellJson(password: _finalshellClassic1))
            .single
            .credential!
            .password,
        'hunter2',
      );
      expect(
        adapter
            .parse(_finalshellJson(password: _finalshellClassic2))
            .single
            .credential!
            .password,
        'correct horse battery staple',
      );
    });

    test('supports the map-shaped password field', () {
      final content = jsonEncode({
        'host': '10.0.0.2',
        'port': 22,
        'password': {'encode': 'des', 'secret': _finalshellClassic1},
      });
      final connections = FinalShellAdapter().parse(content);
      expect(connections.single.credential!.password, 'hunter2');
    });

    test('uses plaintext passwords that are not base64', () {
      final connections = FinalShellAdapter().parse(
        _finalshellJson(password: 's3cret plain'),
      );
      expect(connections.single.credential!.password, 's3cret plain');
    });

    test('imports private-key credentials from a readable key file', () {
      final directory = Directory.systemTemp.createTempSync(
        'finalshell_adapter_test',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final keyFile = File('${directory.path}/id_rsa');
      keyFile.writeAsStringSync('KEY-CONTENT\n');

      final content = _finalshellJson(
        password: 'ignored',
        authMode: 'privateKey',
        extra: {'privateKey': 'id_rsa', 'passphrase': 'key-pass'},
      );
      final connections = FinalShellAdapter().parse(
        content,
        baseDirectory: directory.path,
      );
      final credential = connections.single.credential!;
      expect(credential.type, CredentialType.privateKey);
      expect(credential.privateKey, contains('KEY-CONTENT'));
      expect(credential.keyPassphrase, 'key-pass');
    });

    test('yields no credential when the key file is missing', () {
      final connections = FinalShellAdapter().parse(
        _finalshellJson(password: 'x', authMode: 'privateKey'),
      );
      expect(connections.single.credential, isNull);
    });
  });

  group('OpenSshConfigAdapter', () {
    test('detects configs with global directives before Host blocks', () {
      const config = '''
AddKeysToAgent yes
ServerAliveInterval 30

Host production
  HostName production.internal
''';

      expect(OpenSshConfigAdapter().supports(config), isTrue);
      expect(detectThirdPartyAdapter(config), isA<OpenSshConfigAdapter>());
    });

    test('applies global and wildcard defaults to concrete hosts', () {
      const config = '''
User global-user

Host production
  HostName production.internal

Host *
  Port 2200
  User fallback-user
''';

      final connection = OpenSshConfigAdapter().parse(config).single;

      expect(connection.name, 'production');
      expect(connection.host, 'production.internal');
      expect(connection.username, 'global-user');
      expect(connection.port, 2200);
    });

    test('parses host blocks, skips wildcards, reads relative keys', () {
      final directory = Directory.systemTemp.createTempSync(
        'openssh_adapter_test',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final keyDir = Directory('${directory.path}/keys')..createSync();
      File('${keyDir.path}/prod_key').writeAsStringSync('PROD-KEY\n');

      const config = '''
# comment
Host jump
  HostName jump.internal
  User alice
  Port 2222
  IdentityFile ~/.ssh/jump_key

Host prod prod2
  HostName 10.0.0.5
  User root
  IdentityFile keys/prod_key

Host *.example.com
  HostName 10.0.0.9
''';

      final connections = OpenSshConfigAdapter().parse(
        config,
        baseDirectory: directory.path,
      );
      expect(connections, hasLength(2));

      final jump = connections[0];
      expect(jump.name, 'jump');
      expect(jump.host, 'jump.internal');
      expect(jump.port, 2222);
      expect(jump.username, 'alice');
      expect(jump.credential, isNull); // ~/.ssh/jump_key does not exist.

      final prod = connections[1];
      expect(prod.name, 'prod');
      expect(prod.host, '10.0.0.5');
      expect(prod.port, 22);
      expect(prod.credential!.privateKey, contains('PROD-KEY'));
    });

    test('rejects key paths that escape the import directory via ..', () {
      final directory = Directory.systemTemp.createTempSync(
        'openssh_traversal_test',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      // A readable secret placed *outside* the import directory.
      final outside = Directory('${directory.path}/../openssh_secret_neighbor')
        ..createSync(recursive: true);
      addTearDown(() => outside.deleteSync(recursive: true));
      File('${outside.path}/id_rsa').writeAsStringSync('STOLEN-KEY\n');

      const config = '''
Host victim
  HostName 10.0.0.6
  User root
  IdentityFile ../openssh_secret_neighbor/id_rsa
''';
      final connections = OpenSshConfigAdapter().parse(
        config,
        baseDirectory: directory.path,
      );
      expect(connections.single.credential, isNull);
    });

    test('rejects ~/ paths outside the .ssh directory', () {
      const config = '''
Host victim
  HostName 10.0.0.7
  User root
  IdentityFile ~/notes/secret
''';
      final connections = OpenSshConfigAdapter().parse(config);
      expect(connections.single.credential, isNull);
    });

    test(
      'rejects a relative key symlink that escapes the import directory',
      () {
        if (Platform.isWindows) return;
        final directory = Directory.systemTemp.createTempSync(
          'openssh_symlink_test',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final outside = File('${directory.path}_outside_key')
          ..writeAsStringSync('OUTSIDE-KEY\n');
        addTearDown(() {
          if (outside.existsSync()) outside.deleteSync();
        });
        Link('${directory.path}/linked_key').createSync(outside.path);

        const config = '''
Host victim
  IdentityFile linked_key
''';
        final connections = OpenSshConfigAdapter().parse(
          config,
          baseDirectory: directory.path,
        );

        expect(connections.single.credential, isNull);
      },
    );

    test('falls back to the pattern as hostname', () {
      const config = 'Host mybox\n  User admin\n';
      final connections = OpenSshConfigAdapter().parse(config);
      expect(connections.single.host, 'mybox');
      expect(connections.single.username, 'admin');
    });
  });

  group('XShellAdapter', () {
    test('imports connection metadata without a password', () {
      const session = '''
[CONNECTION]
Host=192.168.1.2
Port=2222

[USER_AUTHENTICATION]
Authentication=Password
UserName=root
Password=encrypted-blob
''';
      final connections = XShellAdapter().parse(session);
      expect(connections.single.host, '192.168.1.2');
      expect(connections.single.port, 2222);
      expect(connections.single.username, 'root');
      expect(connections.single.credential, isNull);
    });

    test('reads the public-key file when readable', () {
      final directory = Directory.systemTemp.createTempSync(
        'xshell_adapter_test',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      File('${directory.path}/id_ed25519').writeAsStringSync('ED25519-KEY\n');

      final session = '''
[CONNECTION]
Host=git.internal
Port=22

[USER_AUTHENTICATION]
Authentication=PublicKey
UserName=deploy
KeyFilePath=id_ed25519
''';
      final connections = XShellAdapter().parse(
        session,
        baseDirectory: directory.path,
      );
      expect(
        connections.single.credential!.privateKey,
        contains('ED25519-KEY'),
      );
    });
  });

  group('SecureCrtAdapter', () {
    test('imports metadata with hex dword port', () {
      const session = '''
[Sessions\\db]
S:"Hostname"=db.internal
D:"Port"=00001606
S:"Username"=admin
S:"PublicKeyFile"=
''';
      final connections = SecureCrtAdapter().parse(session);
      expect(connections.single.host, 'db.internal');
      expect(connections.single.port, 0x1606);
      expect(connections.single.username, 'admin');
      expect(connections.single.credential, isNull);
    });
  });

  group('MobaXtermAdapter', () {
    test('imports SSH sessions, skips RDP, folders become tags', () {
      const sessions = '''
[Bookmarks]
SubRep=
ImgNum=42
Deck=#109#0%192.168.137.40%22%deck%%0%0%%%%%0%0%0%%%-1%0%0%0%%1080%%0%0%1%#MobaFont%10%0%0%-1%15%236,236,236%30,30,30%180,180,192%0%-1%0%%xterm%-1%0%_Std_Colors_0_%80%24%0%1%-1%<none>%%0%0%-1%-1#0# #-1
[Bookmarks_1]
SubRep=Lab
ImgNum=41
Raspi=#109#0%raspi.local%22%pi%%-1%-1%%%%%0%0%0%%%-1%0%0%0%%1080%%0%0%1%#MobaFont%10%0%0%-1%15%236,236,236%30,30,30%180,180,192%0%-1%0%%xterm%-1%0%_Std_Colors_0_%80%24%0%1%-1%<none>%%0%0%-1%-1#0# #-1
RdpBox=#91#4%10.0.0.9%3389%%0%0%0%-1%0%0%0%0%0%0%0%0%0%0%0%0%0%0%0%0%0%0%0%0%0%0%0%0%0%0%0%0%0%0%0%0#MobaFont%10%0%0%-1%15%236,236,236%30,30,30%180,180,192%0%-1%0%%xterm%-1%0%_Std_Colors_0_%80%24%0%1%-1%<none>%%0%0%-1%-1#0# #-1
''';
      final connections = MobaXtermAdapter().parse(sessions);
      expect(connections, hasLength(2));

      expect(connections[0].name, 'Deck');
      expect(connections[0].host, '192.168.137.40');
      expect(connections[0].port, 22);
      expect(connections[0].username, 'deck');
      expect(connections[0].tags, isEmpty);

      expect(connections[1].name, 'Raspi');
      expect(connections[1].host, 'raspi.local');
      expect(connections[1].username, 'pi');
      expect(connections[1].tags, ['Lab']);
    });
  });

  group('PuTTYAdapter', () {
    test('parses host:port and dword port', () {
      const registry = '''
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\\Software\\SimonTatham\\PuTTY\\Sessions\\web]
"HostName"="10.0.0.7:2222"
"UserName"="deploy"
"PortNumber"=dword:000008ae
"PublicKeyFile"=""
''';
      final connections = PuTTYAdapter().parse(registry);
      expect(connections.single.name, 'web');
      expect(connections.single.host, '10.0.0.7');
      expect(connections.single.port, 2222);
      expect(connections.single.username, 'deploy');
      expect(connections.single.credential, isNull);
    });

    test('splits nested session folder names', () {
      const registry = '''
[HKEY_CURRENT_USER\\Software\\SimonTatham\\PuTTY\\Sessions\\cloud\\prod]
"HostName"="10.0.0.8"
"UserName"="root"
''';
      final connections = PuTTYAdapter().parse(registry);
      expect(connections.single.name, 'prod');
      expect(connections.single.host, '10.0.0.8');
    });
  });

  group('detectThirdPartyAdapter', () {
    test('recognizes every supported format', () {
      expect(
        detectThirdPartyAdapter(_finalshellJson(password: _finalshellClassic1)),
        isA<FinalShellAdapter>(),
      );
      expect(
        detectThirdPartyAdapter('Host web\n  HostName 10.0.0.1\n'),
        isA<OpenSshConfigAdapter>(),
      );
      expect(
        detectThirdPartyAdapter('[CONNECTION]\nHost=10.0.0.1\n'),
        isA<XShellAdapter>(),
      );
      expect(
        detectThirdPartyAdapter('[Sessions\\x]\nS:"Hostname"=10.0.0.1\n'),
        isA<SecureCrtAdapter>(),
      );
      expect(
        detectThirdPartyAdapter('[Bookmarks]\nSubRep=\n'),
        isA<MobaXtermAdapter>(),
      );
      expect(
        detectThirdPartyAdapter(
          '[HKEY_CURRENT_USER\\Software\\SimonTatham\\PuTTY\\Sessions\\x]',
        ),
        isA<PuTTYAdapter>(),
      );
      expect(detectThirdPartyAdapter('random text'), isNull);
    });
  });

  group('ConnectionImportService third-party integration', () {
    late AppDatabase database;
    late VaultService vault;
    late ServerRepository repository;
    late ConnectionImportService service;

    setUp(() async {
      final directory = Directory.systemTemp.createTempSync(
        'adapter_integration_test',
      );
      database = AppDatabase(filePath: '${directory.path}/test.sqlite');
      vault = VaultService(database, secureStorage: _MemoryStorage());
      await vault.create('vault-password');
      repository = ServerRepository(database, vault);
      service = ConnectionImportService(database, vault);
    });

    tearDown(() => database.close());

    test('imports a decrypted FinalShell server end to end', () async {
      final candidates = await service.previewThirdParty(
        _finalshellJson(password: _finalshellNewVector1),
      );
      expect(candidates, hasLength(1));
      expect(candidates.single.connection.source, 'FinalShell');

      await service.import(candidates);
      final imported = (await repository.all()).single;
      expect(imported.name, 'prod');
      final credential = await repository.credentialFor(imported);
      expect(credential.password, 'hunter2');
    });

    test('previewAny routes OpenSSH configs to the adapter', () async {
      final candidates = await service.previewAny(
        'Host web\n  HostName 10.0.0.1\n  User root\n',
      );
      expect(candidates.single.connection.source, 'OpenSSH config');
      expect(candidates.single.connection.host, '10.0.0.1');
    });

    test('previewAny rejects unknown content', () async {
      expect(
        () => service.previewAny('this is not a connection file'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
