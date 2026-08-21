import 'dart:ui';

import 'package:flutter/painting.dart';

import '../atlas/atlas.dart';
import '../atlas/sprite_buffer.dart';
import 'terminal_painter.dart';

/// Paints underline decoration sprites via [Canvas.drawRawAtlas].
///
/// Underlines are rasterized as white glyphs in the atlas (one per style)
/// and tinted per-sprite with the underline color via [BlendMode.modulate].
/// Drawn BEFORE text so that descender glyphs cover the underline at
/// intersections.
class UnderlinePainter implements TerminalPainter {
  final Paint _paint;
  final Atlas _atlas;
  final SpriteBuffer _sprites;

  UnderlinePainter(this._atlas, this._sprites) : _paint = Paint();

  @override
  void paint(Canvas canvas) {
    final image = _atlas.decorationImage;
    final underline = _sprites.underline;
    if (image == null || !underline.hasSprites) return;
    canvas.drawRawAtlas(
      image,
      underline.sealedTransforms,
      underline.sealedRects,
      underline.sealedColors,
      BlendMode.modulate,
      null,
      _paint,
    );
  }
}
