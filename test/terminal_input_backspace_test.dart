import 'package:flterm/flterm.dart' as flterm;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/terminal_color_scheme.dart';
import 'package:maid_kit/servers/terminal_session_adapter.dart';
import 'package:xterm/xterm.dart' as xterm;

/// Android soft keyboards report backspace through the IME, never as a
/// physical-key hardware event. These tests drive both terminal renderers
/// through the exact platform messages an Android IME produces and assert the
/// deletion reaches the shell.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<flterm.TerminalController> pumpFltermTerminal(
    WidgetTester tester,
  ) async {
    final controller = flterm.TerminalController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: flterm.TerminalView(controller: controller),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(flterm.TerminalView));
    await tester.pump();
    return controller;
  }

  testWidgets('flterm: full-value IME backspace reaches the shell', (
    tester,
  ) async {
    final controller = await pumpFltermTerminal(tester);
    final bytes = <List<int>>[];
    controller.onOutput = bytes.add;

    // IME buffer after sentinel (' ') + typed 'l': ' l'.
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: ' l',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump();

    // Backspace deletes the sentinel: buffer becomes ''.
    tester.testTextInput.updateEditingValue(
      TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0)),
    );
    await tester.pump();

    final all = bytes.expand((b) => b).toList();
    expect(all, contains(0x6c), reason: 'typed character must reach the shell');
    expect(
      all,
      contains(0x7f),
      reason:
          'backspace must reach the shell, got ${all.map((b) => b.toRadixString(16))}',
    );
  });

  testWidgets('flterm: delta-model backspace reaches the shell', (
    tester,
  ) async {
    final controller = await pumpFltermTerminal(tester);
    final bytes = <List<int>>[];
    controller.onOutput = bytes.add;

    // Type 'l' via delta insertion on sentinel ' '.
    await _sendDelta(tester, {
      'oldText': ' ',
      'deltaStart': 1,
      'deltaEnd': 1,
      'deltaText': 'l',
      'composingBase': -1,
      'composingExtent': -1,
      'selectionBase': 2,
      'selectionExtent': 2,
    });

    // Backspace via deletion delta ' ' -> ''.
    await _sendDelta(tester, {
      'oldText': ' ',
      'deltaStart': 0,
      'deltaEnd': 1,
      'deltaText': '',
      'composingBase': -1,
      'composingExtent': -1,
      'selectionBase': 0,
      'selectionExtent': 0,
    });

    final all = bytes.expand((b) => b).toList();
    expect(all, contains(0x6c), reason: 'typed character must reach the shell');
    expect(all, contains(0x7f), reason: 'deletion delta must reach the shell');
  });

  testWidgets('flterm: IME key events without a physical key are mapped', (
    tester,
  ) async {
    final controller = await pumpFltermTerminal(tester);
    final bytes = <List<int>>[];
    controller.onOutput = bytes.add;

    // Soft keyboards synthesize backspace as a raw key event with scanCode 0
    // (no physical key). Dispatch a KeyMessage through the focus system, the
    // same path the engine's raw key events take.
    final keyEvent = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey(0),
      logicalKey: LogicalKeyboardKey.backspace,
      timeStamp: const Duration(milliseconds: 1),
    );
    // The engine delivers Android raw key events through this deprecated
    // KeyMessage path (see FocusManager.handleKeyMessage); it is the only way
    // to synthesize the physicalKey-less events soft keyboards produce.
    // ignore: deprecated_member_use
    ServicesBinding.instance.keyEventManager.keyMessageHandler?.call(
      // ignore: deprecated_member_use
      KeyMessage(<KeyEvent>[keyEvent], null),
    );
    await tester.pump();

    final all = bytes.expand((b) => b).toList();
    expect(
      all,
      contains(0x7f),
      reason:
          'IME backspace key event must reach the shell, got ${all.map((b) => b.toRadixString(16))}',
    );
  });

  testWidgets('xterm: IME backspace reaches the shell via delete detection', (
    tester,
  ) async {
    final adapter = XtermTerminalSessionAdapter(
      colorScheme: TerminalColorSchemes.defaultScheme,
    );
    addTearDown(adapter.dispose);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: adapter.buildView())),
    );
    await tester.tap(find.byType(xterm.TerminalView));
    await tester.pump();
    // xterm arms a 300ms double-tap timer on tap; let it expire so the test
    // does not end with a pending timer.
    await tester.pump(const Duration(milliseconds: 350));

    // deleteDetection keeps a two-space sentinel in the IME buffer.
    final view = tester.widget<xterm.TerminalView>(
      find.byType(xterm.TerminalView),
    );
    expect(view.deleteDetection, isTrue, reason: 'mobile must enable the flag');

    final output = StringBuffer();
    view.terminal.onOutput = output.write;

    // IME buffer after sentinel ('  ') + typed 'l': '  l'.
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: '  l',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    await tester.pump();

    // Backspace deletes one sentinel char: buffer becomes ' '.
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: ' ',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();

    expect(output.toString(), contains('l'));
    expect(
      output.toString().codeUnits,
      contains(0x7f),
      reason:
          'backspace must reach the shell, got ${output.toString().codeUnits}',
    );
  });
}

Future<void> _sendDelta(WidgetTester tester, Map<String, dynamic> delta) async {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.handlePlatformMessage(
    SystemChannels.textInput.name,
    SystemChannels.textInput.codec.encodeMethodCall(
      MethodCall('TextInputClient.updateEditingStateWithDeltas', <dynamic>[
        // -1 is the magic test client id accepted in debug builds.
        -1,
        <String, dynamic>{
          'deltas': [delta],
        },
      ]),
    ),
    (ByteData? data) {},
  );
  await tester.pump();
}
