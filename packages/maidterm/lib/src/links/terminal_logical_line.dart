import 'package:flutter/foundation.dart' show internal;
import 'package:libghostty/libghostty.dart'
    show GridRef, InvalidValueException, Position, Terminal;

import '../foundation/cell_range.dart';

/// Visible terminal cells flattened into one wrapped logical line.
///
/// [text], [map], [cells], and [uris] describe the same trimmed content:
/// every text offset has a source cell in [map], and every retained cell has a
/// text start/end offset used by link detectors.
@internal
final class TerminalLogicalLine {
  final String text;
  final List<Position> map;
  final List<Position> cells;
  final List<String?> uris;
  final List<int> _cellStartOffsets;
  final List<int> _cellEndOffsets;

  TerminalLogicalLine(this.text, this.map, this.cells, this.uris)
    : _cellStartOffsets = _startOffsetsFor(map, cells),
      _cellEndOffsets = _endOffsetsFor(map, cells);

  const TerminalLogicalLine._(
    this.text,
    this.map,
    this.cells,
    this.uris,
    this._cellStartOffsets,
    this._cellEndOffsets,
  );

  /// Whether [position] is one of the retained visible cells.
  bool contains(Position position) => cells.contains(position);

  /// Returns the cell range covered by retained cell indexes.
  CellRange rangeForCellRange(int startCellIndex, int endCellIndex) {
    RangeError.checkValidIndex(startCellIndex, cells, 'startCellIndex');
    RangeError.checkValueInInterval(
      endCellIndex,
      startCellIndex,
      cells.length - 1,
      'endCellIndex',
    );
    return CellRange(start: cells[startCellIndex], end: cells[endCellIndex]);
  }

  /// Returns the cell range covered by text offsets.
  CellRange rangeForOffsets(int start, int end) {
    RangeError.checkValidRange(start, end, map.length);
    if (start == end) throw RangeError.range(end, start + 1, map.length, 'end');

    return CellRange(start: map[start], end: map[end - 1]);
  }

  /// Returns the text covered by retained cell indexes.
  String textForCellRange(int startCellIndex, int endCellIndex) {
    RangeError.checkValidIndex(startCellIndex, cells, 'startCellIndex');
    RangeError.checkValueInInterval(
      endCellIndex,
      startCellIndex,
      cells.length - 1,
      'endCellIndex',
    );
    return text.substring(
      _cellStartOffsets[startCellIndex],
      _cellEndOffsets[endCellIndex],
    );
  }

  /// Builds the wrapped logical line containing [position].
  static TerminalLogicalLine? atPosition(
    Terminal terminal,
    Position position, {
    required int rows,
    required int cols,
  }) {
    if (rows <= 0 ||
        cols <= 0 ||
        position.row < 0 ||
        position.row >= rows ||
        position.col < 0 ||
        position.col >= cols) {
      return null;
    }

    var startRow = position.row;
    while (startRow > 0 && (_rowWrap(terminal, startRow - 1) ?? false)) {
      startRow--;
    }

    var endRow = position.row;
    while (endRow < rows - 1 && (_rowWrap(terminal, endRow) ?? false)) {
      endRow++;
    }

    final current = _LogicalLineBuilder();
    for (var row = startRow; row <= endRow; row++) {
      final wrap = current.addRow(terminal, row, cols);
      if (wrap == null) return null;
    }
    if (current.isEmpty) return null;
    final line = current.finish();
    return line.contains(position) ? line : null;
  }

  /// Builds every visible wrapped logical line in viewport order.
  static List<TerminalLogicalLine> visible(
    Terminal terminal, {
    required int rows,
    required int cols,
  }) {
    if (rows <= 0 || cols <= 0) return const [];

    final lines = <TerminalLogicalLine>[];
    var current = _LogicalLineBuilder();

    for (var row = 0; row < rows; row++) {
      final wrap = current.addRow(terminal, row, cols);
      if (wrap == null) break;
      if (!wrap) {
        lines.add(current.finish());
        current = _LogicalLineBuilder();
      }
    }
    if (!current.isEmpty) lines.add(current.finish());
    return lines;
  }

  static GridRef? _cellAt(Terminal terminal, int row, int col) {
    try {
      return GridRef.at(
        terminal,
        Position(row: row, col: col),
        pointTag: .viewport,
      );
    } on InvalidValueException {
      return null;
    }
  }

  static List<int> _endOffsetsFor(List<Position> map, List<Position> cells) {
    return [
      for (final cell in cells)
        map.lastIndexWhere((position) => position == cell) + 1,
    ];
  }

  static bool? _rowWrap(Terminal terminal, int row) {
    return _cellAt(terminal, row, 0)?.rowWrap;
  }

  static List<int> _startOffsetsFor(List<Position> map, List<Position> cells) {
    return [
      for (final cell in cells) map.indexWhere((position) => position == cell),
    ];
  }
}

final class _LogicalLineBuilder {
  final _text = StringBuffer();
  final List<Position> _map = [];
  final List<Position> _cells = [];
  final List<String?> _uris = [];
  final List<int> _cellStartOffsets = [];
  final List<int> _cellEndOffsets = [];

  bool get isEmpty => _cells.isEmpty;

  bool? addRow(Terminal terminal, int row, int cols) {
    final firstCell = TerminalLogicalLine._cellAt(terminal, row, 0);
    if (firstCell == null) return null;
    final rowWrap = firstCell.rowWrap;

    for (var col = 0; col < cols; col++) {
      final position = Position(row: row, col: col);
      final cell = col == 0
          ? firstCell
          : TerminalLogicalLine._cellAt(terminal, row, col);
      if (cell == null) break;
      if (cell.wide == .spacerTail) continue;

      final start = _text.length;
      _cells.add(position);
      _uris.add(cell.hyperlinkUri);
      final content = cell.content;
      if (content.isEmpty) {
        _text.write(' ');
        _map.add(position);
        _cellStartOffsets.add(start);
        _cellEndOffsets.add(_text.length);
        continue;
      }

      _text.write(content);
      _map.addAll(List.filled(content.length, position));
      _cellStartOffsets.add(start);
      _cellEndOffsets.add(_text.length);
    }
    return rowWrap;
  }

  TerminalLogicalLine finish() {
    final raw = _text.toString();
    final end = raw.trimRight().length;
    final cellCount = _cellStartOffsets.lastIndexWhere(
      (offset) => offset < end,
    );
    final cellsEnd = cellCount + 1;
    return TerminalLogicalLine._(
      raw.substring(0, end),
      List.unmodifiable(_map.take(end)),
      List.unmodifiable(_cells.take(cellsEnd)),
      List.unmodifiable(_uris.take(cellsEnd)),
      List.unmodifiable(_cellStartOffsets.take(cellsEnd)),
      List.unmodifiable(_cellEndOffsets.take(cellsEnd)),
    );
  }
}
