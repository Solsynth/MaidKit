part of '../sprite_face.dart';

final class PowerlineFlame extends SpriteGlyph {
  final bool right;

  const PowerlineFlame({required this.right});

  @override
  void paint(Canvas canvas, Rect cell, SpriteContext ctx) {
    final thickness = ctx.thickness(cell);
    final midTop = cell.top + cell.height / 2 - thickness / 2;
    final midBottom = cell.top + cell.height / 2 + thickness / 2;

    final top = ctx.path..reset();
    if (right) {
      top.moveTo(cell.left, cell.top);
      top.lineTo(cell.right, cell.top);
      top.lineTo(cell.left + cell.width / 2, midTop);
      top.lineTo(cell.left, midTop);
    } else {
      top.moveTo(cell.right, cell.top);
      top.lineTo(cell.left, cell.top);
      top.lineTo(cell.left + cell.width / 2, midTop);
      top.lineTo(cell.right, midTop);
    }
    top.close();
    canvas.drawPath(top, ctx.fill);

    final bottom = ctx.path..reset();
    if (right) {
      bottom.moveTo(cell.left, cell.bottom);
      bottom.lineTo(cell.right, cell.bottom);
      bottom.lineTo(cell.left + cell.width / 2, midBottom);
      bottom.lineTo(cell.left, midBottom);
    } else {
      bottom.moveTo(cell.right, cell.bottom);
      bottom.lineTo(cell.left, cell.bottom);
      bottom.lineTo(cell.left + cell.width / 2, midBottom);
      bottom.lineTo(cell.right, midBottom);
    }
    bottom.close();
    canvas.drawPath(bottom, ctx.fill);
  }
}
