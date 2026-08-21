part of '../sprite_face.dart';

final class BoxStub extends SpriteGlyph {
  final bool top;
  final bool right;
  final bool heavy;

  const BoxStub({required this.top, required this.right, this.heavy = false});

  @override
  void paint(Canvas canvas, Rect cell, SpriteContext ctx) {
    final thickness = heavy ? ctx.heavyThickness(cell) : ctx.thickness(cell);
    final w = cell.width;
    final h = cell.height;
    final ox = cell.left;
    final oy = cell.top;
    final half = w / 2;

    final vLeft = ox + (w - thickness) / 2;
    final vRight = vLeft + thickness;
    drawBox(canvas, ctx.fill, vLeft, oy, vRight, oy + h);

    final barTop = top ? oy : oy + h - thickness;
    final barBottom = barTop + thickness;
    final barLeft = right ? ox + half : ox;
    final barRight = right ? ox + w : ox + half;
    drawBox(canvas, ctx.fill, barLeft, barTop, barRight, barBottom);
  }
}
