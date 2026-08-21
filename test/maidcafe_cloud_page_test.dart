import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart' as ez;
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart' as ez_tr;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/cloud_sync_service.dart';
import 'package:maid_kit/servers/maidcafe_daemon_detail_page.dart';
import 'package:maid_kit/servers/maidcafe_cloud_page.dart';
import 'package:maid_kit/servers/maidcafe_connect.dart';
import 'package:maid_kit/servers/maidcafe_preferences.dart';
import 'package:maid_kit/servers/maidcafe_service.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/theme.dart';

MaidCafeDaemon _daemon({
  String id = 'daemon-1',
  String name = 'host-1',
  DateTime? disconnectedAt,
}) => MaidCafeDaemon(
  id: id,
  name: name,
  enabled: true,
  lastSeenAt: null,
  createdAt: DateTime.utc(2026, 8, 13),
  updatedAt: DateTime.utc(2026, 8, 13),
  hostId: 'host-42',
  disconnectedAt: disconnectedAt,
);
MaidCafeNotification _notification() => MaidCafeNotification(
  id: 'n1',
  accountId: 'account-1',
  daemonId: 'daemon-1',
  kind: 'maidcafe.daemon.alert',
  title: 'Webhook backup failed',
  body: 'exit code 1',
  metadata: const {},
  readAt: null,
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

MaidCafeQuota _quota() => const MaidCafeQuota(
  workspaceId: 'ws-1',
  maxDaemons: 5,
  pollingIntervalSeconds: 30,
  metricsRetentionDays: 30,
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

  @override
  Future<List<MaidCafeCloudAction>> listActions(String daemonId) async => [
    _cloudAction(),
  ];

  @override
  Future<List<MaidCafeCloudContainer>> listContainers(
    String daemonId, {
    String? compose,
    String? state,
    DateTime? before,
    int limit = 100,
  }) async => const [];

  @override
  Future<List<MaidCafeCloudLog>> listLogs(
    String daemonId, {
    String? containerId,
    DateTime? before,
    int limit = 100,
  }) async => const [];

  String? createdCredentialLabel;
  List<String> createdActionNames = const [];
  List<String> createdHostIds = const [];

  @override
  Future<MaidCafeCredential> createCredential({
    required String label,
    List<String> daemonIds = const [],
    List<String> hostIds = const [],
    List<String> actionNames = const [],
  }) async {
    createdCredentialLabel = label;
    createdActionNames = actionNames;
    createdHostIds = hostIds;
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

  @override
  Future<List<MaidCafeCredential>> listCredentials() async => [_credential()];
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
    MaidCafeDaemon? daemon,
    List<MaidCafeMetric> metrics = const [],
    Future<List<MaidCafeMetric>> Function(Ref ref, String daemonId)?
    metricsLoader,
    Future<List<MaidCafeNotification>> Function(Ref ref, String workspaceId)?
    notificationsLoader,
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
        (ref, workspaceId) async => [daemon ?? _daemon()],
      ),
      maidCafeQuotaProvider.overrideWith((ref, workspaceId) async => _quota()),
      maidCafeMetricsProvider.overrideWith(
        metricsLoader ?? ((Ref ref, String daemonId) async => metrics),
      ),
      maidCafeCloudActionsProvider.overrideWith(
        (ref, daemonId) async => [_cloudAction()],
      ),
      maidCafeServiceProvider.overrideWithValue(
        service ?? _FakeMaidCafeService(),
      ),
      maidCafeNotificationsProvider.overrideWith(
        notificationsLoader ??
            ((ref, workspaceId) async =>
                signedIn ? [_notification()] : const <MaidCafeNotification>[]),
      ),
      maidCafeUnreadNotificationCountProvider.overrideWith(
        (ref, workspaceId) async => signedIn ? 1 : 0,
      ),
      maidCafeNotificationTopicsProvider.overrideWith(
        (ref, workspaceId) async => const [
          MaidCafeNotificationTopic(
            topic: 'maidcafe.daemon.alert',
            description: 'Daemon alerts',
          ),
        ],
      ),
      maidCafeNotificationPreferencesProvider.overrideWith(
        (ref, workspaceId) async => const <MaidCafeNotificationPreference>[],
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

  Future<void> pumpDetail(
    WidgetTester tester, {
    required _FakeMaidCafeService service,
  }) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: ProviderScope(
          overrides: [maidCafeServiceProvider.overrideWithValue(service)],
          child: MaterialApp(
            theme: createMaidKitTheme(Brightness.light),
            locale: const Locale('en', 'US'),
            supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: MaidCafeDaemonDetailPage(daemon: _daemon()),
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

  testWidgets('signed in renders daemon and unread badge', (tester) async {
    await pumpPage(tester);

    expect(find.text('host-1'), findsOneWidget);
    // Reported actions no longer occupy fleet cards; they live in the detail
    // page's Actions tab.
    expect(find.text('Backup data'), findsNothing);

    // The feed lives on the notifications tab.
    await tester.tap(find.text('maidCafeNotifications'.tr()));
    await tester.pumpAndSettle();
    expect(find.text('maidCafeUnreadCount'.tr(args: ['1'])), findsOneWidget);
    expect(find.text('Webhook backup failed'), findsOneWidget);
    expect(find.text('exit code 1'), findsOneWidget);
  });

  testWidgets('notifications refresh from pull and top-edge hover', (
    tester,
  ) async {
    var fetches = 0;
    await pumpPage(
      tester,
      notificationsLoader: (ref, workspaceId) async {
        fetches++;
        return [_notification()];
      },
    );

    await tester.tap(find.text('maidCafeNotifications'.tr()));
    await tester.pumpAndSettle();
    expect(fetches, 1);

    final refreshIndicator = find.byType(RefreshIndicator);
    final refreshTopLeft = tester.getTopLeft(refreshIndicator);
    await tester.dragFrom(
      refreshTopLeft + const Offset(300, 180),
      const Offset(0, 420),
    );
    await tester.pumpAndSettle();
    expect(fetches, greaterThan(1));

    final refreshButton = find.byKey(
      const ValueKey('maidcafe-notifications-refresh'),
    );
    final ignorePointer = find
        .ancestor(of: refreshButton, matching: find.byType(IgnorePointer))
        .first;
    expect(tester.widget<IgnorePointer>(ignorePointer).ignoring, isTrue);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final topLeft = tester.getTopLeft(refreshIndicator);
    await gesture.moveTo(topLeft + const Offset(100, 2));
    await tester.pump();
    expect(tester.widget<IgnorePointer>(ignorePointer).ignoring, isFalse);
    await gesture.removePointer();
  });

  testWidgets('fleet card surfaces a cloud heartbeat disconnect', (
    tester,
  ) async {
    await pumpPage(
      tester,
      daemon: _daemon(disconnectedAt: DateTime.utc(2026, 8, 17, 12, 0)),
    );

    expect(find.text('maidCafeDisconnected'.tr()), findsOneWidget);
  });

  testWidgets('fleet tab renders the workspace quota with daemon usage', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.text('maidCafeQuota'.tr()), findsOneWidget);
    expect(find.text('maidCafeQuotaMaxDaemons'.tr()), findsOneWidget);
    // One daemon registered against a max of five.
    expect(find.text('1 / 5'), findsOneWidget);
    expect(find.text('maidCafeQuotaSeconds'.tr(args: ['30'])), findsOneWidget);
    expect(find.text('maidCafeQuotaDays'.tr(args: ['30'])), findsOneWidget);
    final usageBar = tester.widget<LinearProgressIndicator>(
      find.byWidgetPredicate(
        (widget) => widget is LinearProgressIndicator && widget.minHeight == 6,
      ),
    );
    expect(usageBar.value, closeTo(0.2, 0.001));
  });

  testWidgets('daemon card surfaces load, disk and uptime from samples', (
    tester,
  ) async {
    final now = DateTime.now();
    await pumpPage(
      tester,
      metrics: [
        for (var i = 0; i < 5; i++)
          MaidCafeMetric(
            id: 'm$i',
            daemonId: 'daemon-1',
            sentAt: now.subtract(Duration(minutes: 5 * (4 - i))),
            receivedAt: now,
            uptimeSeconds: 3 * 86400 + 4 * 3600,
            processMemoryBytes: 1 << 30,
            cpuPercent: 30,
            cpuCount: 8,
            load1: 2.5,
            load5: 2.0,
            load15: 1.5,
            memoryUsedPercent: 40,
            memoryUsedBytes: (4 * (1 << 30) * 40) ~/ 100,
            memoryTotalBytes: 4 * (1 << 30),
            diskTotalKb: 102400,
            diskAvailableKb: 25600,
            webhookExecutions: 12,
            webhookFailures: 0,
          ),
      ],
    );

    expect(find.text('Load / CPU (1 min)'), findsOneWidget);
    expect(find.textContaining('2.50'), findsOneWidget);
    expect(find.text('Disk used'), findsOneWidget);
    // (102400 - 25600) / 102400 = 75% used.
    expect(find.text('75%'), findsOneWidget);
    expect(find.text('CPU usage'), findsOneWidget);
    expect(find.text('30%'), findsOneWidget);
    expect(
      find.textContaining('maidCafeUptime'.tr(args: ['3d 4h'])),
      findsOneWidget,
    );
  });
  testWidgets('daemon card offers a quick copy id action', (tester) async {
    await pumpPage(tester);

    final copyButton = find.byTooltip('maidCafeCopyDaemonId'.tr());
    expect(copyButton, findsOneWidget);
    await tester.tap(copyButton);
    await tester.pump();
  });

  testWidgets('cloud page polls the cloud for fresh daemon metrics', (
    tester,
  ) async {
    var fetches = 0;
    await pumpPage(
      tester,
      metricsLoader: (ref, daemonId) async {
        fetches++;
        return const <MaidCafeMetric>[];
      },
    );
    expect(fetches, 1); // initial load of the fleet tab

    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();
    expect(fetches, greaterThan(1));
  });

  testWidgets('detail actions invoke through the relay', (tester) async {
    final service = _FakeMaidCafeService();
    await pumpDetail(tester, service: service);

    await tester.tap(find.text('daemonDetailActions'.tr()));
    await tester.pumpAndSettle();
    expect(find.text('maidCafeRequestNotification'.tr()), findsOneWidget);
    await tester.tap(find.text('maidCafeNativeOpRun'.tr()));
    await tester.pumpAndSettle();

    expect(service.invokedActionName, 'backup');
  });

  testWidgets('credentials card creates and shows the one-time token', (
    tester,
  ) async {
    final service = _FakeMaidCafeService();
    await pumpPage(tester, service: service);

    // Credentials live on their own tab.
    await tester.tap(find.text('maidCafeCredentials'.tr()));
    await tester.pumpAndSettle();

    expect(find.text('ci-backup'), findsOneWidget);

    await tester.tap(find.text('maidCafeCredentialCreate'.tr()));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'maidCafeCredentialLabel'.tr()),
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
    // The sheet offers a copyable curl invocation against this cloud.
    expect(find.text('maidCafeCredentialCurlTitle'.tr()), findsOneWidget);
    expect(find.textContaining(maidCafeDefaultCloudUrl), findsOneWidget);
    expect(
      find.textContaining("Authorization: Bearer mk_test-token"),
      findsOneWidget,
    );
  });

  testWidgets('credential sheet picks action and host scopes from dropdowns', (
    tester,
  ) async {
    final service = _FakeMaidCafeService();
    await pumpPage(tester, service: service);

    await tester.tap(find.text('maidCafeCredentials'.tr()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('maidCafeCredentialCreate'.tr()));
    await tester.pumpAndSettle();

    // The actions picker offers every daemon-reported action; selecting it
    // scopes the credential to that action name. The menu stays open while
    // checking items; tapping the hint below dismisses it.
    await tester.tap(find.text('maidCafeCredentialActionsScope'.tr()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Backup data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('maidCafeCredentialScopesHint'.tr()));
    await tester.pumpAndSettle();

    // The hosts picker offers the stable host ids the daemons reported.
    await tester.tap(find.text('maidCafeCredentialHostsScope'.tr()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('host-42'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('maidCafeCredentialScopesHint'.tr()));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'maidCafeCredentialLabel'.tr()),
      'ci-deploy',
    );
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, 'maidCafeCredentialCreate'.tr()).last,
    );
    await tester.pumpAndSettle();

    expect(service.createdCredentialLabel, 'ci-deploy');
    expect(service.createdActionNames, ['backup']);
    expect(service.createdHostIds, ['host-42']);
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
            maidCafeNotificationsProvider.overrideWith(
              (ref, workspaceId) async => [_notification()],
            ),
            maidCafeUnreadNotificationCountProvider.overrideWith(
              (ref, workspaceId) async => 1,
            ),
            maidCafeNotificationTopicsProvider.overrideWith(
              (ref, workspaceId) async => const [
                MaidCafeNotificationTopic(
                  topic: 'maidcafe.daemon.alert',
                  description: 'Daemon alerts',
                ),
              ],
            ),
            maidCafeNotificationPreferencesProvider.overrideWith(
              (ref, workspaceId) async =>
                  const <MaidCafeNotificationPreference>[],
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
