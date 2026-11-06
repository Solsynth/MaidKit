import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/tabs_screen.dart';
import 'package:maid_kit/servers/terminal_color_scheme.dart';
import 'package:maid_kit/servers/terminal_session_adapter.dart';
import 'package:maid_kit/servers/terminal_tabs_provider.dart';
import 'package:maid_kit/servers/tmux_control_client.dart';
import 'package:maid_kit/servers/tmux_preferences.dart';
import 'package:maid_kit/snippets/snippet_repository.dart';
import 'package:maid_kit/theme.dart';

/// A tmux client whose transport the test owns.
class _Control {
  _Control() {
    client = TmuxControlClient(
      output: _output.stream,
      write: _answer,
      onClosed: (_) {},
    );
  }

  final _output = StreamController<Uint8List>();
  late final TmuxControlClient client;
  var _block = 0;

  void feed(String text) => _output.add(Uint8List.fromList(utf8.encode(text)));

  void _answer(List<int> bytes) {
    final command = utf8.decode(bytes).trimRight();
    _block++;
    final lines = command.startsWith('list-windows') ? '@1\t0\tbash\t1' : '';
    scheduleMicrotask(() {
      feed(
        '%begin 1 $_block 0\n${lines.isEmpty ? '' : '$lines\n'}%end 1 $_block 0\n',
      );
    });
  }
}

/// Renders a terminal without a platform plugin: the tmux pane surface only
/// needs an adapter that can report its streams.
class _PlainAdapter implements TerminalSessionAdapter {
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
  void unfocus() {}

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
  }) => const SizedBox(key: ValueKey('terminal-view'));

  @override
  int find(String query, {bool caseSensitive = false}) => 0;

  @override
  void findJump(int index) {}

  @override
  void findClear() {}

  @override
  Future<void> dispose() async {}
}

class _PlainFactory implements TerminalSessionAdapterFactory {
  @override
  TerminalSessionAdapter create() => _PlainAdapter();
}

Server _server() => const Server(
  id: 1,
  name: 'Build host',
  host: 'build.example',
  port: 22,
  username: 'deploy',
  collectStats: true,
  collectSystemInfo: false,
  connectionType: 'ssh',
  maidCafeTerminalViaCloud: false,
);

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
  });

  testWidgets('a tmux session renders one pane per tmux pane', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final overlayKey = GlobalKey<OverlayState>();
    IslandUIFoundation.configureOverlay(overlayKey);
    final control = _Control();
    addTearDown(() async {
      await control.client.dispose();
    });

    final container = ProviderContainer(
      overrides: [
        serversProvider.overrideWith(
          (ref) => Stream.value(<Server>[_server()]),
        ),
        savedCredentialsProvider.overrideWith(
          (ref) => Stream.value(<SavedCredential>[]),
        ),
        scriptSnippetsProvider.overrideWith(
          (ref) => Stream.value(<ScriptSnippet>[]),
        ),
        biometricUnlockEnabledProvider.overrideWith(
          (ref) => Future.value(false),
        ),
        cloudUserProvider.overrideWith((ref) async => null),
        terminalSessionAdapterFactoryProvider.overrideWithValue(
          _PlainFactory(),
        ),
        tmuxSettingsProvider.overrideWithValue(InMemoryTmuxSettings()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: EasyLocalization(
          supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
          path: 'assets/translations',
          fallbackLocale: const Locale('en', 'US'),
          child: MaterialApp(
            theme: createMaidKitTheme(Brightness.light),
            locale: const Locale('en', 'US'),
            home: Overlay(
              key: overlayKey,
              initialEntries: [
                OverlayEntry(
                  builder: (context) =>
                      const Scaffold(body: SessionsWorkspace()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await container
        .read(terminalTabsProvider.notifier)
        .openTmux(
          _server(),
          sessionName: 'maidkit-build',
          control: control.client,
          transport: TerminalTransport.tmux,
          closeTransport: () async {},
        );
    await tester.pumpAndSettle();

    // tmux reports a two-pane window; both panes have to be on screen.
    control.feed(
      '%layout-change @1 '
      '{"V":2,"L":{"t":"h","w":160,"h":24,"x":0,"y":0,'
      '"c":[{"t":"p","w":80,"h":24,"x":0,"y":0,"I":"%0"},'
      '{"t":"p","w":80,"h":24,"x":80,"y":0,"I":"%1"}]}} *\n',
    );
    await tester.pumpAndSettle();

    final tab = container.read(terminalTabsProvider).selectedTab!;
    expect(tab.panes, hasLength(2));
    expect(find.byKey(const ValueKey('terminal-view')), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    // The workspace saves its snapshot on a debounce; let it fire and dispose
    // the container before the tree so no timer outlives the test.
    await tester.pump(const Duration(seconds: 1));
    container.dispose();
    await tester.pumpAndSettle();
  });
}
