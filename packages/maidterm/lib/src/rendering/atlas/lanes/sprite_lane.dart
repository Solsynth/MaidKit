import 'dart:ui';

import '../../sprite/sprite_face.dart';
import '../atlas_config.dart';
import '../atlas_entry.dart';
import 'atlas_lane.dart';

/// Rasterizes built-in geometry glyphs into the sprite atlas.
class SpriteLane extends AtlasLane {
  // Extra atlas pixels outside the sampled source rect. The sampled source
  // may itself extend beyond the cell so sprites can draw cell-overflowing
  // geometry while keeping cell coordinates stable.
  static const _sourceGutter = 1.0;

  final List<({SpriteGlyph glyph, Rect cell, Rect source})> _pending = [];
  final _spriteContext = SpriteContext();

  var _pxCellWidth = 0.0;
  var _pxCellHeight = 0.0;

  SpriteLane({super.initialSize, super.maxSize}) : super(entryLane: .sprite);

  @override
  bool get hasPending => _pending.isNotEmpty;

  @override
  void clearPending() {
    _pending.clear();
  }

  @override
  void configure(AtlasConfig config) {
    _pxCellWidth = config.metrics.cellWidth * config.devicePixelRatio;
    _pxCellHeight = config.metrics.cellHeight * config.devicePixelRatio;
  }

  @override
  void paintPending(Canvas canvas) {
    for (final (:glyph, :cell, :source) in _pending) {
      final paintRect = source.inflate(_sourceGutter);
      canvas.save();
      canvas.clipRect(paintRect, doAntiAlias: false);
      _paintGlyph(canvas, glyph, cell);
      _paintSourceGutter(canvas, glyph, cell, source);
      canvas.restore();
    }
    _pending.clear();
  }

  /// Reserves an atlas slot for [glyph] and returns its [AtlasEntry].
  ///
  /// The sprite is painted by its own geometry (no font rasterization) into
  /// the reserved rect on the next [ensureImage]. [span] controls how many
  /// cell widths the glyph occupies.
  AtlasEntry rasterizeSprite(SpriteGlyph glyph, {int span = 1}) {
    const g = _sourceGutter;
    final pxWidth = (_pxCellWidth * span).ceil().toDouble();
    final pxHeight = _pxCellHeight.ceil().toDouble();
    final sourcePadding = _sourcePadding(pxWidth, pxHeight);
    final slot = allocate(
      width: pxWidth + (sourcePadding + g) * 2,
      height: pxHeight + (sourcePadding + g) * 2,
      bearingX: -sourcePadding,
      bearingY: -sourcePadding,
    );
    final source = Rect.fromLTRB(
      slot.srcLeft + g,
      slot.srcTop + g,
      slot.srcRight - g,
      slot.srcBottom - g,
    );
    final cell = source.deflate(sourcePadding);
    final entry = AtlasEntry(
      srcLeft: source.left,
      srcTop: source.top,
      srcRight: source.right,
      srcBottom: source.bottom,
      bearingY: slot.bearingY,
      bearingX: slot.bearingX,
      lane: slot.lane,
    );

    _pending.add((glyph: glyph, cell: cell, source: source));
    return entry;
  }

  void _copyGutter(
    Canvas canvas,
    SpriteGlyph glyph,
    Rect cell,
    Rect clip,
    double dx,
    double dy,
  ) {
    canvas.save();
    canvas.clipRect(clip, doAntiAlias: false);
    canvas.translate(dx, dy);
    _paintGlyph(canvas, glyph, cell);
    canvas.restore();
  }

  void _paintGlyph(Canvas canvas, SpriteGlyph glyph, Rect cell) {
    _spriteContext.reset();
    glyph.paint(canvas, cell, _spriteContext);
  }

  void _paintSourceGutter(
    Canvas canvas,
    SpriteGlyph glyph,
    Rect cell,
    Rect source,
  ) {
    const g = _sourceGutter;
    final l = source.left;
    final t = source.top;
    final r = source.right;
    final b = source.bottom;
    final w = source.width;
    final h = source.height;

    // Keep sprite geometry tied to the sampled cell. Painting once into an
    // inflated cell would move fractional block and mosaic boundaries.
    _copyGutter(canvas, glyph, cell, .fromLTWH(l - g, t, g, h), -g, 0);
    _copyGutter(canvas, glyph, cell, .fromLTWH(r, t, g, h), g, 0);
    _copyGutter(canvas, glyph, cell, .fromLTWH(l, t - g, w, g), 0, -g);
    _copyGutter(canvas, glyph, cell, .fromLTWH(l, b, w, g), 0, g);
    _copyGutter(canvas, glyph, cell, .fromLTWH(l - g, t - g, g, g), -g, -g);
    _copyGutter(canvas, glyph, cell, .fromLTWH(r, t - g, g, g), g, -g);
    _copyGutter(canvas, glyph, cell, .fromLTWH(l - g, b, g, g), -g, g);
    _copyGutter(canvas, glyph, cell, .fromLTWH(r, b, g, g), g, g);
  }

  double _sourcePadding(double pxWidth, double pxHeight) {
    final cell = Rect.fromLTWH(0, 0, pxWidth, pxHeight);
    // Bounds a stroked segment that extends one thickness past the cell edge
    // plus half its thickness perpendicular to the stroke.
    return (_spriteContext.thickness(cell) * 1.5).ceilToDouble();
  }
}
