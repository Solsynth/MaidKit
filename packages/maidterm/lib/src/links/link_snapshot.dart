import 'package:flutter/foundation.dart' show immutable, internal, listEquals;
import 'package:libghostty/libghostty.dart' show Position;

import '../foundation/cell_range.dart';
import 'link_match.dart';

/// Link styling state for the visible viewport.
@internal
@immutable
final class LinkSnapshot {
  static const empty = LinkSnapshot([]);

  final List<LinkMatch> matches;
  final CellRange? highlighted;

  const LinkSnapshot(this.matches, {this.highlighted});

  factory LinkSnapshot.highlighted(CellRange range) {
    return LinkSnapshot(const [], highlighted: range);
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(matches), highlighted);

  bool get isEmpty => matches.isEmpty && highlighted == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkSnapshot &&
          listEquals(matches, other.matches) &&
          highlighted == other.highlighted;

  /// Whether [position] is in a link with idle styling.
  bool contains(Position position) {
    return matches.any((match) => match.visibleAt(position));
  }

  /// Whether [position] should use highlighted link styling.
  bool isHighlighted(Position position) {
    final range = highlighted;
    if (range == null) return false;
    if (!range.contains(position)) return false;
    if (matches.isEmpty) return true;
    return matches.any((match) => match.contains(position));
  }

  /// Returns this snapshot with a different highlighted range.
  LinkSnapshot withHighlighted(CellRange? range) {
    if (highlighted == range) return this;
    if (matches.isEmpty && range == null) return empty;
    if (matches.isEmpty && range != null) return .highlighted(range);

    return LinkSnapshot(matches, highlighted: range);
  }
}
