// The picker a plain "open terminal" goes through when the host already holds
// sessions the user started: it lists them next to a fresh-terminal row, and
// the row the user taps is the session that gets attached.
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/tmux_sessions.dart';
import 'package:maid_kit/servers/tmux_sessions_sheet.dart';

const _server = Server(
  id: 7,
  name: 'build host',
  host: 'build.example',
  port: 22,
  username: 'deploy',
  collectStats: false,
  collectSystemInfo: false,
  connectionType: 'ssh',
  maidCafeTerminalViaCloud: false,
);

Widget _harness(
  String? Function(String?) onChosen,
  List<TmuxSessionInfo> sessions,
) {
  return EasyLocalization(
    supportedLocales: const [Locale('en', 'US')],
    path: 'assets/translations',
    fallbackLocale: const Locale('en', 'US'),
    child: MaterialApp(
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', 'US')],
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                final chosen = await showTmuxAttachPicker(
                  context,
                  _server,
                  defaultName: 'maidkit-build-host',
                  sessions: sessions,
                );
                onChosen(chosen);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

TmuxSessionInfo _session(String name, {int windows = 1, int attached = 0}) =>
    TmuxSessionInfo(
      name: name,
      windows: windows,
      createdAt: DateTime.utc(2026),
      attached: attached,
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  testWidgets('a user session can be picked instead of a new terminal', (
    tester,
  ) async {
    String? chosen = 'unset';
    await tester.pumpWidget(
      _harness((value) => chosen = value, [
        _session('work', windows: 2, attached: 1),
      ]),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('work'), findsOneWidget);
    expect(find.text('2 · 1'), findsOneWidget);
    // The new-terminal row names the session it would create, so the choice is
    // between two real things rather than between "existing" and "vague".
    expect(find.text('maidkit-build-host'), findsOneWidget);

    await tester.tap(find.text('work'));
    await tester.pumpAndSettle();
    expect(chosen, 'work');
  });

  testWidgets('the new-terminal row starts a fresh session', (tester) async {
    String? chosen = 'unset';
    await tester.pumpWidget(
      _harness((value) => chosen = value, [_session('work')]),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('sessionsTmuxAttachNew'));
    await tester.pumpAndSettle();
    // Empty means "nothing was picked": the caller keeps its own default name.
    expect(chosen, '');
  });

  testWidgets('dismissing the sheet opens nothing', (tester) async {
    String? chosen = 'unset';
    await tester.pumpWidget(
      _harness((value) => chosen = value, [_session('work')]),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(chosen, isNull);
  });
}
