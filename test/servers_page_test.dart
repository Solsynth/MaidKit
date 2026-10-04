import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/servers/server_models.dart';
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

  testWidgets('a daemon server reopens and saves its terminal user', (
    tester,
  ) async {
    // A tall surface so the daemon section is laid out and the save button is
    // reachable without scrolling.
    await tester.binding.setSurfaceSize(const Size(1200, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    ServerDraft? saved;
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
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async {
                      saved = await showModalBottomSheet<ServerDraft>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        builder: (_) => const ServerEditorDialog(
                          credentials: [],
                          initial: ServerDraft(
                            name: 'Daemon host',
                            host: 'daemon.local',
                            port: 8747,
                            username: '',
                            connectionType: ServerConnectionType.maidcafe,
                            maidCafeTerminalUrl: 'https://daemon.example',
                            maidCafeTerminalUser: 'deploy',
                          ),
                        ),
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The stored account reopens in the daemon section's field.
    final field = find.ancestor(
      of: find.text('serverMaidCafeTerminalUserLabel'.tr()),
      matching: find.byType(TextFormField),
    );
    expect(field, findsOneWidget);
    expect(find.text('deploy'), findsOneWidget);

    await tester.enterText(field, 'nginx');
    // The form is a lazy list: the save button is below the fold.
    final saveButton = find.text('serverSaveAndConnect'.tr());
    await tester.scrollUntilVisible(
      saveButton,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(saved?.maidCafeTerminalUser, 'nginx');
    expect(saved?.connectionType, ServerConnectionType.maidcafe);
  });
}
