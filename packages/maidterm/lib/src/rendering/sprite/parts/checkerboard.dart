part of '../sprite_face.dart';

final class Checkerboard extends SpriteGlyph {
  final bool inverted;

  const Checkerboard({this.inverted = false});

  @override
  void paint(Canvas canvas, Rect cell, SpriteContext ctx) {
    final w = cell.width;
    final h = cell.height;
    final ySize = (4 * (h / w)).round();
    const xSize = 4;

    for (var yi = 0; yi < ySize; yi++) {
      for (var xi = 0; xi < xSize; xi++) {
        final fill = (xi + yi) % 2 == (inverted ? 1 : 0);
        if (!fill) continue;
        drawBox(
          canvas,
          ctx.fill,
          cell.left + (w * xi / xSize).roundToDouble(),
          cell.top + (h * yi / ySize).roundToDouble(),
          cell.left + (w * (xi + 1) / xSize).roundToDouble(),
          cell.top + (h * (yi + 1) / ySize).roundToDouble(),
        );
      }
    }
  }
}
