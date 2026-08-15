import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart' as ez;
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart' as ez_tr;
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/routing/app_router.dart';
import 'package:maid_kit/servers/port_forwarding_models.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/snippets/snippet_repository.dart';
import 'package:maid_kit/theme.dart';

/// Navigation rail button state: settings icon fill on selection and
/// port-forward indicator sizing.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
    // Drift's driftDatabase() asks path_provider for a temp dir.
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return Directory.systemTemp.path;
        });
    // The EasyLocalization widget's asset load never completes under
    // FakeAsync, so prime the singleton with real en-US translations.
    // Otherwise `.plural()` throws on `_locale`.
    final enMap =
        jsonDecode(File('assets/translations/en-US.json').readAsStringSync())
            as Map<String, dynamic>;
    ez.Localization.load(
      const Locale('en', 'US'),
      translations: ez_tr.Translations(enMap),
      ignorePluralRules: false,
    );
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
            scriptSnippetsProvider.overrideWith(
              (ref) => Stream.value(<ScriptSnippet>[]),
            ),
            cloudUserProvider.overrideWith((ref) => Future.value(null)),
            biometricUnlockEnabledProvider.overrideWith(
              (ref) => Future.value(false),
            ),
            portForwardsProvider.overrideWith(
              (ref) => Stream.value([
                ActivePortForward(
                  id: 'f1',
                  serverId: 1,
                  serverName: 'test-server',
                  direction: PortForwardDirection.local,
                  kind: PortForwardKind.tcp,
                  bindHost: '127.0.0.1',
                  bindPort: 8080,
                  targetHost: 'example.com',
                  targetPort: 80,
                ),
              ]),
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

  Finder settingsIcon() => find.descendant(
    of: find.byTooltip('tabSettings'.tr()),
    matching: find.byType(Icon),
  );

  testWidgets('rail settings icon fills only while the settings tab is open', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(tester.widget<Icon>(settingsIcon()).fill, 0);

    await tester.tap(find.byTooltip('settingsAccount'.tr()));
    await tester.pumpAndSettle();
    expect(tester.widget<Icon>(settingsIcon()).fill, 1);

    await tester.tap(find.byIcon(Symbols.dns));
    await tester.pumpAndSettle();
    expect(tester.widget<Icon>(settingsIcon()).fill, 0);
  });

  testWidgets('rail gear opens the quick settings sheet', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('tabSettings'.tr()));
    await tester.pumpAndSettle();

    expect(find.byType(SheetScaffold), findsOneWidget);
    expect(find.text('openAllSettings'.tr()), findsOneWidget);

    // Theme control updates the app theme mode.
    final segmented = tester.widget<SegmentedButton<ThemeMode>>(
      find.byType(SegmentedButton<ThemeMode>),
    );
    expect(segmented.selected, isNot({ThemeMode.dark}));
    await tester.tap(find.text('settingsThemeDark'.tr()));
    await tester.pumpAndSettle();
    final after = tester.widget<SegmentedButton<ThemeMode>>(
      find.byType(SegmentedButton<ThemeMode>),
    );
    expect(after.selected, {ThemeMode.dark});

    // "Open all settings" pops the sheet and lands on the settings tab.
    await tester.tap(find.text('openAllSettings'.tr()));
    await tester.pumpAndSettle();
    expect(find.byType(SheetScaffold), findsNothing);
    expect(tester.widget<Icon>(settingsIcon()).fill, 1);
  });

  testWidgets('port-forward rail button matches the settings button size', (
    tester,
  ) async {
    await pumpApp(tester);

    final settingsBox = tester.getSize(find.byTooltip('tabSettings'.tr()));
    final forwardBox = tester.getSize(
      find.byType(PopupMenuButton<ActivePortForward>),
    );
    expect(forwardBox, settingsBox);
    expect(forwardBox, const Size(40, 40));

    // Badge shows the active count next to the button.
    expect(find.text('1'), findsOneWidget);
  });
}
