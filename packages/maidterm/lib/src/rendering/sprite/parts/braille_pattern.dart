part of '../sprite_face.dart';

final class BraillePattern extends SpriteGlyph {
  final int pattern;

  const BraillePattern(this.pattern);

  @override
  void paint(Canvas canvas, Rect cell, SpriteContext ctx) {
    if (pattern == 0) return;

    final iw = cell.width.toInt();
    final ih = cell.height.toInt();

    var dotW = math.min(iw ~/ 4, ih ~/ 8);
    var xSpacing = iw ~/ 4;
    var ySpacing = ih ~/ 8;
    var xMargin = xSpacing ~/ 2;
    var yMargin = ySpacing ~/ 2;

    var xLeft = iw - 2 * xMargin - xSpacing - 2 * dotW;
    var yLeft = ih - 2 * yMargin - 3 * ySpacing - 4 * dotW;

    if (xLeft >= 2 && yLeft >= 4 && dotW == 0) {
      dotW += 1;
      xLeft -= 2;
      yLeft -= 4;
    }
    if (xLeft >= 2 && xMargin == 0) {
      xMargin = 1;
      xLeft -= 2;
    }
    if (yLeft >= 2 && yMargin == 0) {
      yMargin = 1;
      yLeft -= 2;
    }
    if (xLeft >= 1) {
      xSpacing += 1;
      xLeft -= 1;
    }
    if (yLeft >= 3) {
      ySpacing += 1;
      yLeft -= 3;
    }
    if (xLeft >= 2) {
      xMargin += 1;
      xLeft -= 2;
    }
    if (yLeft >= 2) {
      yMargin += 1;
      yLeft -= 2;
    }
    if (xLeft >= 2 && yLeft >= 4) {
      dotW += 1;
    }

    final xPos = [xMargin, xMargin + dotW + xSpacing];
    final yPos = [
      yMargin,
      yMargin + dotW + ySpacing,
      yMargin + 2 * (dotW + ySpacing),
      yMargin + 3 * (dotW + ySpacing),
    ];

    const dotCol = [0, 0, 0, 1, 1, 1, 0, 1];
    const dotRow = [0, 1, 2, 0, 1, 2, 3, 3];

    final ox = cell.left;
    final oy = cell.top;
    final dw = dotW.toDouble();
    for (var i = 0; i < 8; i++) {
      if (pattern & (1 << i) == 0) continue;
      final dx = ox + xPos[dotCol[i]];
      final dy = oy + yPos[dotRow[i]];
      drawBox(canvas, ctx.fill, dx, dy, dx + dw, dy + dw);
    }
  }
}
