import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/snippets/snippet_confirmation.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  final now = DateTime.utc(2026, 1, 1);

  ScriptSnippet snippet({required bool dangerous}) => ScriptSnippet(
    id: 1,
    name: 'Nuke',
    script: 'rm -rf /',
    excludedFromAutocomplete: false,
    dangerous: dangerous,
    createdAt: now,
    updatedAt: now,
  );

  /// Mounts a button that resolves [confirmDangerousSnippet] on tap.
  Future<void> pumpRunner(
    WidgetTester tester,
    Future<void> Function(BuildContext) onPressed,
  ) async {
    final overlayKey = GlobalKey<OverlayState>();
    IslandUIFoundation.configureOverlay(overlayKey);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        useFallbackTranslations: true,
        child: MaterialApp(
          home: Overlay(
            key: overlayKey,
            initialEntries: [
              OverlayEntry(
                builder: (context) => Center(
                  child: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => onPressed(context),
                      child: const Text('go'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('safe snippets run without a prompt', (tester) async {
    bool? result;
    await pumpRunner(tester, (context) async {
      result = await confirmDangerousSnippet(
        context,
        snippet(dangerous: false),
      );
    });

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('dangerous snippets need both confirmations', (tester) async {
    bool? result;
    await pumpRunner(tester, (context) async {
      result = await confirmDangerousSnippet(context, snippet(dangerous: true));
    });

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('snippetsDangerousTitle'.tr()), findsOneWidget);
    // The snippet cannot run before the second prompt is answered.
    expect(result, isNull);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(
      find.text('snippetsDangerousAgain'.tr(args: ['Nuke'])),
      findsOneWidget,
    );
    expect(result, isNull);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('declining the first prompt cancels the run', (tester) async {
    bool? result;
    await pumpRunner(tester, (context) async {
      result = await confirmDangerousSnippet(context, snippet(dangerous: true));
    });

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('declining the second prompt cancels the run', (tester) async {
    bool? result;
    await pumpRunner(tester, (context) async {
      result = await confirmDangerousSnippet(context, snippet(dangerous: true));
    });

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });
}
