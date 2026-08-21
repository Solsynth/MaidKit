import 'dart:math';
import 'dart:ui';

import 'package:libghostty/libghostty.dart' show UnderlineStyle;

import '../atlas_config.dart';
import '../atlas_entry.dart';
import 'atlas_lane.dart';

/// Rasterizes underline decoration geometry into the decoration atlas.
class DecorationLane extends AtlasLane {
  final List<(UnderlineStyle, AtlasEntry)> _pending = [];

  var _pxCellWidth = 0.0;
  var _pxCellHeight = 0.0;
  var _pxUnderlinePosition = 0.0;
  var _pxUnderlineThickness = 1.0;

  // Bottom padding for decoration sprites (cell height / 4). Allows
  // curly and double underlines to extend below the cell boundary.
  var _pxDecorationPadding = 0.0;

  DecorationLane({super.initialSize, super.maxSize})
    : super(entryLane: .decoration);

  @override
  bool get hasPending => _pending.isNotEmpty;

  @override
  void clearPending() => _pending.clear();

  @override
  void configure(AtlasConfig config) {
    _pxCellWidth = config.metrics.cellWidth * config.devicePixelRatio;
    _pxCellHeight = config.metrics.cellHeight * config.devicePixelRatio;
    _pxUnderlinePosition =
        config.metrics.underlinePosition * config.devicePixelRatio;
    _pxUnderlineThickness = max(
      1.0,
      (config.metrics.underlineThickness * config.devicePixelRatio)
          .ceilToDouble(),
    );
    _pxDecorationPadding = (_pxCellHeight / 4).ceilToDouble();
  }

  @override
  void paintPending(Canvas canvas) {
    for (final (style, entry) in _pending) {
      canvas.save();
      canvas.clipRect(
        Rect.fromLTRB(
          entry.srcLeft,
          entry.srcTop,
          entry.srcRight,
          entry.srcBottom,
        ),
      );
      _paintDecoration(canvas, style, entry);
      canvas.restore();
    }
    _pending.clear();
  }

  /// Rasterizes an underline decoration sprite for the given [style].
  ///
  /// Draws the underline pattern into the atlas in white; per-sprite color
  /// tinting is applied at draw time via [BlendMode.modulate].
  AtlasEntry rasterizeDecoration(UnderlineStyle style) {
    final pxWidth = _pxCellWidth.ceil().toDouble();
    // Sprite is taller than cell to accommodate decorations extending below.
    final pxHeight = (_pxCellHeight + _pxDecorationPadding).ceil().toDouble();
    final entry = allocate(width: pxWidth, height: pxHeight, bearingY: 0);

    _pending.add((style, entry));
    return entry;
  }

  /// Draws an underline decoration pattern into the atlas.
  ///
  /// Each style draws at the font's underline position, clamped so it
  /// stays within the sprite bounds (cell height + padding). The padding
  /// allows curly and double underlines to extend below the cell boundary
  /// without being clipped.
  void _paintDecoration(Canvas canvas, UnderlineStyle style, AtlasEntry entry) {
    final width = entry.srcRight - entry.srcLeft;
    final ox = entry.srcLeft;
    final oy = entry.srcTop;
    final thickness = _pxUnderlineThickness;
    final cellHeight = _pxCellHeight;
    final padding = _pxDecorationPadding;

    switch (style) {
      case UnderlineStyle.none:
        break;

      case UnderlineStyle.single:
        // Clamp underline to stay within the sprite (cell + padding).
        final underlineY = min(
          _pxUnderlinePosition,
          cellHeight + padding - thickness,
        );
        canvas.drawRect(
          Rect.fromLTWH(ox, oy + underlineY, width, thickness),
          Paint()..color = const Color(0xFFFFFFFF),
        );

      case UnderlineStyle.double:
        // Place both lines symmetrically around the underline position,
        // clamped so the lower line stays within the padded sprite.
        final underlineY = min(
          _pxUnderlinePosition,
          cellHeight + padding - 2 * thickness,
        );
        final upperLineY = max(0.0, underlineY - thickness);
        final lowerLineY = underlineY + thickness;
        final paint = Paint()..color = const Color(0xFFFFFFFF);
        canvas.drawRect(
          Rect.fromLTWH(ox, oy + upperLineY, width, thickness),
          paint,
        );
        canvas.drawRect(
          Rect.fromLTWH(ox, oy + lowerLineY, width, thickness),
          paint,
        );

      case UnderlineStyle.dotted:
        // Dot radius derived from line thickness (sqrt(1/2) gives area-
        // equivalent circle). Dot count is bounded: at least 1 dot,
        // at most enough to fit with 2-radius spacing, and at least
        // 1-radius gaps between dots so they don't merge.
        final radius = sqrt1_2 * thickness;
        final centerY = min(
          _pxUnderlinePosition + 0.5 * thickness,
          cellHeight + padding - radius.ceilToDouble(),
        );
        final dotCount = max(
          1.0,
          min(
            (width / (4 * radius)).ceilToDouble(),
            min(
              (width / (3 * radius)).floorToDouble(),
              (width / (2 * radius + 1)).floorToDouble(),
            ),
          ),
        );
        final spacing = width / dotCount;
        final paint = Paint()..color = const Color(0xFFFFFFFF);
        for (var i = 0; i < dotCount.toInt(); i++) {
          canvas.drawCircle(
            Offset(ox + spacing / 2 + spacing * i, oy + centerY),
            radius,
            paint,
          );
        }

      case UnderlineStyle.dashed:
        final underlineY = min(
          _pxUnderlinePosition,
          cellHeight + padding - thickness,
        );
        final intWidth = width.toInt();
        final dashWidth = intWidth ~/ 3 + 1;
        final dashCount = intWidth ~/ dashWidth + 1;
        final paint = Paint()..color = const Color(0xFFFFFFFF);
        for (var i = 0; i < dashCount; i += 2) {
          canvas.drawRect(
            Rect.fromLTWH(
              ox + (i * dashWidth).toDouble(),
              oy + underlineY,
              dashWidth.toDouble(),
              thickness,
            ),
            paint,
          );
        }

      case UnderlineStyle.curly:
        // S-shaped cubic Bezier: starts at bottom-left, curves up to center,
        // then back down to bottom-right. controlRatio (0.4) flattens the
        // curve slightly for a smooth wave that tiles seamlessly across
        // adjacent cells (butt stroke caps prevent overlap at seams).
        final amplitude = width / pi;
        final top = min(
          _pxUnderlinePosition,
          cellHeight + padding - amplitude - thickness,
        );
        final bottom = top + amplitude;
        final center = width / 2;
        const controlRatio = 0.4;

        final path = Path()
          ..moveTo(ox, oy + bottom)
          ..cubicTo(
            ox + center * controlRatio,
            oy + bottom,
            ox + center - center * controlRatio,
            oy + top,
            ox + center,
            oy + top,
          )
          ..cubicTo(
            ox + center + center * controlRatio,
            oy + top,
            ox + width - center * controlRatio,
            oy + bottom,
            ox + width,
            oy + bottom,
          );
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xFFFFFFFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = thickness
            ..strokeCap = StrokeCap.butt
            ..strokeJoin = StrokeJoin.round,
        );
    }
  }
}
