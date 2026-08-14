import 'dart:typed_data';

import 'package:flterm/flterm.dart' as flterm;
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wheel scrolling in the alternate screen buffer must not be dead.
///
/// TUI programs (vim, less, opencode) render in the alternate screen, which
/// has no scrollback. flterm converts wheel gestures there into input the
/// program understands: cursor keys when no mouse tracking is active, wheel
/// button reports with SGR tracking. This used to break because the scroll
/// position kept its primary-screen 0..0 extents after the screen switch,
/// which made the scrollable refuse wheel events entirely.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Uint8List seq(List<int> bytes) => Uint8List.fromList(bytes);

  Future<
    (
      flterm.TerminalController,
      flterm.TerminalScrollController,
      List<List<int>>,
    )
  >
  pumpTerminal(WidgetTester tester) async {
    final controller = flterm.TerminalController();
    final scroll = flterm.TerminalScrollController();
    final bytes = <List<int>>[];
    controller.onOutput = bytes.add;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: flterm.TerminalView(
              controller: controller,
              scrollController: scroll,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return (controller, scroll, bytes);
  }

  Future<void> enterAlternateScreen(
    flterm.TerminalController controller,
  ) async {
    controller.write(
      seq(const [0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x34, 0x39, 0x68]),
    ); // CSI ? 1049 h
  }

  Future<void> wheel(WidgetTester tester, double dy) async {
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: const Offset(300, 200),
        scrollDelta: Offset(0, dy),
      ),
    );
    await tester.pump();
  }

  List<int> outputs(List<List<int>> bytes) => bytes.expand((b) => b).toList();

  testWidgets('alt screen: wheel up/down emits cursor keys', (tester) async {
    final (controller, scroll, bytes) = await pumpTerminal(tester);
    await enterAlternateScreen(controller);
    for (var i = 0; i < 40; i++) {
      controller.write(seq('line $i\r\n'.codeUnits));
    }
    await tester.pump();

    // The position must have been given alternate-screen extents, otherwise
    // wheel events are clamped dead at 0..0.
    expect(scroll.position.minScrollExtent, isNegative);
    expect(scroll.position.maxScrollExtent, isPositive);

    await wheel(tester, -120); // wheel up
    final upOutputs = outputs(bytes);
    expect(
      upOutputs,
      containsAllInOrder(const [0x1b, 0x5b, 0x41]),
      reason:
          'wheel up in alt screen must emit cursor up, got '
          '${upOutputs.map((b) => b.toRadixString(16))}',
    );

    bytes.clear();
    await wheel(tester, 120); // wheel down
    final downOutputs = outputs(bytes);
    expect(
      downOutputs,
      containsAllInOrder(const [0x1b, 0x5b, 0x42]),
      reason:
          'wheel down in alt screen must emit cursor down, got '
          '${downOutputs.map((b) => b.toRadixString(16))}',
    );
  });

  testWidgets(
    'alt screen: wheel scroll with SGR mouse tracking emits wheel buttons',
    (tester) async {
      final (controller, _, bytes) = await pumpTerminal(tester);
      await enterAlternateScreen(controller);
      // Button-event tracking (1000) + SGR encoding (1006).
      controller.write(
        seq(const [0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x30, 0x68]),
      );
      controller.write(
        seq(const [0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x30, 0x36, 0x68]),
      );
      await tester.pump();
      bytes.clear();

      await wheel(tester, -120); // wheel up
      final all = outputs(bytes);
      final report = String.fromCharCodes(all);
      // SGR wheel up is button code 64 and must retain the wheel location.
      expect(report, contains('\x1b[<64;'));
      expect(
        report,
        isNot(contains(';1;1M')),
        reason: 'wheel reports must not use the fixed origin',
      );
    },
  );

  testWidgets('primary screen: wheel still scrolls scrollback', (tester) async {
    final (controller, scroll, _) = await pumpTerminal(tester);
    for (var i = 0; i < 40; i++) {
      controller.write(seq('line $i\r\n'.codeUnits));
    }
    await tester.pump();

    expect(scroll.position.maxScrollExtent, greaterThan(0));

    await wheel(tester, -120);
    expect(
      scroll.position.pixels,
      greaterThan(0),
      reason: 'wheel up on the primary screen must move into scrollback',
    );
  });
}
