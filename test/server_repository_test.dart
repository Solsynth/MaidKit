import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/port_forwarding_models.dart';
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/server_repository.dart';
import 'package:maid_kit/servers/vault_service.dart';

/// In-memory stand-in for the OS keychain, so vault creation (which caches the
/// sync passphrase) works without a platform implementation.
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

/// drift_flutter resolves its native database directory through
/// path_provider; point it at the system temp directory in tests.
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

  group('ServerRepository server configuration', () {
    late AppDatabase database;
    late ServerRepository repository;

    setUp(() {
      final directory = Directory.systemTemp.createTempSync(
        'server_config_test',
      );
      database = AppDatabase(filePath: '${directory.path}/test.sqlite');
      repository = ServerRepository(database, VaultService(database));
    });

    tearDown(() => database.close());

    Future<int> insertCredential() => database
        .into(database.savedCredentials)
        .insert(
          SavedCredentialsCompanion.insert(
            name: 'test',
            credentialType: CredentialType.password.name,
            encryptedCredential: 'x',
            credentialNonce: 'y',
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          ),
        );

    test('create persists environment, snippets, and tags', () async {
      final credentialId = await insertCredential();
      final server = await repository.create(
        ServerDraft(
          name: 'prod-db',
          host: '10.0.0.1',
          port: 22,
          username: 'root',
          credentialId: credentialId,
          environment: {'KUBECONFIG': '/etc/kubernetes/admin.conf'},
          initialSnippets: [3, 7],
          tags: ['prod', 'eu-west'],
          fileManagementInitialPath: '/srv/projects',
          fileManagementFavorites: ['/srv/projects', '/var/log'],
        ),
      );

      expect(decodeEnvironmentMap(server.environment), {
        'KUBECONFIG': '/etc/kubernetes/admin.conf',
      });
      expect(decodeSnippetIdList(server.initialSnippets), [3, 7]);
      expect(decodeStringList(server.tags), ['prod', 'eu-west']);
      expect(server.fileManagementInitialPath, '/srv/projects');
      expect(decodeStringList(server.fileManagementFavorites), [
        '/srv/projects',
        '/var/log',
      ]);
    });

    test('a detected daemon configures the shell route', () async {
      final vault = VaultService(database, secureStorage: _MemoryStorage());
      await vault.create('password');
      final vaultRepository = ServerRepository(database, vault);
      final credentialId = await insertCredential();
      final created = await vaultRepository.create(
        ServerDraft(
          name: 'daemon-host',
          host: '10.0.0.9',
          port: 22,
          username: 'root',
          credentialId: credentialId,
        ),
      );

      // What a probe (or an install) learned about the daemon.
      await vaultRepository.configureMaidCafeTerminal(
        created,
        port: 9443,
        listenHost: '127.0.0.1',
        apiSecret: 'daemon-secret',
        daemonId: 'daemon-1',
        terminalEnabled: false,
      );

      final server = (await vaultRepository.all()).single;
      expect(server.maidCafeTerminalPort, 9443);
      // The daemon's own terminal switch travels with the route, so a failure
      // message does not blame a port that is already open.
      expect(server.maidCafeTerminalEnabled, isFalse);
      // The daemon only listens on its own loopback, so that is the address the
      // app dials (a native client through its forward).
      expect(server.maidCafeTerminalUrl, 'http://127.0.0.1:9443');
      expect(server.maidCafeDaemonId, 'daemon-1');
      expect(server.encryptedMaidCafeMetricsSecret, isNotNull);
      expect(server.hasMaidCafeTerminalRoute, isTrue);
      expect(
        (await vaultRepository.maidCafeTerminalTargetFor(
          server,
          browserBuild: false,
        ))?.baseUrl,
        'http://127.0.0.1:9443',
      );
      // A browser dials the server host on the learned port instead.
      expect(
        (await vaultRepository.maidCafeTerminalTargetFor(
          server,
          browserBuild: true,
        ))?.baseUrl,
        'http://10.0.0.9:9443',
      );
    });

    test('the daemon terminal switch is recorded on its own', () async {
      final vault = VaultService(database, secureStorage: _MemoryStorage());
      await vault.create('password');
      final vaultRepository = ServerRepository(database, vault);
      final credentialId = await insertCredential();
      final created = await vaultRepository.create(
        ServerDraft(
          name: 'daemon-host',
          host: '10.0.0.9',
          port: 22,
          username: 'root',
          credentialId: credentialId,
        ),
      );
      expect(
        (await vaultRepository.all()).single.maidCafeTerminalEnabled,
        isNull,
      );

      await vaultRepository.setMaidCafeTerminalEnabled(created, true);
      expect(
        (await vaultRepository.all()).single.maidCafeTerminalEnabled,
        isTrue,
      );

      // A daemon that stops stating it clears the knowledge again.
      await vaultRepository.setMaidCafeTerminalEnabled(created, null);
      expect(
        (await vaultRepository.all()).single.maidCafeTerminalEnabled,
        isNull,
      );
    });

    test(
      'a daemon address keeps an announced host and falls back to loopback',
      () {
        expect(
          maidCafeDialUrl('daemon.example', 8747),
          'http://daemon.example:8747',
        );
        // Listening on every interface says nothing this app can dial.
        expect(maidCafeDialUrl('0.0.0.0', 8747), 'http://127.0.0.1:8747');
        expect(maidCafeDialUrl('::', 8747), 'http://127.0.0.1:8747');
        expect(maidCafeDialUrl(null, 8747), 'http://127.0.0.1:8747');
      },
    );

    test('a learned credential is stored like an entered one', () async {
      final vault = VaultService(database, secureStorage: _MemoryStorage());
      await vault.create('password');
      final vaultRepository = ServerRepository(database, vault);
      final credentialId = await insertCredential();
      final created = await vaultRepository.create(
        ServerDraft(
          name: 'daemon-host',
          host: '10.0.0.9',
          port: 22,
          username: 'root',
          credentialId: credentialId,
        ),
      );
      expect(await vaultRepository.maidCafeMetricsSecretFor(created), isNull);

      // What reading the daemon's configuration over SSH does with the secret
      // it found: the route that could not be built now has a credential.
      await vaultRepository.setMaidCafeMetricsSecret(created, 'daemon-secret');
      final stored = (await vaultRepository.all()).single;
      expect(
        await vaultRepository.maidCafeMetricsSecretFor(stored),
        'daemon-secret',
      );
      // The ciphertext is what lands in the row, never the secret itself.
      expect(
        stored.encryptedMaidCafeMetricsSecret,
        isNot(contains('daemon-secret')),
      );

      // An empty report never clears a good credential.
      await vaultRepository.setMaidCafeMetricsSecret(stored, '   ');
      expect(
        await vaultRepository.maidCafeMetricsSecretFor(
          (await vaultRepository.all()).single,
        ),
        'daemon-secret',
      );
    });

    test('a forced route overrides the stored transport preference', () async {
      final vault = VaultService(database, secureStorage: _MemoryStorage());
      await vault.create('password');
      final vaultRepository = ServerRepository(database, vault);
      final credentialId = await insertCredential();
      final created = await vaultRepository.create(
        ServerDraft(
          name: 'relay-host',
          host: '10.0.0.9',
          port: 22,
          username: 'root',
          credentialId: credentialId,
          maidCafeTerminalUrl: 'https://daemon.example',
          maidCafeDaemonId: 'daemon-1',
          maidCafeTerminalViaCloud: true,
        ),
      );
      await vaultRepository.updateMaidCafeConfig(
        created,
        daemonUrl: 'http://127.0.0.1:8747',
        metricsSecret: 'metrics',
      );
      final server = (await vaultRepository.all()).single;

      // The relay needs a cloud session, so asking for it must fail loudly
      // instead of quietly dialing the daemon.
      expect(
        await vaultRepository.maidCafeTerminalTargetFor(
          server,
          useCloudRelay: true,
        ),
        isNull,
      );
      // Forcing the daemon route ignores the stored relay preference.
      final direct = await vaultRepository.maidCafeTerminalTargetFor(
        server,
        useCloudRelay: false,
      );
      expect(direct?.baseUrl, 'https://daemon.example');
      expect(direct?.isRelayed, isFalse);
      // The stored preference falls back to the daemon on a device with no
      // cloud session.
      final auto = await vaultRepository.maidCafeTerminalTargetFor(server);
      expect(auto?.isRelayed, isFalse);
      expect(auto?.baseUrl, 'https://daemon.example');
    });

    test(
      'a learned daemon port is saved and dialed on the browser host',
      () async {
        // An unlocked vault with an in-memory keychain, so the metrics secret
        // the daemon terminal authorizes with can be encrypted.
        final vault = VaultService(database, secureStorage: _MemoryStorage());
        await vault.create('password');
        final vaultRepository = ServerRepository(database, vault);

        final credentialId = await insertCredential();
        final created = await vaultRepository.create(
          ServerDraft(
            name: 'web-host',
            host: '10.0.0.9',
            port: 22,
            username: 'root',
            credentialId: credentialId,
            maidCafeTerminalUrl: 'http://127.0.0.1:8747',
          ),
        );
        // A native client probes the daemon over SSH; the address it records is
        // its own tunnel loopback, and the port travels with it.
        await vaultRepository.updateMaidCafeConfig(
          created,
          daemonUrl: 'http://127.0.0.1:8747',
          metricsSecret: 'metrics',
        );
        final server = (await vaultRepository.all()).single;
        expect(server.maidCafeTerminalPort, 8747);

        // A browser has no tunnel, so it dials the same daemon on the host.
        final browser = await vaultRepository.maidCafeTerminalTargetFor(
          server,
          browserBuild: true,
        );
        expect(browser?.baseUrl, 'http://10.0.0.9:8747');

        // A native client keeps the tunnel address it stored.
        final native = await vaultRepository.maidCafeTerminalTargetFor(
          server,
          browserBuild: false,
        );
        expect(native?.baseUrl, 'http://127.0.0.1:8747');
      },
    );

    test('a cleared daemon config drops the learned port', () async {
      final credentialId = await insertCredential();
      final created = await repository.create(
        ServerDraft(
          name: 'web-host',
          host: '10.0.0.9',
          port: 22,
          username: 'root',
          credentialId: credentialId,
        ),
      );
      await repository.updateMaidCafeConfig(
        created,
        daemonUrl: 'http://127.0.0.1:9000',
      );
      expect((await repository.all()).single.maidCafeTerminalPort, 9000);

      await repository.clearMaidCafeConfig(created);
      expect((await repository.all()).single.maidCafeTerminalPort, isNull);
    });

    test('create and update persist chained jump hosts', () async {
      final firstHop = await repository.create(
        const ServerDraft(
          name: 'bastion',
          host: '10.0.0.10',
          port: 22,
          username: 'root',
        ),
      );
      final secondHop = await repository.create(
        ServerDraft(
          name: 'internal-gateway',
          host: '10.0.0.15',
          port: 22,
          username: 'root',
          jumpHostServerId: firstHop.id,
        ),
      );
      final target = await repository.create(
        ServerDraft(
          name: 'internal',
          host: '10.0.0.20',
          port: 22,
          username: 'root',
          jumpHostServerId: secondHop.id,
        ),
      );

      expect(target.jumpHostServerId, secondHop.id);
      await repository.update(
        target,
        const ServerDraft(
          name: 'internal',
          host: '10.0.0.20',
          port: 22,
          username: 'root',
        ),
      );
      expect(
        (await repository.all())
            .singleWhere((server) => server.id == target.id)
            .jumpHostServerId,
        isNull,
      );
    });

    test('update replaces the stored configuration', () async {
      final credentialId = await insertCredential();
      final server = await repository.create(
        ServerDraft(
          name: 'web',
          host: '10.0.0.2',
          port: 22,
          username: 'deploy',
          credentialId: credentialId,
          environment: {'STAGE': 'staging'},
          tags: ['staging'],
        ),
      );
      await repository.update(
        server,
        ServerDraft(
          name: 'web',
          host: '10.0.0.2',
          port: 22,
          username: 'deploy',
          credentialId: credentialId,
          environment: {'STAGE': 'production', 'PORT': '8080'},
          initialSnippets: [9],
          tags: ['prod'],
        ),
      );

      final updated = (await repository.all()).single;
      expect(decodeEnvironmentMap(updated.environment), {
        'STAGE': 'production',
        'PORT': '8080',
      });
      expect(decodeSnippetIdList(updated.initialSnippets), [9]);
      expect(decodeStringList(updated.tags), ['prod']);
    });

    test('empty configuration is stored as null', () async {
      final credentialId = await insertCredential();
      final server = await repository.create(
        ServerDraft(
          name: 'plain',
          host: '10.0.0.3',
          port: 22,
          username: 'user',
          credentialId: credentialId,
        ),
      );

      expect(server.environment, isNull);
      expect(server.initialSnippets, isNull);
      expect(server.tags, isNull);
      expect(decodeEnvironmentMap(server.environment), isEmpty);
      expect(decodeSnippetIdList(server.initialSnippets), isEmpty);
      expect(decodeStringList(server.tags), isEmpty);
      expect(server.fileManagementInitialPath, isNull);
      expect(server.fileManagementFavorites, isNull);
    });

    test('create appends servers after existing ones', () async {
      final first = await repository.create(
        ServerDraft(name: 'one', host: '10.0.0.1', port: 22, username: 'u'),
      );
      final second = await repository.create(
        ServerDraft(name: 'two', host: '10.0.0.2', port: 22, username: 'u'),
      );

      expect(first.sortOrder!, lessThan(second.sortOrder!));
      expect((await repository.all()).map((s) => s.id), [first.id, second.id]);
    });

    test('reorderServers persists the requested order', () async {
      final servers = [
        for (var i = 0; i < 3; i++)
          await repository.create(
            ServerDraft(
              name: 'server-$i',
              host: '10.0.0.$i',
              port: 22,
              username: 'u',
            ),
          ),
      ];

      final reordered = [servers[2].id, servers[0].id, servers[1].id];
      await repository.reorderServers(reordered);

      final expected = [servers[2].id, servers[0].id, servers[1].id];
      expect((await repository.all()).map((s) => s.id), expected);
      final watched = await database.watchServers().first;
      expect(watched.map((s) => s.id), expected);
    });
  });

  group('ServerRepository port-forward presets', () {
    late AppDatabase database;
    late ServerRepository repository;
    late int serverId;

    setUp(() async {
      final directory = Directory.systemTemp.createTempSync(
        'preset_config_test',
      );
      database = AppDatabase(filePath: '${directory.path}/test.sqlite');
      repository = ServerRepository(database, VaultService(database));
      serverId = await repository
          .create(
            const ServerDraft(
              name: 'tunnel',
              host: '10.0.0.9',
              port: 22,
              username: 'root',
            ),
          )
          .then((server) => server.id);
    });

    tearDown(() => database.close());

    Future<void> saveTcp({
      String bindHost = '127.0.0.1',
      int bindPort = 8080,
      String targetHost = '127.0.0.1',
      int targetPort = 80,
      bool autoStart = false,
    }) => repository.savePortForwardConfig(
      serverId: serverId,
      direction: PortForwardDirection.local,
      kind: PortForwardKind.tcp,
      bindHost: bindHost,
      bindPort: bindPort,
      targetHost: targetHost,
      targetPort: targetPort,
      autoStart: autoStart,
    );

    test('save persists a preset and exposes it to watchers', () async {
      await saveTcp();

      final configs = await repository.portForwardConfigsForServer(serverId);
      expect(configs, hasLength(1));
      expect(configs.single.bindHost, '127.0.0.1');
      expect(configs.single.bindPort, 8080);
      expect(configs.single.targetPort, 80);
      expect(configs.single.direction, PortForwardDirection.local.name);
      expect(configs.single.kind, PortForwardKind.tcp.name);
      expect(configs.single.autoStart, isFalse);

      final watched = await repository.watchPortForwardConfigs(serverId).first;
      expect(watched.map((c) => c.id), [configs.single.id]);
    });

    test('saving the same forward updates instead of duplicating', () async {
      await saveTcp();
      await saveTcp(autoStart: true);

      final configs = await repository.portForwardConfigsForServer(serverId);
      expect(configs, hasLength(1));
      // Auto-start can only be turned on by a repeated save.
      expect(configs.single.autoStart, isTrue);
    });

    test('presets are scoped per server', () async {
      final other = await repository.create(
        const ServerDraft(
          name: 'other',
          host: '10.0.0.10',
          port: 22,
          username: 'root',
        ),
      );
      await saveTcp();

      expect(await repository.portForwardConfigsForServer(other.id), isEmpty);
      expect(
        await repository.portForwardConfigsForServer(serverId),
        hasLength(1),
      );
    });

    test('socks5 presets round-trip with empty target fields', () async {
      await repository.savePortForwardConfig(
        serverId: serverId,
        direction: PortForwardDirection.local,
        kind: PortForwardKind.socks5,
        bindHost: '127.0.0.1',
        bindPort: 1080,
        targetHost: '',
        targetPort: 0,
      );

      final configs = await repository.portForwardConfigsForServer(serverId);
      expect(configs.single.kind, PortForwardKind.socks5.name);
      expect(configs.single.targetHost, '');
      expect(configs.single.targetPort, 0);
    });

    test('autoStart toggle and delete remove the preset', () async {
      await saveTcp();
      final config = (await repository.portForwardConfigsForServer(
        serverId,
      )).single;

      await repository.setPortForwardConfigAutoStart(config.id, true);
      expect(
        (await repository.portForwardConfigsForServer(
          serverId,
        )).single.autoStart,
        isTrue,
      );

      await repository.deletePortForwardConfig(config.id);
      expect(await repository.portForwardConfigsForServer(serverId), isEmpty);
    });
  });

  group('ServerRepository runtime watch configs', () {
    late AppDatabase database;
    late ServerRepository repository;
    late int serverId;

    setUp(() async {
      final directory = Directory.systemTemp.createTempSync(
        'runtime_watch_test',
      );
      database = AppDatabase(filePath: '${directory.path}/test.sqlite');
      repository = ServerRepository(database, VaultService(database));
      serverId = await repository
          .create(
            const ServerDraft(
              name: 'runtime-host',
              host: '10.0.0.9',
              port: 22,
              username: 'u',
            ),
          )
          .then((server) => server.id);
    });

    test('setRuntimeEnabled persists and watchers see the toggle', () async {
      await repository.setRuntimeEnabled(serverId, RuntimeKind.java, false);
      final configs = await repository.watchRuntimeWatchConfigs(serverId).first;
      expect(configs, hasLength(1));
      expect(configs.single.runtime, 'java');
      expect(configs.single.enabled, isFalse);
    });

    test(
      'toggling the same runtime twice updates instead of duplicating',
      () async {
        await repository.setRuntimeEnabled(serverId, RuntimeKind.python, false);
        await repository.setRuntimeEnabled(serverId, RuntimeKind.python, true);
        final configs = await repository
            .watchRuntimeWatchConfigs(serverId)
            .first;
        expect(configs, hasLength(1));
        expect(configs.single.enabled, isTrue);
      },
    );

    test('watch configs are scoped per server', () async {
      await repository.setRuntimeEnabled(serverId, RuntimeKind.dotnet, false);
      final otherId = await repository
          .create(
            const ServerDraft(
              name: 'other',
              host: '10.0.0.10',
              port: 22,
              username: 'u',
            ),
          )
          .then((server) => server.id);
      expect(await repository.watchRuntimeWatchConfigs(otherId).first, isEmpty);
    });

    test(
      'setRuntimePinned persists and watchPinnedRuntimeConfigs sees it',
      () async {
        await repository.setRuntimePinned(serverId, 'java', true);
        final pinned = await repository.watchPinnedRuntimeConfigs().first;
        expect(pinned, hasLength(1));
        expect(pinned.single.serverId, serverId);
        expect(pinned.single.runtime, 'java');
        expect(pinned.single.pinned, isTrue);
      },
    );

    test('unpinning removes the row from the pinned watcher', () async {
      await repository.setRuntimePinned(serverId, 'nginx', true);
      await repository.setRuntimePinned(serverId, 'nginx', false);
      expect(await repository.watchPinnedRuntimeConfigs().first, isEmpty);
    });

    test('pins are scoped per server', () async {
      await repository.setRuntimePinned(serverId, 'java', true);
      final otherId = await repository
          .create(
            const ServerDraft(
              name: 'other',
              host: '10.0.0.11',
              port: 22,
              username: 'u',
            ),
          )
          .then((server) => server.id);
      final pinned = await repository.watchPinnedRuntimeConfigs().first;
      expect(pinned, hasLength(1));
      expect(pinned.single.serverId, serverId);
      expect(await repository.watchPinnedRuntimeConfigs().first, hasLength(1));
      // Unpinning server A must not affect server B (no rows exist there).
      expect(await repository.watchRuntimeWatchConfigs(otherId).first, isEmpty);
    });

    test('app settings round-trip through the vault database', () async {
      expect(await repository.getAppSetting('runtime_detected_only'), isNull);
      await repository.setAppSetting('runtime_detected_only', 'false');
      expect(await repository.getAppSetting('runtime_detected_only'), 'false');
      expect(
        await repository.watchAppSetting('runtime_detected_only').first,
        'false',
      );
      // Upsert overwrites.
      await repository.setAppSetting('runtime_detected_only', 'true');
      expect(await repository.getAppSetting('runtime_detected_only'), 'true');
      expect(
        await repository.watchAppSetting('runtime_detected_only').first,
        'true',
      );
    });
  });
}
