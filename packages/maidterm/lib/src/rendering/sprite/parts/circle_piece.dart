part of '../sprite_face.dart';

final class CirclePiece extends SpriteGlyph {
  final int corner;
  final double x;
  final double y;
  final double w;
  final double h;

  const CirclePiece(this.x, this.y, this.w, this.h, this.corner);

  @override
  void paint(Canvas canvas, Rect cell, SpriteContext ctx) {
    final width = cell.width * w;
    final height = cell.height * h;
    final xp = cell.width * x;
    final yp = cell.height * y;
    final thickness = ctx.thickness(cell);
    final halfThickness = thickness * 0.5;
    const control = (math.sqrt2 - 1.0) * 4.0 / 3.0;
    final cw = control * width;
    final ch = control * height;
    final ox = cell.left;
    final oy = cell.top;
    final path = ctx.path;

    path.reset();
    switch (corner) {
      case 0:
        path.moveTo(ox + width - xp, oy + halfThickness - yp);
        path.cubicTo(
          ox + width - cw - xp,
          oy + halfThickness - yp,
          ox + halfThickness - xp,
          oy + height - ch - yp,
          ox + halfThickness - xp,
          oy + height - yp,
        );
      case 1:
        path.moveTo(ox + width - xp, oy + halfThickness - yp);
        path.cubicTo(
          ox + width + cw - xp,
          oy + halfThickness - yp,
          ox + width * 2 - halfThickness - xp,
          oy + height - ch - yp,
          ox + width * 2 - halfThickness - xp,
          oy + height - yp,
        );
      case 2:
        path.moveTo(ox + halfThickness - xp, oy + height - yp);
        path.cubicTo(
          ox + halfThickness - xp,
          oy + height + ch - yp,
          ox + width - cw - xp,
          oy + height * 2 - halfThickness - yp,
          ox + width - xp,
          oy + height * 2 - halfThickness - yp,
        );
      case 3:
        path.moveTo(ox + width * 2 - halfThickness - xp, oy + height - yp);
        path.cubicTo(
          ox + width * 2 - halfThickness - xp,
          oy + height + ch - yp,
          ox + width + cw - xp,
          oy + height * 2 - halfThickness - yp,
          ox + width - xp,
          oy + height * 2 - halfThickness - yp,
        );
      default:
        throw ArgumentError.value(corner, 'corner');
    }

    ctx.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.butt;
    canvas.drawPath(path, ctx.stroke);
  }
}
