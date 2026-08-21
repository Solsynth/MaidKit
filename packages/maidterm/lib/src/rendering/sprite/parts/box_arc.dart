part of '../sprite_face.dart';

final class BoxArc extends SpriteGlyph {
  final int corner;

  const BoxArc(this.corner);

  @override
  void paint(Canvas canvas, Rect cell, SpriteContext ctx) {
    drawArc(canvas, ctx.stroke, ctx.path, corner, cell, ctx.thickness(cell));
  }
}
