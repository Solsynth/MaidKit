import 'dart:convert';

import 'session_layout.dart';

/// Parses one tmux v2 JSON layout into MaidKit's binary layout tree.
///
/// A tmux layout is an n-ary tree: a container cell (`"t":"h"` or `"t":"v"`)
/// holds any number of children, while MaidKit's tree is strictly binary. A
/// container therefore folds left to right — the first child becomes one side
/// of a split and the rest of the children are folded into the other side — so
/// a three-pane row becomes two nested splits rather than one wide node.
///
/// Returns null when [layoutJson] is not a layout this build understands — a
/// malformed cell, a leaf without its pane id, or a broken container. The
/// caller keeps its current tree and waits for the next `%layout-change`.
SessionLayout? tmuxLayoutToSessionLayout(
  String layoutJson, {
  required String windowId,
}) {
  try {
    final decoded = jsonDecode(layoutJson);
    if (decoded is! Map) return null;
    final layout = decoded['L'];
    if (layout is! Map) return null;
    var counter = 0;
    return _convert(layout, windowId, () => 'tmux-$windowId-${counter++}');
  } on FormatException {
    return null;
  }
}

SessionLayout _convert(
  Map<dynamic, dynamic> cell,
  String windowId,
  String Function() nextSplitId,
) {
  final type = cell['t'];
  if (type == 'p') {
    final paneId = cell['I'];
    if (paneId is! String || paneId.isEmpty) {
      throw const FormatException('tmux layout leaf has no pane id');
    }
    return SessionLayoutLeaf(paneId);
  }
  final children = cell['c'];
  if (children is! List || children.isEmpty) {
    throw const FormatException('tmux layout container has no children');
  }
  final cells = [
    for (final child in children)
      if (child is Map)
        child
      else
        throw const FormatException('bad layout cell'),
  ];
  if (cells.length == 1) return _convert(cells.first, windowId, nextSplitId);
  final axis = type == 'v'
      ? SessionSplitAxis.vertical
      : SessionSplitAxis.horizontal;
  return _fold(cells, axis, windowId, nextSplitId);
}

/// Folds [cells] into nested binary splits, keeping tmux's own proportions.
///
/// Each split's ratio is its first child's extent over the extents of every
/// cell still on that side, which reproduces tmux's sizes exactly for two
/// children and proportionally for more.
SessionLayout _fold(
  List<Map<dynamic, dynamic>> cells,
  SessionSplitAxis axis,
  String windowId,
  String Function() nextSplitId,
) {
  final extents = [for (final cell in cells) _extent(cell, axis)];
  final total = extents.fold<double>(0, (sum, value) => sum + value);
  final first = extents.first;
  final rest = cells.sublist(1);
  final restExtent = total - first;
  final ratio = total <= 0 ? 1 / cells.length : first / total;
  final second = rest.length == 1
      ? _convert(rest.first, windowId, nextSplitId)
      : _fold(rest, axis, windowId, nextSplitId);
  // A rest side with no measurable extent would collapse; fall back to an even
  // share so the tree still draws both sides.
  final safeRatio = restExtent <= 0 ? 0.5 : clampSplitRatio(ratio);
  return SessionLayoutSplit(
    id: nextSplitId(),
    axis: axis,
    first: _convert(cells.first, windowId, nextSplitId),
    second: second,
    ratio: safeRatio,
  );
}

/// One cell's extent along [axis]: its width for a horizontal fold, its height
/// for a vertical one.
double _extent(Map<dynamic, dynamic> cell, SessionSplitAxis axis) {
  final key = axis == SessionSplitAxis.horizontal ? 'w' : 'h';
  final value = cell[key];
  if (value is num) return value.toDouble();
  final children = cell['c'];
  if (children is! List) return 0;
  var sum = 0.0;
  for (final child in children) {
    if (child is Map) sum += _extent(child, axis);
  }
  return sum;
}

/// tmux pane ids in the tree's leaf order: left to right, top to bottom.
List<String> tmuxPaneOrder(SessionLayout layout) => [
  for (final paneId in layout.paneIds) paneId,
];
