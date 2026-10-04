import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:maid_kit/containers/project_detail_page.dart';
import 'package:maid_kit/containers/project_repository.dart';
import 'package:maid_kit/containers/projects_page.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/sessions_page.dart';
import 'package:maid_kit/servers/terminal_tabs_provider.dart';
import 'package:maid_kit/theme.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  /// Pumps the pane workspace with one demo project.
  ///
  /// 1280px keeps the project grid tiles wide enough that the untranslated
  /// .tr() keys widget tests render (translations never load under
  /// flutter_test) fit without overflowing the card rows.
  Future<ProviderContainer> pumpWorkspace(WidgetTester tester) async {
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

    final container = ProviderContainer(
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
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: createMaidKitTheme(Brightness.light),
            locale: const Locale('en', 'US'),
            supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const SessionsWorkspace(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  /// Cancels the workspace's snapshot timers before the test ends: the widget
  /// tree is disposed first, then the container the workspace state lives in.
  Future<void> disposeWorkspace(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  }

  testWidgets(
    'a pushed detail stays inside its own pane tab and survives tab switches',
    (WidgetTester tester) async {
      final container = await pumpWorkspace(tester);
      final notifier = container.read(terminalTabsProvider.notifier);

      // Open the Projects destination tab and push its project detail.
      notifier.openProjects();
      await tester.pumpAndSettle();
      expect(find.text('Demo Project'), findsOneWidget);

      await tester.tap(find.text('Demo Project'));
      await tester.pumpAndSettle();

      // The detail is showing inside the Projects tab, which is still a tab
      // in the strip rather than a route that swallowed the workspace.
      expect(find.text('deploymentResourcesTitle'.tr()), findsOneWidget);
      expect(
        find.byType(ProjectDetailPage, skipOffstage: false),
        findsOneWidget,
      );
      expect(find.byType(ProjectsPage, skipOffstage: false), findsOneWidget);
      expect(find.text('tabProjects'.tr()), findsOneWidget);

      // Switch to the dashboard and back: the pushed detail is still open
      // instead of resetting to the project list.
      notifier.openDashboard();
      await tester.pumpAndSettle();
      notifier.openProjects();
      await tester.pumpAndSettle();
      expect(find.text('deploymentResourcesTitle'.tr()), findsOneWidget);

      // Popping the nested detail returns to the projects list.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('deploymentResourcesTitle'.tr()), findsNothing);
      expect(find.text('Demo Project'), findsOneWidget);

      await disposeWorkspace(tester, container);
    },
  );
}
