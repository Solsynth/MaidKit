import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart' as ez;
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart' as ez_tr;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:maid_kit/servers/terminal_tabs_provider.dart';

import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/sessions_page.dart';
import 'package:maid_kit/servers/ssh_connection_manager.dart';
import 'package:maid_kit/servers/terminal_session_adapter.dart';
import 'package:maid_kit/servers/terminal_color_scheme.dart';
import 'package:maid_kit/theme.dart';

/// The band is a row of pills, not a ruled table: no rule above it and no
/// rules between readings.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
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

  testWidgets('draws every reading as its own pill', (tester) async {
    // Readings are the pointer platform's row: on touch the band is the key
    // deck instead, one row deep.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionManagerProvider.overrideWithValue(
              SshConnectionManager(() => throw UnimplementedError()),
            ),
          ],
          child: MaterialApp(
            theme: createMaidKitTheme(Brightness.light),
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: AnimatedTerminalStatusBar(
                  session: SshSessionInfo(
                    serverId: 1,
                    serverName: 'box',
                    connectedAt: DateTime.utc(2026),
                    status: SessionStatus.connected,
                    systemInfo: const ServerSystemInfo(
                      distribution: 'Ubuntu',
                      kernel: '6.8',
                    ),
                  ),
                  terminal: _FakeAdapter(),
                  terminalId: 'terminal-1',
                  transport: TerminalTransport.ssh,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Transport, connection identity, and the host's static label.
      final pills = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .where(
            (box) =>
                box.decoration is BoxDecoration &&
                (box.decoration as BoxDecoration).borderRadius ==
                    MaidKitRadius.pillRadius,
          )
          .toList();
      expect(pills.length, 3);

      final scheme = createMaidKitTheme(Brightness.light).colorScheme;
      for (final pill in pills) {
        final decoration = pill.decoration as BoxDecoration;
        expect(
          decoration.color,
          scheme.surfaceContainerHigh.withValues(alpha: 0.7),
        );
        expect(decoration.border, isNull);
      }

      // No separators and no rule above the band survive anywhere in it.
      final band = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(AnimatedTerminalStatusBar),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(band.color, Colors.transparent);
      expect(
        tester
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .where(
              (box) =>
                  box.decoration is BoxDecoration &&
                  (box.decoration as BoxDecoration).border != null,
            ),
        isEmpty,
      );

      // Pills stay shrink-wrapped instead of stretching to the band's width.
      for (final pill in pills) {
        expect(tester.getSize(find.byWidget(pill)).width, lessThan(400));
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'the mobile key deck reads the real IME inset and releases focus',
    (tester) async {
      // The pane body lives inside a Scaffold, which strips the bottom view
      // insets before the band sees them. The key must therefore read the
      // platform view, or it would never offer to put the keyboard away.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        tester.view.physicalSize = const Size(900, 600);
        tester.view.devicePixelRatio = 1.0;
        tester.view.viewInsets = const FakeViewPadding(bottom: 320);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);

        final terminal = _FakeAdapter();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              connectionManagerProvider.overrideWithValue(
                SshConnectionManager(() => throw UnimplementedError()),
              ),
            ],
            child: MaterialApp(
              theme: createMaidKitTheme(Brightness.light),
              home: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedTerminalStatusBar(
                    session: null,
                    terminal: terminal,
                    terminalId: 'terminal-1',
                    transport: TerminalTransport.ssh,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Symbols.keyboard_hide), findsOneWidget);
        await tester.tap(find.byIcon(Symbols.keyboard_hide));
        await tester.pump();
        expect(terminal.unfocusCount, 1);
        expect(terminal.showKeyboardCount, 0);

        tester.view.viewInsets = const FakeViewPadding();
        await tester.pump();
        expect(find.byIcon(Symbols.keyboard), findsOneWidget);
        await tester.tap(find.byIcon(Symbols.keyboard));
        await tester.pump();
        expect(terminal.showKeyboardCount, 1);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('the deck swaps between navigation keys and control chords', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final terminal = _FakeAdapter();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectionManagerProvider.overrideWithValue(
              SshConnectionManager(() => throw UnimplementedError()),
            ),
          ],
          child: MaterialApp(
            theme: createMaidKitTheme(Brightness.light),
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: AnimatedTerminalStatusBar(
                  session: null,
                  terminal: terminal,
                  terminalId: 'terminal-1',
                  transport: TerminalTransport.ssh,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A navigation key sends its escape sequence, not its label.
      await tester.tap(find.text('←'));
      await tester.pump();
      expect(terminal.inputs, ['\u001b[D']);

      // The modifier arms the control layer and stays put while the run
      // swaps under it.
      await tester.tap(find.text('ctrl'));
      await tester.pumpAndSettle();
      expect(find.text('esc'), findsNothing);
      expect(find.text('C'), findsOneWidget);

      await tester.tap(find.text('C'));
      await tester.pump();
      expect(terminal.inputs, ['\u001b[D', '\u0003']);

      // Pressing the modifier again puts the navigation keys back.
      await tester.tap(find.text('ctrl'));
      await tester.pumpAndSettle();
      expect(find.text('esc'), findsOneWidget);
      expect(find.text('C'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

class _FakeAdapter implements TerminalSessionAdapter {
  var showKeyboardCount = 0;
  var unfocusCount = 0;
  final inputs = <String>[];

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
  int get bufferRows => 0;

  @override
  String? dumpHistory({int maxLines = 4000}) => null;

  @override
  void replayHistory(String text) {}

  @override
  SudoPromptReason? get sudoAutofillReady => null;

  @override
  void bindSudoAutofill(Stream<SudoPromptReason?> reasons) {}

  @override
  void write(Uint8List bytes) {}

  @override
  void sendInput(String text) => inputs.add(text);

  @override
  void showKeyboard() => showKeyboardCount++;

  @override
  void unfocus() => unfocusCount++;

  @override
  Rect? get cursorGlobalRect => null;

  @override
  Widget buildView({
    bool autofocus = false,
    bool readOnly = false,
    bool showCursor = true,
    VoidCallback? onOpenFileManagement,
    bool? transparentBackground,
    TerminalColorScheme? colorScheme,
    FocusOnKeyEventCallback? onKeyEvent,
  }) => const SizedBox.shrink();

  @override
  int find(String query, {bool caseSensitive = false}) => 0;

  @override
  void findJump(int index) {}

  @override
  void findClear() {}

  @override
  Future<void> dispose() async {}
}
