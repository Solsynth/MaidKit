import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:easy_localization/src/localization.dart' as ez;
import 'package:easy_localization/src/translations.dart' as ez_tr;
import 'package:flutter/material.dart' hide Theme;
import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/terminal_session_adapter.dart';
import 'package:maid_kit/servers/terminal_sudo_hint.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
    final enMap =
        jsonDecode(File('assets/translations/en-US.json').readAsStringSync())
            as Map<String, dynamic>;
    ez.Localization.load(
      const Locale('en', 'US'),
      translations: ez_tr.Translations(enMap),
      ignorePluralRules: false,
    );
  });

  Future<void> pumpHint(WidgetTester tester, _HintAdapter adapter) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: MaterialApp(
          home: Scaffold(
            body: TerminalSudoAutofillHint(
              adapter: adapter,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }

  group('TerminalSudoAutofillHint', () {
    testWidgets('shows the hint when autofill is ready', (tester) async {
      final adapter = _HintAdapter(SudoPromptReason.prompt);
      await pumpHint(tester, adapter);

      // initState reads the ready reason immediately.
      expect(find.text('Press Enter to fill saved password'), findsOneWidget);
    });

    testWidgets('hides the hint once the session no longer wants a password', (
      tester,
    ) async {
      final adapter = _HintAdapter(SudoPromptReason.prompt);
      await pumpHint(tester, adapter);
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Press Enter to fill saved password'), findsOneWidget);

      adapter.reason = null;
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Press Enter to fill saved password'), findsNothing);
    });
  });
}

/// Test adapter with a mutable ready reason and a fixed cursor rect.
class _HintAdapter implements TerminalSessionAdapter {
  _HintAdapter(this.reason);

  SudoPromptReason? reason;

  @override
  SudoPromptReason? get sudoAutofillReady => reason;

  @override
  Rect? get cursorGlobalRect => const Rect.fromLTWH(120, 200, 10, 20);

  @override
  Stream<Uint8List> get outgoingBytes => const Stream.empty();

  @override
  Stream<TerminalResize> get resizeEvents => const Stream.empty();

  @override
  Stream<bool> get taskRunning => const Stream.empty();

  @override
  Stream<TerminalTaskActivity> get taskActivity => const Stream.empty();

  @override
  bool get isTaskRunning => false;

  @override
  TerminalTaskActivity get currentTaskActivity =>
      const TerminalTaskActivity(running: false);

  @override
  String? get currentDirectory => null;

  @override
  void write(Uint8List bytes) {}

  @override
  void sendInput(String text) {}

  @override
  void showKeyboard() {}

  @override
  void hideKeyboard() {}

  @override
  Widget buildView({
    bool autofocus = false,
    bool readOnly = false,
    bool showCursor = true,
    VoidCallback? onOpenFileManagement,
    bool? transparentBackground,
    FocusOnKeyEventCallback? onKeyEvent,
  }) => const SizedBox();

  @override
  int find(String query, {bool caseSensitive = false}) => 0;

  @override
  void findJump(int index) {}

  @override
  void findClear() {}

  @override
  Future<void> dispose() async {}
}
