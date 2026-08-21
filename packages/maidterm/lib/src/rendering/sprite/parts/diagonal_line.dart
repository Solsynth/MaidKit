part of '../sprite_face.dart';

final class DiagonalLine extends SpriteGlyph {
  final bool topLeftToBottomRight;

  const DiagonalLine({required this.topLeftToBottomRight});

  @override
  void paint(Canvas canvas, Rect cell, SpriteContext ctx) {
    final thickness = ctx.thickness(cell);
    final half = thickness / 2;
    final start = topLeftToBottomRight
        ? cell.topLeft
        : Offset(cell.right, cell.top);
    final end = topLeftToBottomRight
        ? cell.bottomRight
        : Offset(cell.left, cell.bottom);
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    final ux = dx / length;
    final uy = dy / length;
    final nx = -uy * half;
    final ny = ux * half;
    // A diagonal stroke has to cross the cell corner so adjacent cells share
    // the same stroke body instead of two separately capped segments.
    final extension = thickness;
    final extendedStart = Offset(
      start.dx - ux * extension,
      start.dy - uy * extension,
    );
    final extendedEnd = Offset(
      end.dx + ux * extension,
      end.dy + uy * extension,
    );

    ctx.path
      ..reset()
      ..moveTo(extendedStart.dx + nx, extendedStart.dy + ny)
      ..lineTo(extendedEnd.dx + nx, extendedEnd.dy + ny)
      ..lineTo(extendedEnd.dx - nx, extendedEnd.dy - ny)
      ..lineTo(extendedStart.dx - nx, extendedStart.dy - ny)
      ..close();

    canvas.drawPath(ctx.path, ctx.fill);
  }
}
