import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart' as ez;
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart' as ez_tr;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/agent/agent_selection.dart';
import 'package:maid_kit/agent/conversation_store.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/tabs_screen.dart';
import 'package:maid_kit/servers/ssh_connection_manager.dart';
import 'package:maid_kit/servers/terminal_session_adapter.dart';
import 'package:maid_kit/servers/terminal_tabs_provider.dart';
import 'package:maid_kit/shared/presentation/maidkit_window_scaffold.dart';
import 'package:maid_kit/shared/presentation/window_chrome.dart';
import 'package:maid_kit/snippets/snippet_repository.dart';
import 'package:maid_kit/theme.dart';

class _RecordingConnectionManager extends SshConnectionManager {
  _RecordingConnectionManager() : super(() => throw UnimplementedError());
}

class _StubSelectionNotifier extends AgentSelectionNotifier {
  @override
  Future<AgentSelectionSettings> build() async =>
      InMemoryAgentSelectionSettings();
}

/// A terminal that only renders a focusable host, so the terminal's own key
/// hook is exercised without a renderer.
class _KeyHostAdapter implements TerminalSessionAdapter {
  _KeyHostAdapter() {
    outgoing.listen(sent.add);
  }

  final sent = <Uint8List>[];
  final _outgoing = StreamController<Uint8List>.broadcast();

  /// Keys the terminal host handed to the app after its own handling, so a
  /// test can tell the terminal's hook ran instead of the window shell's.
  final handledKeys = <LogicalKeyboardKey>[];
  final focusNode = FocusNode();

  Stream<Uint8List> get outgoing => _outgoing.stream;

  @override
  Stream<Uint8List> get outgoingBytes => _outgoing.stream;

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
  int get bufferRows => 100;

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
  void sendInput(String text) =>
      _outgoing.add(Uint8List.fromList(utf8.encode(text)));

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
  }) => Focus(
    focusNode: focusNode,
    autofocus: autofocus,
    // A real renderer encodes whatever its hook ignores and keeps the event,
    // so nothing it swallows ever reaches the window shell.
    onKeyEvent: (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      handledKeys.add(event.logicalKey);
      final result = onKeyEvent?.call(node, event) ?? KeyEventResult.ignored;
      return result == KeyEventResult.ignored ? KeyEventResult.handled : result;
    },
    child: const SizedBox.expand(),
  );

  @override
  int find(String query, {bool caseSensitive = false}) => 0;

  @override
  void findJump(int index) {}

  @override
  void findClear() {}

  @override
  Future<void> dispose() async {
    focusNode.dispose();
    await _outgoing.close();
  }
}

Iterable<SessionLayoutSplit> _splits(SessionLayout layout) sync* {
  switch (layout) {
    case SessionLayoutLeaf():
      return;
    case SessionLayoutSplit(:final first, :final second):
      yield layout;
      yield* _splits(first);
      yield* _splits(second);
  }
}

/// Cmd/Ctrl+D splits the focused pane to the right and its Shift variant
/// splits below — from the window shell, and from inside a focused terminal
/// that would otherwise encode the chord for the remote shell.
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

  /// Pumps the window shell around the workspace, where the app-level
  /// shortcuts live.
  Future<ProviderContainer> pumpWindow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final overlayKey = GlobalKey<OverlayState>();
    IslandUIFoundation.configureOverlay(overlayKey);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: ProviderScope(
          overrides: [
            // The desktop frame is what holds focus in the app; here the
            // workspace keeps it instead so key events reach the window.
            desktopWindowProvider.overrideWithValue(false),
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
            mcpServersProvider.overrideWith(
              (ref) => Stream.value(const <McpServer>[]),
            ),
            agentProvidersProvider.overrideWith(
              (ref) => Stream.value(const <AgentProvider>[]),
            ),
            agentProviderModelsProvider.overrideWith(
              (ref, providerId) => Stream.value(const <AgentProviderModel>[]),
            ),
            agentConversationsProvider.overrideWith(
              (ref) => Stream.value(const <AgentConversation>[]),
            ),
            agentSelectionProvider.overrideWith(() => _StubSelectionNotifier()),
          ],
          child: MaterialApp(
            theme: createMaidKitTheme(Brightness.light),
            home: Overlay(
              key: overlayKey,
              initialEntries: [
                OverlayEntry(
                  builder: (context) => MaidKitWindowScaffold(
                    child: Focus(
                      autofocus: true,
                      child: const Scaffold(body: SessionsWorkspace()),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(SessionsWorkspace)),
    );
  }

  /// Sends a key chord with the modifier [usesCommandGlyph] picks, so the
  /// same test covers the Cmd and the Ctrl platform.
  Future<void> pressSplit(
    WidgetTester tester, {
    required bool shift,
    bool control = false,
  }) async {
    final modifier = control
        ? LogicalKeyboardKey.controlLeft
        : LogicalKeyboardKey.metaLeft;
    await tester.sendKeyDownEvent(modifier);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();
  }

  /// Runs [body] as if the app were on [platform]. The override has to be
  /// cleared inside the test body: the binding rejects a test that leaves a
  /// debug variable behind before tear-down runs.
  Future<void> onPlatform(
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets(
    'Cmd+D splits right and Shift+Cmd+D splits below',
    (tester) => onPlatform(TargetPlatform.macOS, () async {
      final container = await pumpWindow(tester);

      await pressSplit(tester, shift: false);
      var tab = container.read(terminalTabsProvider).selectedTab!;
      expect(tab.panes, hasLength(2));
      expect(
        (tab.layout as SessionLayoutSplit).axis,
        SessionSplitAxis.horizontal,
      );

      await pressSplit(tester, shift: true);
      tab = container.read(terminalTabsProvider).selectedTab!;
      expect(tab.panes, hasLength(3));
      // The newest split hangs below the pane that had focus, so the vertical
      // node's second child is the pane the workspace just focused.
      final below = _splits(
        tab.layout,
      ).singleWhere((split) => split.axis == SessionSplitAxis.vertical);
      expect((below.second as SessionLayoutLeaf).paneId, tab.focusedPaneId);

      // Ctrl+D is the shell's end-of-input on a Mac; it must not split.
      await pressSplit(tester, shift: false, control: true);
      expect(
        container.read(terminalTabsProvider).selectedTab!.panes,
        hasLength(3),
      );
    }),
  );

  testWidgets(
    'Ctrl+D splits on platforms that use Ctrl as command',
    (tester) => onPlatform(TargetPlatform.linux, () async {
      final container = await pumpWindow(tester);

      await pressSplit(tester, shift: false, control: true);
      expect(
        container.read(terminalTabsProvider).selectedTab!.panes,
        hasLength(2),
      );

      // Cmd is not this platform's command modifier, so it stays the shell's.
      await pressSplit(tester, shift: false);
      expect(
        container.read(terminalTabsProvider).selectedTab!.panes,
        hasLength(2),
      );
    }),
  );

  testWidgets(
    'the palette prints the split chords beside their actions',
    (tester) => onPlatform(TargetPlatform.macOS, () async {
      await pumpWindow(tester);

      await tester.tap(find.byTooltip('sessionsSessionActions'.tr()));
      await tester.pumpAndSettle();

      final right = find.widgetWithText(ListTile, 'sessionsSplitRight'.tr());
      expect(
        find.descendant(of: right, matching: find.text('⌘D')),
        findsOneWidget,
      );
      final down = find.widgetWithText(ListTile, 'sessionsSplitDown'.tr());
      expect(
        find.descendant(of: down, matching: find.text('⇧⌘D')),
        findsOneWidget,
      );
    }),
  );

  testWidgets(
    'a focused terminal splits instead of sending the chord',
    (tester) => onPlatform(TargetPlatform.macOS, () async {
      final adapter = _KeyHostAdapter();
      addTearDown(adapter.dispose);
      final container = await pumpWindow(tester);

      container.read(terminalTabsProvider.notifier).state = TerminalTabsState(
        tabs: [
          WorkspaceTab(
            id: 'terminal-1',
            panes: {
              'pane-1': TabPane(
                id: 'pane-1',
                tab: TerminalTab(
                  id: 'terminal-1',
                  serverId: 1,
                  serverName: 'Test server',
                  terminal: adapter,
                  transport: TerminalTransport.ssh,
                ),
              ),
            },
            layout: const SessionLayoutLeaf('pane-1'),
            focusedPaneId: 'pane-1',
          ),
        ],
        selectedTabId: 'terminal-1',
      );
      await tester.pumpAndSettle();

      await pressSplit(tester, shift: false);

      expect(
        container.read(terminalTabsProvider).selectedTab!.panes,
        hasLength(2),
      );
      // The remote shell never saw Ctrl+D, so the terminal did not exit.
      expect(adapter.sent, isEmpty);
    }),
  );
}
