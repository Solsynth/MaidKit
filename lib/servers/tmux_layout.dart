import 'dart:convert';

import 'session_layout.dart';

/// Parses one tmux layout into MaidKit's binary layout tree.
///
/// Two serializations have to be accepted, because tmux chooses between them by
/// version rather than by request. Format 2 (`{"V":2,"L":…}`) only appears once
/// the client sets the `new-layouts` flag, which older tmux does not know;
/// those builds answer with the legacy format 1 string
/// (`b25d,80x24,0,0,0` — a checksum followed by nested cells). A client that
/// understood only the JSON would project nothing at all on such a host: an
/// empty tab with no error to explain it. See
/// [tmuxLegacyLayoutToSessionLayout].
///
/// A tmux layout is an n-ary tree: a container cell holds any number of
/// children, while MaidKit's tree is strictly binary. A container therefore
/// folds left to right — the first child becomes one side of a split and the
/// rest are folded into the other side — so a three-pane row becomes two nested
/// splits rather than one wide node.
///
/// Returns null when [layout] is not a layout this build understands — a
/// malformed cell, a leaf without its pane id, or a broken container. The
/// caller keeps its current tree and waits for the next `%layout-change`.
SessionLayout? tmuxLayoutToSessionLayout(
  String layout, {
  required String windowId,
}) {
  final trimmed = layout.trim();
  if (!trimmed.startsWith('{')) {
    return tmuxLegacyLayoutToSessionLayout(trimmed, windowId: windowId);
  }
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) return null;
    final cell = decoded['L'];
    if (cell is! Map) return null;
    var counter = 0;
    return _convert(cell, windowId, () => 'tmux-$windowId-${counter++}');
  } on FormatException {
    return null;
  }
}

/// Parses tmux's legacy (format 1) layout string.
///
/// The grammar, as `layout_append_v1` writes it: a cell is
/// `<width>x<height>,<x>,<y>`, a leaf appends `,<pane index>`, and a container
/// appends `{…}` for a left/right split or `[…]` for a top/bottom one. The
/// whole string is prefixed by a four-hex-digit checksum and a comma.
///
/// The pane field is a bare index rather than the `%N` id the rest of the
/// client speaks, so it is rewritten to that form; on a normal session the two
/// agree, and one alphabet keeps the layout comparable across formats.
SessionLayout? tmuxLegacyLayoutToSessionLayout(
  String layout, {
  required String windowId,
}) {
  final comma = layout.indexOf(',');
  if (comma != 4) return null;
  final body = layout.substring(comma + 1);
  if (body.isEmpty) return null;
  var index = 0;
  var counter = 0;

  ({SessionLayout layout, int width, int height})? read() {
    final cell = _readLegacyCell(body, index);
    if (cell == null) return null;
    index = cell.next;
    final opener = index < body.length ? body[index] : '';
    if (opener != '{' && opener != '[') {
      return (
        layout: SessionLayoutLeaf('%${cell.paneIndex}'),
        width: cell.width,
        height: cell.height,
      );
    }
    final closer = opener == '{' ? '}' : ']';
    index++;
    final children = <({SessionLayout layout, int width, int height})>[];
    while (index < body.length && body[index] != closer) {
      final child = read();
      if (child == null) return null;
      children.add(child);
      if (index < body.length && body[index] == ',') index++;
    }
    if (index >= body.length || children.isEmpty) return null;
    index++;
    return (
      layout: _foldChildren(
        children,
        opener == '{' ? SessionSplitAxis.horizontal : SessionSplitAxis.vertical,
        () => 'tmux-$windowId-${counter++}',
      ),
      width: cell.width,
      height: cell.height,
    );
  }

  return read()?.layout;
}

/// One legacy cell header: `<width>x<height>,<x>,<y>[,<pane index>]`.
///
/// The pane index is present only on a leaf; a container's header ends at the
/// bracket that opens its children.
({int width, int height, int paneIndex, int next})? _readLegacyCell(
  String body,
  int start,
) {
  final match = _legacyCell.matchAsPrefix(body, start);
  if (match == null) return null;
  return (
    width: int.parse(match.group(1)!),
    height: int.parse(match.group(2)!),
    paneIndex: int.tryParse(match.group(3) ?? '') ?? -1,
    next: match.end,
  );
}

// `<w>x<h>,<x>,<y>` followed by an optional `,<pane index>`. No `^` anchor:
// matchAsPrefix anchors at the offset itself, and `^` would only match the
// very start of the string, so every cell after the first would fail.
final _legacyCell = RegExp(r'(\d+)x(\d+),\d+,\d+(?:,(\d+))?');

/// Folds already-parsed legacy children into nested binary splits, keeping the
/// proportions their own extents give.
SessionLayout _foldChildren(
  List<({SessionLayout layout, int width, int height})> children,
  SessionSplitAxis axis,
  String Function() nextSplitId,
) {
  if (children.length == 1) return children.first.layout;
  final extents = [
    for (final child in children)
      (axis == SessionSplitAxis.horizontal ? child.width : child.height)
          .toDouble(),
  ];
  final total = extents.fold<double>(0, (sum, value) => sum + value);
  final rest = children.sublist(1);
  return SessionLayoutSplit(
    id: nextSplitId(),
    axis: axis,
    first: children.first.layout,
    second: rest.length == 1
        ? rest.first.layout
        : _foldChildren(rest, axis, nextSplitId),
    ratio: total <= 0
        ? clampSplitRatio(1 / children.length)
        : clampSplitRatio(extents.first / total),
  );
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
