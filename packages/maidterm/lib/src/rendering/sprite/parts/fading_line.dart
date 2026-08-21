part of '../sprite_face.dart';

final class FadingLine extends SpriteGlyph {
  final int direction;

  const FadingLine(this.direction);

  @override
  void paint(Canvas canvas, Rect cell, SpriteContext ctx) {
    final thickness = ctx.thickness(cell);
    final color = ctx.fill.color;
    final w = cell.width;
    final h = cell.height;
    final hTop = (h - thickness) / 2;
    final vLeft = (w - thickness) / 2;

    if (direction == 0 || direction == 2) {
      final steps = h.toInt();
      for (var i = 0; i < steps; i++) {
        final fraction = i / steps;
        final alpha = direction == 0 ? 1.0 - fraction : fraction;
        ctx.fill.color = color.withValues(alpha: alpha);
        drawBox(
          canvas,
          ctx.fill,
          cell.left + vLeft,
          cell.top + i,
          cell.left + vLeft + thickness,
          cell.top + i + 1,
        );
      }
    } else {
      final steps = w.toInt();
      for (var i = 0; i < steps; i++) {
        final fraction = i / steps;
        final alpha = direction == 1 ? 1.0 - fraction : fraction;
        ctx.fill.color = color.withValues(alpha: alpha);
        drawBox(
          canvas,
          ctx.fill,
          cell.left + i,
          cell.top + hTop,
          cell.left + i + 1,
          cell.top + hTop + thickness,
        );
      }
    }

    ctx.fill.color = color;
  }
}
