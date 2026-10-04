import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart' as ez;
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart' as ez_tr;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/sessions_page.dart';
import 'package:maid_kit/servers/terminal_tabs_provider.dart';
import 'package:maid_kit/snippets/snippet_repository.dart';
import 'package:maid_kit/theme.dart';

/// The pane tab strip keeps one title on a narrow pane — the tab the user is
/// on — and animates the titles in and out instead of snapping the layout.
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

  Future<void> pumpWorkspace(WidgetTester tester, Size windowSize) async {
    tester.view.physicalSize = windowSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
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
          ],
          child: MaterialApp(
            theme: createMaidKitTheme(Brightness.light),
            home: const Scaffold(body: SessionsWorkspace()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The strip's tab list. Pane tab bodies are keyed by tab id too, so a chip
  /// has to be matched inside the strip rather than by key alone.
  final strip = find.byWidgetPredicate(
    (widget) => widget is ListView && widget.scrollDirection == Axis.horizontal,
  );

  Finder chip(String tabId) =>
      find.descendant(of: strip, matching: find.byKey(ValueKey(tabId)));

  /// Width of the title area inside one chip: zero while the title is
  /// collapsed into its icon, the label's own width once it is expanded.
  double titleWidth(WidgetTester tester, String tabId) => tester
      .getSize(
        find.descendant(of: chip(tabId), matching: find.byType(ClipRect)),
      )
      .width;

  double labelWidth(WidgetTester tester, String tabId) => tester
      .getSize(find.descendant(of: chip(tabId), matching: find.byType(Text)))
      .width;

  Future<TerminalTabsNotifier> openTabs(
    WidgetTester tester,
    List<void Function(TerminalTabsNotifier)> open,
  ) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SessionsWorkspace)),
    );
    final notifier = container.read(terminalTabsProvider.notifier);
    for (final call in open) {
      call(notifier);
      await tester.pumpAndSettle();
    }
    return notifier;
  }

  testWidgets('a narrow pane draws the focused tab title only', (tester) async {
    await pumpWorkspace(tester, const Size(500, 800));
    // Pane tabs: dashboard, then assets, which the open focuses.
    await openTabs(tester, [(notifier) => notifier.openAssets()]);

    // Focused tab: title fully out (its label plus the gap before it).
    // Background tab: title collapsed to nothing.
    expect(
      titleWidth(tester, 'assets'),
      greaterThanOrEqualTo(labelWidth(tester, 'assets')),
    );
    expect(titleWidth(tester, 'dashboard'), 0);

    // A wide pane brings every title back, at full width.
    tester.view.physicalSize = const Size(1400, 900);
    await tester.pumpAndSettle();
    expect(
      titleWidth(tester, 'dashboard'),
      greaterThanOrEqualTo(labelWidth(tester, 'dashboard')),
    );
    expect(
      titleWidth(tester, 'assets'),
      greaterThanOrEqualTo(labelWidth(tester, 'assets')),
    );
  });

  testWidgets('a title expands out of its icon and collapses back', (
    tester,
  ) async {
    await pumpWorkspace(tester, const Size(500, 800));
    final notifier = await openTabs(tester, [
      (notifier) => notifier.openAssets(),
    ]);

    final collapsed = titleWidth(tester, 'dashboard');
    notifier.select(DashboardTab().id);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final midFlight = titleWidth(tester, 'dashboard');
    await tester.pumpAndSettle();
    final expanded = titleWidth(tester, 'dashboard');

    // Focus reveals the title over time rather than all at once.
    expect(midFlight, greaterThan(collapsed));
    expect(midFlight, lessThan(expanded));
  });
}
