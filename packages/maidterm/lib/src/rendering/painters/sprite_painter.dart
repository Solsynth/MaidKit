import 'dart:ui';

import 'package:flutter/painting.dart';

import '../atlas/atlas.dart';
import '../atlas/sprite_buffer.dart';
import 'terminal_painter.dart';

/// Paints built-in sprite glyphs via a batched [Canvas.drawRawAtlas] call.
///
/// Sprite glyphs live in their own atlas texture and are tinted per-sprite
/// with the resolved cell foreground.
class SpritePainter implements TerminalPainter {
  final Paint _paint;
  final Atlas _atlas;
  final SpriteBuffer _sprites;

  SpritePainter(this._atlas, this._sprites) : _paint = Paint();

  @override
  void paint(Canvas canvas) {
    final sprites = _sprites.sprite;
    final image = _atlas.spriteImage;
    if (image == null || !sprites.hasSprites) return;
    canvas.drawRawAtlas(
      image,
      sprites.sealedTransforms,
      sprites.sealedRects,
      sprites.sealedColors,
      BlendMode.modulate,
      null,
      _paint,
    );
  }
}
