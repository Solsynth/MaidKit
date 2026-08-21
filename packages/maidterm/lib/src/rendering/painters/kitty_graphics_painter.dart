import 'dart:ui';

import 'package:flutter/painting.dart';

import '../kitty_image_cache.dart';
import '../paint_state.dart';
import 'terminal_painter.dart';

/// Paints one ordered Kitty graphics placement list.
///
/// [TerminalPainterStack] splits placements by [KittyPaintLayer] before paint,
/// so this painter only clips and draws the list it receives.
class KittyGraphicsPainter implements TerminalPainter {
  final Paint _paint;
  final KittyImageCache _cache;
  final TerminalPaintState _state;
  final List<KittyPlacementSnapshot> _snapshots;

  KittyGraphicsPainter({
    required this._cache,
    required this._state,
    required this._snapshots,
  }) : _paint = Paint()..filterQuality = .low;

  @override
  void paint(Canvas canvas) {
    if (_snapshots.isEmpty) return;
    final width = _state.cols * _state.metrics.cellWidth;
    final height = _state.rows * _state.metrics.cellHeight;
    if (width <= 0 || height <= 0) return;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, width, height));
    for (final snap in _snapshots) {
      final cached = _cache.lookupById(snap.imageId);
      if (cached is! KittyImageReady) continue;

      canvas.drawImageRect(cached.image, snap.src, snap.dst, _paint);
    }
    canvas.restore();
  }
}

/// Paint-order bucket a Kitty placement falls into based on its z-index.
///
/// Mirrors the Kitty graphics protocol's three-bucket convention.
enum KittyPaintLayer {
  /// Painted beneath cell backgrounds.
  belowBg,

  /// Painted between cell backgrounds and text.
  belowText,

  /// Painted above text, beneath the selection overlay.
  aboveText;

  // The protocol splits negative z values in half at INT32_MIN / 2:
  // anything further negative than that paints below the cell
  // background, the rest paints above the background but below text.
  static const int _bgThreshold = -1 << 30;

  /// Returns the layer for a placement with the given [z].
  static KittyPaintLayer forZ(int z) {
    if (z >= 0) return aboveText;
    if (z < _bgThreshold) return belowBg;
    return belowText;
  }
}

/// Placement data consumed by [KittyGraphicsPainter], decoupled from
/// the live terminal so paint never reaches back into libghostty.
class KittyPlacementSnapshot {
  final int imageId;

  /// Destination rectangle in the same logical-pixel space as cells.
  final Rect dst;

  /// Source rectangle in the image's own pixel space.
  final Rect src;

  /// Signed z-index. See [KittyPaintLayer] for the layer mapping.
  final int z;

  const KittyPlacementSnapshot({
    required this.imageId,
    required this.dst,
    required this.src,
    required this.z,
  });
}
