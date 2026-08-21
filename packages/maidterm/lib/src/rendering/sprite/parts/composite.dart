part of '../sprite_face.dart';

final class Composite extends SpriteGlyph {
  final List<SpriteGlyph> parts;

  const Composite(this.parts);

  @override
  void paint(Canvas canvas, Rect cell, SpriteContext ctx) {
    final fillColor = ctx.fill.color;
    final strokeColor = ctx.stroke.color;
    final fillBlendMode = ctx.fill.blendMode;
    final strokeBlendMode = ctx.stroke.blendMode;
    for (final part in parts) {
      ctx.resetForGlyph(
        fillColor: fillColor,
        strokeColor: strokeColor,
        fillBlendMode: fillBlendMode,
        strokeBlendMode: strokeBlendMode,
      );
      part.paint(canvas, cell, ctx);
    }
  }
}
