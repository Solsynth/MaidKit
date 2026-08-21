part of '../sprite_face.dart';

final class BoxSpur extends SpriteGlyph {
  final BoxSpurY y;
  final BoxSpurSide side;
  final BoxSpurHalf half;

  const BoxSpur({required this.y, required this.side, required this.half});

  @override
  void paint(Canvas canvas, Rect cell, SpriteContext ctx) {
    final thickness = ctx.thickness(cell);
    final w = cell.width;
    final h = cell.height;
    final ox = cell.left;
    final oy = cell.top;

    final hTop = switch (y) {
      .top => oy,
      .center => oy + (h - thickness) / 2,
      .bottom => oy + h - thickness,
    };
    drawBox(canvas, ctx.fill, ox, hTop, ox + w, hTop + thickness);

    final vLeft = switch (side) {
      .left => ox,
      .right => ox + w - thickness,
    };
    final vTop = switch (half) {
      .top => oy,
      .bottom => oy + h / 2,
    };
    final vBottom = switch (half) {
      .top => oy + h / 2,
      .bottom => oy + h,
    };
    drawBox(canvas, ctx.fill, vLeft, vTop, vLeft + thickness, vBottom);
  }
}

enum BoxSpurHalf { top, bottom }

enum BoxSpurSide { left, right }

enum BoxSpurY { top, center, bottom }
