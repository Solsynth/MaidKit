part of '../sprite_face.dart';

final class PowerlineSemicircle extends SpriteGlyph {
  final bool right;
  final bool filled;

  const PowerlineSemicircle({required this.right, required this.filled});

  @override
  void paint(Canvas canvas, Rect cell, SpriteContext ctx) {
    const c = (math.sqrt2 - 1.0) * 4.0 / 3.0;
    final w = cell.width;
    final h = cell.height;
    final r = math.min(w, h / 2);
    final path = ctx.path..reset();

    if (right) {
      path.moveTo(cell.left, cell.top);
      path.cubicTo(
        cell.left + r * c,
        cell.top,
        cell.left + r,
        cell.top + r - r * c,
        cell.left + r,
        cell.top + r,
      );
      path.lineTo(cell.left + r, cell.top + h - r);
      path.cubicTo(
        cell.left + r,
        cell.top + h - r + r * c,
        cell.left + r * c,
        cell.bottom,
        cell.left,
        cell.bottom,
      );
    } else {
      path.moveTo(cell.right, cell.top);
      path.cubicTo(
        cell.right - r * c,
        cell.top,
        cell.right - r,
        cell.top + r - r * c,
        cell.right - r,
        cell.top + r,
      );
      path.lineTo(cell.right - r, cell.top + h - r);
      path.cubicTo(
        cell.right - r,
        cell.top + h - r + r * c,
        cell.right - r * c,
        cell.bottom,
        cell.right,
        cell.bottom,
      );
    }

    if (filled) {
      final fillPath = Path.from(path)..close();
      canvas.drawPath(fillPath, ctx.fill);
      return;
    }

    final clipPath = Path.from(path)..close();
    final thickness = ctx.thickness(cell);
    ctx.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.butt;
    canvas.save();
    canvas.clipPath(clipPath);
    canvas.drawPath(path, ctx.stroke);
    canvas.restore();
  }
}
