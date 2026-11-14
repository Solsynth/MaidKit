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
  _Control({this.initialLayout = _onePane, this.supportsNewLayouts = true}) {
    client = TmuxControlClient(
      output: _output.stream,
      write: _onWrite,
      onClosed: (_) {},
    );
    // Every real attach opens with this greeting, and the client holds its
    // commands until it arrives. Sending it here keeps the fake paced like the
    // transport it stands in for.
    scheduleMicrotask(() => feed('\x1bP1000p%begin 1 312 0\n%end 1 312 0\n'));
  }

  /// Whether this build knows `refresh-client -f new-layouts`. A tmux that does
  /// not answers with `%error` and keeps reporting format 1 layouts.
  final bool supportsNewLayouts;

  /// What `#{window_layout}` reports when the client attaches, standing in for
  /// a session that already has panes and is not about to emit an event.
  final String initialLayout;

  /// What `capture-pane` reports above the visible screen.
  String scrollback = '';

  /// Panes running a full-screen program, whose screen must not be seeded.
  final alternateOn = <String>{};

  String _paneInCommand(String command) {
    final match = RegExp(r'-t (%\d+)').firstMatch(command);
    return match?.group(1) ?? '';
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
    final refusedFlag =
        !supportsNewLayouts && command.startsWith('refresh-client -f');
    final lines = switch (command) {
      // The session has one window, window 0, active, named bash. The fields
      // are joined with the separator the command actually asked for: tmux does
      // not expand `\t` escapes in a format, so a literal backslash-t comes
      // back as those two characters and the client must not split on it.
      _ when command.startsWith('list-windows') => [
        '@1',
        '0',
        'bash',
        '1',
      ].join(_separatorIn(command)),
      _ when command.startsWith('list-panes') => '',
      // tmux's scrollback above the visible screen, replayed on attach.
      _ when command.startsWith('capture-pane') => scrollback,
      // The attach-time layout pull, which is the only way an idle session's
      // panes ever reach the workspace.
      // `alternate_on` asks whether the pane runs a full-screen program; the
      // scrollback seed skips those.
      _ when command.contains('alternate_on') =>
        alternateOn.contains(_paneInCommand(command)) ? '1' : '0',
      _ when command.startsWith('display-message') => initialLayout,
      _ => '',
    };
    // Answer on a microtask: the command is registered after this write.
    scheduleMicrotask(() {
      final kind = refusedFlag ? 'error' : 'end';
      feed(
        '%begin 1 $_block 0\n${lines.isEmpty ? '' : '$lines\n'}%$kind 1 $_block 0\n',
      );
    });
  }

  /// The field separator [command]'s format string really carries.
  String _separatorIn(String command) {
    if (command.contains(r'\t')) return r'\t';
    return '\t';
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

  /// Presses keys in this pane, the way the renderer forwards them.
  void emitInput(List<int> bytes) => _input.add(Uint8List.fromList(bytes));

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

  final replayed = <String>[];

  @override
  void replayHistory(String text) => replayed.add(text);

  /// Every reason the pane's wiring posted, for the hint at the cursor.
  final sudoReasons = <SudoPromptReason?>[];
  StreamSubscription<SudoPromptReason?>? _sudoSub;

  @override
  SudoPromptReason? get sudoAutofillReady => sudoReasons.lastOrNull;

  @override
  void bindSudoAutofill(Stream<SudoPromptReason?> reasons) {
    _sudoSub?.cancel();
    _sudoSub = reasons.listen(sudoReasons.add);
  }

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
  Future<void> dispose() async {
    await _sudoSub?.cancel();
    await _input.close();
    await _resize.close();
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
  Future<void> mount({String? layout, String? autoFillSecret}) async {
    await container
        .read(terminalTabsProvider.notifier)
        .openTmux(
          _server(),
          sessionName: 'maidkit-build',
          control: control.client,
          autoFillSecret: autoFillSecret,
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

  test('a restored split tab keeps its beside pane', () async {
    // A restored workspace rebuilds a split tab with the terminal's pane empty
    // and whatever sat beside it mounted, then reattaches the session into
    // that pane. The session has to land in *that* tab: opening a second one
    // would throw the reservation away and leave the beside pane alone.
    final fileTab = FileManagementTab(
      id: 'files-1',
      serverId: _server().id,
      serverName: _server().name,
    );
    final restored = WorkspaceTab(
      id: 'restored-tab',
      panes: {
        'term-pane': const TabPane(id: 'term-pane'),
        'files-pane': TabPane(id: 'files-pane', tab: fileTab),
      },
      layout: const SessionLayoutSplit(
        id: 'restored-split',
        axis: SessionSplitAxis.horizontal,
        first: SessionLayoutLeaf('term-pane'),
        second: SessionLayoutLeaf('files-pane'),
      ),
      focusedPaneId: 'files-pane',
    );
    container.read(terminalTabsProvider.notifier).state = TerminalTabsState(
      tabs: [restored],
      selectedTabId: 'restored-tab',
    );

    await container
        .read(terminalTabsProvider.notifier)
        .openTmux(
          _server(),
          sessionName: 'maidkit-build',
          control: control.client,
          transport: TerminalTransport.tmux,
          closeTransport: control.close,
          paneId: 'term-pane',
        );
    await pumpEventQueue();

    final tabs = container.read(terminalTabsProvider).tabs;
    expect(
      tabs,
      hasLength(1),
      reason: 'the reservation is reused, not duplicated',
    );
    final tab = tabs.single;
    expect(tab.panes['files-pane']?.tab, same(fileTab));
    // Both tmux panes are mounted, and the file manager is still beside them.
    // The session reports a single pane here, so the reserved one is filled by
    // it and the placeholder never becomes a pane of its own.
    expect(
      tab.panes.values.map((pane) => pane.tab).whereType<TerminalTab>().length,
      1,
      reason: 'the session reattached into the pane the restore reserved',
    );
    expect(tab.panes.keys, containsAll(<String>['files-pane']));
    expect(
      container.read(terminalTabsProvider.notifier).tmuxForTab(tab.id),
      isNotNull,
    );
  });

  test('attaching to an idle session pulls its layout', () async {
    // No `%layout-change` is ever fed: tmux only emits one from events, so an
    // untouched session reports nothing after the attach. The pull is what has
    // to fill the tab, otherwise it stays the empty placeholder it opened as.
    await mount();
    final tab = container.read(terminalTabsProvider).selectedTab!;
    expect(tab.panes, hasLength(1));
    expect(control.written, contains('display-message'));
    expect(control.written, contains('#{window_layout}'));
    expect(binding().paneIds, ['%0']);
  });

  test('the window list is asked for with real tabs', () async {
    // tmux does not expand `\t` in a format, so an escaped separator arrives as
    // a backslash and a t. Splitting on that yields one field, the active
    // window stays unknown, and no layout is ever pulled — an empty tab on
    // every tmux version. The fake echoes whichever separator it was sent, so
    // this only passes when the command carries a literal tab.
    await mount();
    final listCommand = control.writes.firstWhere(
      (command) => command.startsWith('list-windows'),
    );
    expect(listCommand, contains('\t'));
    expect(listCommand, isNot(contains(r'\t')));
    expect(binding().windowId, '@1');
    expect(binding().paneIds, ['%0']);
  });

  test(
    'a session that reports no layout fails instead of staying empty',
    () async {
      // The caller falls back to a plain terminal when this throws. Leaving an
      // empty pane behind would hide the failure entirely, which is what made
      // the escaped-separator bug invisible.
      addTearDown(control.close);
      container.dispose();
      control = _Control(initialLayout: '');
      container = ProviderContainer(
        overrides: [
          terminalSessionAdapterFactoryProvider.overrideWithValue(factory),
          tmuxSettingsProvider.overrideWithValue(InMemoryTmuxSettings()),
        ],
      );
      addTearDown(container.dispose);
      await expectLater(
        container
            .read(terminalTabsProvider.notifier)
            .openTmux(
              _server(),
              sessionName: 'maidkit-build',
              control: control.client,
              transport: TerminalTransport.tmux,
              closeTransport: control.close,
            ),
        throwsA(isA<TmuxControlException>()),
      );
      // Only the workspace's dashboard floor is left: the tmux tab was rolled
      // back rather than left on screen as an empty pane.
      final tabs = container.read(terminalTabsProvider).tabs;
      expect(tabs, hasLength(1));
      expect(tabs.single.tabs.single, isA<DashboardTab>());
    },
  );

  test('two panes on an idle session mount from the pulled layout', () async {
    addTearDown(control.close);
    container.dispose();
    control = _Control(initialLayout: _twoPanes);
    container = ProviderContainer(
      overrides: [
        terminalSessionAdapterFactoryProvider.overrideWithValue(factory),
        tmuxSettingsProvider.overrideWithValue(InMemoryTmuxSettings()),
      ],
    );
    addTearDown(container.dispose);
    await mount();
    expect(
      container.read(terminalTabsProvider).selectedTab!.panes,
      hasLength(2),
    );
  });

  test('a tmux without new-layouts still mounts its panes', () async {
    // Older tmux does not know the flag, answers `%error`, and reports the
    // legacy format 1 layout from both the pull and the event. The tab has to
    // mirror it rather than staying empty.
    addTearDown(control.close);
    container.dispose();
    control = _Control(
      initialLayout:
          '5525,80x24,0,0{5x24,0,0,0,4x24,6,0,13,'
          '9x24,11,0,11,19x24,21,0,9,39x24,41,0,6}',
      supportsNewLayouts: false,
    );
    container = ProviderContainer(
      overrides: [
        terminalSessionAdapterFactoryProvider.overrideWithValue(factory),
        tmuxSettingsProvider.overrideWithValue(InMemoryTmuxSettings()),
      ],
    );
    addTearDown(container.dispose);
    await mount();
    expect(
      container.read(terminalTabsProvider).selectedTab!.panes,
      hasLength(5),
    );
    expect(binding().paneIds, ['%0', '%13', '%11', '%9', '%6']);
    // A later event in the same legacy format re-tiles the same way.
    control.layout('bb11,80x24,0,0[40x12,0,0,3,39x11,0,13,4]');
    await pumpEventQueue();
    expect(binding().paneIds, ['%3', '%4']);
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

  test('a sudo prompt in a pane autofills the saved password', () async {
    // Each pane is a real shell behind tmux, so it needs the same
    // interception a plain SSH terminal has. A pane that never has a secret
    // forwarded must not receive one, and pressing Enter anywhere else is
    // left alone.
    await mount(layout: _onePane, autoFillSecret: 'hunter2');
    final adapter = factory.adapters.single;
    control.feed('%output %0 [sudo] password for deploy: \n');
    await pumpEventQueue();
    // The hint follows the same watcher, so it is up before Enter is pressed.
    expect(adapter.sudoReasons, [SudoPromptReason.prompt]);
    control.writes.clear();
    adapter.emitInput([0x0d]);
    await pumpEventQueue();
    expect(control.written, 'send-keys -H -t %0 68 75 6E 74 65 72 32 0D');
  });

  test(
    'a tmux pane without a saved password forwards keys untouched',
    () async {
      await mount(layout: _onePane);
      final adapter = factory.adapters.single;
      control.feed('%output %0 [sudo] password for deploy: \n');
      await pumpEventQueue();
      // Every output chunk posts the pane's current reason, which stays null
      // when there is no secret to fill.
      expect(adapter.sudoReasons, everyElement(isNull));
      control.writes.clear();
      adapter.emitInput([0x0d]);
      await pumpEventQueue();
      expect(control.written, 'send-keys -H -t %0 0D');
    },
  );

  test('a resize reports the client size to tmux', () async {
    // One pane fills the session, so its own viewport *is* the client extent.
    await mount(layout: _onePane);
    control.writes.clear();
    factory.adapters.first.emitResize(120, 36);
    await pumpEventQueue();
    expect(control.written, contains('refresh-client -C 120x36'));
  });

  test('a split pane never resizes the session to its own half', () async {
    // Two panes share one session: `refresh-client -C` is the whole client, so
    // reporting a single pane's width would tell tmux the session is half the
    // size it is drawn at - and every full-screen program in it would wrap.
    await mount(layout: _twoPanes);
    control.writes.clear();
    factory.adapters[0].emitResize(80, 40);
    factory.adapters[1].emitResize(80, 40);
    await pumpEventQueue();
    expect(control.written, contains('refresh-client -C 161x40'));
    expect(control.written, isNot(contains('refresh-client -C 80x40')));
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

  test('a full-screen program is not given a scrollback seed', () async {
    // vim, less and friends live on the alternate screen: replaying that into a
    // fresh emulator prints their cursor-addressed UI as literal text, which is
    // how they came out garbled and wrapped.
    control.alternateOn.add('%0');
    control.scrollback = 'stale screen text';
    await mount(layout: _onePane);
    await pumpEventQueue();
    expect(factory.adapters.single.replayed, isEmpty);
    expect(
      control.written,
      isNot(contains('capture-pane -S')),
      reason: 'the screen of a full-screen program is not history',
    );
  });

  test('padding under the prompt is not replayed as history', () async {
    // `capture-pane` returns the whole grid, so a screen of blank rows would
    // scroll the pane to emptiness when replayed.
    control.scrollback = 'echo HI\r\nHI\r\nuser@h:~ \$\n\n\n\n\n';
    await mount(layout: _onePane);
    await pumpEventQueue();
    expect(factory.adapters.single.replayed.single, endsWith('user@h:~ \$'));
  });

  test('a pane tmux does not own survives a layout change', () async {
    // The terminal's context menu splits the file manager in beside it. tmux
    // knows nothing about that pane, so a `%layout-change` used to treat it as
    // a pane that went away and release it - the browser closed the moment it
    // opened. Only panes mirroring this binding may be retired here.
    await mount(layout: _onePane);
    final tabId = container.read(terminalTabsProvider).selectedTab!.id;
    final notifier = container.read(terminalTabsProvider.notifier);
    notifier.openFileManagement(_server(), splitRight: true);
    await pumpEventQueue();
    final withFiles = container.read(terminalTabsProvider).selectedTab!;
    final filesPane = withFiles.panes.values.firstWhere(
      (pane) => pane.tab is FileManagementTab,
    );
    final filesPaneCount = withFiles.panes.length;

    // A window event re-projects the layout.
    control.layout(_onePane);
    await pumpEventQueue();

    final after = container.read(terminalTabsProvider).tabById(tabId)!;
    expect(
      after.panes.containsKey(filesPane.id),
      isTrue,
      reason: 'tmux must not close a pane it never opened',
    );
    expect(after.panes[filesPane.id]!.tab, isA<FileManagementTab>());
    expect(
      after.layout.paneIds,
      containsAll(<String>[filesPane.id]),
      reason: 'the pane stays in the tree, or it is mounted nowhere',
    );
    expect(after.panes.length, filesPaneCount);
  });

  test('a fresh attach replays the scrollback tmux still holds', () async {
    // Attaching paints the current screen only, so a session that has been
    // running for a while opens as if its earlier output never happened. The
    // output above the screen is still in tmux's own history and is replayed
    // before any live output arrives.
    control.scrollback = 'earlier line one\nearlier line two';
    await mount(layout: _onePane);
    await pumpEventQueue();
    expect(
      factory.adapters.single.replayed.join(),
      contains('earlier line one'),
    );
    expect(
      control.written,
      contains('capture-pane -p -e -t %0'),
      reason: 'the history comes from tmux, not from a second render',
    );
    expect(
      control.written,
      isNot(contains('-E -1')),
      reason: 'the screen is captured too, or a reattach loses the prompt',
    );
  });

  test('a reattach does not replay the history twice', () async {
    control.scrollback = 'only once';
    await mount(layout: _onePane);
    await pumpEventQueue();
    control.layout(_onePane);
    await pumpEventQueue();
    expect(
      factory.adapters.single.replayed.where((t) => t.contains('only once')),
      hasLength(1),
    );
  });

  test(
    'a dropped channel keeps the tab, its panes, and its scrollback',
    () async {
      // tmux never said the session ended: the channel under the client went away
      // mid-task. The work is still running on the host, so closing the tab
      // would claim it was over and throw away a session the user can still
      // attach to.
      await mount(layout: _onePane);
      final tabId = container.read(terminalTabsProvider).selectedTab!.id;
      final paneIds = container
          .read(terminalTabsProvider)
          .selectedTab!
          .layout
          .paneIds;
      await control.close();
      await pumpEventQueue();
      final tab = container.read(terminalTabsProvider).tabById(tabId);
      expect(tab, isNotNull, reason: 'the tab stays where it was');
      expect(tab!.layout.paneIds, paneIds);
      expect(
        container
            .read(terminalTabsProvider.notifier)
            .tmuxForTab(tabId)!
            .transportLost,
        isTrue,
      );
    },
  );

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

  test('a tmux exit drops its transport instead of leaking it', () async {
    // When tmux ends the session itself there is nothing left to detach, but
    // the channel the client rode is still open. Leaving it to whoever closes
    // the tab would hold a shell on the host for as long as the app runs.
    await mount(layout: _onePane);
    expect(control.closed, isFalse);
    control.feed('%exit session destroyed\n');
    await pumpEventQueue();
    expect(control.closed, isTrue);
  });

  test('closing a tab closes the transport exactly once', () async {
    // Detach and kill end the session differently but share one connection;
    // the second path must not try to close a transport already dropped.
    await mount(layout: _onePane);
    final tabId = container.read(terminalTabsProvider).selectedTab!.id;
    await container.read(terminalTabsProvider.notifier).closeTab(tabId);
    await pumpEventQueue();
    expect(control.closed, isTrue);
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
