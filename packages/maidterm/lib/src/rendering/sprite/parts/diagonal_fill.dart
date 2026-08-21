part of '../sprite_face.dart';

final class DiagonalFill extends SpriteGlyph {
  final bool topLeftToBottomRight;

  const DiagonalFill({required this.topLeftToBottomRight});

  @override
  void paint(Canvas canvas, Rect cell, SpriteContext ctx) {
    final thickness = ctx.thickness(cell);
    final w = cell.width;
    final h = cell.height;
    final lineCount = (w / (2 * thickness)).floor();
    if (lineCount == 0) return;

    final stride = (w / lineCount).roundToDouble();

    ctx.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.butt;

    for (var i = -lineCount; i <= lineCount; i++) {
      if (topLeftToBottomRight) {
        final topX = i * stride;
        canvas.drawLine(
          Offset(cell.left + topX, cell.top),
          Offset(cell.left + topX + h, cell.bottom),
          ctx.stroke,
        );
      } else {
        final topX = w + i * stride;
        canvas.drawLine(
          Offset(cell.left + topX, cell.top),
          Offset(cell.left + topX - h, cell.bottom),
          ctx.stroke,
        );
      }
    }
  }
}
