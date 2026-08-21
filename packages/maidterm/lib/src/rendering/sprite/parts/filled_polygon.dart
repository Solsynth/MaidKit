part of '../sprite_face.dart';

final class FilledPolygon extends SpriteGlyph {
  final double alpha;
  final bool inverted;
  final List<(double, double)> vertices;

  const FilledPolygon(this.vertices, {this.alpha = 1.0, this.inverted = false});

  @override
  void paint(Canvas canvas, Rect cell, SpriteContext ctx) {
    final originalColor = ctx.fill.color;
    if (alpha < 1.0) ctx.fill.color = originalColor.withValues(alpha: alpha);

    final w = cell.width;
    final h = cell.height;
    final path = ctx.path;
    path.reset();

    var first = true;
    for (final (vx, vy) in vertices) {
      final px = (cell.left + vx * w).roundToDouble();
      final py = (cell.top + vy * h).roundToDouble();
      if (first) {
        path.moveTo(px, py);
        first = false;
      } else {
        path.lineTo(px, py);
      }
    }
    path.close();

    if (inverted) {
      path.addRect(cell);
      path.fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(path, ctx.fill);
    path.fillType = PathFillType.nonZero;
    if (alpha < 1.0) ctx.fill.color = originalColor;
  }
}
