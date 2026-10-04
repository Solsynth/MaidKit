import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/servers/maidcafe_metoer.dart';
import 'package:maid_kit/servers/notifications_modal.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/theme.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  Future<void> pumpModal(
    WidgetTester tester, {
    required Future<List<MaidCafeMetoerNotification>> Function() load,
    int unread = 0,
  }) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        useFallbackTranslations: true,
        child: ProviderScope(
          overrides: [
            maidCafeMetoerNotificationsProvider.overrideWith((ref) => load()),
            maidCafeMetoerUnreadCountProvider.overrideWith(
              (ref) async => unread,
            ),
          ],
          child: MaterialApp(
            theme: createMaidKitTheme(Brightness.light),
            home: Scaffold(body: NotificationModal(onDismiss: () {})),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpBell(WidgetTester tester, {required int unread}) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        useFallbackTranslations: true,
        child: ProviderScope(
          overrides: [
            maidCafeMetoerUnreadCountProvider.overrideWith(
              (ref) async => unread,
            ),
          ],
          child: MaterialApp(
            theme: createMaidKitTheme(Brightness.light),
            home: const Scaffold(body: NotificationsBellButton()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  MaidCafeMetoerNotification notification({
    required String id,
    required String topic,
    required Duration age,
    String? title,
    String subtitle = '',
    String body = '',
    bool unread = true,
    Map<String, dynamic> meta = const {},
  }) => MaidCafeMetoerNotification(
    id: id,
    topic: topic,
    title: title,
    subtitle: subtitle,
    body: body,
    meta: meta,
    createdAt: DateTime.now().subtract(age),
    viewedAt: unread ? null : DateTime.now(),
  );

  testWidgets('the feed lists one row per notification with its age', (
    tester,
  ) async {
    await pumpModal(
      tester,
      load: () async => [
        notification(
          id: 'n1',
          topic: 'daemon.alarm.disk_used_percent',
          age: const Duration(minutes: 2),
          title: 'Disk almost full',
          subtitle: 'host-1',
          body: 'Disk /var is 91% full.',
        ),
        notification(
          id: 'n2',
          topic: 'daemon.reconnect',
          age: const Duration(hours: 3),
          unread: false,
        ),
      ],
    );

    expect(find.text('Disk almost full'), findsOneWidget);
    expect(find.text('host-1'), findsOneWidget);
    expect(find.text('Disk /var is 91% full.'), findsOneWidget);
    expect(find.text('agentMinutesAgo'.tr(args: ['2'])), findsOneWidget);
    expect(find.text('agentHoursAgo'.tr(args: ['3'])), findsOneWidget);
    // A notification the cloud sent without a title is named by its topic.
    expect(find.text('Daemon Reconnect'), findsOneWidget);
    // The topic icons, including the title fallback, key off the topic.
    expect(find.byIcon(Symbols.notification_important), findsOneWidget);
    expect(find.byIcon(Symbols.cloud_done), findsOneWidget);
    // No untranslated placeholder survives into the rows.
    expect(find.textContaining('{'), findsNothing);
  });

  testWidgets('an empty feed says so instead of showing an error', (
    tester,
  ) async {
    await pumpModal(tester, load: () async => const []);

    expect(find.text('maidCafeNoNotifications'.tr()), findsOneWidget);
    expect(find.text('maidCafeRetry'.tr()), findsNothing);
  });

  testWidgets('a failed fetch shows the transport message and retries', (
    tester,
  ) async {
    var attempts = 0;
    await pumpModal(
      tester,
      load: () async {
        attempts++;
        throw const MaidCafeMetoerException('Could not reach Metoer.');
      },
    );

    expect(find.text('Could not reach Metoer.'), findsOneWidget);
    final before = attempts;

    await tester.tap(find.text('maidCafeRetry'.tr()));
    await tester.pumpAndSettle();

    expect(attempts, greaterThan(before));
    expect(
      find.text('Could not reach Metoer.'),
      findsOneWidget,
      reason: 'the retry failed too, so the modal keeps reporting it',
    );
  });

  testWidgets('the bell carries the unread count', (tester) async {
    await pumpBell(tester, unread: 3);

    expect(
      find.byTooltip('maidCafeUnreadCount'.tr(args: ['3'])),
      findsOneWidget,
    );
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('the bell hides its badge when nothing is unread', (
    tester,
  ) async {
    await pumpBell(tester, unread: 0);

    expect(find.byTooltip('maidCafeNotifications'.tr()), findsOneWidget);
    expect(find.byType(Badge), findsOneWidget);
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
  });
}
