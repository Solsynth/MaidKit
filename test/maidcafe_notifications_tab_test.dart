import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart' as ez;
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart' as ez_tr;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maid_kit/servers/cloud_sync_service.dart';
import 'package:maid_kit/servers/maidcafe_notifications_tab.dart';
import 'package:maid_kit/servers/maidcafe_service.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/theme.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:shared_preferences/shared_preferences.dart';

MaidCafeNotification _notification({
  String id = 'n1',
  String kind = 'daemon.alarm.disk_used_percent',
  String title = 'Disk almost full',
  String subtitle = '/var is at 92%',
  String body = 'threshold 80%',
  Map<String, dynamic> metadata = const {'daemon_name': 'prod-vps'},
  DateTime? readAt,
  DateTime? createdAt,
}) => MaidCafeNotification(
  id: id,
  accountId: 'account-1',
  daemonId: 'daemon-1',
  kind: kind,
  title: title,
  subtitle: subtitle,
  body: body,
  metadata: metadata,
  readAt: readAt,
  createdAt: createdAt ?? DateTime.utc(2026, 10, 2, 3),
);

class _FakeMaidCafeService extends MaidCafeService {
  _FakeMaidCafeService()
    : super(
        baseUrl: maidCafeDefaultCloudUrl,
        cloudSync: CloudSyncService(vaultId: 'test'),
      );

  final List<String> readIds = [];
  String? markedAllWorkspaceId;
  int listCalls = 0;
  DateTime? lastBefore;
  int? lastLimit;
  List<MaidCafeNotification> olderPage = const [];

  @override
  Future<void> markNotificationRead(String notificationId) async {
    readIds.add(notificationId);
  }

  @override
  Future<void> markAllNotificationsRead({required String workspaceId}) async {
    markedAllWorkspaceId = workspaceId;
  }

  @override
  Future<List<MaidCafeNotification>> listNotifications({
    required String workspaceId,
    bool unread = false,
    String? daemonId,
    int limit = 100,
    DateTime? before,
  }) async {
    listCalls++;
    lastBefore = before;
    lastLimit = limit;
    return olderPage;
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
    final enMap =
        jsonDecode(File('assets/translations/en-US.json').readAsStringSync())
            as Map<String, dynamic>;
    ez.Localization.load(
      const Locale('en', 'US'),
      translations: ez_tr.Translations(enMap),
      ignorePluralRules: false,
    );
  });

  Future<_FakeMaidCafeService> pumpTab(
    WidgetTester tester, {
    List<MaidCafeNotification>? notifications,
    int unreadCount = 1,
    Future<List<MaidCafeNotification>> Function()? loader,
    _FakeMaidCafeService? service,
    String workspaceId = 'ws-1',
  }) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fake = service ?? _FakeMaidCafeService();
    final items = notifications ?? [_notification()];
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: ProviderScope(
          overrides: [
            maidCafeServiceProvider.overrideWithValue(fake),
            maidCafeNotificationsProvider.overrideWith(
              (ref, workspaceId) async =>
                  loader == null ? items : await loader(),
            ),
            maidCafeUnreadNotificationCountProvider.overrideWith(
              (ref, workspaceId) async => unreadCount,
            ),
            maidCafeNotificationTopicsProvider.overrideWith(
              (ref, workspaceId) async => const [
                MaidCafeNotificationTopic(
                  topic: 'daemon.alarm.disk_used_percent',
                  description: 'Disk alarms',
                ),
                MaidCafeNotificationTopic(
                  topic: 'webhook.failure',
                  description: 'Webhook failures',
                ),
              ],
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
            home: Scaffold(
              body: MaidCafeNotificationsTab(workspaceId: workspaceId),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  testWidgets('renders a Solian-style row with topic, daemon, and body', (
    tester,
  ) async {
    await pumpTab(tester);

    expect(find.text('Disk almost full'), findsOneWidget);
    expect(find.text('/var is at 92%'), findsOneWidget);
    expect(find.text('threshold 80%'), findsOneWidget);
    expect(find.textContaining('Disk alarms'), findsOneWidget);
    expect(find.textContaining('prod-vps'), findsOneWidget);
    expect(find.text('maidCafeUnreadCount'.tr(args: ['1'])), findsOneWidget);
  });

  testWidgets('unread only hides rows that are already read', (tester) async {
    await pumpTab(
      tester,
      notifications: [
        _notification(),
        _notification(
          id: 'n2',
          kind: 'webhook.failure',
          title: 'Backup failed',
          subtitle: '',
          body: 'exit code 1',
          readAt: DateTime.utc(2026, 10, 2, 4),
        ),
      ],
      unreadCount: 1,
    );

    expect(find.text('Backup failed'), findsOneWidget);
    await tester.tap(find.text('maidCafeUnreadOnly'.tr()));
    await tester.pumpAndSettle();
    expect(find.text('Backup failed'), findsNothing);
    expect(find.text('Disk almost full'), findsOneWidget);
  });

  testWidgets('tapping an unread row marks it read', (tester) async {
    final fake = await pumpTab(tester);

    await tester.tap(find.text('Disk almost full'));
    await tester.pumpAndSettle();
    expect(fake.readIds, ['n1']);
  });

  testWidgets('mark all read targets the selected workspace', (tester) async {
    final fake = await pumpTab(tester);

    await tester.tap(find.text('maidCafeMarkAllRead'.tr()));
    await tester.pumpAndSettle();
    expect(fake.markedAllWorkspaceId, 'ws-1');
  });

  testWidgets('load older appends the page behind the oldest row', (
    tester,
  ) async {
    final first = [
      for (var i = 0; i < 100; i++)
        _notification(
          id: 'n$i',
          title: 'Alert $i',
          createdAt: DateTime.utc(2026, 10, 2).subtract(Duration(minutes: i)),
        ),
    ];
    final fake = _FakeMaidCafeService()
      ..olderPage = [_notification(id: 'old-1', title: 'Ancient alert')];
    await pumpTab(tester, notifications: first, service: fake);

    expect(find.text('Ancient alert'), findsNothing);
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('maidcafe-notifications-load-older')),
      find.byType(CustomScrollView),
      const Offset(0, -400),
    );
    await tester.tap(
      find.byKey(const ValueKey('maidcafe-notifications-load-older')),
    );
    await tester.pumpAndSettle();

    expect(fake.listCalls, 1);
    expect(fake.lastLimit, 100);
    expect(fake.lastBefore, first.last.createdAt);
    expect(find.text('Ancient alert'), findsOneWidget);
    // A short page means the history ended, so the button goes away.
    expect(
      find.byKey(const ValueKey('maidcafe-notifications-load-older')),
      findsNothing,
    );

    // Switching workspaces must not carry the other feed's tail along.
    await pumpTab(
      tester,
      workspaceId: 'ws-2',
      notifications: [_notification(id: 'other', title: 'Other feed')],
      service: fake,
    );
    expect(find.text('Ancient alert'), findsNothing);
    expect(find.text('Other feed'), findsOneWidget);
  });

  testWidgets('refresh keeps the last page visible while it reloads', (
    tester,
  ) async {
    var fetches = 0;
    await pumpTab(
      tester,
      loader: () async {
        fetches++;
        return [_notification()];
      },
    );
    expect(fetches, 1);

    await tester.tap(
      find.byKey(const ValueKey('maidcafe-notifications-refresh')),
    );
    await tester.pump();
    // skipLoadingOnRefresh keeps the row instead of flashing the skeleton.
    expect(find.text('Disk almost full'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(fetches, 2);
    expect(find.text('Disk almost full'), findsOneWidget);
  });

  testWidgets('empty feed explains there is nothing to show', (tester) async {
    await pumpTab(tester, notifications: const [], unreadCount: 0);

    expect(find.text('maidCafeNoNotifications'.tr()), findsOneWidget);
    expect(find.text('maidCafeMarkAllRead'.tr()), findsNothing);
  });

  testWidgets('pull to refresh refetches the feed', (tester) async {
    var fetches = 0;
    await pumpTab(
      tester,
      loader: () async {
        fetches++;
        return [_notification()];
      },
    );

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 320),
      1000,
    );
    await tester.pumpAndSettle();
    expect(fetches, greaterThan(1));
  });
}
