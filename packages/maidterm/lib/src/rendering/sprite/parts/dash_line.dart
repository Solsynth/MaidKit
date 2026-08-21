part of '../sprite_face.dart';

final class DashLine extends SpriteGlyph {
  final int count;
  final bool heavy;
  final bool horizontal;

  const DashLine({
    required this.horizontal,
    required this.count,
    this.heavy = false,
  });

  @override
  void paint(Canvas canvas, Rect cell, SpriteContext ctx) {
    final thickness = heavy ? ctx.heavyThickness(cell) : ctx.thickness(cell);
    final gap = math.max(4.0, ctx.thickness(cell));

    if (horizontal) {
      drawDashHorizontal(canvas, ctx.fill, count, thickness, gap, cell);
    } else {
      drawDashVertical(canvas, ctx.fill, count, thickness, gap, cell);
    }
  }
}
