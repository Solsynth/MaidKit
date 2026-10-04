import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart' as ez;
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart' as ez_tr;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/assets_page.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/sessions_page.dart';
import 'package:maid_kit/servers/ssh_connection_manager.dart';
import 'package:maid_kit/servers/terminal_tabs_provider.dart';
import 'package:maid_kit/snippets/snippet_repository.dart';
import 'package:maid_kit/theme.dart';

class _RecordingConnectionManager extends SshConnectionManager {
  _RecordingConnectionManager() : super(() => throw UnimplementedError());
}

/// The workspace launcher: the pane tab strip's session-actions palette is the
/// only way to open a destination now, so it has to list every page a
/// destination owns — including each page of the assets tab.
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
    // Prime the singleton with real en-US translations so `.plural()` works.
    final enMap =
        jsonDecode(File('assets/translations/en-US.json').readAsStringSync())
            as Map<String, dynamic>;
    ez.Localization.load(
      const Locale('en', 'US'),
      translations: ez_tr.Translations(enMap),
      ignorePluralRules: false,
    );
  });

  Future<void> pumpWorkspace(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // The palette renders through IslandUIFoundation's overlay, so the test
    // installs the key the app installs at startup.
    final overlayKey = GlobalKey<OverlayState>();
    IslandUIFoundation.configureOverlay(overlayKey);

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
            biometricUnlockEnabledProvider.overrideWith(
              (ref) => Future.value(false),
            ),
            connectionManagerProvider.overrideWithValue(
              _RecordingConnectionManager(),
            ),
            cloudUserProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            theme: createMaidKitTheme(Brightness.light),
            locale: const Locale('en', 'US'),
            home: Overlay(
              key: overlayKey,
              initialEntries: [
                OverlayEntry(
                  builder: (context) =>
                      const Scaffold(body: SessionsWorkspace()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openPalette(WidgetTester tester, {String? query}) async {
    await tester.tap(find.byTooltip('sessionsSessionActions'.tr()));
    await tester.pumpAndSettle();
    if (query == null) return;
    // The palette list is short and scrollable, so entries are reached the way
    // a user reaches them: by typing.
    await tester.enterText(
      find.descendant(
        of: find.byType(SearchBar),
        matching: find.byType(TextField),
      ),
      query,
    );
    await tester.pumpAndSettle();
  }

  int assetsSection(WidgetTester tester) =>
      tester.widget<TabBar>(find.byType(TabBar)).controller!.index;

  testWidgets('the palette opens the assets page on any of its pages', (
    tester,
  ) async {
    await pumpWorkspace(tester);

    // The palette is searchable; each assets page is reachable by name.
    await openPalette(tester, query: 'connect');
    final assetsConnectionsEntry = find.widgetWithText(
      ListTile,
      'assetsConnections'.tr(),
    );
    expect(assetsConnectionsEntry, findsOneWidget);
    await tester.tap(assetsConnectionsEntry);
    await tester.pumpAndSettle();
    expect(find.byType(AssetsPage), findsOneWidget);
    expect(assetsSection(tester), AssetsSection.connections.index);

    // Re-opening the already open tab on another page switches to it instead
    // of opening a second assets tab.
    await openPalette(tester, query: 'git');
    final tabGithubEntry = find.widgetWithText(ListTile, 'tabGithub'.tr());
    expect(tabGithubEntry, findsOneWidget);
    await tester.tap(tabGithubEntry);
    await tester.pumpAndSettle();

    expect(find.byType(AssetsPage), findsOneWidget);
    expect(assetsSection(tester), AssetsSection.github.index);

    await openPalette(tester, query: 'cred');
    final assetsCredentialsTitleEntry = find.widgetWithText(
      ListTile,
      'assetsCredentialsTitle'.tr(),
    );
    expect(assetsCredentialsTitleEntry, findsOneWidget);
    await tester.tap(assetsCredentialsTitleEntry);
    await tester.pumpAndSettle();

    expect(find.byType(AssetsPage), findsOneWidget);
    expect(assetsSection(tester), AssetsSection.credentials.index);

    await openPalette(tester, query: 'snip');
    final tabSnippetsEntry = find.widgetWithText(ListTile, 'tabSnippets'.tr());
    expect(tabSnippetsEntry, findsOneWidget);
    await tester.tap(tabSnippetsEntry);
    await tester.pumpAndSettle();

    expect(find.byType(AssetsPage), findsOneWidget);
    expect(assetsSection(tester), AssetsSection.snippets.index);
  });

  testWidgets('the command palette splits the focused pane', (tester) async {
    await pumpWorkspace(tester);
    expect(find.text('sessionsNewPane'.tr()), findsNothing);

    await openPalette(tester, query: 'split');
    final splitDown = find.widgetWithText(ListTile, 'sessionsSplitDown'.tr());
    expect(splitDown, findsOneWidget);
    await tester.tap(splitDown);
    await tester.pumpAndSettle();

    // The pane the split added has no tabs yet, so its strip says so.
    expect(find.text('sessionsNewPane'.tr()), findsOneWidget);
  });
}
