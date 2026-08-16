import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart' show SizedBox;
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/cloud_sync_service.dart';
import 'package:maid_kit/servers/maidcafe_connect.dart';
import 'package:maid_kit/servers/maidcafe_service.dart';
import 'package:maid_kit/servers/maidcafe_stream.dart';

Server _server() => Server(
  id: 1,
  name: 'Build host',
  host: 'build.example',
  port: 22,
  username: 'builder',
  collectStats: true,
  collectSystemInfo: true,
  connectionType: 'ssh',
);

class _FakeService extends MaidCafeService {
  _FakeService()
    : super(
        baseUrl: maidCafeDefaultCloudUrl,
        cloudSync: CloudSyncService(vaultId: 'test'),
      );

  String? registeredName;
  String? registeredWorkspaceId;

  @override
  Future<MaidCafeDaemonCredential> createDaemon({
    required String name,
    required String workspaceId,
  }) async {
    registeredName = name;
    registeredWorkspaceId = workspaceId;
    return MaidCafeDaemonCredential(
      id: 'daemon-new',
      name: name,
      enabled: true,
      lastSeenAt: null,
      createdAt: DateTime.utc(2026, 8, 13),
      updatedAt: DateTime.utc(2026, 8, 13),
      secret: 'cloud-secret',
    );
  }
}

MaidCafeDaemonAccess _access() => MaidCafeDaemonAccess(
  port: 8747,
  apiSecret: 'api-secret',
  id: 'old-id',
  transport: 'http',
  listenHost: '127.0.0.1',
  configText: '[daemon]\nid = "old-id"',
  metricsInterval: '1m',
  requestTimeout: '10s',
  scriptTimeout: '30s',
  maxBodyBytes: 65536,
  maxConcurrentRuns: 4,
);

/// [WidgetRef] is sealed and only widgets can provide it; a throwaway
/// Consumer is the lightest harness.
Future<WidgetRef> _widgetRef(WidgetTester tester) async {
  late WidgetRef captured;
  await tester.pumpWidget(
    ProviderScope(
      child: Consumer(
        builder: (context, ref, _) {
          captured = ref;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return captured;
}

void main() {
  testWidgets(
    'connect patches an installed daemon and registers it in the workspace',
    (tester) async {
      final service = _FakeService();
      String? capturedScript;
      String? savedUrl;
      var installs = 0;
      var invalidations = 0;
      final connector = MaidCafeServerConnectorImpl(
        service: service,
        cloudUrl: () async => 'https://mk.solsynth.dev',
        sudoPassword: (_) async => 'sudo-pass',
        runScript: ({required server, required script, sudoPassword}) async {
          capturedScript = script;
        },
        saveDaemonUrl: (server, url) async {
          savedUrl = url;
        },
        installDaemon:
            ({
              required ref,
              required server,
              required daemon,
              required cloudUrl,
              required sudoPassword,
              required port,
            }) async {
              installs++;
            },
        invalidateSession: (_) => invalidations++,
      );
      final ref = await _widgetRef(tester);

      final credential = await connector.connect(
        server: _server(),
        workspaceId: 'ws-1',
        probe: MaidCafeServerProbe(
          MaidCafeServerProbeStatus.installed,
          access: _access(),
        ),
        ref: ref,
      );

      expect(service.registeredName, 'Build host');
      expect(service.registeredWorkspaceId, 'ws-1');
      expect(credential.secret, 'cloud-secret');
      expect(capturedScript, isNotNull);
      // The config-sync script ships the patched config base64-encoded.
      final encoded = RegExp(r"""printf '%s' '([A-Za-z0-9+/=]+)' \| base64""")
          .firstMatch(capturedScript!)
          ?.group(1);
      expect(encoded, isNotNull);
      final patched = utf8.decode(base64Decode(encoded!));
      expect(patched, contains('id = "daemon-new"'));
      expect(patched, contains('cloudUrl = "https://mk.solsynth.dev"'));
      expect(patched, contains('cloudSecret = "cloud-secret"'));
      expect(savedUrl, 'http://127.0.0.1:8747');
      expect(installs, 0);
      expect(invalidations, 1);
    },
  );

  testWidgets('connect installs the bundle for a server without MaidCafe', (
    tester,
  ) async {
    final service = _FakeService();
    var scriptRuns = 0;
    MaidCafeDaemonCredential? installedDaemon;
    String? installedCloudUrl;
    int? installedPort;
    final connector = MaidCafeServerConnectorImpl(
      service: service,
      cloudUrl: () async => 'https://mk.solsynth.dev',
      sudoPassword: (_) async => null,
      runScript: ({required server, required script, sudoPassword}) async {
        scriptRuns++;
      },
      saveDaemonUrl: (server, url) async {},
      installDaemon:
          ({
            required ref,
            required server,
            required daemon,
            required cloudUrl,
            required sudoPassword,
            required port,
          }) async {
            installedDaemon = daemon;
            installedCloudUrl = cloudUrl;
            installedPort = port;
          },
      invalidateSession: (_) {},
    );
    final ref = await _widgetRef(tester);

    await connector.connect(
      server: _server(),
      workspaceId: 'ws-1',
      probe: const MaidCafeServerProbe(MaidCafeServerProbeStatus.notInstalled),
      ref: ref,
    );

    expect(scriptRuns, 0);
    expect(installedDaemon?.id, 'daemon-new');
    expect(installedDaemon?.secret, 'cloud-secret');
    expect(installedCloudUrl, 'https://mk.solsynth.dev');
    expect(installedPort, 8747);
  });
}
