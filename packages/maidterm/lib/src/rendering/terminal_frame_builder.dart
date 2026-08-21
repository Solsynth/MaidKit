import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:libghostty/libghostty.dart';

import '../foundation/dynamic_color.dart';
import '../foundation/terminal_theme.dart';
import '../links/link_snapshot.dart';
import 'atlas/atlas.dart';
import 'atlas/sprite_buffer.dart';
import 'cell_content_resolver.dart';
import 'codepoint_classification.dart';
import 'paint_state.dart';

const _italicOverhangFontSizeFactor = 0.15;

// Conservative context lets boundary-crossing ligatures shape correctly.
const _operatorLigatureContextCells = 16;

// Above common wide terminal columns; caps pathological operator animations.
const _operatorRunChunkCells = 256;

/// ASCII punctuation/operator: not digit, not uppercase, not lowercase.
bool _isOperator(int cp) {
  return cp < 0x30 ||
      (cp > 0x39 && cp < 0x41) ||
      (cp > 0x5A && cp < 0x61) ||
      cp > 0x7A;
}

bool _isRemovedPreeditCodepoint(int cp) {
  return (cp >= 0x0000 && cp <= 0x001F) ||
      (cp >= 0x007F && cp <= 0x009F) ||
      (cp >= 0x200B && cp <= 0x200F) ||
      (cp >= 0x202A && cp <= 0x202E) ||
      (cp >= 0x2060 && cp <= 0x206F) ||
      cp == 0xFFFC ||
      cp == 0xFEFF;
}

bool _isWideEmojiCodepoint(int cp) {
  return (cp >= 0x1F000 && cp <= 0x1FAFF) || (cp >= 0x2600 && cp <= 0x27BF);
}

bool _isZeroWidthPreeditCodepoint(int cp) {
  return (cp >= 0x0300 && cp <= 0x036F) ||
      (cp >= 0x1AB0 && cp <= 0x1AFF) ||
      (cp >= 0x1DC0 && cp <= 0x1DFF) ||
      (cp >= 0x20D0 && cp <= 0x20FF) ||
      (cp >= 0xFE00 && cp <= 0xFE0F) ||
      (cp >= 0xFE20 && cp <= 0xFE2F) ||
      (cp >= 0xE0100 && cp <= 0xE01EF);
}

int _preeditCellWidth(int cp) {
  return isCjkCodepoint(cp) || _isWideEmojiCodepoint(cp) ? 2 : 1;
}

int _resolveColorArgb(
  TerminalPaintState state,
  CellColor color, {
  required bool isForeground,
  int? defaultForeground,
  int? defaultBackground,
}) {
  return switch (color) {
    DefaultColor() =>
      isForeground
          ? defaultForeground ?? state.terminalForegroundArgb
          : defaultBackground ?? state.terminalBackgroundArgb,
    RgbColor() => color.toArgb32,
    PaletteColor(:final index) => state.terminalPaletteArgb[index],
  };
}

(int foreground, int background) _resolveStyleColors(
  TerminalPaintState state,
  Style style, {
  int? defaultForeground,
  int? defaultBackground,
}) {
  var foreground = _resolveColorArgb(
    state,
    style.foreground,
    isForeground: true,
    defaultForeground: defaultForeground,
    defaultBackground: defaultBackground,
  );
  var background = _resolveColorArgb(
    state,
    style.background,
    isForeground: false,
    defaultForeground: defaultForeground,
    defaultBackground: defaultBackground,
  );

  if (style.bold) {
    final boldColor = state.theme.boldColor;
    if (boldColor != null) {
      foreground = boldColor.toARGB32();
    } else if (state.theme.boldIsBright) {
      final raw = style.foreground;
      if (raw is PaletteColor && raw.index < 8) {
        foreground = state.terminalPaletteArgb[raw.index + 8];
      }
    }
  }

  if (style.inverse) (foreground, background) = (background, foreground);
  if (style.faint) {
    foreground = (state.faintAlpha << 24) | (foreground & 0x00FFFFFF);
  }

  return (foreground, background);
}

/// Tracks per-row dirtiness from sources outside libghostty's own row-dirty
/// flag, such as selection, blink, layout, or atlas changes.
///
/// [TerminalFrameBuilder] combines this with [RowIterator.dirty] when deciding
/// whether to re-emit each row, and clears it at the end of every build.
class RowDirtyTracker {
  var _rows = Uint8List(0);
  var _anyDirty = false;

  bool get anyDirty => _anyDirty;

  /// Whether [row] is marked dirty. Out-of-range rows read as clean.
  bool isDirty(int row) => row >= 0 && row < _rows.length && _rows[row] != 0;

  void markAll() {
    if (_rows.isEmpty) return;
    _rows.fillRange(0, _rows.length, 1);
    _anyDirty = true;
  }

  /// Marks rows `[from, toExclusive)` dirty, clamped to the current row count.
  void markRange(int from, int toExclusive) {
    final start = from < 0 ? 0 : from;
    final end = toExclusive > _rows.length ? _rows.length : toExclusive;
    if (start >= end) return;
    _rows.fillRange(start, end, 1);
    _anyDirty = true;
  }

  /// Marks a single [row] dirty. Out-of-range rows are ignored.
  void markRow(int row) {
    if (row < 0 || row >= _rows.length) return;
    _rows[row] = 1;
    _anyDirty = true;
  }

  /// Resizes to track [rowCount] rows and clears all flags.
  void resize(int rowCount) {
    if (_rows.length != rowCount) {
      _rows = Uint8List(rowCount);
    } else {
      _rows.fillRange(0, rowCount, 0);
    }
    _anyDirty = false;
  }

  void _clear() {
    if (!_anyDirty) return;
    _rows.fillRange(0, _rows.length, 0);
    _anyDirty = false;
  }
}

/// Builds terminal visual layers for the current frame.
///
/// Reads terminal cells and writes [SpriteBuffer] channels for text, emoji,
/// built-in sprites, backgrounds, and decorations. The render object owns
/// lifecycle/layout/paint ordering; this class owns frame state sync, dirty-row
/// buffer generation, cursor visual resolution, and cell-content routing.
class TerminalFrameBuilder {
  final Atlas _atlas;
  final RowIterator _rows;
  final CellIterator _cells;
  final SpriteBuffer _sprites;
  final RenderState _renderState;
  final TerminalPaintState _state;
  final RowDirtyTracker _dirtyRows;
  final CellContentResolver _content;

  late final _TerminalRowBuilder _rowBuilder;
  late final _CursorFrameBuilder _cursorBuilder;

  TerminalFrameBuilder(this._atlas, this._sprites, this._state)
    : _content = CellContentResolver(_atlas),
      _renderState = RenderState(),
      _rows = RowIterator(),
      _cells = CellIterator(),
      _dirtyRows = RowDirtyTracker() {
    _rowBuilder = _TerminalRowBuilder(
      atlas: _atlas,
      sprites: _sprites,
      state: _state,
      content: _content,
    );
    _cursorBuilder = _CursorFrameBuilder(_state, _content);
  }

  /// Reconfigures sprite storage for the current grid size.
  void configure(int rows, int cols) {
    _sprites.configure(rows, cols);
    _dirtyRows.resize(rows);
  }

  /// Releases the owned libghostty iterators.
  void dispose() {
    _cells.dispose();
    _rows.dispose();
    _renderState.dispose();
  }

  /// Rebuilds every visible row on the next sync.
  void markAllRowsDirty() => _dirtyRows.markAll();

  /// Rebuilds rows `[from, toExclusive)` on the next sync.
  void markRowsDirty(int from, int toExclusive) {
    _dirtyRows.markRange(from, toExclusive);
  }

  /// Re-resolves the cursor glyph from the last cursor cell snapshot.
  ///
  /// Used when flterm-side state changes, such as focus or blink visibility,
  /// without a new terminal render state.
  void refreshCursorGlyph() => _cursorBuilder.refreshGlyph();

  /// Syncs terminal state into paint-ready buffers.
  void sync(
    Terminal terminal, {
    required bool terminalDirty,
    String preeditText = '',
    LinkSnapshot linkSnapshot = .empty,
  }) {
    var dirty = DirtyState.clean;

    _rowBuilder.linkSnapshot = linkSnapshot;

    if (terminalDirty) {
      dirty = _renderState.update(terminal);
      final scrollbar = terminal.scrollbar;
      final terminalColorsChanged = _state.updateTerminalColors(
        _renderState.colors,
      );

      _state.viewportOffset = scrollbar.offset;
      // RenderState updates colors even when its dirty result is clean.
      // Since sprite buffers cache resolved ARGB values, color changes need
      // the same full rebuild as other global terminal-state changes.
      if (terminalColorsChanged) dirty = .full;

      _cursorBuilder.sync(
        terminal: terminal,
        renderState: _renderState,
        scrollbar: scrollbar,
      );
    }

    // Preedit text is render-only state. It can dirty rows even when the
    // terminal render state is unchanged, such as a composing update over a
    // stable prompt.
    final preeditRows = _rowBuilder.updatePreedit(
      preeditText,
      cursor: _state.cursor,
    );
    if (preeditRows.previous case final row?) _dirtyRows.markRow(row);
    if (preeditRows.current case final row?) _dirtyRows.markRow(row);
    _state.preeditActive = _rowBuilder.hasPreedit;

    final hasDirtyRows = _dirtyRows.anyDirty;
    if (terminalDirty) {
      if (dirty != .clean || hasDirtyRows) {
        _build(dirty == .clean ? .partial : dirty);
        _renderState.dirty = .clean;
      }
    } else if (hasDirtyRows) {
      _build(.partial);
    }
  }

  void _build(DirtyState dirty) {
    _rowBuilder.beginFrame();

    final rebuildAll = dirty != DirtyState.partial;
    _rows.reset(_renderState);

    var row = 0;
    while (_rows.next()) {
      if (row >= _state.rows) break;
      if (rebuildAll || _rows.dirty || _dirtyRows.isDirty(row)) {
        _rowBuilder.rebuildRow(row, _rows, _cells);
        _rows.dirty = false;
      }
      row++;
    }

    _dirtyRows._clear();
    _atlas.ensureImage();
    _sprites.seal();
  }
}

/// Batches consecutive ASCII operators so font ligatures can apply.
final class _AsciiOperatorRun {
  final _codepoints = <int>[];
  var x = 0.0;

  int get first => _codepoints.first;

  bool get isEmpty => _codepoints.isEmpty;

  int get length => _codepoints.length;

  String get text => String.fromCharCodes(_codepoints);

  void add(int codepoint, double cellX) {
    if (_codepoints.isEmpty) x = cellX;
    _codepoints.add(codepoint);
  }

  void clear() => _codepoints.clear();

  String textSlice(int start, int end) {
    return String.fromCharCodes(_codepoints, start, end);
  }
}

/// Snapshot of the cell under the cursor.
///
/// Captured during state sync so cursor painting can render the character
/// under a block cursor without touching terminal state during paint.
final class _CursorCellSnapshot {
  final String content;
  final Style style;
  final bool wide;

  const _CursorCellSnapshot(this.content, this.style, {required this.wide});
}

/// Resolves cursor geometry, colors, and block-cursor glyph state.
final class _CursorFrameBuilder {
  final TerminalPaintState _state;
  final CellContentResolver _content;
  var _cursor = const Cursor();
  _CursorCellSnapshot? _lastCell;

  _CursorFrameBuilder(this._state, this._content);

  void refreshGlyph() {
    final cell = _lastCell;
    final entry = _resolveGlyph();
    _state.cursorAtlasEntry = entry;
    if (entry == null || cell == null) return;

    // The character under a block cursor paints in CursorTheme.text (or the
    // terminal background when unset) so it contrasts with the cursor fill.
    final (cellFg, cellBg) = _resolveCellColors(cell);
    final glyphColor =
        _state.theme.cursor.text?.resolve(
          cellForeground: cellFg,
          cellBackground: cellBg,
        ) ??
        Color(_state.terminalBackgroundArgb);
    _state.cursorGlyphPaint.colorFilter = ColorFilter.mode(
      glyphColor,
      BlendMode.modulate,
    );
  }

  void sync({
    required Terminal terminal,
    required RenderState renderState,
    required Scrollbar scrollbar,
  }) {
    final cursor = renderState.cursor;
    final scrollbackLen = scrollbar.total - scrollbar.visible;
    final inViewport =
        cursor.visible &&
        (scrollbackLen <= 0 || scrollbar.offset >= scrollbackLen) &&
        cursor.position.row >= 0 &&
        cursor.position.row < _state.rows &&
        cursor.position.col >= 0 &&
        cursor.position.col < _state.cols;

    if (!inViewport) {
      _hide(cursor);
      return;
    }

    final adjustedCursor = cursor.wideTail && cursor.position.col > 0
        ? cursor.copyWith(
            position: cursor.position.copyWith(col: cursor.position.col - 1),
          )
        : cursor;
    final effectiveCursor = adjustedCursor.shape == CursorShape.block
        ? adjustedCursor.copyWith(shape: _state.theme.cursor.shape)
        : adjustedCursor;
    final ref = GridRef.at(terminal, effectiveCursor.position);
    final cell = _CursorCellSnapshot(ref.content, ref.style, wide: ref.isWide);

    _cursor = effectiveCursor;
    _lastCell = cell;
    _state.cursor = effectiveCursor;
    _state.cursorWide = cell.wide;
    _resolveFillColor(terminal, cell);
    refreshGlyph();
  }

  void _hide(Cursor cursor) {
    _cursor = cursor;
    _lastCell = null;
    _state.cursor = cursor.copyWith(visible: false);
    _state.cursorWide = false;
    _state.cursorAtlasEntry = null;
  }

  (Color, Color) _resolveCellColors(_CursorCellSnapshot cell) {
    final (fg, bg) = _resolveStyleColors(_state, cell.style);
    return (Color(fg), Color(bg));
  }

  // An OSC 12 color reported by libghostty overrides the theme cursor color.
  void _resolveFillColor(Terminal terminal, _CursorCellSnapshot cell) {
    final osc = terminal.cursorColor;
    if (osc != null) {
      _state.cursorColorArgb = osc.toArgb32;
      return;
    }
    final themeCursor = _state.theme.cursor.color;
    if (themeCursor == null) {
      _state.cursorColorArgb = _state.terminalForegroundArgb;
      return;
    }
    final (cellFg, cellBg) = _resolveCellColors(cell);
    _state.cursorColorArgb = themeCursor
        .resolve(cellForeground: cellFg, cellBackground: cellBg)
        .toARGB32();
  }

  AtlasEntry? _resolveGlyph() {
    final cell = _lastCell;
    if (cell == null ||
        !_state.cursorFocused ||
        _cursor.shape != CursorShape.block) {
      return null;
    }
    final style = cell.style;
    if (cell.content.isEmpty ||
        style.invisible ||
        (style.blink && !_state.blinkVisible)) {
      return null;
    }

    final runes = cell.content.runes;
    return _content.resolve(
      content: cell.content,
      codepoint: runes.first,
      graphemeLength: runes.length,
      style: style,
      span: cell.wide ? 2 : 1,
    );
  }
}

/// Emits text, emoji, and built-in sprite foreground channels.
final class _ForegroundEmitter {
  final SpriteBuffer _sprites;
  final _FrameSnapshot _frame;
  final TerminalPaintState _state;
  final CellContentResolver _content;
  final _AsciiOperatorRun _operators;
  TerminalTheme? _lastTextStyleTheme;
  TextStyle? _lastTextStyle;
  var _lastTextStyleForeground = 0;
  var _lastTextStyleBold = false;
  var _lastTextStyleItalic = false;

  _ForegroundEmitter(this._sprites, this._content, this._frame, this._state)
    : _operators = _AsciiOperatorRun();

  void emit(CellIterator cell, _RowBuildState row, {required int span}) {
    if (!cell.hasText) {
      flush(row);
      return;
    }

    final codepoint = cell.codepoint;
    final style = row.style;

    if (span == 1 && codepoint > 0x20 && codepoint < 0x7F) {
      if (_isOperator(codepoint)) {
        _operators.add(codepoint, row.spriteX);
        return;
      }

      flush(row);
      _emitCodepoint(codepoint, row, style: style, x: row.spriteX);
      return;
    }

    flush(row);
    final entry = _content.resolveCell(cell, style: style, span: span);
    if (entry == null) return;
    _emitEntry(entry, row, x: row.spriteX, wideText: span == 2);
  }

  void emitPreedit(
    _PreeditCodepoint codepoint,
    _RowBuildState row, {
    required double x,
  }) {
    final content = String.fromCharCode(codepoint.codepoint);
    final entry = _content.resolve(
      content: content,
      codepoint: codepoint.codepoint,
      graphemeLength: 1,
      style: const Style(),
      span: codepoint.span,
    );
    if (entry == null) return;
    _emitEntry(
      entry,
      row,
      x: x,
      wideText: codepoint.span == 2,
      foreground: _state.terminalForegroundArgb,
    );
  }

  void flush(_RowBuildState row) {
    if (_operators.isEmpty) return;

    final style = row.style;
    if (_operators.length == 1) {
      _emitCodepoint(_operators.first, row, style: style, x: _operators.x);
    } else {
      _emitShapedRun(_operators, row, style: style);
    }
    _operators.clear();
  }

  void _emitCodepoint(
    int codepoint,
    _RowBuildState row, {
    required Style style,
    required double x,
  }) {
    final entry = _content.resolveCodepoint(codepoint, style: style);
    _emitEntry(entry, row, x: x, wideText: false);
  }

  void _emitEntry(
    AtlasEntry entry,
    _RowBuildState row, {
    required double x,
    required bool wideText,
    int? foreground,
  }) {
    final color = foreground ?? row.foreground;
    switch (entry.lane) {
      case .emoji:
        _sprites.emoji.add(x, row.rowY, entry, _frame.inverseDpr);
      case .sprite:
        _sprites.sprite.add(
          x + entry.bearingX * _frame.inverseDpr,
          row.rowY + entry.bearingY * _frame.inverseDpr,
          entry,
          _frame.inverseDpr,
          color,
        );
      case .text:
        final sprites = wideText ? _sprites.wide : _sprites.regular;
        sprites.add(
          x + entry.bearingX * _frame.inverseDpr,
          row.rowY + entry.bearingY * _frame.inverseDpr,
          entry,
          _frame.inverseDpr,
          color,
        );
      case .decoration:
        throw StateError('Decoration atlas entries cannot paint cell content.');
    }
  }

  void _emitShapedChunk(
    String text,
    _RowBuildState row, {
    required Style style,
    required double runX,
    required int textStart,
    required int coreStart,
    required int coreEnd,
  }) {
    final theme = _state.theme;
    final textX = runX + _frame.cellWidth * textStart;
    final coreX = runX + _frame.cellWidth * coreStart;
    final coreWidth = _frame.cellWidth * (coreEnd - coreStart);
    final overhang = style.italic
        ? math.max(
            1.0,
            (theme.fontSize * _italicOverhangFontSizeFactor).ceilToDouble(),
          )
        : 0.0;
    final paragraph =
        (ParagraphBuilder(_frame.paragraphStyle)
              ..pushStyle(_textStyle(row.foreground, style))
              ..addText(text)
              ..pop())
            .build()
          ..layout(const ParagraphConstraints(width: .infinity));
    _sprites.shaped.add(
      ShapedRun(
        paragraph: paragraph,
        offset: Offset(
          textX,
          row.rowY + _state.metrics.baseline - paragraph.alphabeticBaseline,
        ),
        clip: Rect.fromLTWH(
          coreX,
          row.rowY,
          coreWidth + overhang,
          _frame.cellHeight,
        ),
      ),
    );
  }

  void _emitShapedRun(
    _AsciiOperatorRun run,
    _RowBuildState row, {
    required Style style,
  }) {
    final length = run.length;
    if (length <= _operatorRunChunkCells) {
      _emitShapedChunk(
        run.text,
        row,
        style: style,
        runX: run.x,
        textStart: 0,
        coreStart: 0,
        coreEnd: length,
      );
      return;
    }

    var coreStart = 0;
    while (coreStart < length) {
      final coreEnd = math.min(coreStart + _operatorRunChunkCells, length);
      final textStart = math.max(0, coreStart - _operatorLigatureContextCells);
      final textEnd = math.min(length, coreEnd + _operatorLigatureContextCells);
      _emitShapedChunk(
        run.textSlice(textStart, textEnd),
        row,
        style: style,
        runX: run.x,
        textStart: textStart,
        coreStart: coreStart,
        coreEnd: coreEnd,
      );
      coreStart = coreEnd;
    }
  }

  TextStyle _textStyle(int foreground, Style style) {
    final theme = _state.theme;
    final bold = style.bold;
    final italic = style.italic;
    final cached = _lastTextStyle;
    if (cached != null &&
        identical(theme, _lastTextStyleTheme) &&
        foreground == _lastTextStyleForeground &&
        bold == _lastTextStyleBold &&
        italic == _lastTextStyleItalic) {
      return cached;
    }

    final textStyle = TextStyle(
      color: Color(foreground),
      fontSize: theme.fontSize,
      fontFamily: theme.fontFamily,
      decoration: TextDecoration.none,
      fontWeight: bold ? .bold : theme.fontWeight,
      fontStyle: italic ? .italic : .normal,
      fontFamilyFallback: theme.fontFamilyFallback,
    );
    _lastTextStyleTheme = theme;
    _lastTextStyleForeground = foreground;
    _lastTextStyleBold = bold;
    _lastTextStyleItalic = italic;
    return _lastTextStyle = textStyle;
  }
}

/// Frame-scoped metrics and theme values read by row emitters.
final class _FrameSnapshot {
  late ParagraphStyle paragraphStyle;
  TerminalTheme? _paragraphStyleTheme;
  var cellWidth = 0.0;
  var cellHeight = 0.0;
  var underlinePosition = 0.0;
  var underlineThickness = 0.0;
  var strikethroughPosition = 0.0;
  var strikethroughThickness = 0.0;
  var overlinePosition = 0.0;
  var inverseDpr = 1.0;
  var defaultBackgroundArgb = 0;
  var cols = 0;
  var applyCellOpacity = false;
  var cellOpacityAlpha = 255;
  int resolveBgArgb(int argb, {required bool inverse}) {
    if (!applyCellOpacity || inverse) return argb;
    final currentAlpha = (argb >>> 24) & 0xFF;
    final newAlpha = (currentAlpha * cellOpacityAlpha + 127) ~/ 255;
    return (newAlpha << 24) | (argb & 0x00FFFFFF);
  }

  void update(TerminalPaintState state, {required Atlas atlas}) {
    final metrics = state.metrics;
    cellWidth = metrics.cellWidth;
    cellHeight = metrics.cellHeight;
    underlinePosition = metrics.underlinePosition;
    underlineThickness = metrics.underlineThickness;
    strikethroughPosition = metrics.strikethroughPosition;
    strikethroughThickness = metrics.strikethroughThickness;
    overlinePosition = metrics.overlinePosition;
    inverseDpr = 1.0 / atlas.devicePixelRatio;
    defaultBackgroundArgb = state.terminalBackgroundArgb;
    cols = state.cols;

    final theme = state.theme;
    if (!identical(theme, _paragraphStyleTheme)) {
      paragraphStyle = ParagraphStyle(
        fontSize: theme.fontSize,
        fontFamily: theme.fontFamily,
        textAlign: .start,
        textDirection: TextDirection.ltr,
      );
      _paragraphStyleTheme = theme;
    }
    applyCellOpacity =
        theme.backgroundOpacityCells && theme.backgroundOpacity < 1.0;
    cellOpacityAlpha = theme.backgroundOpacityAlpha;
  }
}

final class _PreeditCodepoint {
  final int codepoint;
  final int span;

  const _PreeditCodepoint(this.codepoint, this.span);
}

/// Cell-based terminal range temporarily replaced by visible preedit text.
///
/// [startCol] and [endCol] are terminal columns. [codepointOffset] points at
/// the first visible codepoint when overflow clips the preedit from the left.
final class _PreeditRange {
  final int row;
  final int startCol;
  final int endCol;
  final int codepointOffset;
  final List<_PreeditCodepoint> codepoints;

  const _PreeditRange({
    required this.row,
    required this.startCol,
    required this.endCol,
    required this.codepointOffset,
    required this.codepoints,
  });

  bool overlaps(int row, int col, int span) {
    final cellEndCol = col + span;
    return row == this.row && col < endCol && cellEndCol > startCol;
  }

  bool sameGeometry(_PreeditRange? other) {
    return other != null &&
        row == other.row &&
        startCol == other.startCol &&
        endCol == other.endCol &&
        codepointOffset == other.codepointOffset;
  }

  static _PreeditRange? resolve({
    required String text,
    required Cursor cursor,
    required int rows,
    required int cols,
  }) {
    if (!cursor.visible ||
        cursor.position.row < 0 ||
        cursor.position.row >= rows ||
        cursor.position.col < 0 ||
        cursor.position.col >= cols ||
        rows <= 0 ||
        cols <= 0) {
      return null;
    }

    final preedit = _PreeditText.parse(text);
    if (preedit.isEmpty) return null;

    final startCol = preedit.startCol(cursor.position.col, cols);
    final visible = preedit.visibleSuffix(cols - startCol);
    final visibleWidth = visible.width;
    final endCol = startCol + visibleWidth;
    if (startCol >= endCol) return null;

    return _PreeditRange(
      row: cursor.position.row,
      startCol: startCol,
      endCol: endCol,
      codepointOffset: visible.codepointOffset,
      codepoints: preedit.codepoints,
    );
  }
}

/// Preedit text split into terminal-cell spans.
///
/// Rendering uses these spans instead of paragraph widths so CJK, emoji, and
/// narrow text replace exactly the terminal cells they occupy.
final class _PreeditText {
  final List<_PreeditCodepoint> codepoints;
  final int cellWidth;

  const _PreeditText(this.codepoints, this.cellWidth);

  factory _PreeditText.parse(String text) {
    if (text.isEmpty) return const _PreeditText([], 0);

    final codepoints = <_PreeditCodepoint>[];
    var cellWidth = 0;
    for (final cp in text.runes) {
      if (_isRemovedPreeditCodepoint(cp) || _isZeroWidthPreeditCodepoint(cp)) {
        continue;
      }
      final span = _preeditCellWidth(cp);
      cellWidth += span;
      codepoints.add(_PreeditCodepoint(cp, span));
    }

    return _PreeditText(codepoints, cellWidth);
  }

  bool get isEmpty => codepoints.isEmpty;

  int startCol(int cursorCol, int cols) {
    final rightWidth = cols - cursorCol;
    return cellWidth <= rightWidth
        ? cursorCol
        : math.max(0, cursorCol - (cellWidth - rightWidth));
  }

  ({int codepointOffset, int width}) visibleSuffix(int maxWidth) {
    var codepointOffset = codepoints.length;
    var width = 0;
    for (var i = codepoints.length - 1; i >= 0; i--) {
      final nextWidth = width + codepoints[i].span;
      if (nextWidth > maxWidth) break;
      width = nextWidth;
      codepointOffset = i;
    }
    return (codepointOffset: codepointOffset, width: width);
  }
}

/// Mutable visual state for the row currently being rebuilt.
final class _RowBuildState {
  var row = 0;
  var col = 0;
  var spriteX = 0.0;
  var rowY = 0.0;
  var rowBottom = 0.0;

  var prevStyleId = -1;
  int? prevBackgroundArgb;
  var prevSelected = false;
  HyperlinkStyle? prevLinkStyle;

  var baseForeground = 0xFFFFFFFF;
  var baseBackground = 0;
  var baseBackgroundExplicit = false;
  var foreground = 0xFFFFFFFF;
  var background = 0;
  var backgroundInverse = false;
  var backgroundExplicit = false;
  var hidden = false;
  var hasDecoration = false;
  var style = const Style();

  var bgRunStart = 0;
  var bgRunArgb = 0;
  var bgRunInverse = false;
  var bgRunExplicit = false;
  var preeditEmitted = false;

  void advance(int span, double cellWidth) {
    col += span;
    spriteX += cellWidth * span;
  }

  void reset(int row, _FrameSnapshot frame) {
    this.row = row;
    rowY = row * frame.cellHeight;
    rowBottom = rowY + frame.cellHeight;
    col = 0;
    spriteX = 0.0;
    prevStyleId = -1;
    prevBackgroundArgb = null;
    prevSelected = false;
    prevLinkStyle = null;
    baseForeground = 0xFFFFFFFF;
    baseBackground = frame.defaultBackgroundArgb;
    baseBackgroundExplicit = false;
    foreground = 0xFFFFFFFF;
    background = frame.defaultBackgroundArgb;
    backgroundInverse = false;
    backgroundExplicit = false;
    hidden = false;
    hasDecoration = false;
    style = const Style();
    bgRunStart = 0;
    bgRunArgb = frame.defaultBackgroundArgb;
    bgRunInverse = false;
    bgRunExplicit = false;
    preeditEmitted = false;
  }
}

/// Resolves and caches style-derived colors for the current frame.
final class _StyleResolver {
  // Covers common 256-color fg/bg animation palettes within one frame.
  static const _maxEntries = 1024;

  final TerminalPaintState _state;
  final Int32List _gen;
  final Int32List _foreground;
  final Int32List _background;
  final Uint8List _explicitBg;
  final List<Style?> _styles;
  var _generation = 0;

  var _defaultFg = 0;
  var _defaultBg = 0;

  _StyleResolver(this._state)
    : _gen = Int32List(_maxEntries),
      _foreground = Int32List(_maxEntries),
      _background = Int32List(_maxEntries),
      _explicitBg = Uint8List(_maxEntries),
      _styles = List<Style?>.filled(_maxEntries, null);

  void beginFrame() {
    _generation++;
    _defaultFg = _state.terminalForegroundArgb;
    _defaultBg = _state.terminalBackgroundArgb;
  }

  void update(
    CellIterator cell, {
    required int? backgroundArgb,
    required bool selected,
    required HyperlinkStyle? linkStyle,
    required _RowBuildState row,
  }) {
    if (cell.styleId != row.prevStyleId ||
        backgroundArgb != row.prevBackgroundArgb ||
        linkStyle != row.prevLinkStyle) {
      final (fg, bg, style, explicitBg) = _resolveBase(
        cell,
        backgroundArgb: backgroundArgb,
      );
      row.prevStyleId = cell.styleId;
      row.prevBackgroundArgb = backgroundArgb;
      row.baseForeground = fg;
      row.baseBackground = bg;
      row.baseBackgroundExplicit = explicitBg;
      row.backgroundInverse = style.inverse;
      row.style = style;
      row.hidden = style.invisible || (!_state.blinkVisible && style.blink);
      row.hasDecoration =
          style.underline != .none || style.strikethrough || style.overline;
    }

    if (selected) {
      final selection = _state.theme.selection;
      row.foreground = _resolveSelectionColor(
        row,
        selection.foreground,
        _state.terminalBackgroundArgb,
      );
      row.background = _resolveSelectionColor(
        row,
        selection.background,
        _state.terminalForegroundArgb,
      );
      row.backgroundExplicit = true;
    } else {
      row.foreground = row.baseForeground;
      row.background = row.baseBackground;
      row.backgroundExplicit = row.baseBackgroundExplicit;
    }

    if (linkStyle != null) {
      final textColor = linkStyle.textColor;
      if (textColor != null) row.foreground = textColor.toARGB32();
      if (linkStyle.underline != .none) {
        final style = row.style;
        row.style = Style(
          bold: style.bold,
          italic: style.italic,
          faint: style.faint,
          blink: style.blink,
          inverse: style.inverse,
          invisible: style.invisible,
          overline: style.overline,
          strikethrough: style.strikethrough,
          foreground: style.foreground,
          background: style.background,
          underline: style.underline == .none ? linkStyle.underline : .double,
          underlineColor: _rgbColor(linkStyle.underlineColor),
        );
        row.hasDecoration = true;
      }
    }

    row.prevSelected = selected;
    row.prevLinkStyle = linkStyle;
  }

  (int foreground, int background, Style style, bool explicitBg) _resolveBase(
    CellIterator cell, {
    required int? backgroundArgb,
  }) {
    final id = cell.styleId;
    if (!cell.hasStyling && backgroundArgb == null) {
      return (_defaultFg, _defaultBg, const Style(), false);
    }

    final style = cell.style;
    final contentBackground = style.background is DefaultColor
        ? backgroundArgb
        : null;
    if (contentBackground != null) {
      final (foreground, background) = _resolveStyleColors(
        _state,
        style,
        defaultForeground: _defaultFg,
        defaultBackground: _defaultBg,
      );
      return (
        foreground,
        style.inverse ? background : contentBackground,
        style,
        true,
      );
    }

    if (id < _maxEntries && _gen[id] == _generation) {
      return (
        _foreground[id],
        _background[id],
        _styles[id]!,
        _explicitBg[id] != 0,
      );
    }

    final (foreground, background) = _resolveStyleColors(
      _state,
      style,
      defaultForeground: _defaultFg,
      defaultBackground: _defaultBg,
    );
    var explicitBg = style.background is! DefaultColor;

    if (style.inverse) explicitBg = true;

    if (id < _maxEntries) {
      _gen[id] = _generation;
      _foreground[id] = foreground;
      _background[id] = background;
      _explicitBg[id] = explicitBg ? 1 : 0;
      _styles[id] = style;
    }

    return (foreground, background, style, explicitBg);
  }

  int _resolveSelectionColor(
    _RowBuildState row,
    DynamicColor? override,
    int fallbackArgb,
  ) {
    if (override == null) return fallbackArgb;
    return override
        .resolve(
          cellForeground: Color(row.baseForeground),
          cellBackground: Color(row.baseBackground),
        )
        .toARGB32();
  }
}

RgbColor? _rgbColor(Color? color) {
  if (color == null) return null;
  return RgbColor(
    (color.r * 255.0).round().clamp(0, 255),
    (color.g * 255.0).round().clamp(0, 255),
    (color.b * 255.0).round().clamp(0, 255),
  );
}

/// Rebuilds dirty rows into background, foreground, and decoration channels.
final class _TerminalRowBuilder {
  final Atlas _atlas;
  final SpriteBuffer _sprites;
  final TerminalPaintState _state;
  final _FrameSnapshot _frame;
  final _RowBuildState _row;
  final _StyleResolver _styles;
  late final _ForegroundEmitter _foreground;
  var _preeditText = '';
  _PreeditRange? _preeditRange;
  LinkSnapshot linkSnapshot = .empty;
  var _hasLinks = false;

  _TerminalRowBuilder({
    required this._atlas,
    required this._sprites,
    required this._state,
    required CellContentResolver content,
  }) : _frame = _FrameSnapshot(),
       _row = _RowBuildState(),
       _styles = _StyleResolver(_state) {
    _foreground = _ForegroundEmitter(_sprites, content, _frame, _state);
  }

  bool get hasPreedit => _preeditRange != null;

  void beginFrame() {
    _frame.update(_state, atlas: _atlas);
    _styles.beginFrame();
    _hasLinks = !linkSnapshot.isEmpty;
  }

  void rebuildRow(int rowIndex, RowIterator rows, CellIterator cells) {
    _sprites.beginRow(rowIndex);
    _row.reset(rowIndex, _frame);
    cells.reset(rows);

    while (cells.next() && _row.col < _frame.cols) {
      _writeCell(cells);
    }

    _foreground.flush(_row);
    _finishBackgroundRun(_row);
    _sprites.endRow();
  }

  ({int? previous, int? current}) updatePreedit(
    String text, {
    required Cursor cursor,
  }) {
    final previous = _preeditRange;
    final previousText = _preeditText;
    final next = _PreeditRange.resolve(
      text: text,
      cursor: cursor,
      rows: _state.rows,
      cols: _state.cols,
    );

    _preeditText = text;
    _preeditRange = next;

    if (previousText == text &&
        (next?.sameGeometry(previous) ?? previous == null)) {
      return (previous: null, current: null);
    }

    return (previous: previous?.row, current: next?.row);
  }

  void _closeBackgroundSpan(_RowBuildState row, int span) {
    final endCol = row.col + span > _frame.cols ? _frame.cols : row.col + span;
    _flushBackgroundRun(row, endCol);
    row.bgRunStart = endCol;
    row.bgRunArgb = _frame.defaultBackgroundArgb;
    row.bgRunInverse = false;
    row.bgRunExplicit = false;
  }

  void _emitDecorations(
    _RowBuildState row, {
    required double x,
    required int span,
  }) {
    final style = row.style;
    final right = x + _frame.cellWidth * span;

    final underlineColor = style.underlineColor;
    final color = underlineColor != null
        ? _resolveColorArgb(_state, underlineColor, isForeground: true)
        : row.foreground;

    if (style.underline != UnderlineStyle.none) {
      final entry = _atlas.addDecoration(style.underline);
      for (var i = 0; i < span; i++) {
        _sprites.underline.add(
          x + _frame.cellWidth * i,
          row.rowY,
          entry,
          _frame.inverseDpr,
          color,
        );
      }
    }

    if (style.strikethrough) {
      final strikeY = row.rowY + _frame.strikethroughPosition;
      _sprites.decoration.add(
        x,
        strikeY,
        right,
        strikeY + _frame.strikethroughThickness,
        row.foreground,
      );
    }

    if (style.overline) {
      final overY = row.rowY + _frame.overlinePosition;
      _sprites.decoration.add(
        x,
        overY,
        right,
        overY + _frame.underlineThickness,
        row.foreground,
      );
    }
  }

  void _emitPreedit(_PreeditRange range) {
    final row = _row;
    final underlineY = row.rowY + _frame.underlinePosition;
    _sprites.decoration.add(
      range.startCol * _frame.cellWidth,
      underlineY,
      range.endCol * _frame.cellWidth,
      underlineY + _frame.underlineThickness,
      _state.terminalForegroundArgb,
    );

    var col = range.startCol;
    for (var i = range.codepointOffset; i < range.codepoints.length; i++) {
      final codepoint = range.codepoints[i];
      final nextCol = col + codepoint.span;
      if (nextCol > range.endCol) break;
      final x = col * _frame.cellWidth;
      _foreground.emitPreedit(codepoint, row, x: x);
      col = nextCol;
    }
  }

  void _finishBackgroundRun(_RowBuildState row) {
    _flushBackgroundRun(row, _frame.cols);
  }

  void _flushBackgroundRun(_RowBuildState row, int endCol) {
    if (!row.bgRunExplicit || row.bgRunStart >= endCol) return;
    _sprites.background.add(
      row.bgRunStart * _frame.cellWidth,
      row.rowY,
      endCol * _frame.cellWidth,
      row.rowBottom,
      _frame.resolveBgArgb(row.bgRunArgb, inverse: row.bgRunInverse),
    );
  }

  void _skipPreeditCell(CellIterator cell, _PreeditRange range, int span) {
    final row = _row;
    if (!row.preeditEmitted) {
      // Emit the overlay once at the first covered terminal cell, after
      // closing real background/text runs up to the overlay boundary.
      _foreground.flush(row);
      _flushBackgroundRun(row, range.startCol);
      row.bgRunStart = range.endCol;
      row.bgRunArgb = _frame.defaultBackgroundArgb;
      row.bgRunInverse = false;
      row.bgRunExplicit = false;
      _emitPreedit(range);
      row.preeditEmitted = true;
    }

    if (span == 2) cell.next();
    row.advance(span, _frame.cellWidth);
  }

  void _syncBackgroundRun(_RowBuildState row) {
    final sameRun =
        row.background == row.bgRunArgb &&
        row.backgroundExplicit == row.bgRunExplicit &&
        row.backgroundInverse == row.bgRunInverse;
    if (sameRun) return;

    _flushBackgroundRun(row, row.col);

    row.bgRunArgb = row.background;
    row.bgRunStart = row.col;
    row.bgRunInverse = row.backgroundInverse;
    row.bgRunExplicit = row.backgroundExplicit;
  }

  void _writeCell(CellIterator cell) {
    final row = _row;
    final span = cell.wide == .wide ? 2 : 1;
    final preedit = _preeditRange;
    if (preedit != null && preedit.overlaps(row.row, row.col, span)) {
      _skipPreeditCell(cell, preedit, span);
      return;
    }

    final selected = cell.isSelected;
    final HyperlinkStyle? linkStyle;
    if (!_hasLinks) {
      linkStyle = null;
    } else {
      final position = Position(row: row.row, col: row.col);
      linkStyle = linkSnapshot.isHighlighted(position)
          ? _state.theme.hyperlink.highlighted
          : linkSnapshot.contains(position)
          ? _state.theme.hyperlink.idle
          : null;
    }
    final backgroundArgb = cell.hasText ? null : cell.backgroundArgb;
    if (cell.styleId != row.prevStyleId ||
        backgroundArgb != row.prevBackgroundArgb ||
        selected != row.prevSelected ||
        linkStyle != row.prevLinkStyle) {
      _foreground.flush(row);
      _styles.update(
        cell,
        backgroundArgb: backgroundArgb,
        selected: selected,
        linkStyle: linkStyle,
        row: row,
      );
    }
    _syncBackgroundRun(row);

    if (!row.hidden) {
      final x = row.spriteX;
      _foreground.emit(cell, row, span: span);
      if (row.hasDecoration) {
        _emitDecorations(row, x: x, span: span);
      }
    } else {
      _foreground.flush(row);
    }

    if (span == 2) {
      _closeBackgroundSpan(row, span);
      cell.next();
    }
    row.advance(span, _frame.cellWidth);
  }
}
