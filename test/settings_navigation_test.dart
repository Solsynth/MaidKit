import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/routing/app_router.dart';
import 'package:maid_kit/servers/cloud_sync_service.dart';
import 'package:maid_kit/servers/maidcafe_cloud_page.dart';
import 'package:maid_kit/servers/maidcafe_metoer.dart';
import 'package:maid_kit/servers/maidcafe_service.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/snippets/snippet_repository.dart';
import 'package:maid_kit/theme.dart';
import 'package:maid_kit/servers/maidcafe_server_tab.dart';
import 'package:solsynth_express/solsynth_express.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    Size size = const Size(1200, 800),
    bool settle = true,
  }) async {
    final router = AppRouter();
    addTearDown(router.dispose);

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: ProviderScope(
          overrides: [
            serversProvider.overrideWith((ref) => Stream.value(<Server>[])),
            savedCredentialsProvider.overrideWith(
              (ref) => Stream.value(<SavedCredential>[]),
            ),
            scriptSnippetsProvider.overrideWith(
              (ref) => Stream.value(<ScriptSnippet>[]),
            ),
            cloudUserProvider.overrideWith((ref) => Future.value(null)),
            cloudWorkspacesProvider.overrideWith(
              (ref) => Future.value(const <CloudWorkspace>[]),
            ),
            maidCafeMetoerNotificationsProvider.overrideWith(
              (ref) => Future.value(const <MaidCafeMetoerNotification>[]),
            ),
            maidCafeMetoerUnreadCountProvider.overrideWith(
              (ref) => Future.value(0),
            ),
            maidCafeCredentialsProvider.overrideWith(
              (ref) => Future.value(const <MaidCafeCredential>[]),
            ),
            biometricUnlockEnabledProvider.overrideWith(
              (ref) => Future.value(false),
            ),
          ],
          child: MaterialApp.router(
            theme: createMaidKitTheme(Brightness.light),
            locale: const Locale('en', 'US'),
            supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            routerConfig: router.config(),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  testWidgets('opens Settings from the desktop navigation rail', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('tabSettings'.tr()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('settingsTerminal'.tr()).first);
    await tester.pumpAndSettle();
    expect(find.text('settingsTerminalRenderer'.tr()), findsOneWidget);

    await tester.tap(find.text('settingsAbout'.tr()).first);
    await tester.pumpAndSettle();
    expect(find.text('settingsAbout'.tr()), findsWidgets);
  });

  testWidgets('uses category tabs on mobile settings', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester, size: const Size(390, 844));

    await tester.tap(find.byIcon(Symbols.settings).last);
    await tester.pumpAndSettle();

    expect(find.byType(TabBar), findsOneWidget);
    final terminalTab = find.text('settingsTerminal'.tr()).first;
    await tester.ensureVisible(terminalTab);
    await tester.tap(terminalTab);
    await tester.pumpAndSettle();
    expect(find.text('settingsTerminalRenderer'.tr()), findsOneWidget);
  });

  testWidgets('opens Assets from the desktop navigation rail', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Symbols.inventory_2));
    await tester.pumpAndSettle();

    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('assetsConnections'.tr()), findsOneWidget);
    expect(find.text('tabGithub'.tr()), findsOneWidget);
    expect(find.text('assetsCredentialsTitle'.tr()), findsOneWidget);
    expect(find.text('tabSnippets'.tr()), findsOneWidget);

    expect(find.text('assetsConnectionsDescription'.tr()), findsOneWidget);

    await tester.tap(find.text('assetsCredentialsTitle'.tr()));
    await tester.pumpAndSettle();
    expect(find.text('assetsConnectionsDescription'.tr()), findsNothing);
    expect(find.text('assetsCredentialsDescription'.tr()), findsOneWidget);

    await tester.tap(find.text('assetsConnections'.tr()));
    await tester.pumpAndSettle();
    expect(find.text('assetsConnectionsDescription'.tr()), findsOneWidget);
  });
  testWidgets('opens MaidCafe Cloud from the profile rail button', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('maidCafeCloudTitle'.tr()));
    await tester.pumpAndSettle();

    expect(find.byType(MaidCafeCloudPage), findsOneWidget);
  });
  testWidgets('opens MaidCafe Cloud from the mobile dashboard navigation', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester, size: const Size(390, 844));

    await tester.tap(find.byIcon(Symbols.cloud));
    await tester.pumpAndSettle();

    expect(find.byType(MaidCafeCloudPage), findsOneWidget);
  });

  testWidgets(
    'MaidCafe cloud connection lives in Settings with a self-hosted push hint',
    (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byTooltip('tabSettings'.tr()));
      await tester.pumpAndSettle();

      final solarCategory = find.text('settingsSolarNetwork'.tr());
      await tester.ensureVisible(solarCategory);
      await tester.tap(solarCategory);
      await tester.pumpAndSettle();

      expect(find.text('maidCafeCloudUrl'.tr()), findsOneWidget);
      // The default cloud (mk.solsynth.dev) is a supported Ring publisher.
      expect(find.text('maidCafeSelfHostedPushHint'.tr()), findsNothing);

      await tester.enterText(
        find.widgetWithText(TextField, 'maidCafeCloudUrl'.tr()),
        'https://cloud.local:8080',
      );
      await tester.tap(find.text('maidCafeApply'.tr()));
      await tester.pumpAndSettle();

      expect(find.text('maidCafeSelfHostedPushHint'.tr()), findsOneWidget);
    },
  );
  testWidgets('hides MaidCafe Cloud from Assets on mobile', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester, size: const Size(500, 800), settle: false);

    await tester.tap(find.byIcon(Symbols.inventory_2));
    await tester.pumpAndSettle();

    expect(find.text('assetsConnections'.tr()), findsOneWidget);
    expect(find.text('maidCafeTitle'.tr()), findsNothing);
  });

  testWidgets('shows the MaidCafe label and installer in a server detail tab', (
    WidgetTester tester,
  ) async {
    final server = Server(
      id: 1,
      name: 'Build host',
      host: 'build.example',
      port: 22,
      username: 'builder',
      collectStats: true,
      collectSystemInfo: true,
      connectionType: 'ssh',
      maidCafeDaemonUrl: 'http://127.0.0.1:8747',
    );
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: ProviderScope(
          child: MaterialApp(
            theme: createMaidKitTheme(Brightness.light),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: MaidCafeServerTab(
              server: server,
              connected: true,
              connectionError: null,
              onConnect: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('maidCafeTitle'.tr()), findsOneWidget);
    expect(find.text('maidCafeInstallApplication'.tr()), findsOneWidget);
    expect(find.text('maidCafeActions'.tr()), findsNothing);
    expect(find.text('maidCafeServerConfigTitle'.tr()), findsNothing);
    expect(find.text('maidCafeServerDaemonUrl'.tr()), findsNothing);
  });
  testWidgets('channel picker lays out inside a dialog', (
    WidgetTester tester,
  ) async {
    final channel = DistributionChannel(
      id: 'rolling-id',
      name: 'rolling',
      displayName: 'Rolling',
      displayNames: const {},
      description: 'Nightly builds',
      descriptions: const {},
      latest: null,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: createMaidKitTheme(Brightness.light),
        home: Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: MaidCafeInstallChannelPicker(
                channels: [channel],
                selected: null,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('rolling'), findsOneWidget);
  });
}
