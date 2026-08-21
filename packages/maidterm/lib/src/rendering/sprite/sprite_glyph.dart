part of 'sprite_face.dart';

sealed class SpriteGlyph {
  const SpriteGlyph();

  void paint(Canvas canvas, Rect cell, SpriteContext ctx);
}
