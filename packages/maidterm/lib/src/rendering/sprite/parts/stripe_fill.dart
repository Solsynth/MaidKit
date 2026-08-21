part of '../sprite_face.dart';

final class StripeFill extends SpriteGlyph {
  const StripeFill();

  @override
  void paint(Canvas canvas, Rect cell, SpriteContext ctx) {
    final h = cell.height;
    final q1 = (h / 4).roundToDouble();
    final q2 = (h / 2).roundToDouble();
    final q3 = (h * 3 / 4).roundToDouble();

    drawBox(
      canvas,
      ctx.fill,
      cell.left,
      cell.top + q1,
      cell.right,
      cell.top + q2,
    );
    drawBox(
      canvas,
      ctx.fill,
      cell.left,
      cell.top + q3,
      cell.right,
      cell.bottom,
    );
  }
}
