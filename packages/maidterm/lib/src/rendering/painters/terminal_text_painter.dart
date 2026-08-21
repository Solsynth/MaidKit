import 'dart:ui';

import 'package:flutter/painting.dart';

import '../atlas/atlas.dart';
import '../atlas/sprite_buffer.dart';
import 'terminal_painter.dart';

/// Paints regular-width and wide text glyphs via batched [Canvas.drawRawAtlas]
/// calls.
///
/// Text glyphs are pre-rendered into an [Atlas] during the update phase.
/// The atlas stores white glyph bitmaps tinted per-sprite via
/// [BlendMode.modulate] to produce colored text with zero per-glyph draw
/// calls.
class TerminalTextPainter implements TerminalPainter {
  final Paint _paint;
  final Atlas _atlas;
  final AtlasSprites _wide;
  final AtlasSprites _regular;

  TerminalTextPainter(this._atlas, this._wide, this._regular)
    : _paint = Paint();

  @override
  void paint(Canvas canvas) {
    final image = _atlas.textImage;
    if (image == null) return;

    if (_regular.hasSprites) {
      canvas.drawRawAtlas(
        image,
        _regular.sealedTransforms,
        _regular.sealedRects,
        _regular.sealedColors,
        BlendMode.modulate,
        null,
        _paint,
      );
    }
    if (_wide.hasSprites) {
      canvas.drawRawAtlas(
        image,
        _wide.sealedTransforms,
        _wide.sealedRects,
        _wide.sealedColors,
        BlendMode.modulate,
        null,
        _paint,
      );
    }
  }
}
