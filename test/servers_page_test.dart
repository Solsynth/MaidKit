import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/servers/servers_page.dart';
import 'package:maid_kit/servers/tailscale_settings_section.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        useFallbackTranslations: true,
        child: ProviderScope(
          overrides: [
            tailscaleSnapshotProvider.overrideWith((ref) => Stream.value(null)),
          ],
          child: const MaterialApp(
            home: Scaffold(body: ServerEditorDialog(credentials: [])),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('new server hides serial connection option', (tester) async {
    await pumpEditor(tester);

    expect(find.text('serverConnectionSerial'.tr()), findsNothing);
  });

  testWidgets('accepts whitespace-only SSH passwords', (tester) async {
    await pumpEditor(tester);

    final password = find.byType(TextFormField).last;
    await tester.enterText(password, '     ');
    await tester.tap(find.text('commonSave'.tr()));
    await tester.pumpAndSettle();

    expect(find.byType(ServerEditorDialog), findsNothing);
  });

  testWidgets('advanced server sections start collapsed', (tester) async {
    await pumpEditor(tester);

    for (final key in [
      'serverProxyLabel',
      'serverEnvironmentLabel',
      'serverInitialSnippetsLabel',
      'serverTagsLabel',
    ]) {
      final label = find.text(key.tr());
      await tester.scrollUntilVisible(
        label,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      final tile = find.ancestor(
        of: label,
        matching: find.byType(ExpansionTile),
      );
      expect(tile, findsOneWidget);
      expect(tester.widget<ExpansionTile>(tile).initiallyExpanded, isFalse);
    }
  });
}
