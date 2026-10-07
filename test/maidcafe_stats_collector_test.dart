import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/maidcafe_stats.dart';
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/server_repository.dart';
import 'package:maid_kit/servers/ssh_connection_manager.dart';
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

/// The reason a card's manual refresh reports for a host whose daemon read
/// cannot happen. Each outcome is a different thing for the operator to fix, so
/// the collector has to tell them apart rather than let the caller blame the
/// SSH transport a browser never had.
void main() {
  _mockPathProvider();

  late AppDatabase database;
  late ServerRepository repository;
  late MaidCafeStatsCollector collector;

  setUp(() async {
    final directory = Directory.systemTemp.createTempSync('maidcafe_stats');
    database = AppDatabase(filePath: '${directory.path}/test.sqlite');
    final vault = VaultService(database, secureStorage: _MemoryStorage());
    await vault.create('vault-password');
    repository = ServerRepository(database, vault);
    collector = MaidCafeStatsCollector(
      repository: repository,
      manager: SshConnectionManager(() => throw UnimplementedError()),
    );
  });

  tearDown(() => database.close());

  Future<Server> createServer({
    String? terminalUrl = 'https://daemon.example',
    bool collectStats = true,
    String? daemonId,
  }) => repository.create(
    ServerDraft(
      name: 'build host',
      host: 'build.example',
      port: 22,
      username: 'builder',
      collectStats: collectStats,
      maidCafeTerminalUrl: terminalUrl,
      maidCafeDaemonId: daemonId,
    ),
  );

  test('a host with no daemon address this client can dial', () async {
    final server = await createServer(terminalUrl: null, collectStats: true);

    expect(
      await collector.blockerFor(server),
      MaidCafeStatsBlocker.routeMissing,
    );
    expect(collector.endpointFor(server), isNull);
  });

  test('collection switched off for the host reads as no route', () async {
    final server = await createServer(collectStats: false);

    expect(
      await collector.blockerFor(server),
      MaidCafeStatsBlocker.routeMissing,
    );
  });

  test('a stored endpoint with no credential stored for it', () async {
    final server = await createServer();

    expect(
      await collector.blockerFor(server),
      MaidCafeStatsBlocker.credentialMissing,
    );
  });

  test('the metrics secret stands in for the terminal secret', () async {
    final server = await createServer();
    await repository.updateMaidCafeConfig(
      server,
      daemonUrl: 'https://daemon.example',
      metricsSecret: 'metrics-secret',
    );

    expect(
      await collector.blockerFor(await repository.currentServer(server)),
      isNull,
    );
  });

  test(
    'the dedicated terminal secret is preferred when it is stored',
    () async {
      final server = await createServer();
      await repository.updateMaidCafeConfig(
        server,
        daemonUrl: 'https://daemon.example',
        metricsSecret: 'metrics-secret',
      );
      await repository.update(
        server,
        ServerDraft(
          name: server.name,
          host: server.host,
          port: server.port,
          username: server.username,
          maidCafeTerminalUrl: server.maidCafeTerminalUrl,
          maidCafeTerminalSecret: 'terminal-secret',
        ),
      );

      final stored = await repository.currentServer(server);
      expect(
        await repository.maidCafeTerminalSecretFor(stored),
        'terminal-secret',
      );
      expect(
        await repository.maidCafeMetricsSecretFor(stored),
        'metrics-secret',
      );
      expect(await collector.blockerFor(stored), isNull);
    },
  );
}
