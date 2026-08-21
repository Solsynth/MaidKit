part of 'sprite_face.dart';

void drawBox(Canvas c, Paint p, double l, double t, double r, double b) {
  c.drawRect(Rect.fromLTRB(l, t, r, b), p);
}

void drawArc(
  Canvas c,
  Paint stroke,
  Path path,
  int corner,
  Rect cell,
  double thickness,
) {
  final cx = cell.width / 2;
  final cy = cell.height / 2;
  final r = math.min(cell.width, cell.height) / 2;
  const s = 0.25;

  path.reset();
  final ox = cell.left;
  final oy = cell.top;

  switch (corner) {
    case 0:
      // top-left: connects down and right (╭)
      path.moveTo(ox + cx, oy);
      path.lineTo(ox + cx, oy + cy - r);
      path.cubicTo(
        ox + cx,
        oy + cy - s * r,
        ox + cx - s * r,
        oy + cy,
        ox + cx - r,
        oy + cy,
      );
      path.lineTo(ox, oy + cy);
    case 1:
      // top-right: connects down and left (╮)
      path.moveTo(ox + cx, oy);
      path.lineTo(ox + cx, oy + cy - r);
      path.cubicTo(
        ox + cx,
        oy + cy - s * r,
        ox + cx + s * r,
        oy + cy,
        ox + cx + r,
        oy + cy,
      );
      path.lineTo(ox + cell.width, oy + cy);
    case 2:
      // bottom-left: connects up and right (╰)
      path.moveTo(ox + cx, oy + cell.height);
      path.lineTo(ox + cx, oy + cy + r);
      path.cubicTo(
        ox + cx,
        oy + cy + s * r,
        ox + cx - s * r,
        oy + cy,
        ox + cx - r,
        oy + cy,
      );
      path.lineTo(ox, oy + cy);
    case 3:
      // bottom-right: connects up and left (╯)
      path.moveTo(ox + cx, oy + cell.height);
      path.lineTo(ox + cx, oy + cy + r);
      path.cubicTo(
        ox + cx,
        oy + cy + s * r,
        ox + cx + s * r,
        oy + cy,
        ox + cx + r,
        oy + cy,
      );
      path.lineTo(ox + cell.width, oy + cy);
  }

  stroke
    ..strokeWidth = thickness
    ..strokeCap = .butt;
  c.drawPath(path, stroke);
}

void drawDashHorizontal(
  Canvas c,
  Paint fill,
  int count,
  double thickness,
  double desiredGap,
  Rect cell,
) {
  final w = cell.width;
  final h = cell.height;

  if (w < count + count) {
    final lt = math.max(1.0, (w / 8).roundToDouble());
    drawBox(
      c,
      fill,
      cell.left,
      cell.top + (h - lt) / 2,
      cell.right,
      cell.top + (h + lt) / 2,
    );
    return;
  }

  final gapW = math.min(desiredGap, w / (2 * count));
  final totalGap = gapW * count;
  final dashW = (w - totalGap) / count;
  final cy = cell.top + (h - thickness) / 2;

  var dx = cell.left + gapW / 2;
  for (var i = 0; i < count; i++) {
    drawBox(c, fill, dx, cy, dx + dashW, cy + thickness);
    dx += dashW + gapW;
  }
}

void drawDashVertical(
  Canvas c,
  Paint fill,
  int count,
  double thickness,
  double desiredGap,
  Rect cell,
) {
  final w = cell.width;
  final h = cell.height;

  if (h < count + count) {
    final lt = math.max(1.0, (w / 8).roundToDouble());
    drawBox(
      c,
      fill,
      cell.left + (w - lt) / 2,
      cell.top,
      cell.left + (w + lt) / 2,
      cell.bottom,
    );
    return;
  }

  final gapH = math.min(desiredGap, h / (2 * count));
  final totalGap = gapH * count;
  final dashH = (h - totalGap) / count;
  final cx = cell.left + (w - thickness) / 2;

  var dy = cell.top + gapH / 2;
  for (var i = 0; i < count; i++) {
    drawBox(c, fill, cx, dy, cx + thickness, dy + dashH);
    dy += dashH + gapH;
  }
}
