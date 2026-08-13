import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:maid_kit/containers/project_repository.dart';
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

    // 1280px keeps the project grid tiles wide enough that the untranslated
    // .tr() keys widget tests render (translations never load under
    // flutter_test) fit without overflowing the card rows.
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final project = DeploymentProject(
      id: 1,
      name: 'Demo Project',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final resource = DeploymentResource(
      id: 1,
      projectId: 1,
      kind: 'compose',
      name: 'web',
      configuration: '{}',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

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
            deploymentProjectsProvider.overrideWith(
              (ref) => Stream.value([project]),
            ),
            deploymentResourcesProvider.overrideWith(
              (ref) => Stream.value([resource]),
            ),
            composeProjectLinksProvider.overrideWith(
              (ref) => Stream.value(<ComposeProjectLink>[]),
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

  testWidgets(
    'detail pages stay inside their tab: rail stays switchable and the '
    'detail survives tab round-trips',
    (WidgetTester tester) async {
      await pumpApp(tester);

      final rail = find.byType(NavigationRail);
      Finder railIcon(IconData icon) =>
          find.descendant(of: rail, matching: find.byIcon(icon));

      // Open the Projects tab and its project detail.
      await tester.tap(railIcon(Symbols.deployed_code));
      await tester.pumpAndSettle();
      expect(find.text('Demo Project'), findsOneWidget);

      await tester.tap(find.text('Demo Project'));
      await tester.pumpAndSettle();

      // Detail page is showing and the tab rail is still on screen.
      expect(find.text('deploymentResourcesTitle'.tr()), findsOneWidget);
      expect(railIcon(Symbols.dns), findsOneWidget);

      // Switch to the Servers tab: detail is out of view.
      await tester.tap(railIcon(Symbols.dns));
      await tester.pumpAndSettle();
      expect(find.text('deploymentResourcesTitle'.tr()), findsNothing);

      // Switch back: the pushed detail is still open (not reset to the list).
      await tester.tap(railIcon(Symbols.deployed_code));
      await tester.pumpAndSettle();
      expect(find.text('deploymentResourcesTitle'.tr()), findsOneWidget);

      // Popping the nested detail returns to the projects list.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('deploymentResourcesTitle'.tr()), findsNothing);
      expect(find.text('Demo Project'), findsOneWidget);
    },
  );
}
