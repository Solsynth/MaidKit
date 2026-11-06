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
import 'package:maid_kit/servers/tmux_terminal.dart';

/// A tmux control transport that answers every command the way tmux does for a
/// fresh session with one window, so the client never waits on the test.
class _Control {
  _Control() {
    client = TmuxControlClient(
      output: _output.stream,
      write: _onWrite,
      onClosed: (_) {},
    );
  }

  final _output = StreamController<Uint8List>();
  final writes = <String>[];
  late final TmuxControlClient client;
  var closed = false;
  var _block = 0;

  String get written => writes.join('\n');

  void feed(String text) => _output.add(Uint8List.fromList(utf8.encode(text)));

  /// Reports a layout for the session's active window.
  void layout(String json) => feed('%layout-change @1 $json *\n');

  void _onWrite(List<int> bytes) {
    final command = utf8.decode(bytes).trimRight();
    writes.add(command);
    _block++;
    final lines = switch (command) {
      // The session has one window, window 0, active, named bash.
      _ when command.startsWith('list-windows') => '@1\t0\tbash\t1',
      _ when command.startsWith('list-panes') => '',
      _ => '',
    };
    // Answer on a microtask: the command is registered after this write.
    scheduleMicrotask(() {
      feed(
        '%begin 1 $_block 0\n${lines.isEmpty ? '' : '$lines\n'}%end 1 $_block 0\n',
      );
    });
  }

  Future<void> close() async {
    closed = true;
    if (!_output.isClosed) await _output.close();
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

class _RecordingAdapter implements TerminalSessionAdapter {
  final _written = <int>[];
  final _input = StreamController<Uint8List>.broadcast();
  final _resize = StreamController<TerminalResize>.broadcast();

  String get writtenText => utf8.decode(_written, allowMalformed: true);

  void emitResize(int columns, int rows) => _resize.add(
    TerminalResize(columns: columns, rows: rows, pixelWidth: 0, pixelHeight: 0),
  );

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
  void replayHistory(String text) {}

  @override
  SudoPromptReason? get sudoAutofillReady => null;

  @override
  void bindSudoAutofill(Stream<SudoPromptReason?> reasons) {}

  @override
  void write(Uint8List bytes) => _written.addAll(bytes);

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
  Future<void> dispose() async {}
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
const _twoPanes =
    '{"V":2,"L":{"t":"h","w":160,"h":24,"x":0,"y":0,'
    '"c":[{"t":"p","w":80,"h":24,"x":0,"y":0,"I":"%0"},'
    '{"t":"p","w":80,"h":24,"x":80,"y":0,"I":"%1"}]}}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Control control;
  late _RecordingAdapterFactory factory;
  late ProviderContainer container;

  setUp(() {
    control = _Control();
    factory = _RecordingAdapterFactory();
    container = ProviderContainer(
      overrides: [
        terminalSessionAdapterFactoryProvider.overrideWithValue(factory),
        tmuxSettingsProvider.overrideWithValue(InMemoryTmuxSettings()),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(control.close);
  });

  /// Mounts the session and reports [layout] for its active window.
  Future<void> mount({String? layout}) async {
    await container
        .read(terminalTabsProvider.notifier)
        .openTmux(
          _server(),
          sessionName: 'maidkit-build',
          control: control.client,
          transport: TerminalTransport.tmux,
          closeTransport: control.close,
        );
    await pumpEventQueue();
    if (layout != null) {
      control.layout(layout);
      await pumpEventQueue();
    }
  }

  TmuxTabBinding binding() {
    final tab = container.read(terminalTabsProvider).selectedTab!;
    return container.read(terminalTabsProvider.notifier).tmuxForTab(tab.id)!;
  }

  test('the first layout mounts one terminal per tmux pane', () async {
    await mount(layout: _twoPanes);
    final tab = container.read(terminalTabsProvider).selectedTab!;
    expect(tab.panes, hasLength(2));
    final contents = tab.tabs.toList();
    expect(contents, hasLength(2));
    for (final content in contents) {
      expect(content, isA<TerminalTab>());
      expect((content as TerminalTab).transport, TerminalTransport.tmux);
      expect(content.tmux, same(binding()));
    }
    // The window list is remembered for the palette's window switch.
    expect(binding().windows, hasLength(1));
    expect(binding().windows.single.name, 'bash');
  });

  test('%output reaches only its own pane emulator', () async {
    await mount(layout: _twoPanes);
    control.feed('%output %1 hello\n');
    await pumpEventQueue();
    // The bridge batches output on a short timer before handing it to the
    // emulator, so the flush has to run.
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(factory.adapters, hasLength(2));
    expect(factory.adapters[0].writtenText, isEmpty);
    expect(factory.adapters[1].writtenText, 'hello');
  });

  test('a resize reports the client size to tmux', () async {
    await mount(layout: _onePane);
    control.writes.clear();
    factory.adapters.first.emitResize(120, 36);
    await pumpEventQueue();
    expect(control.written, contains('refresh-client -C 120x36'));
  });

  test('a pane that disappears loses its content', () async {
    await mount(layout: _twoPanes);
    expect(
      container.read(terminalTabsProvider).selectedTab!.panes,
      hasLength(2),
    );
    control.layout(_onePane);
    await pumpEventQueue();
    expect(
      container.read(terminalTabsProvider).selectedTab!.panes,
      hasLength(1),
    );
    expect(binding().paneIds, ['%0']);
  });

  test('splitting asks tmux instead of adding a local pane', () async {
    await mount(layout: _onePane);
    control.writes.clear();
    container
        .read(terminalTabsProvider.notifier)
        .splitSelectedTab(SessionSplitAxis.horizontal);
    await pumpEventQueue();
    expect(control.written, contains('split-window -t %0 -h'));
    expect(
      container.read(terminalTabsProvider).selectedTab!.panes,
      hasLength(1),
    );
  });

  test('closing a pane kills the tmux pane', () async {
    await mount(layout: _twoPanes);
    final tab = container.read(terminalTabsProvider).selectedTab!;
    control.writes.clear();
    await container
        .read(terminalTabsProvider.notifier)
        .closePaneInTab(tab.id, tab.focusedPaneId);
    await pumpEventQueue();
    expect(control.written, contains('kill-pane -t '));
  });

  test('detaching on close leaves the session running', () async {
    await mount(layout: _onePane);
    control.writes.clear();
    await container
        .read(terminalTabsProvider.notifier)
        .closeTab(container.read(terminalTabsProvider).selectedId!);
    await pumpEventQueue();
    expect(control.written, contains('detach-client'));
    expect(control.written, isNot(contains('kill-session')));
    expect(control.closed, isTrue);
  });

  test('killing on close ends the session', () async {
    container.dispose();
    container = ProviderContainer(
      overrides: [
        terminalSessionAdapterFactoryProvider.overrideWithValue(factory),
        tmuxSettingsProvider.overrideWithValue(
          InMemoryTmuxSettings(detachOnClose: false),
        ),
      ],
    );
    addTearDown(container.dispose);
    await mount(layout: _onePane);
    control.writes.clear();
    await container
        .read(terminalTabsProvider.notifier)
        .closeTab(container.read(terminalTabsProvider).selectedId!);
    await pumpEventQueue();
    expect(control.written, contains('kill-session -t maidkit-build'));
  });

  test('a tmux exit drops the tab without a close guard', () async {
    await mount(layout: _onePane);
    final before = container.read(terminalTabsProvider).tabs.length;
    control.feed('%exit session destroyed\n');
    await pumpEventQueue();
    expect(container.read(terminalTabsProvider).tabs.length, before - 1);
    expect(
      container
          .read(terminalTabsProvider)
          .tabs
          .any((tab) => tab.id == 'dashboard'),
      isTrue,
      reason: 'only the tmux tab goes away',
    );
  });

  test('a tmux tab is found by its id and names its transport', () async {
    await mount(layout: _onePane);
    final tab = container.read(terminalTabsProvider).selectedTab!;
    expect(
      container.read(terminalTabsProvider.notifier).tmuxForTab(tab.id),
      same(binding()),
    );
    final content = tab.tabs.first as TerminalTab;
    expect(content.transport.labelKey, 'terminalTransportTmux');
  });
}
