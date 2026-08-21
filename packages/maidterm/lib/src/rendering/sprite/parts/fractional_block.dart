part of '../sprite_face.dart';

final class FractionalBlock extends SpriteGlyph {
  final double alpha;
  final double x0;
  final double y0;
  final double x1;
  final double y1;

  const FractionalBlock(this.x0, this.y0, this.x1, this.y1, {this.alpha = 1.0});

  @override
  void paint(Canvas canvas, Rect cell, SpriteContext ctx) {
    final originalColor = ctx.fill.color;
    if (alpha < 1.0) {
      ctx.fill.color = originalColor.withValues(alpha: alpha);
    }
    final w = cell.width;
    final h = cell.height;
    drawBox(
      canvas,
      ctx.fill,
      cell.left + (w * x0).roundToDouble(),
      cell.top + (h * y0).roundToDouble(),
      cell.left + (w * x1).roundToDouble(),
      cell.top + (h * y1).roundToDouble(),
    );
    if (alpha < 1.0) {
      ctx.fill.color = originalColor;
    }
  }
}
