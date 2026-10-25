import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart' as ez;
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart' as ez_tr;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:maid_kit/servers/terminal_tabs_provider.dart';

import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/sessions_page.dart';
import 'package:maid_kit/servers/ssh_connection_manager.dart';
import 'package:maid_kit/servers/terminal_session_adapter.dart';
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
  });
}

class _FakeAdapter implements TerminalSessionAdapter {
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
  void sendInput(String text) {}

  @override
  void showKeyboard() {}

  @override
  void hideKeyboard() {}

  @override
  Rect? get cursorGlobalRect => null;

  @override
  Widget buildView({
    bool autofocus = false,
    bool readOnly = false,
    bool showCursor = true,
    VoidCallback? onOpenFileManagement,
    bool? transparentBackground,
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
