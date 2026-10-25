/// Axis of a session split. [horizontal] places panes left/right;
/// [vertical] places them top/bottom.
enum SessionSplitAxis { horizontal, vertical }

/// Binary tree describing how session panes are arranged on screen.
///
/// Leaves reference **pane** ids (each pane owns its own tab strip).
sealed class SessionLayout {
  const SessionLayout();

  /// Pane ids currently present in this subtree.
  Iterable<String> get paneIds;

  bool containsPane(String paneId) => paneIds.contains(paneId);

  /// Whether this tree has more than one pane.
  bool get isSplit;
}

/// Single pane region.
class SessionLayoutLeaf extends SessionLayout {
  const SessionLayoutLeaf(this.paneId);

  final String paneId;

  @override
  Iterable<String> get paneIds sync* {
    yield paneId;
  }

  @override
  bool get isSplit => false;

  @override
  bool operator ==(Object other) =>
      other is SessionLayoutLeaf && other.paneId == paneId;

  @override
  int get hashCode => paneId.hashCode;
}

/// Two child layouts separated along [axis], with [ratio] of space for [first].
class SessionLayoutSplit extends SessionLayout {
  const SessionLayoutSplit({
    required this.id,
    required this.axis,
    required this.first,
    required this.second,
    this.ratio = 0.5,
  });

  final String id;
  final SessionSplitAxis axis;
  final SessionLayout first;
  final SessionLayout second;

  /// Fraction of the cross-axis space allocated to [first] (0–1).
  final double ratio;

  @override
  Iterable<String> get paneIds sync* {
    yield* first.paneIds;
    yield* second.paneIds;
  }

  @override
  bool get isSplit => true;

  SessionLayoutSplit copyWith({
    SessionSplitAxis? axis,
    SessionLayout? first,
    SessionLayout? second,
    double? ratio,
  }) => SessionLayoutSplit(
    id: id,
    axis: axis ?? this.axis,
    first: first ?? this.first,
    second: second ?? this.second,
    ratio: ratio ?? this.ratio,
  );

  @override
  bool operator ==(Object other) =>
      other is SessionLayoutSplit &&
      other.id == id &&
      other.axis == axis &&
      other.first == first &&
      other.second == second &&
      other.ratio == ratio;

  @override
  int get hashCode => Object.hash(id, axis, first, second, ratio);
}

/// Clamps a split ratio so neither pane collapses.
double clampSplitRatio(double ratio, {double min = 0.15, double max = 0.85}) {
  if (ratio < min) return min;
  if (ratio > max) return max;
  return ratio;
}

/// Exchanges where two panes sit in the tree.
///
/// A pane keeps its id — and with it its content and state — so a drag only
/// changes which slot the layout draws it in. Every split keeps its id, axis
/// and ratio; only the leaves move.
SessionLayout swapPaneSlots(
  SessionLayout layout,
  String firstPaneId,
  String secondPaneId,
) {
  if (firstPaneId == secondPaneId) return layout;
  // A swap names two slots that must both exist: with one of them gone — the
  // pane was closed while the drag was in flight — the tree stays as it is.
  if (!layout.containsPane(firstPaneId) || !layout.containsPane(secondPaneId)) {
    return layout;
  }
  return _swapSlots(layout, firstPaneId, secondPaneId);
}

SessionLayout _swapSlots(
  SessionLayout layout,
  String firstPaneId,
  String secondPaneId,
) {
  switch (layout) {
    case SessionLayoutLeaf(paneId: final paneId):
      if (paneId == firstPaneId) return SessionLayoutLeaf(secondPaneId);
      if (paneId == secondPaneId) return SessionLayoutLeaf(firstPaneId);
      return layout;
    case SessionLayoutSplit(
      id: final id,
      axis: final axis,
      first: final first,
      second: final second,
      ratio: final ratio,
    ):
      final newFirst = _swapSlots(first, firstPaneId, secondPaneId);
      final newSecond = _swapSlots(second, firstPaneId, secondPaneId);
      if (identical(newFirst, first) && identical(newSecond, second)) {
        return layout;
      }
      return SessionLayoutSplit(
        id: id,
        axis: axis,
        first: newFirst,
        second: newSecond,
        ratio: ratio,
      );
  }
}

/// Replaces the leaf for [focusedPaneId] with a split of that leaf and a new
/// leaf for [newPaneId]. Returns the unchanged tree if the focused leaf is
/// not found.
SessionLayout splitPane({
  required SessionLayout layout,
  required String focusedPaneId,
  required String newPaneId,
  required SessionSplitAxis axis,
  required String splitId,
  double ratio = 0.5,
}) {
  switch (layout) {
    case SessionLayoutLeaf(paneId: final leafId):
      if (leafId != focusedPaneId) return layout;
      return SessionLayoutSplit(
        id: splitId,
        axis: axis,
        first: SessionLayoutLeaf(leafId),
        second: SessionLayoutLeaf(newPaneId),
        ratio: clampSplitRatio(ratio),
      );
    case SessionLayoutSplit(
      id: final splitNodeId,
      axis: final splitAxis,
      first: final first,
      second: final second,
      ratio: final splitRatio,
    ):
      return SessionLayoutSplit(
        id: splitNodeId,
        axis: splitAxis,
        first: splitPane(
          layout: first,
          focusedPaneId: focusedPaneId,
          newPaneId: newPaneId,
          axis: axis,
          splitId: splitId,
          ratio: ratio,
        ),
        second: splitPane(
          layout: second,
          focusedPaneId: focusedPaneId,
          newPaneId: newPaneId,
          axis: axis,
          splitId: splitId,
          ratio: ratio,
        ),
        ratio: splitRatio,
      );
  }
}

/// Sets the ratio on the split node with [splitId].
SessionLayout applySplitRatio(
  SessionLayout layout,
  String splitId,
  double ratio,
) {
  final clamped = clampSplitRatio(ratio);
  switch (layout) {
    case SessionLayoutLeaf():
      return layout;
    case SessionLayoutSplit(
      id: final id,
      axis: final axis,
      first: final first,
      second: final second,
      ratio: final currentRatio,
    ):
      if (id == splitId) {
        return SessionLayoutSplit(
          id: id,
          axis: axis,
          first: first,
          second: second,
          ratio: clamped,
        );
      }
      return SessionLayoutSplit(
        id: id,
        axis: axis,
        first: applySplitRatio(first, splitId, clamped),
        second: applySplitRatio(second, splitId, clamped),
        ratio: currentRatio,
      );
  }
}

/// Removes [paneId] from the tree, collapsing splits that lose a child.
/// Returns null when the tree becomes empty.
SessionLayout? removePaneFromLayout(SessionLayout layout, String paneId) {
  switch (layout) {
    case SessionLayoutLeaf(paneId: final leafId):
      return leafId == paneId ? null : layout;
    case SessionLayoutSplit(
      id: final id,
      axis: final axis,
      first: final first,
      second: final second,
      ratio: final ratio,
    ):
      final newFirst = removePaneFromLayout(first, paneId);
      final newSecond = removePaneFromLayout(second, paneId);
      if (newFirst == null) return newSecond;
      if (newSecond == null) return newFirst;
      return SessionLayoutSplit(
        id: id,
        axis: axis,
        first: newFirst,
        second: newSecond,
        ratio: ratio,
      );
  }
}

/// Preferred pane id to focus after [removedPaneId] is closed.
String? fallbackPaneAfterRemove(
  SessionLayout? before,
  String removedPaneId,
  List<String> remainingPaneIds,
) {
  if (remainingPaneIds.isEmpty) return null;
  if (before == null) return remainingPaneIds.first;

  final sibling = _siblingPane(before, removedPaneId);
  if (sibling != null && remainingPaneIds.contains(sibling)) return sibling;

  for (final id in before.paneIds) {
    if (id != removedPaneId && remainingPaneIds.contains(id)) return id;
  }
  return remainingPaneIds.first;
}

String? _siblingPane(SessionLayout layout, String paneId) {
  switch (layout) {
    case SessionLayoutLeaf():
      return null;
    case SessionLayoutSplit(first: final first, second: final second):
      if (first is SessionLayoutLeaf && first.paneId == paneId) {
        return second.paneIds.firstOrNull;
      }
      if (second is SessionLayoutLeaf && second.paneId == paneId) {
        return first.paneIds.firstOrNull;
      }
      return _siblingPane(first, paneId) ?? _siblingPane(second, paneId);
  }
}
