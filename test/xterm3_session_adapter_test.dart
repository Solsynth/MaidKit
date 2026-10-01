import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:maid_kit/servers/terminal_session_adapter.dart';
import 'package:maid_kit/servers/xterm3_session_adapter.dart';

void main() {
  Xterm3SessionAdapter createAdapter({
    bool cursorAnimationEnabled = true,
    bool keywordHighlightEnabled = true,
  }) {
    final adapter = Xterm3SessionAdapter(
      cursorAnimationEnabled: cursorAnimationEnabled,
      keywordHighlightEnabled: keywordHighlightEnabled,
    );
    addTearDown(adapter.dispose);
    return adapter;
  }

  Widget harness(
    TerminalSessionAdapter adapter, {
    bool showCursor = true,
    bool readOnly = false,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 900,
          height: 500,
          child: adapter.buildView(showCursor: showCursor, readOnly: readOnly),
        ),
      ),
    ),
  );

  test('remote output reaches the buffer and never echoes back', () async {
    final adapter = createAdapter();
    final outgoing = <Uint8List>[];
    final subscription = adapter.outgoingBytes.listen(outgoing.add);
    addTearDown(subscription.cancel);

    adapter.write(Uint8List.fromList(utf8.encode('total 4\r\nfile.txt\r\n')));
    await pumpEventQueue();

    expect(adapter.dumpHistory(), contains('file.txt'));
    expect(outgoing, isEmpty);
  });

  test('a UTF-8 sequence split across reads is decoded once', () {
    final adapter = createAdapter();
    // One byte per read is the worst case a socket can produce.
    for (final byte in utf8.encode('héllo 🚀')) {
      adapter.write(Uint8List.fromList([byte]));
    }

    final history = adapter.dumpHistory();
    expect(history, contains('héllo 🚀'));
    expect(history, isNot(contains('\uFFFD')));
  });

  test('replayed scrollback never reaches the shell', () async {
    final adapter = createAdapter();
    final outgoing = <Uint8List>[];
    final subscription = adapter.outgoingBytes.listen(outgoing.add);
    addTearDown(subscription.cancel);

    adapter.replayHistory('previous output\r\n');

    expect(adapter.dumpHistory(), contains('previous output'));
    expect(adapter.isTaskRunning, isFalse);
    expect(outgoing, isEmpty);
  });

  test(
    'typed input is encoded for the shell and marks the task running',
    () async {
      final adapter = createAdapter();
      final outgoing = <Uint8List>[];
      final subscription = adapter.outgoingBytes.listen(outgoing.add);
      addTearDown(subscription.cancel);

      adapter.sendInput('ls\r');
      await pumpEventQueue();

      expect(utf8.decode(outgoing.single), 'ls\r');
      expect(adapter.isTaskRunning, isTrue);

      adapter.write(
        Uint8List.fromList(utf8.encode('file.txt\r\nuser@host:~\$ ')),
      );

      expect(adapter.isTaskRunning, isFalse);
    },
  );

  test('history capture keeps only the requested trailing lines', () {
    final adapter = createAdapter();
    final output = [for (var i = 0; i < 40; i++) 'line $i'].join('\r\n');
    adapter.write(Uint8List.fromList(utf8.encode('$output\r\n')));

    final lines = adapter.dumpHistory(maxLines: 5)!.split('\n');

    expect(lines, hasLength(5));
    expect(lines.last, 'line 39');
  });

  test('OSC 7 reports the shell working directory', () {
    final adapter = createAdapter();

    adapter.write(
      Uint8List.fromList(utf8.encode('\x1b]7;file:///srv/app\x07')),
    );

    expect(adapter.currentDirectory, '/srv/app');
  });

  test('a bound autofill stream drives the sudo hint reason', () async {
    final adapter = createAdapter();
    final reasons = StreamController<SudoPromptReason?>();
    addTearDown(reasons.close);
    adapter.bindSudoAutofill(reasons.stream);

    reasons.add(SudoPromptReason.prompt);
    await pumpEventQueue();

    expect(adapter.sudoAutofillReady, SudoPromptReason.prompt);
  });

  test('find counts scrollback matches and honours case sensitivity', () {
    final adapter = createAdapter();
    adapter.write(
      Uint8List.fromList(
        utf8.encode('needle one\r\nplain\r\nneedle two\r\nNEEDLE three\r\n'),
      ),
    );

    expect(adapter.find('needle'), 3);
    expect(adapter.find('needle', caseSensitive: true), 2);

    adapter.findJump(1);
    adapter.findClear();
    expect(adapter.find(''), 0);
  });

  testWidgets('mounted view reports its grid size to the shell', (
    tester,
  ) async {
    final adapter = createAdapter();
    final resizes = <TerminalResize>[];
    final subscription = adapter.resizeEvents.listen(resizes.add);
    addTearDown(subscription.cancel);

    await tester.pumpWidget(harness(adapter));
    await tester.pump();

    expect(resizes, isNotEmpty);
    final last = resizes.last;
    expect(last.columns, greaterThan(0));
    expect(last.rows, greaterThan(0));
    expect(last.pixelWidth, greaterThan(0));
    expect(last.pixelHeight, greaterThan(0));

    // Let the deferred tint pass run so no timer outlives the widget tree.
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('log surfaces hide the caret and the preference drives blink', (
    tester,
  ) async {
    final animated = createAdapter(cursorAnimationEnabled: true);
    await tester.pumpWidget(harness(animated));
    await tester.pump();
    await tester.pump();

    expect(animated.debugTerminal.cursorBlinkMode, isTrue);
    expect(animated.debugTerminal.cursorVisibleMode, isTrue);

    final logSurface = createAdapter(cursorAnimationEnabled: false);
    await tester.pumpWidget(harness(logSurface, showCursor: false));
    await tester.pump();
    await tester.pump();

    expect(logSurface.debugTerminal.cursorBlinkMode, isFalse);
    expect(logSurface.debugTerminal.cursorVisibleMode, isFalse);

    // Let the deferred tint passes run so no timer outlives the widget tree.
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('keyword matches in the visible rows are tinted', (tester) async {
    final adapter = createAdapter();
    await tester.pumpWidget(harness(adapter));
    await tester.pump();

    adapter.write(
      Uint8List.fromList(utf8.encode('build failed: permission denied\r\n')),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(adapter.debugKeywordHighlightCount, greaterThan(0));
  });

  testWidgets('plain output leaves the buffer untinted', (tester) async {
    final adapter = createAdapter();
    await tester.pumpWidget(harness(adapter));
    await tester.pump();

    adapter.write(Uint8List.fromList(utf8.encode('every line is fine\r\n')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(adapter.debugKeywordHighlightCount, 0);
  });
}
