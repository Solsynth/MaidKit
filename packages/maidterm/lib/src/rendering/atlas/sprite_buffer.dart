import 'dart:typed_data';
import 'dart:ui';

import 'atlas_entry.dart';

/// A shaped text run that must be painted through Flutter's paragraph shaper.
///
/// Used for terminal text where ligatures matter. These runs are not atlas
/// entries because Flutter does not expose glyph IDs, and caching arbitrary
/// source strings as atlas images causes unbounded native image growth.
final class ShapedRun {
  final Paragraph paragraph;
  final Offset offset;
  final Rect clip;

  const ShapedRun({
    required this.paragraph,
    required this.offset,
    required this.clip,
  });

  void dispose() => paragraph.dispose();
}

/// Row-retained shaped text runs.
///
/// Dirty rows replace only their own paragraph runs. Clean rows keep their
/// already laid-out paragraphs so repaint does not require reshaping.
final class ShapedRunBuffer {
  List<List<ShapedRun>> _rows = const [];
  var _activeRuns = 0;
  var _currentRow = -1;

  int get count => _activeRuns;

  List<List<ShapedRun>> get rows => _rows;

  void add(ShapedRun run) {
    assert(_currentRow >= 0, 'add() called outside beginRow/endRow');
    _rows[_currentRow].add(run);
    _activeRuns++;
  }

  void beginRow(int row) {
    _currentRow = row;
    final runs = _rows[row];
    _activeRuns -= runs.length;
    for (final run in runs) {
      run.dispose();
    }
    runs.clear();
  }

  void configure(int rowCount) {
    _disposeRows();
    _activeRuns = 0;
    _currentRow = -1;
    _rows = List.generate(rowCount, (_) => <ShapedRun>[]);
  }

  void dispose() {
    _disposeRows();
    _rows = const [];
    _activeRuns = 0;
    _currentRow = -1;
  }

  void endRow() {
    assert(_currentRow >= 0, 'endRow() without beginRow()');
    _currentRow = -1;
  }

  void seal() {
    assert(_currentRow < 0, 'seal() called before endRow()');
  }

  void _disposeRows() {
    for (final row in _rows) {
      for (final run in row) {
        run.dispose();
      }
      row.clear();
    }
    _activeRuns = 0;
  }
}

/// Sprite data for [Canvas.drawRawAtlas] calls, organized as fixed per-row
/// slot ranges for incremental row-dirty rebuilds.
///
/// Each row owns a contiguous slice of `stride` slots in the flat buffer.
/// Dirty rows rewrite their slots via [beginRow]/[add]/[endRow]; clean
/// rows keep the sprites they had last frame with zero work. [seal]
/// packs each channel's active slots into a tight array so painters
/// submit exactly `count` sprites to [Canvas.drawRawAtlas] without
/// interleaved degenerate quads (Skia does not reliably cull scale-0
/// RSTransforms, so leaving them in the submission corrupts output).
///
/// Packing on [seal] is incremental: only rows from the first dirty
/// row onward are re-copied; rows before it keep their packed position
/// because their counts are unchanged.
class AtlasSprites {
  var _transforms = Float32List(0);
  var _rects = Float32List(0);
  var _colors = Int32List(0);
  var _rowCounts = Int32List(0);
  var _packedTransforms = Float32List(0);
  var _packedRects = Float32List(0);
  var _packedColors = Int32List(0);
  var _packedStarts = Int32List(0);
  var _rowCount = 0;
  var _stride = 0;
  var _activeSlots = 0;
  var _currentRow = -1;
  var _writeOffset = 0;
  var _firstDirtyRow = 0;

  /// Total number of active sprites across all rows.
  int get count => _activeSlots;

  /// Whether any row has at least one active sprite.
  bool get hasSprites => _activeSlots > 0;

  /// Per-sprite ARGB tints, packed to `count` entries after [seal].
  Int32List get sealedColors =>
      Int32List.sublistView(_packedColors, 0, _activeSlots);

  /// Per-sprite source rects (LTRB), packed to `count * 4` floats after [seal].
  Float32List get sealedRects =>
      Float32List.sublistView(_packedRects, 0, _activeSlots * 4);

  /// Per-sprite RST transforms, packed to `count * 4` floats after [seal].
  Float32List get sealedTransforms =>
      Float32List.sublistView(_packedTransforms, 0, _activeSlots * 4);

  /// Appends a sprite to the current row (must be inside [beginRow]/[endRow]).
  void add(
    double x,
    double y,
    AtlasEntry entry,
    double inverseDpr, [
    int argb = 0,
  ]) {
    assert(_currentRow >= 0, 'add() called outside beginRow/endRow');
    assert(_writeOffset < _stride, 'row $_currentRow exceeded stride $_stride');
    final slot = _currentRow * _stride + _writeOffset;
    final offset4 = slot * 4;
    _transforms[offset4] = inverseDpr;
    _transforms[offset4 + 1] = 0.0;
    _transforms[offset4 + 2] = x;
    _transforms[offset4 + 3] = y;
    _rects[offset4] = entry.srcLeft;
    _rects[offset4 + 1] = entry.srcTop;
    _rects[offset4 + 2] = entry.srcRight;
    _rects[offset4 + 3] = entry.srcBottom;
    _colors[slot] = argb;
    _writeOffset++;
  }

  /// Begins rewriting row [row]'s slots. Call only for dirty rows.
  void beginRow(int row) {
    _currentRow = row;
    _writeOffset = 0;
    if (row < _firstDirtyRow) _firstDirtyRow = row;
  }

  /// Reconfigures the buffer for a grid of [rowCount] rows with [stride]
  /// slots per row.
  ///
  /// Grows on demand; shrinks only when the current buffer is more than
  /// 4x the new requirement so routine resize drags don't churn
  /// allocations but a step down from (e.g.) 300x100 to 80x24 releases
  /// the excess.
  void configure(int rowCount, int stride) {
    _rowCount = rowCount;
    _stride = stride;
    final totalSlots = rowCount * stride;
    final need = totalSlots * 4;
    if (_transforms.length < need || _transforms.length > need * 4) {
      _transforms = Float32List(need);
      _rects = Float32List(need);
      _colors = Int32List(totalSlots);
    }
    if (_rowCounts.length < rowCount || _rowCounts.length > rowCount * 4) {
      _rowCounts = Int32List(rowCount);
    } else {
      _rowCounts.fillRange(0, rowCount, 0);
    }
    _activeSlots = 0;
    _currentRow = -1;
    _writeOffset = 0;
    _firstDirtyRow = 0;
  }

  /// Releases all buffers so their memory can be collected. The instance
  /// must not be used again after this call.
  void dispose() {
    _transforms = Float32List(0);
    _rects = Float32List(0);
    _colors = Int32List(0);
    _rowCounts = Int32List(0);
    _packedTransforms = Float32List(0);
    _packedRects = Float32List(0);
    _packedColors = Int32List(0);
    _packedStarts = Int32List(0);
    _activeSlots = 0;
    _rowCount = 0;
    _stride = 0;
    _currentRow = -1;
    _writeOffset = 0;
    _firstDirtyRow = 0;
  }

  /// Finishes the current row.
  void endRow() {
    assert(_currentRow >= 0, 'endRow() without beginRow()');
    final oldCount = _rowCounts[_currentRow];
    final newCount = _writeOffset;
    _activeSlots += newCount - oldCount;
    _rowCounts[_currentRow] = newCount;
    _currentRow = -1;
  }

  /// Packs active slots into the contiguous arrays returned by
  /// [sealedTransforms] and friends.
  ///
  /// Incremental: rows before [_firstDirtyRow] already sit at the right
  /// packed offsets from the previous seal, so only rows from that
  /// point onward are re-copied. When the packed buffer has to grow,
  /// the prefix is no longer backed by valid data and we restart from
  /// row 0.
  void seal() {
    if (_firstDirtyRow >= _rowCount) return;

    final need = _activeSlots;
    var start = _firstDirtyRow;
    if (need > 0 &&
        (_packedTransforms.length < need * 4 ||
            _packedTransforms.length > need * 16)) {
      _packedTransforms = Float32List(need * 4);
      _packedRects = Float32List(need * 4);
      _packedColors = Int32List(need);
      start = 0;
    }
    if (_packedStarts.length < _rowCount + 1) {
      _packedStarts = Int32List(_rowCount + 1);
      start = 0;
    }

    var dst = _packedStarts[start];
    for (var row = start; row < _rowCount; row++) {
      _packedStarts[row] = dst;
      final rowCount = _rowCounts[row];
      if (rowCount > 0) {
        final srcBase = row * _stride;
        _packedTransforms.setRange(
          dst * 4,
          (dst + rowCount) * 4,
          _transforms,
          srcBase * 4,
        );
        _packedRects.setRange(
          dst * 4,
          (dst + rowCount) * 4,
          _rects,
          srcBase * 4,
        );
        _packedColors.setRange(dst, dst + rowCount, _colors, srcBase);
      }
      dst += rowCount;
    }
    _packedStarts[_rowCount] = dst;
    _firstDirtyRow = _rowCount;
  }
}

/// Rect and color data for [Canvas.drawVertices] calls, organized as
/// fixed per-row slot ranges.
///
/// Stores LTRB rects during the sprite build phase. [buildVertices]
/// expands active rects into a tight indexed triangle-quad buffer for
/// a single [Canvas.drawVertices] call. Used for cell backgrounds and
/// text decorations (underlines, strikethroughs, overlines).
///
/// Expansion on [buildVertices] is incremental: rows before the first
/// dirty row keep their vertex data from the previous call. A fresh
/// [Vertices] is constructed only when rect contents actually changed.
class RectSprites {
  var _rects = Float32List(0);
  var _colors = Int32List(0);
  var _rowCounts = Int32List(0);
  var _positions = Float32List(0);
  var _vertexColors = Int32List(0);
  var _vertexStarts = Int32List(0);
  Vertices? _cachedVertices;
  var _rowCount = 0;
  var _stride = 0;
  var _activeSlots = 0;
  var _currentRow = -1;
  var _writeOffset = 0;
  var _firstDirtyRow = 0;

  /// The [Vertices] produced by the most recent [buildVertices] call,
  /// or null when no row has an active rect.
  Vertices? get cachedVertices => _cachedVertices;

  /// Total number of active rects across all rows.
  int get count => _activeSlots;

  /// Whether any row has at least one active rect.
  bool get hasSprites => _activeSlots > 0;

  /// Appends a colored rect to the current row.
  void add(double left, double top, double right, double bottom, int argb) {
    assert(_currentRow >= 0, 'add() called outside beginRow/endRow');
    assert(_writeOffset < _stride, 'row $_currentRow exceeded stride $_stride');
    final slot = _currentRow * _stride + _writeOffset;
    final offset4 = slot * 4;
    _rects[offset4] = left;
    _rects[offset4 + 1] = top;
    _rects[offset4 + 2] = right;
    _rects[offset4 + 3] = bottom;
    _colors[slot] = argb;
    _writeOffset++;
  }

  /// Begins rewriting row [row]'s slots. Call only for dirty rows.
  void beginRow(int row) {
    _currentRow = row;
    _writeOffset = 0;
    if (row < _firstDirtyRow) _firstDirtyRow = row;
  }

  /// Walks per-row active rects and expands them into a tight indexed
  /// triangle-quad buffer for [Canvas.drawVertices].
  ///
  /// Returns null when no row has any active rect. Returns the cached
  /// [Vertices] unchanged when no row has been dirtied since the last
  /// call (skipping the per-cell expand and the [Vertices.raw] alloc).
  Vertices? buildVertices(Uint16List indices) {
    if (_firstDirtyRow >= _rowCount) return _cachedVertices;

    final posLen = _activeSlots * 8;
    final colLen = _activeSlots * 4;
    var start = _firstDirtyRow;
    if (_activeSlots > 0 &&
        (_positions.length < posLen || _positions.length > posLen * 4)) {
      _positions = Float32List(posLen);
      _vertexColors = Int32List(colLen);
      start = 0;
    }
    if (_vertexStarts.length < _rowCount + 1) {
      _vertexStarts = Int32List(_rowCount + 1);
      start = 0;
    }

    var dst = _vertexStarts[start];
    for (var row = start; row < _rowCount; row++) {
      _vertexStarts[row] = dst;
      final rowCount = _rowCounts[row];
      if (rowCount > 0) {
        final srcBase = row * _stride;
        for (var i = 0; i < rowCount; i++) {
          final srcOffset = (srcBase + i) * 4;
          final left = _rects[srcOffset];
          final top = _rects[srcOffset + 1];
          final right = _rects[srcOffset + 2];
          final bottom = _rects[srcOffset + 3];
          final posOffset = dst * 8;
          _positions[posOffset] = left;
          _positions[posOffset + 1] = top;
          _positions[posOffset + 2] = right;
          _positions[posOffset + 3] = top;
          _positions[posOffset + 4] = right;
          _positions[posOffset + 5] = bottom;
          _positions[posOffset + 6] = left;
          _positions[posOffset + 7] = bottom;
          final argb = _colors[srcBase + i];
          final colOffset = dst * 4;
          _vertexColors[colOffset] = argb;
          _vertexColors[colOffset + 1] = argb;
          _vertexColors[colOffset + 2] = argb;
          _vertexColors[colOffset + 3] = argb;
          dst++;
        }
      }
    }
    _vertexStarts[_rowCount] = dst;
    _firstDirtyRow = _rowCount;

    _cachedVertices?.dispose();
    if (_activeSlots == 0) return _cachedVertices = null;
    return _cachedVertices = Vertices.raw(
      VertexMode.triangles,
      Float32List.sublistView(_positions, 0, posLen),
      colors: Int32List.sublistView(_vertexColors, 0, colLen),
      indices: Uint16List.sublistView(indices, 0, _activeSlots * 6),
    );
  }

  /// Reconfigures the buffer for [rowCount] rows with [stride] slots per row.
  ///
  /// Grows on demand; shrinks only when the current buffer is more than
  /// 4x the new requirement.
  void configure(int rowCount, int stride) {
    _rowCount = rowCount;
    _stride = stride;
    final totalSlots = rowCount * stride;
    final need = totalSlots * 4;
    if (_rects.length < need || _rects.length > need * 4) {
      _rects = Float32List(need);
      _colors = Int32List(totalSlots);
    }
    if (_rowCounts.length < rowCount || _rowCounts.length > rowCount * 4) {
      _rowCounts = Int32List(rowCount);
    } else {
      _rowCounts.fillRange(0, rowCount, 0);
    }
    _activeSlots = 0;
    _currentRow = -1;
    _writeOffset = 0;
    _firstDirtyRow = 0;
    _cachedVertices?.dispose();
    _cachedVertices = null;
  }

  /// Releases all buffers and any cached [Vertices]. The instance must
  /// not be used again after this call.
  void dispose() {
    _rects = Float32List(0);
    _colors = Int32List(0);
    _rowCounts = Int32List(0);
    _positions = Float32List(0);
    _vertexColors = Int32List(0);
    _vertexStarts = Int32List(0);
    _cachedVertices?.dispose();
    _cachedVertices = null;
    _activeSlots = 0;
    _rowCount = 0;
    _stride = 0;
    _currentRow = -1;
    _writeOffset = 0;
    _firstDirtyRow = 0;
  }

  /// Finishes the current row.
  void endRow() {
    assert(_currentRow >= 0, 'endRow() without beginRow()');
    final oldCount = _rowCounts[_currentRow];
    final newCount = _writeOffset;
    _activeSlots += newCount - oldCount;
    _rowCounts[_currentRow] = newCount;
    _currentRow = -1;
  }
}

/// Assembled sprite data for all terminal visual layers, organized as
/// fixed per-row slot ranges for incremental row-dirty rebuilds.
///
/// Written by the terminal frame builder during the update phase. Read by
/// painters during the paint phase. Dirty rows are rewritten via
/// [beginRow]/[endRow]; clean rows are left untouched across frames.
/// [seal] packs each channel's active slots into tight buffers (atlas
/// channels for [Canvas.drawRawAtlas], rect channels for
/// [Canvas.drawVertices]).
///
/// Contains sprite channels consumed by dedicated painters:
/// [regular] and [wide] for text, [sprite] for built-in glyph geometry,
/// [emoji] for full-color glyphs, [background] for cell color runs,
/// [underline] for underline decoration sprites, and [decoration] for
/// strikethroughs and overlines.
class SpriteBuffer {
  /// Regular-width text glyphs.
  final AtlasSprites regular;

  /// Wide (2-cell) text glyphs (CJK).
  final AtlasSprites wide;

  /// Built-in sprite glyphs.
  final AtlasSprites sprite;

  /// Full-color emoji glyphs.
  final AtlasSprites emoji;

  /// Cell background color runs.
  final RectSprites background;

  /// Underline decoration atlas sprites, tinted with underline color.
  final AtlasSprites underline;

  /// Rect-based decorations (strikethroughs, overlines).
  final RectSprites decoration;

  /// Paragraph-shaped text runs for ligatures.
  final ShapedRunBuffer shaped;

  var _indices = Uint16List(0);

  SpriteBuffer()
    : regular = AtlasSprites(),
      wide = AtlasSprites(),
      sprite = AtlasSprites(),
      emoji = AtlasSprites(),
      background = RectSprites(),
      underline = AtlasSprites(),
      decoration = RectSprites(),
      shaped = ShapedRunBuffer();

  /// Finalized background vertex data, available after [seal].
  Vertices? get backgroundVertices => background.cachedVertices;

  /// Finalized decoration vertex data, available after [seal].
  Vertices? get decorationVertices => decoration.cachedVertices;

  /// Begins rewriting row [row] across every channel.
  ///
  /// Call once per dirty row, followed by the emit calls and [endRow].
  /// Clean rows must not be bracketed: their slots stay untouched.
  void beginRow(int row) {
    regular.beginRow(row);
    wide.beginRow(row);
    sprite.beginRow(row);
    emoji.beginRow(row);
    background.beginRow(row);
    underline.beginRow(row);
    decoration.beginRow(row);
    shaped.beginRow(row);
  }

  /// Reconfigures all channels for a grid of [rows] rows and [cols]
  /// columns.
  ///
  /// Stride per channel is the per-row upper bound on sprite emits:
  /// `cols + 1` for text/background/underline channels (cells emit
  /// at most once plus one end-of-row flush), and `2 * cols + 1` for
  /// decorations (a cell can emit both strikethrough and overline).
  void configure(int rows, int cols) {
    final atlasStride = cols + 1;
    regular.configure(rows, atlasStride);
    wide.configure(rows, atlasStride);
    sprite.configure(rows, atlasStride);
    emoji.configure(rows, atlasStride);
    background.configure(rows, atlasStride);
    underline.configure(rows, atlasStride);
    decoration.configure(rows, 2 * cols + 1);
    shaped.configure(rows);
  }

  /// Releases buffers, sized arrays and cached [Vertices] for all
  /// channels. The buffer must not be used again after this call.
  void dispose() {
    regular.dispose();
    wide.dispose();
    sprite.dispose();
    emoji.dispose();
    background.dispose();
    underline.dispose();
    decoration.dispose();
    shaped.dispose();
    _indices = Uint16List(0);
  }

  /// Ends the row started by [beginRow] across every channel.
  void endRow() {
    regular.endRow();
    wide.endRow();
    sprite.endRow();
    emoji.endRow();
    background.endRow();
    underline.endRow();
    decoration.endRow();
    shaped.endRow();
  }

  /// Packs atlas channels and builds vertex data for rect channels.
  void seal() {
    regular.seal();
    wide.seal();
    sprite.seal();
    emoji.seal();
    underline.seal();
    shaped.seal();
    final maxRects = background.count > decoration.count
        ? background.count
        : decoration.count;
    if (maxRects > 0) _ensureIndices(maxRects);
    background.buildVertices(_indices);
    decoration.buildVertices(_indices);
  }

  void _ensureIndices(int rectCount) {
    final needed = rectCount * 6;
    if (_indices.length >= needed) return;
    // Power-of-two growth amortizes churn when rect counts drift across
    // frames.
    var size = _indices.isEmpty ? 384 : _indices.length;
    while (size < needed) {
      size *= 2;
    }
    final indices = Uint16List(size);
    final quadCount = size ~/ 6;
    for (var i = 0; i < quadCount; i++) {
      final base = i * 4;
      final offset = i * 6;
      indices[offset] = base;
      indices[offset + 1] = base + 1;
      indices[offset + 2] = base + 2;
      indices[offset + 3] = base;
      indices[offset + 4] = base + 2;
      indices[offset + 5] = base + 3;
    }
    _indices = indices;
  }
}
