part of '../sprite_face.dart';

final class CornerDiagonalLines extends SpriteGlyph {
  final bool tl;
  final bool tr;
  final bool bl;
  final bool br;

  const CornerDiagonalLines({
    this.tl = false,
    this.tr = false,
    this.bl = false,
    this.br = false,
  });

  @override
  void paint(Canvas canvas, Rect cell, SpriteContext ctx) {
    final thickness = ctx.thickness(cell);
    final centerX = cell.left + (cell.width / 2).ceilToDouble();
    final centerY = cell.top + (cell.height / 2).ceilToDouble();

    ctx.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.butt;

    if (tl) {
      canvas.drawLine(
        Offset(centerX, cell.top),
        Offset(cell.left, centerY),
        ctx.stroke,
      );
    }
    if (tr) {
      canvas.drawLine(
        Offset(centerX, cell.top),
        Offset(cell.right, centerY),
        ctx.stroke,
      );
    }
    if (bl) {
      canvas.drawLine(
        Offset(centerX, cell.bottom),
        Offset(cell.left, centerY),
        ctx.stroke,
      );
    }
    if (br) {
      canvas.drawLine(
        Offset(centerX, cell.bottom),
        Offset(cell.right, centerY),
        ctx.stroke,
      );
    }
  }
}
