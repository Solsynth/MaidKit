part of '../sprite_face.dart';

final class StrokedPolygon extends SpriteGlyph {
  final bool closed;
  final List<(double, double)> vertices;

  const StrokedPolygon(this.vertices, {this.closed = true});

  @override
  void paint(Canvas canvas, Rect cell, SpriteContext ctx) {
    final w = cell.width;
    final h = cell.height;
    final thickness = ctx.thickness(cell);
    final path = ctx.path;
    path.reset();

    var first = true;
    for (final (vx, vy) in vertices) {
      final px = cell.left + vx * w;
      final py = cell.top + vy * h;
      if (first) {
        path.moveTo(px, py);
        first = false;
      } else {
        path.lineTo(px, py);
      }
    }
    if (closed) {
      path.close();
      ctx.stroke
        ..strokeWidth = thickness * 2
        ..strokeCap = StrokeCap.butt;
      canvas.save();
      canvas.clipPath(path);
      canvas.drawPath(path, ctx.stroke);
      canvas.restore();
      return;
    }

    ctx.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.butt;
    canvas.drawPath(path, ctx.stroke);
  }
}
