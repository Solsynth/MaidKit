part of '../sprite_face.dart';

final class KnockoutComposite extends SpriteGlyph {
  final List<SpriteGlyph> cutouts;

  const KnockoutComposite(this.cutouts);

  @override
  void paint(Canvas canvas, Rect cell, SpriteContext ctx) {
    canvas.saveLayer(cell, Paint());
    drawBox(canvas, ctx.fill, cell.left, cell.top, cell.right, cell.bottom);

    final fillColor = ctx.fill.color;
    final strokeColor = ctx.stroke.color;
    final fillBlendMode = ctx.fill.blendMode;
    final strokeBlendMode = ctx.stroke.blendMode;

    for (final cutout in cutouts) {
      ctx.resetForGlyph(
        fillColor: fillColor,
        strokeColor: strokeColor,
        fillBlendMode: BlendMode.clear,
        strokeBlendMode: BlendMode.clear,
      );
      cutout.paint(canvas, cell, ctx);
    }

    ctx.fill
      ..color = fillColor
      ..blendMode = fillBlendMode;
    ctx.stroke
      ..color = strokeColor
      ..blendMode = strokeBlendMode;
    canvas.restore();
  }
}
