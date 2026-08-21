import 'dart:ui';

import '../atlas/sprite_buffer.dart';
import 'terminal_painter.dart';

/// Paints paragraph-shaped text runs that need ligature shaping.
final class ShapedRunPainter implements TerminalPainter {
  final ShapedRunBuffer _runs;

  ShapedRunPainter(this._runs);

  @override
  void paint(Canvas canvas) {
    if (_runs.count == 0) return;

    for (final row in _runs.rows) {
      for (final run in row) {
        canvas.save();
        canvas.clipRect(run.clip);
        canvas.drawParagraph(run.paragraph, run.offset);
        canvas.restore();
      }
    }
  }
}
