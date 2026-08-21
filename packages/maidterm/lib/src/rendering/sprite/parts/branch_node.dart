part of '../sprite_face.dart';

final class BranchNode extends SpriteGlyph {
  final bool up;
  final bool right;
  final bool down;
  final bool left;
  final bool filled;

  const BranchNode({
    this.up = false,
    this.right = false,
    this.down = false,
    this.left = false,
    this.filled = false,
  });

  @override
  void paint(Canvas canvas, Rect cell, SpriteContext ctx) {
    final thickness = ctx.thickness(cell);
    final w = cell.width;
    final h = cell.height;

    final hTop = (h - thickness) / 2;
    final hBottom = hTop + thickness;
    final vLeft = (w - thickness) / 2;
    final vRight = vLeft + thickness;

    final cx = vLeft + thickness / 2;
    final cy = hTop + thickness / 2;
    final radius = math.min(math.min(cx, cy), math.min(w - cx, h - cy));

    if (up) {
      drawBox(
        canvas,
        ctx.fill,
        cell.left + vLeft,
        cell.top,
        cell.left + vRight,
        cell.top + (cy - radius + thickness / 2).ceilToDouble(),
      );
    }
    if (right) {
      drawBox(
        canvas,
        ctx.fill,
        cell.left + (cx + radius - thickness / 2).floorToDouble(),
        cell.top + hTop,
        cell.right,
        cell.top + hBottom,
      );
    }
    if (down) {
      drawBox(
        canvas,
        ctx.fill,
        cell.left + vLeft,
        cell.top + (cy + radius - thickness / 2).floorToDouble(),
        cell.left + vRight,
        cell.bottom,
      );
    }
    if (left) {
      drawBox(
        canvas,
        ctx.fill,
        cell.left,
        cell.top + hTop,
        cell.left + (cx - radius + thickness / 2).ceilToDouble(),
        cell.top + hBottom,
      );
    }

    final center = Offset(cell.left + cx, cell.top + cy);
    if (filled) {
      canvas.drawCircle(center, radius, ctx.fill);
    } else {
      ctx.stroke
        ..strokeWidth = thickness
        ..strokeCap = StrokeCap.butt;
      canvas.drawCircle(center, radius - thickness / 2, ctx.stroke);
    }
  }
}
