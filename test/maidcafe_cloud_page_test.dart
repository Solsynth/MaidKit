import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart' as ez;
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart' as ez_tr;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/cloud_sync_service.dart';
import 'package:maid_kit/servers/maidcafe_cloud_page.dart';
import 'package:maid_kit/servers/maidcafe_connect.dart';
import 'package:maid_kit/servers/maidcafe_metoer.dart';
import 'package:maid_kit/servers/maidcafe_preferences.dart';
import 'package:maid_kit/servers/maidcafe_service.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/theme.dart';

MaidCafeDaemon _daemon({String id = 'daemon-1', String name = 'host-1'}) =>
    MaidCafeDaemon(
      id: id,
      name: name,
      enabled: true,
      lastSeenAt: null,
      createdAt: DateTime.utc(2026, 8, 13),
      updatedAt: DateTime.utc(2026, 8, 13),
    );

MaidCafeMetoerNotification _notification() => MaidCafeMetoerNotification(
  id: 'n1',
  topic: 'maidcafe.daemon.alert',
  title: 'Webhook backup failed',
  body: 'exit code 1',
  viewedAt: null,
  createdAt: DateTime.utc(2026, 8, 13),
);

MaidCafeCloudAction _cloudAction() => const MaidCafeCloudAction(
  name: 'backup',
  displayName: 'Backup data',
  enabled: true,
  notifyOnSuccess: false,
  notifyOnFailure: true,
  timeout: '',
  cwd: '',
  user: '',
  updatedAt: null,
);

MaidCafeCredential _credential() => MaidCafeCredential(
  id: 'cred-1',
  label: 'ci-backup',
  daemonIds: const [],
  hostIds: const ['host-42'],
  actionNames: const ['backup'],
  createdAt: DateTime.utc(2026, 8, 13),
);

class _FakeMaidCafeService extends MaidCafeService {
  _FakeMaidCafeService()
    : super(
        baseUrl: maidCafeDefaultCloudUrl,
        cloudSync: CloudSyncService(vaultId: 'test'),
      );

  String? registeredWorkspaceId;
  String? invokedActionName;

  @override
  Future<MaidCafeDaemonCredential> createDaemon({
    required String name,
    required String workspaceId,
  }) async {
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

  @override
  Future<MaidCafeWebhookResult> invokeActionViaCloud({
    required String daemonId,
    required String actionName,
    Map<String, dynamic> body = const {},
  }) async {
    invokedActionName = actionName;
    return MaidCafeWebhookResult(
      statusCode: 200,
      body: Uint8List(0),
      headers: const {},
    );
  }

  String? createdCredentialLabel;

  @override
  Future<MaidCafeCredential> createCredential({
    required String label,
    List<String> daemonIds = const [],
    List<String> hostIds = const [],
    List<String> actionNames = const [],
  }) async {
    createdCredentialLabel = label;
    return MaidCafeCredential(
      id: 'cred-new',
      label: label,
      daemonIds: daemonIds,
      hostIds: hostIds,
      actionNames: actionNames,
      createdAt: DateTime.utc(2026, 8, 13),
      token: 'mk_test-token',
    );
  }
}

class _FakeConnector implements MaidCafeServerConnector {
  int? connectedServerId;
  String? connectedWorkspaceId;

  @override
  Future<MaidCafeDaemonCredential> connect({
    required Server server,
    required String workspaceId,
    required MaidCafeServerProbe probe,
    required WidgetRef ref,
  }) async {
    connectedServerId = server.id;
    connectedWorkspaceId = workspaceId;
    return MaidCafeDaemonCredential(
      id: 'daemon-new',
      name: server.name,
      enabled: true,
      lastSeenAt: null,
      createdAt: DateTime.utc(2026, 8, 13),
      updatedAt: DateTime.utc(2026, 8, 13),
      secret: 'cloud-secret',
    );
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return Directory.systemTemp.path;
        });
    final enMap =
        jsonDecode(File('assets/translations/en-US.json').readAsStringSync())
            as Map<String, dynamic>;
    ez.Localization.load(
      const Locale('en', 'US'),
      translations: ez_tr.Translations(enMap),
      ignorePluralRules: false,
    );
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    bool signedIn = true,
    _FakeMaidCafeService? service,
  }) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final overrides = [
      maidCafeSettingsProvider.overrideWithValue(InMemoryMaidCafeSettings()),
      serversProvider.overrideWith((ref) => Stream.value(<Server>[])),
      cloudUserProvider.overrideWith(
        (ref) => Future.value(
          signedIn
              ? const CloudUser(name: 'Ada Lovelace', handle: 'ada')
              : null,
        ),
      ),
      cloudWorkspacesProvider.overrideWith(
        (ref) => Future.value(
          signedIn
              ? const [
                  CloudWorkspace(id: 'ws-1', slug: 'ws', name: 'Workspace'),
                ]
              : const <CloudWorkspace>[],
        ),
      ),
      maidCafeDaemonsProvider.overrideWith(
        (ref, workspaceId) async => [_daemon()],
      ),
      maidCafeMetricsProvider.overrideWith(
        (ref, daemonId) async => const <MaidCafeMetric>[],
      ),
      maidCafeCloudActionsProvider.overrideWith(
        (ref, daemonId) async => [_cloudAction()],
      ),
      maidCafeCredentialsProvider.overrideWith((ref) async => [_credential()]),
      maidCafeServiceProvider.overrideWithValue(
        service ?? _FakeMaidCafeService(),
      ),
      maidCafeMetoerNotificationsProvider.overrideWith(
        (ref) => Future.value(
          signedIn ? [_notification()] : const <MaidCafeMetoerNotification>[],
        ),
      ),
      maidCafeMetoerUnreadCountProvider.overrideWith(
        (ref) => Future.value(signedIn ? 1 : 0),
      ),
    ];
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            theme: createMaidKitTheme(Brightness.light),
            locale: const Locale('en', 'US'),
            supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const MaidCafeCloudPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('signed out renders the Solarpass sign-in CTA', (tester) async {
    await pumpPage(tester, signedIn: false);

    expect(find.text('settingsCloudSignIn'.tr()), findsOneWidget);
    expect(find.text('maidCafeNoWorkspaces'.tr()), findsOneWidget);
  });

  testWidgets('signed in renders daemon, unread badge, and notification', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.text('host-1'), findsOneWidget);
    expect(find.text('maidCafeUnreadCount'.tr(args: ['1'])), findsOneWidget);
    expect(find.text('Webhook backup failed'), findsOneWidget);
    expect(find.text('exit code 1'), findsOneWidget);
    // Actions the daemon reported to the cloud render as invocable chips.
    expect(find.text('Backup data'), findsOneWidget);
  });

  testWidgets('cloud action chips invoke through the relay', (tester) async {
    final service = _FakeMaidCafeService();
    await pumpPage(tester, service: service);

    await tester.tap(find.text('Backup data'));
    await tester.pumpAndSettle();

    expect(service.invokedActionName, 'backup');
  });

  testWidgets('credentials card creates and shows the one-time token', (
    tester,
  ) async {
    final service = _FakeMaidCafeService();
    await pumpPage(tester, service: service);

    expect(find.text('ci-backup'), findsOneWidget);

    await tester.tap(find.text('maidCafeCredentialCreate'.tr()));
    await tester.pumpAndSettle();

    await tester.enterText(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          )
          .first,
      'ci-deploy',
    );
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, 'maidCafeCredentialCreate'.tr()).last,
    );
    await tester.pumpAndSettle();

    expect(service.createdCredentialLabel, 'ci-deploy');
    expect(find.text('maidCafeCredentialToken'.tr()), findsOneWidget);
    expect(find.text('mk_test-token'), findsOneWidget);
  });

  testWidgets('manual register flow shows the one-time config snippet', (
    tester,
  ) async {
    final service = _FakeMaidCafeService();
    await pumpPage(tester, service: service);

    await tester.tap(find.text('maidCafeRegister'.tr()));
    await tester.pumpAndSettle();

    expect(find.text('maidCafeNoServers'.tr()), findsOneWidget);
    expect(find.text('maidCafeRegisterManually'.tr()), findsOneWidget);

    await tester.tap(find.text('maidCafeRegisterManually'.tr()));
    await tester.pumpAndSettle();

    final dialogField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(dialogField, 'host-1');
    await tester.pump();

    await tester.tap(
      find.widgetWithText(FilledButton, 'maidCafeRegister'.tr()).last,
    );
    await tester.pumpAndSettle();

    expect(service.registeredWorkspaceId, 'ws-1');
    expect(find.text('maidCafeOneTimeSecret'.tr()), findsOneWidget);
    expect(find.text('cloud-secret'), findsOneWidget);
    expect(find.textContaining('cloudSecret = "cloud-secret"'), findsOneWidget);
    expect(find.textContaining('id = "daemon-new"'), findsOneWidget);
  });

  testWidgets('register flow connects a server automatically', (tester) async {
    final connector = _FakeConnector();
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final server = Server(
      id: 1,
      name: 'Build host',
      host: 'build.example',
      port: 22,
      username: 'builder',
      collectStats: true,
      collectSystemInfo: true,
      connectionType: 'ssh',
    );
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: ProviderScope(
          overrides: [
            maidCafeSettingsProvider.overrideWithValue(
              InMemoryMaidCafeSettings(),
            ),
            serversProvider.overrideWith((ref) => Stream.value([server])),
            cloudUserProvider.overrideWith(
              (ref) => Future.value(
                const CloudUser(name: 'Ada Lovelace', handle: 'ada'),
              ),
            ),
            cloudWorkspacesProvider.overrideWith(
              (ref) => Future.value(const [
                CloudWorkspace(id: 'ws-1', slug: 'ws', name: 'Workspace'),
              ]),
            ),
            maidCafeDaemonsProvider.overrideWith(
              (ref, workspaceId) async => [_daemon()],
            ),
            maidCafeServiceProvider.overrideWithValue(_FakeMaidCafeService()),
            maidCafeCloudActionsProvider.overrideWith(
              (ref, daemonId) async => [_cloudAction()],
            ),
            maidCafeCredentialsProvider.overrideWith(
              (ref) async => [_credential()],
            ),
            maidCafeServerProbeProvider.overrideWith(
              (ref, serverId) async => const MaidCafeServerProbe(
                MaidCafeServerProbeStatus.installed,
              ),
            ),
            maidCafeServerConnectorProvider.overrideWithValue(connector),
            maidCafeMetoerNotificationsProvider.overrideWith(
              (ref) => Future.value([_notification()]),
            ),
            maidCafeMetoerUnreadCountProvider.overrideWith(
              (ref) => Future.value(1),
            ),
          ],
          child: MaterialApp(
            theme: createMaidKitTheme(Brightness.light),
            locale: const Locale('en', 'US'),
            supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const MaidCafeCloudPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('maidCafeRegister'.tr()));
    await tester.pumpAndSettle();

    expect(find.text('Build host'), findsOneWidget);
    expect(find.text('maidCafeRegisterManually'.tr()), findsNothing);
    await tester.tap(find.text('Build host'));
    await tester.pumpAndSettle();

    expect(connector.connectedServerId, 1);
    expect(connector.connectedWorkspaceId, 'ws-1');
    expect(find.text('maidCafeOneTimeSecret'.tr()), findsOneWidget);
    expect(find.text('cloud-secret'), findsOneWidget);
    expect(find.textContaining('cloudSecret = "cloud-secret"'), findsOneWidget);
  });
}
