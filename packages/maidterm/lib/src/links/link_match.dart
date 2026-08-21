import 'package:flutter/foundation.dart' show immutable, internal;
import 'package:libghostty/libghostty.dart' show Position;

import 'link_settings.dart';

/// A detected link candidate before overlap resolution.
///
/// Detectors can report more than one match for the same cells. Priority,
/// length, and source order decide which candidate survives.
@internal
@immutable
final class LinkMatch {
  final int priority;
  final bool hoverOnly;

  /// Stable tie-breaker for otherwise equivalent matches.
  ///
  /// Lower values win.
  final int sourceOrder;
  final ActivatedLink link;

  const LinkMatch({
    required this.link,
    required this.priority,
    required this.hoverOnly,
    required this.sourceOrder,
  });

  @override
  int get hashCode => Object.hash(priority, hoverOnly, sourceOrder, link);

  int get length => link.range.sortLength;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkMatch &&
          priority == other.priority &&
          hoverOnly == other.hoverOnly &&
          sourceOrder == other.sourceOrder &&
          link == other.link;

  bool contains(Position position) => link.range.contains(position);

  bool overlaps(LinkMatch other) {
    return link.range.overlaps(other.link.range);
  }

  bool visibleAt(Position position) => contains(position) && !hoverOnly;

  /// Chooses the strongest non-overlapping matches from [matches].
  static List<LinkMatch> resolveOverlaps(List<LinkMatch> matches) {
    final result = <LinkMatch>[];
    final sorted = [...matches]..sort(_compare);
    for (final match in sorted) {
      if (result.any((existing) => existing.overlaps(match))) continue;
      result.add(match);
    }
    return result;
  }

  static int _compare(LinkMatch a, LinkMatch b) {
    final byPriority = b.priority.compareTo(a.priority);
    if (byPriority != 0) return byPriority;
    final byLength = b.length.compareTo(a.length);
    if (byLength != 0) return byLength;
    final bySourceOrder = a.sourceOrder.compareTo(b.sourceOrder);
    if (bySourceOrder != 0) return bySourceOrder;
    final byRow = a.link.range.start.row.compareTo(b.link.range.start.row);
    if (byRow != 0) return byRow;
    return a.link.range.start.col.compareTo(b.link.range.start.col);
  }
}
