import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/servers/server_connection_actions.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  /// Pumps a page whose button opens the account picker, and returns a way to
  /// read what the picker produced once it closes.
  Future<String? Function()> pumpPicker(
    WidgetTester tester, {
    required List<String> accounts,
    String? current,
  }) async {
    String? chosen;
    var closed = false;
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        useFallbackTranslations: true,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    chosen = await chooseMaidCafeTerminalUser(
                      context,
                      accounts: accounts,
                      current: current,
                    );
                    closed = true;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () {
      expect(closed, isTrue, reason: 'the picker never returned');
      return chosen;
    };
  }

  testWidgets('offers the daemon account and every allowlisted one', (
    tester,
  ) async {
    final result = await pumpPicker(
      tester,
      accounts: const ['deploy', 'nginx'],
    );

    expect(
      find.text('serverMaidCafeTerminalUserDaemonAccount'.tr()),
      findsOneWidget,
    );
    expect(find.text('deploy'), findsOneWidget);
    expect(find.text('nginx'), findsOneWidget);

    await tester.tap(find.text('deploy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('commonOpen'.tr()));
    await tester.pumpAndSettle();
    expect(result(), 'deploy');
  });

  testWidgets('the daemon account is a choice of its own', (tester) async {
    final result = await pumpPicker(tester, accounts: const ['deploy']);

    await tester.tap(find.text('serverMaidCafeTerminalUserDaemonAccount'.tr()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('commonOpen'.tr()));
    await tester.pumpAndSettle();
    // The empty string is the daemon's own account — the value the daemon
    // reads when no account is requested.
    expect(result(), '');
  });

  testWidgets('opening without touching the radio keeps the stored account', (
    tester,
  ) async {
    final result = await pumpPicker(
      tester,
      accounts: const ['deploy', 'nginx'],
      current: 'nginx',
    );

    await tester.tap(find.text('commonOpen'.tr()));
    await tester.pumpAndSettle();
    expect(result(), 'nginx');
  });

  testWidgets('an account the daemon no longer lists is not preselected', (
    tester,
  ) async {
    final result = await pumpPicker(
      tester,
      accounts: const ['deploy'],
      current: 'removed-user',
    );

    await tester.tap(find.text('commonOpen'.tr()));
    await tester.pumpAndSettle();
    expect(result(), '');
  });

  testWidgets('dismissing the sheet chooses nothing', (tester) async {
    final result = await pumpPicker(tester, accounts: const ['deploy']);

    await tester.tap(find.text('commonCancel'.tr()));
    await tester.pumpAndSettle();
    expect(result(), isNull);
  });
}
