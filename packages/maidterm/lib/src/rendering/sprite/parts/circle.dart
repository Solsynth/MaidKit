part of '../sprite_face.dart';

final class Circle extends SpriteGlyph {
  final bool filled;
  final double cx;
  final double cy;
  final double radiusFraction;

  const Circle(this.cx, this.cy, this.radiusFraction, {required this.filled});

  @override
  void paint(Canvas canvas, Rect cell, SpriteContext ctx) {
    final px = cell.left + cx * cell.width;
    final py = cell.top + cy * cell.height;
    final radius = radiusFraction * math.min(cell.width, cell.height);

    if (filled) {
      canvas.drawCircle(Offset(px, py), radius, ctx.fill);
    } else {
      final thickness = ctx.thickness(cell);
      ctx.stroke.strokeWidth = thickness;
      canvas.drawCircle(Offset(px, py), radius - thickness / 2, ctx.stroke);
    }
  }
}
