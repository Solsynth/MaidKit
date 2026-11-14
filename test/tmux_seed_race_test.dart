import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/terminal_color_scheme.dart';
import 'package:maid_kit/servers/terminal_session_adapter.dart';
import 'package:maid_kit/servers/terminal_tabs_provider.dart';
import 'package:maid_kit/servers/tmux_control_client.dart';
import 'package:maid_kit/servers/tmux_preferences.dart';

/// A control transport whose answers arrive only when the test says so, so a
/// first paint can be raced against the history seed deterministically.
class _PacedControl {
  _PacedControl({required this.layout}) {
    client = TmuxControlClient(
      output: _output.stream,
      write: _onWrite,
      onClosed: (_) {},
    );
    scheduleMicrotask(() => feed('\x1bP1000p%begin 1 312 0\n%end 1 312 0\n'));
  }

  final String layout;
  final _output = StreamController<Uint8List>();
  final _commands = <String>[];
  final _held = <String, List<void Function()>>{};
  late final TmuxControlClient client;
  var _block = 0;

  void feed(String text) => _output.add(Uint8List.fromList(utf8.encode(text)));

  /// Reports a layout for the session's active window.
  void emitLayout(String json) => feed('%layout-change @1 $json *\n');

  /// Answers [command] now, or holds it until [release] is called.
  void hold(String command) => _held[command] = [];

  void release(String command) {
    for (final answer in _held.remove(command) ?? const <void Function()>[]) {
      answer();
    }
  }

  Future<void> close() async {
    if (!_output.isClosed) await _output.close();
  }

  void _onWrite(List<int> bytes) {
    final command = utf8.decode(bytes).trimRight();
    _commands.add(command);
    _block++;
    final lines = switch (command) {
      _ when command.startsWith('list-windows') => '@1\t0\tbash\t1',
      _ when command.contains('alternate_on') => '0',
      _ when command.startsWith('capture-pane') => 'stale screen above the prompt',
      _ when command.startsWith('display-message') => layout,
      _ => '',
    };
    void answer() {
      feed(
        '%begin 1 $_block 0\n${lines.isEmpty ? '' : '$lines\n'}%end 1 $_block 0\n',
      );
    }

    final key = _held.keys.firstWhere(
      (candidate) => command.startsWith(candidate),
      orElse: () => '',
    );
    if (key.isNotEmpty) {
      _held[key]!.add(answer);
      return;
    }
    scheduleMicrotask(answer);
  }
}

class _RecordingAdapter implements TerminalSessionAdapter {
  final _written = <int>[];
  final _input = StreamController<Uint8List>.broadcast();
  final _resize = StreamController<TerminalResize>.broadcast();
  final replayed = <String>[];

  String get writtenText => utf8.decode(_written, allowMalformed: true);

  @override
  void replayHistory(String text) => replayed.add(text);

  @override
  void write(Uint8List bytes) => _written.addAll(bytes);

  @override
  Stream<Uint8List> get outgoingBytes => _input.stream;

  @override
  Stream<TerminalResize> get resizeEvents => _resize.stream;

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
  SudoPromptReason? get sudoAutofillReady => null;

  @override
  void bindSudoAutofill(Stream<SudoPromptReason?> reasons) {}

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
  }) => const SizedBox.shrink();

  @override
  int find(String query, {bool caseSensitive = false}) => 0;

  @override
  void findJump(int index) {}

  @override
  void findClear() {}

  @override
  Future<void> dispose() async {
    await _input.close();
    await _resize.close();
  }
}

class _RecordingAdapterFactory implements TerminalSessionAdapterFactory {
  final adapters = <_RecordingAdapter>[];

  @override
  TerminalSessionAdapter create() {
    final adapter = _RecordingAdapter();
    adapters.add(adapter);
    return adapter;
  }
}

Server _server() => const Server(
  id: 7,
  name: 'Build host',
  host: 'build.example',
  port: 22,
  username: 'deploy',
  collectStats: true,
  collectSystemInfo: false,
  connectionType: 'ssh',
  maidCafeTerminalViaCloud: false,
);

const _onePane = '{"V":2,"L":{"t":"p","w":80,"h":24,"x":0,"y":0,"I":"%0"}}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a first paint that beats the history seed is not overwritten by it',
    () async {
      // On a fresh session tmux paints the shell's first screen as soon as the
      // client attaches, while the scrollback capture is still in flight. The
      // capture's answer describes a screen that no longer exists: replaying it
      // writes it at the live cursor, pushes the real prompt off the screen, and
      // the pane reads as blank until a keypress prints something.
      final control = _PacedControl(layout: _onePane)
        ..hold('capture-pane');
      final factory = _RecordingAdapterFactory();
      final container = ProviderContainer(
        overrides: [
          terminalSessionAdapterFactoryProvider.overrideWithValue(factory),
          tmuxSettingsProvider.overrideWithValue(InMemoryTmuxSettings()),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(control.close);

      final opening = container
          .read(terminalTabsProvider.notifier)
          .openTmux(
            _server(),
            sessionName: 'maidkit-build',
            control: control.client,
            transport: TerminalTransport.tmux,
            closeTransport: control.close,
          );
      await pumpEventQueue();
      control.emitLayout(_onePane);
      await pumpEventQueue();
      // The shell's first paint arrives before the capture's answer.
      control.feed('%output %0 \$ \n');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(factory.adapters.single.writtenText, contains(r'$ '));

      control.release('capture-pane');
      await pumpEventQueue();
      await opening;
      expect(
        factory.adapters.single.replayed,
        isEmpty,
        reason: 'live output already holds a newer screen than the capture',
      );
    },
  );

  test('a capture that lands first is still replayed', () async {
    // The opposite order: the pane drew nothing yet, so the capture is the only
    // thing that can put the session's screen on it.
    final control = _PacedControl(layout: _onePane)..hold('capture-pane');
    final factory = _RecordingAdapterFactory();
    final container = ProviderContainer(
      overrides: [
        terminalSessionAdapterFactoryProvider.overrideWithValue(factory),
        tmuxSettingsProvider.overrideWithValue(InMemoryTmuxSettings()),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(control.close);

    final opening = container
        .read(terminalTabsProvider.notifier)
        .openTmux(
          _server(),
          sessionName: 'maidkit-build',
          control: control.client,
          transport: TerminalTransport.tmux,
          closeTransport: control.close,
        );
    await pumpEventQueue();
    control.emitLayout(_onePane);
    await pumpEventQueue();
    control.release('capture-pane');
    await opening;
    expect(factory.adapters.single.replayed, hasLength(1));
  });
}
