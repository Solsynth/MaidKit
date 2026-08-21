import 'dart:ui';

import 'package:libghostty/libghostty.dart' show Position;
import 'package:meta/meta.dart';

/// Pixel dimensions of a single terminal cell, derived from font metrics.
///
/// Used throughout the rendering and gesture layers to convert between
/// pixel coordinates and cell grid positions. All values are in logical
/// pixels (pre device-pixel-ratio). Recalculated when the theme's font
/// family or size changes, which triggers a layout pass on the
/// [TerminalView].
///
/// ```dart
/// const metrics = CellMetrics(
///   cellWidth: 8.0,
///   cellHeight: 17.0,
///   baseline: 13.0,
/// );
/// final (cols, rows) = metrics.gridSize(width, height);
/// final rect = metrics.cellRect(const Position(row: 3, col: 10), .zero);
/// ```
@immutable
final class CellMetrics {
  /// Width of one character cell in logical pixels.
  final double cellWidth;

  /// Height of one character cell in logical pixels.
  ///
  /// Equal to the full typographic line height snapped to the device pixel
  /// grid. All backgrounds, cursors, selections, and decorations use this
  /// height.
  final double cellHeight;

  /// Distance from the top of the cell to the alphabetic baseline.
  ///
  /// Used by text painters to vertically position glyphs within the cell.
  final double baseline;

  /// Distance from the top of the cell to the top of the underline.
  ///
  /// Derived from the font's underline position metric (from the `post`
  /// table), converted to a top-of-cell coordinate. Falls back to one
  /// underline thickness below the baseline.
  final double underlinePosition;

  /// Thickness of underline and overline decorations in logical pixels.
  ///
  /// Derived from the font's underline thickness metric, with a minimum
  /// of 1 pixel. Also used for overline thickness.
  final double underlineThickness;

  /// Distance from the top of the cell to the top of the strikethrough.
  ///
  /// Derived from the font's strikethrough position metric (from the
  /// `OS/2` table), or estimated as centered on the ex-height.
  final double strikethroughPosition;

  /// Thickness of the strikethrough decoration in logical pixels.
  ///
  /// Derived from the font's strikethrough size metric, with a minimum
  /// of 1 pixel. Falls back to the underline thickness.
  final double strikethroughThickness;

  /// Distance from the top of the cell to the top of the overline.
  ///
  /// Always 0 (top of cell).
  final double overlinePosition;

  const CellMetrics({
    required this.cellWidth,
    required this.cellHeight,
    required this.baseline,
    this.underlinePosition = 0,
    this.underlineThickness = 1,
    this.strikethroughPosition = 0,
    this.strikethroughThickness = 1,
    this.overlinePosition = 0,
  }) : assert(cellWidth >= 0, 'cellWidth must be non-negative'),
       assert(cellHeight >= 0, 'cellHeight must be non-negative'),
       assert(baseline >= 0, 'baseline must be non-negative');

  @override
  int get hashCode => Object.hash(
    cellWidth,
    cellHeight,
    baseline,
    underlinePosition,
    underlineThickness,
    strikethroughPosition,
    strikethroughThickness,
    overlinePosition,
  );

  @override
  bool operator ==(Object other) =>
      other is CellMetrics &&
      other.cellWidth == cellWidth &&
      other.cellHeight == cellHeight &&
      other.baseline == baseline &&
      other.underlinePosition == underlinePosition &&
      other.underlineThickness == underlineThickness &&
      other.strikethroughPosition == strikethroughPosition &&
      other.strikethroughThickness == strikethroughThickness &&
      other.overlinePosition == overlinePosition;

  /// Converts a pixel [position] to terminal cell coordinates.
  ///
  /// Returns `(0, 0)` for any axis where the cell dimension is zero.
  /// The position is not clamped to the grid, so callers should bounds-check
  /// the result against the terminal dimensions.
  Position cellAt(Offset position) {
    final row = cellHeight > 0 ? (position.dy / cellHeight).floor() : 0;
    final col = cellWidth > 0 ? (position.dx / cellWidth).floor() : 0;
    return Position(row: row, col: col);
  }

  /// Returns the pixel rect for a horizontal range of cells on [row].
  ///
  /// [startCol] is inclusive, [endCol] is exclusive. The [offset] is added
  /// to position the rect within the parent coordinate space (e.g., padding).
  Rect cellRangeRect(int row, int startCol, int endCol, Offset offset) {
    return Rect.fromLTWH(
      offset.dx + startCol * cellWidth,
      offset.dy + row * cellHeight,
      (endCol - startCol) * cellWidth,
      cellHeight,
    );
  }

  /// Returns the pixel rect for a single cell at ([row], [col]).
  Rect cellRect(Position position, Offset offset) {
    return cellRangeRect(position.row, position.col, position.col + 1, offset);
  }

  /// Computes how many columns and rows fit in the given pixel dimensions.
  (int cols, int rows) gridSize(double width, double height) {
    final cols = cellWidth > 0 ? (width / cellWidth).floor() : 0;
    final rows = cellHeight > 0 ? (height / cellHeight).floor() : 0;
    return (cols, rows);
  }

  @override
  String toString() =>
      'CellMetrics(cellWidth: $cellWidth, '
      'cellHeight: $cellHeight, baseline: $baseline)';
}
