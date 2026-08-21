import 'package:flutter/foundation.dart' show immutable, internal;
import 'package:libghostty/libghostty.dart' show PointTag, Position;

/// Inclusive range of terminal cells in one coordinate space.
///
/// ```dart
/// final range = CellRange(
///   start: const Position(row: 2, col: 4),
///   end: const Position(row: 2, col: 12),
/// );
///
/// final inside = range.contains(const Position(row: 2, col: 8));
/// ```
@immutable
final class CellRange {
  /// First cell in the range.
  final Position start;

  /// Last cell in the range.
  final Position end;

  /// Coordinate space used by [start] and [end].
  final PointTag pointTag;

  const CellRange({
    required this.start,
    required this.end,
    this.pointTag = .viewport,
  });

  @override
  int get hashCode => Object.hash(start, end, pointTag);

  /// Whether [start] and [end] are on the same terminal row.
  bool get isSingleRow => start.row == end.row;

  @internal
  int get sortLength => isSingleRow ? end.col - start.col + 1 : 1 << 20;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CellRange &&
          start == other.start &&
          end == other.end &&
          pointTag == other.pointTag;

  /// Whether [position] is inside this inclusive range.
  bool contains(Position position) {
    if (position.row < start.row || position.row > end.row) return false;
    if (position.row == start.row && position.col < start.col) return false;
    if (position.row == end.row && position.col > end.col) return false;
    return true;
  }

  /// Whether this range intersects [other].
  bool overlaps(CellRange other) {
    if (pointTag != other.pointTag) return false;
    if (start.row > other.end.row || other.start.row > end.row) return false;
    for (var row = start.row; row <= end.row; row++) {
      final thisStart = row == start.row ? start.col : 0;
      final thisEnd = row == end.row ? end.col : 1 << 30;
      final otherStart = row == other.start.row ? other.start.col : 0;
      final otherEnd = row == other.end.row ? other.end.col : 1 << 30;
      if (thisStart <= otherEnd && otherStart <= thisEnd) return true;
    }
    return false;
  }
}
