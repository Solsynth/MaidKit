part of '../sprite_face.dart';

final class BoxLines extends SpriteGlyph {
  final int up;
  final int right;
  final int down;
  final int left;

  const BoxLines({this.up = 0, this.right = 0, this.down = 0, this.left = 0});

  @override
  void paint(Canvas canvas, Rect cell, SpriteContext ctx) {
    final lt = ctx.thickness(cell);
    final ht = lt * 2;
    final w = cell.width;
    final h = cell.height;
    final ox = cell.left;
    final oy = cell.top;

    final hLightTop = (h - lt) / 2;
    final hLightBot = hLightTop + lt;
    final hHeavyTop = (h - ht) / 2;
    final hHeavyBot = hHeavyTop + ht;
    final hDoubleTop = hLightTop - lt;
    final hDoubleBot = hLightBot + lt;

    final vLightLeft = (w - lt) / 2;
    final vLightRight = vLightLeft + lt;
    final vHeavyLeft = (w - ht) / 2;
    final vHeavyRight = vHeavyLeft + ht;
    final vDoubleLeft = vLightLeft - lt;
    final vDoubleRight = vLightRight + lt;

    final upBottom = _extent(
      left,
      right,
      down,
      up,
      hHeavyBot,
      hDoubleBot,
      hLightBot,
      hLightTop,
    );
    final downTop = _extent(
      left,
      right,
      up,
      down,
      hHeavyTop,
      hDoubleTop,
      hLightTop,
      hLightBot,
    );
    final leftRight = _extent(
      up,
      down,
      left,
      right,
      vHeavyRight,
      vDoubleRight,
      vLightRight,
      vLightLeft,
    );
    final rightLeft = _extent(
      up,
      down,
      right,
      left,
      vHeavyLeft,
      vDoubleLeft,
      vLightLeft,
      vLightRight,
    );

    final paint = ctx.fill..isAntiAlias = false;

    switch (up) {
      case 1:
        drawBox(
          canvas,
          paint,
          ox + vLightLeft,
          oy,
          ox + vLightRight,
          oy + upBottom,
        );
      case 2:
        drawBox(
          canvas,
          paint,
          ox + vHeavyLeft,
          oy,
          ox + vHeavyRight,
          oy + upBottom,
        );
      case 3:
        final lb = left == 3 ? hLightTop : upBottom;
        final rb = right == 3 ? hLightTop : upBottom;
        drawBox(canvas, paint, ox + vDoubleLeft, oy, ox + vLightLeft, oy + lb);
        drawBox(
          canvas,
          paint,
          ox + vLightRight,
          oy,
          ox + vDoubleRight,
          oy + rb,
        );
    }

    switch (right) {
      case 1:
        drawBox(
          canvas,
          paint,
          ox + rightLeft,
          oy + hLightTop,
          ox + w,
          oy + hLightBot,
        );
      case 2:
        drawBox(
          canvas,
          paint,
          ox + rightLeft,
          oy + hHeavyTop,
          ox + w,
          oy + hHeavyBot,
        );
      case 3:
        final tl = up == 3 ? vLightRight : rightLeft;
        final bl = down == 3 ? vLightRight : rightLeft;
        drawBox(
          canvas,
          paint,
          ox + tl,
          oy + hDoubleTop,
          ox + w,
          oy + hLightTop,
        );
        drawBox(
          canvas,
          paint,
          ox + bl,
          oy + hLightBot,
          ox + w,
          oy + hDoubleBot,
        );
    }

    switch (down) {
      case 1:
        drawBox(
          canvas,
          paint,
          ox + vLightLeft,
          oy + downTop,
          ox + vLightRight,
          oy + h,
        );
      case 2:
        drawBox(
          canvas,
          paint,
          ox + vHeavyLeft,
          oy + downTop,
          ox + vHeavyRight,
          oy + h,
        );
      case 3:
        final lt2 = left == 3 ? hLightBot : downTop;
        final rt = right == 3 ? hLightBot : downTop;
        drawBox(
          canvas,
          paint,
          ox + vDoubleLeft,
          oy + lt2,
          ox + vLightLeft,
          oy + h,
        );
        drawBox(
          canvas,
          paint,
          ox + vLightRight,
          oy + rt,
          ox + vDoubleRight,
          oy + h,
        );
    }

    switch (left) {
      case 1:
        drawBox(
          canvas,
          paint,
          ox,
          oy + hLightTop,
          ox + leftRight,
          oy + hLightBot,
        );
      case 2:
        drawBox(
          canvas,
          paint,
          ox,
          oy + hHeavyTop,
          ox + leftRight,
          oy + hHeavyBot,
        );
      case 3:
        final tr = up == 3 ? vLightLeft : leftRight;
        final br = down == 3 ? vLightLeft : leftRight;
        drawBox(canvas, paint, ox, oy + hDoubleTop, ox + tr, oy + hLightTop);
        drawBox(canvas, paint, ox, oy + hLightBot, ox + br, oy + hDoubleBot);
    }
  }

  static double _extent(
    int perp1,
    int perp2,
    int parallel,
    int self,
    double heavy,
    double dbl,
    double light,
    double alt,
  ) {
    if (perp1 == 2 || perp2 == 2) return heavy;
    if (perp1 != perp2 || parallel == self) {
      return (perp1 == 3 || perp2 == 3) ? dbl : light;
    }
    if (perp1 == 0 && perp2 == 0) return light;
    return alt;
  }
}
