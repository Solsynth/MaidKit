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
import 'package:maid_kit/servers/tabs_screen.dart';
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
      find.byKey(const ValueKey('command-palette-search')),
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

  testWidgets('the command palette splits a tab into a second, empty pane', (
    tester,
  ) async {
    await pumpWorkspace(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SessionsWorkspace)),
    );

    // The dashboard tab is the workspace floor and does not split, so the
    // split entry only appears on a content tab.
    await openPalette(tester, query: 'split');
    expect(
      find.widgetWithText(ListTile, 'sessionsSplitDown'.tr()),
      findsNothing,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('command-palette-search')), findsNothing);
    expect(container.read(terminalTabsProvider).tabs.single.hasSplits, isFalse);

    await openPalette(tester, query: 'conn');
    await tester.tap(find.widgetWithText(ListTile, 'assetsConnections'.tr()));
    await tester.pumpAndSettle();
    final before = container.read(terminalTabsProvider);
    expect(before.tabs.last.hasSplits, isFalse);

    await openPalette(tester, query: 'split');
    final splitDown = find.widgetWithText(ListTile, 'sessionsSplitDown'.tr());
    expect(splitDown, findsOneWidget);
    await tester.tap(splitDown);
    await tester.pumpAndSettle();

    // The split belongs to the tab the user was on: the workspace still lists
    // the dashboard and the assets tab, the latter with two panes, and the new
    // pane waits on the launcher for a choice.
    final after = container.read(terminalTabsProvider);
    expect(after.tabs, hasLength(2));
    final split = after.tabs.last;
    expect(split.hasSplits, isTrue);
    expect(split.panes, hasLength(2));
    expect(split.panes[split.focusedPaneId]!.isEmpty, isTrue);
    expect(after.selectedTabId, split.id);
  });

  testWidgets('the palette is driven from the keyboard and grouped by target', (
    tester,
  ) async {
    await pumpWorkspace(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SessionsWorkspace)),
    );
    container.read(terminalTabsProvider.notifier).openSettings();
    await tester.pumpAndSettle();

    await openPalette(tester);
    // Untitled sections give the unfiltered list its shape.
    expect(find.text('sessionsPaletteGroupTab'.tr()), findsOneWidget);
    expect(find.text('sessionsPaletteGroupWorkspace'.tr()), findsOneWidget);
    // The first row is highlighted, so a bare Enter runs it.
    expect(
      tester.widget<ListTile>(find.byType(ListTile).last).selected,
      isNot(true),
    );

    await tester.enterText(
      find.byKey(const ValueKey('command-palette-search')),
      'split',
    );
    await tester.pumpAndSettle();
    // Filtering drops the headings: the matches read as one ranked list.
    expect(find.text('sessionsPaletteGroupTab'.tr()), findsNothing);

    // ↑↓ move the highlight; Enter runs whatever it is on.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ListTile>(
            find.widgetWithText(ListTile, 'sessionsSplitDown'.tr()),
          )
          .selected,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final split = container.read(terminalTabsProvider).selectedTab!;
    expect(split.hasSplits, isTrue);
    expect(split.panes[split.focusedPaneId]!.isEmpty, isTrue);
  });
}
