import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/routing/app_router.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/theme.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  Future<void> pumpApp(WidgetTester tester) async {
    final router = AppRouter();
    addTearDown(router.dispose);

    tester.view.physicalSize = const Size(1200, 800);
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
    await tester.pumpAndSettle();
  }

  testWidgets('opens Settings from the desktop navigation rail', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    final settingsLabel = 'tabSettings'.tr();
    await tester.tap(find.byTooltip(settingsLabel));
    await tester.pumpAndSettle();

    expect(find.text('settingsTitle'.tr()), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('settingsTerminalRenderer'.tr()),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('settingsTerminalRenderer'.tr()), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('settingsAbout'.tr()),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('settingsAbout'.tr()), findsOneWidget);
  });

  testWidgets('opens Assets from the desktop navigation rail', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Symbols.inventory_2));
    await tester.pumpAndSettle();

    expect(find.text('assetsConnections'.tr()), findsOneWidget);
    expect(find.text('assetsCredentialsTitle'.tr()), findsOneWidget);
  });
}
