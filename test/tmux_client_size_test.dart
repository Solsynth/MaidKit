// The client extent tmux is told. `refresh-client -C` sizes the *whole session*,
// and tmux then splits that extent among the panes, so a mirrored pane cannot
// report its own viewport: with a split open, the last pane to report would
// halve the session and every full-screen program in it would be told a width
// it is not drawn at - which is how a TUI's progress output wrapped wrongly.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/terminal_session_adapter.dart';
import 'package:maid_kit/servers/terminal_tabs_provider.dart';
import 'package:maid_kit/servers/tmux_control_client.dart';
import 'package:maid_kit/servers/tmux_preferences.dart';

const _twoPanes =
    '{"V":2,"L":{"t":"h","w":160,"h":40,'
    '"c":[{"t":"p","w":80,"h":40,"x":0,"y":0,"I":"%0"},'
    '{"t":"p","w":80,"h":40,"x":80,"y":0,"I":"%1"}]}}';

/// A control transport that answers tmux's commands and records the resizes.
class _Control {
  _Control() {
    client = TmuxControlClient(
      output: _output.stream,
      write: _onWrite,
      onClosed: (_) {},
    );
    scheduleMicrotask(() => feed('\x1bP1000p%begin 1 0 0\n%end 1 0 0\n'));
  }

  final _output = StreamController<Uint8List>();
  final writes = <String>[];
  late final TmuxControlClient client;
  var _block = 0;

  String get written => writes.join('\n');

  List<String> get resizes => [
    for (final w in writes)
      if (w.startsWith('refresh-client -C')) w,
  ];

  void feed(String text) => _output.add(Uint8List.fromList(utf8.encode(text)));

  void layout(String json) => feed('%layout-change @1 $json *\n');

  void _onWrite(List<int> bytes) {
    final command = utf8.decode(bytes).trimRight();
    writes.add(command);
    _block++;
    final n = _block;
    final lines = switch (command) {
      _ when command.startsWith('list-windows') => '@1\t0\tbash\t1',
      // No full-screen program: the scrollback seed may capture.
      _ when command.contains('alternate_on') => '0',
      _ when command.startsWith('capture-pane') => '',
      _ when command.startsWith('display-message') => _twoPanes,
      _ => '',
    };
    scheduleMicrotask(() {
      feed('%begin 1 $n 0\n${lines.isEmpty ? '' : '$lines\n'}%end 1 $n 0\n');
    });
  }

  Future<void> close() async {
    if (!_output.isClosed) await _output.close();
  }
}

/// An adapter that reports whatever size the test says its viewport has.
class _SizedAdapter implements TerminalSessionAdapter {
  final _resize = StreamController<TerminalResize>.broadcast();

  void show(int columns, int rows) => _resize.add(
    TerminalResize(
      columns: columns,
      rows: rows,
      pixelWidth: columns * 8,
      pixelHeight: rows * 16,
    ),
  );

  @override
  Stream<TerminalResize> get resizeEvents => _resize.stream;

  @override
  Stream<Uint8List> get outgoingBytes => const Stream.empty();

  @override
  Stream<bool> get taskRunning => const Stream.empty();

  @override
  Stream<TerminalTaskActivity> get taskActivity => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Factory implements TerminalSessionAdapterFactory {
  final adapters = <_SizedAdapter>[];

  @override
  TerminalSessionAdapter create() {
    final adapter = _SizedAdapter();
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
  collectStats: false,
  collectSystemInfo: false,
  connectionType: 'ssh',
  maidCafeTerminalViaCloud: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Control control;
  late _Factory factory;
  late ProviderContainer container;

  setUp(() {
    control = _Control();
    factory = _Factory();
    container = ProviderContainer(
      overrides: [
        terminalSessionAdapterFactoryProvider.overrideWithValue(factory),
        tmuxSettingsProvider.overrideWithValue(InMemoryTmuxSettings()),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(control.close);
  });

  Future<void> mount() async {
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
    control.layout(_twoPanes);
    await pumpEventQueue();
  }

  test('two side-by-side panes add up to one client width', () async {
    await mount();
    expect(factory.adapters, hasLength(2));
    // Each pane is drawn 80 columns wide in a 160-column session.
    factory.adapters[0].show(80, 40);
    factory.adapters[1].show(80, 40);
    await pumpEventQueue();

    expect(control.resizes.last, 'refresh-client -C 161x40');
    expect(
      control.resizes.where((r) => r == 'refresh-client -C 80x40'),
      isEmpty,
      reason: 'a pane must never resize the whole session to its own half',
    );
  });

  test('a growing pane keeps the session wide enough for both', () async {
    await mount();
    factory.adapters[0].show(80, 40);
    factory.adapters[1].show(80, 40);
    await pumpEventQueue();

    factory.adapters[0].show(100, 40);
    await pumpEventQueue();

    expect(control.resizes.last, 'refresh-client -C 181x40');
  });

  test('a half-known layout sends no extent at all', () async {
    await mount();
    // Only one pane has been laid out; guessing here would resize the session
    // to half what it should be.
    factory.adapters[0].show(80, 40);
    await pumpEventQueue();

    expect(control.resizes, isEmpty);
  });
}
