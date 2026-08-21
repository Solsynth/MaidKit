part of '../sprite_face.dart';

final class GridFill extends SpriteGlyph {
  final bool separated;
  final int columns;
  final int rows;
  final int pattern;

  const GridFill(
    this.columns,
    this.rows,
    this.pattern, {
    this.separated = false,
  });

  @override
  void paint(Canvas canvas, Rect cell, SpriteContext ctx) {
    final w = cell.width;
    final h = cell.height;
    final gap = separated ? ctx.thickness(cell) / 2 : 0.0;

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < columns; col++) {
        final bit = row * columns + col;
        if (pattern & (1 << bit) == 0) continue;

        drawBox(
          canvas,
          ctx.fill,
          cell.left + (w * col / columns).roundToDouble() + gap,
          cell.top + (h * row / rows).roundToDouble() + gap,
          cell.left + (w * (col + 1) / columns).roundToDouble() - gap,
          cell.top + (h * (row + 1) / rows).roundToDouble() - gap,
        );
      }
    }
  }
}
