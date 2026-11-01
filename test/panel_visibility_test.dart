import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:maid_kit/shared/presentation/panel.dart';
import 'package:maid_kit/theme.dart';

/// Geometry of the probe: a focused sheet, a paper gutter and an idle sheet
/// laid side by side, in one [RepaintBoundary] so a single frame can be read
/// back as pixels.
const _probeWidth = 460.0;
const _probeHeight = 200.0;
const _gutterWidth = 40.0;

/// Columns sampled across the idle sheet's left edge, in logical pixels.
const _edgeColumns = [246, 247, 248, 249, 250, 251, 252, 253, 254];

class _Frame {
  _Frame(this._bytes, this._width);

  final List<int> _bytes;
  final int _width;

  List<int> at(int x, int y) {
    final i = (y * _width + x) * 4;
    return [_bytes[i], _bytes[i + 1], _bytes[i + 2]];
  }

  int luminance(int x, int y) {
    final rgb = at(x, y);
    return (rgb[0] * 299 + rgb[1] * 587 + rgb[2] * 114) ~/ 1000;
  }
}

/// Renders one [MaidKitPanel] split: focused on the left, idle on the right,
/// both on the workspace paper.
Future<_Frame> _pumpSplit(WidgetTester tester, Brightness brightness) async {
  tester.view.physicalSize = const Size(_probeWidth, _probeHeight);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final key = GlobalKey();
  final theme = createMaidKitTheme(brightness);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: RepaintBoundary(
        key: key,
        child: ColoredBox(
          // The workspace paper: the tone the tab bar and every page paint.
          color: theme.colorScheme.surfaceContainerLowest,
          child: const Row(
            children: [
              Expanded(
                child: MaidKitPanel(
                  margin: EdgeInsets.zero,
                  child: SizedBox.expand(),
                ),
              ),
              SizedBox(width: _gutterWidth),
              Expanded(
                child: MaidKitPanel(
                  emphasized: false,
                  margin: EdgeInsets.zero,
                  child: SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return (await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final frame = _Frame(data!.buffer.asUint8List(), image.width);
    image.dispose();
    return frame;
  }))!;
}

void main() {
  // A panel's body may paint no surface of its own — the file manager's pane is
  // transparent — so an idle pane has to survive on its own chrome. These
  // probes are the invariant that broke: an idle pane whose tone matched the
  // paper and whose border was none was invisible next to the paper it sat on.
  for (final brightness in Brightness.values) {
    group('an idle panel on the workspace paper (${brightness.name})', () {
      const focusedX = 105;
      const paperX = 230;
      const idleX = 355;
      const midY = 100;

      testWidgets('steps off the paper, leaving the focused pane lit', (
        tester,
      ) async {
        final frame = await _pumpSplit(tester, brightness);
        final focused = frame.luminance(focusedX, midY);
        final paper = frame.luminance(paperX, midY);
        final idle = frame.luminance(idleX, midY);

        // A split reads as one live card on one quiet sheet: the focused pane
        // is the sheet that moves away from the paper, and the two differ
        // enough to tell apart without the edge.
        expect((focused - paper).abs(), greaterThan(6));
        expect((focused - idle).abs(), greaterThan(6));
        // The idle tone is either a step off the paper or the paper itself,
        // never a jump into the lit card's tone.
        expect(
          (idle - paper).abs() < (focused - paper).abs() || idle == paper,
          isTrue,
        );
      });

      testWidgets('keeps a hairline so a borderless body still reads', (
        tester,
      ) async {
        final frame = await _pumpSplit(tester, brightness);
        final paper = frame.luminance(paperX, midY);
        final edge = [
          for (final x in _edgeColumns)
            (frame.luminance(x, midY) - paper).abs(),
        ];

        // The idle sheet's left edge must show a painted line: a pixel that is
        // meaningfully darker or lighter than the paper, not an antialiased
        // whisper of it.
        expect(
          edge.reduce((a, b) => a > b ? a : b),
          greaterThan(12),
          reason: 'idle panel edge must be visible against the paper',
        );
      });
    });
  }
}
