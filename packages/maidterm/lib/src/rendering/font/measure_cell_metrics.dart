import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/painting.dart';

import '../../foundation.dart' show CellMetrics;
import 'font_table_metrics.dart';

/// Measures cell dimensions by laying out reference characters with
/// the given font configuration.
///
/// Returns a [CellMetrics] with:
/// - Cell width: advance width of 'M' (widest common character), snapped up
///   to the device pixel grid.
/// - Cell height: full typographic line height (ascent + |descent|),
///   snapped up to the device pixel grid.
/// - Baseline: distance from the top of the cell, centered within the
///   snapped cell height.
/// - Underline and strikethrough positions and thicknesses read from the
///   font's `post` and `OS/2` tables when [fontData] (raw TTF/OTF bytes)
///   is provided. Heuristic fallbacks are used otherwise.
///
/// ```dart
/// final metrics = measureCellMetrics(
///   fontFamily: 'JetBrains Mono',
///   fontSize: 14.0,
///   fontData: File('JetBrainsMono-Regular.ttf').readAsBytesSync(),
/// );
/// final (cols, rows) = metrics.gridSize(viewWidth, viewHeight);
/// ```
CellMetrics measureCellMetrics({
  required double fontSize,
  required String fontFamily,
  FontWeight fontWeight = .normal,
  List<String>? fontFamilyFallback,
  Uint8List? fontData,
  double devicePixelRatio = 1.0,
}) {
  assert(devicePixelRatio > 0, 'devicePixelRatio must be positive');

  final style = TextStyle(
    fontSize: fontSize,
    fontFamily: fontFamily,
    fontWeight: fontWeight,
    fontFamilyFallback: fontFamilyFallback,
  );

  final widthPainter = TextPainter(
    text: TextSpan(text: 'M', style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final faceWidth = widthPainter.width;
  widthPainter.dispose();

  // 'Mgj' exercises both ascenders and descenders so the line metrics
  // reflect the full typographic extent.
  final vertPainter = TextPainter(
    text: TextSpan(text: 'Mgj', style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final ascent = vertPainter.computeDistanceToActualBaseline(.alphabetic);
  final faceHeight = vertPainter.height;
  vertPainter.dispose();

  final cellWidth = _ceilToDevicePixel(faceWidth, devicePixelRatio);
  final cellHeight = _ceilToDevicePixel(faceHeight, devicePixelRatio);

  final baseline = _roundToDevicePixel(
    ascent + (cellHeight - faceHeight) / 2,
    devicePixelRatio,
  );

  final fontMetrics = fontData != null ? parseFontTableMetrics(fontData) : null;

  // Pixels-per-unit: converts font design units to logical pixels.
  final ppu = fontMetrics != null ? fontSize / fontMetrics.unitsPerEm : 0.0;

  final capHeight = fontMetrics?.capHeight != null
      ? fontMetrics!.capHeight! * ppu
      : 0.75 * ascent;
  final exHeight = fontMetrics?.exHeight != null
      ? fontMetrics!.exHeight! * ppu
      : 0.75 * capHeight;

  // Fallback thickness: 0.15 * exHeight (heuristic).
  final underlineThickness = max(
    1.0,
    (fontMetrics?.underlineThickness != null
            ? fontMetrics!.underlineThickness! * ppu
            : 0.15 * exHeight)
        .ceilToDouble(),
  );

  // Fallback position: one thickness below baseline.
  final rawUnderlinePosition = fontMetrics?.underlinePosition != null
      ? (baseline - fontMetrics!.underlinePosition! * ppu).roundToDouble()
      : (baseline + underlineThickness).roundToDouble();
  final underlinePosition = min(
    rawUnderlinePosition,
    cellHeight - underlineThickness,
  );

  // Fallback thickness: same as underline.
  final strikethroughThickness = max(
    1.0,
    (fontMetrics?.strikethroughThickness != null
            ? fontMetrics!.strikethroughThickness! * ppu
            : underlineThickness)
        .ceilToDouble(),
  );

  // Fallback position: centered on the ex-height.
  final strikethroughPosition = fontMetrics?.strikethroughPosition != null
      ? (baseline - fontMetrics!.strikethroughPosition! * ppu).roundToDouble()
      : (baseline - (exHeight + strikethroughThickness) * 0.5).roundToDouble();

  return CellMetrics(
    cellWidth: cellWidth,
    cellHeight: cellHeight,
    baseline: baseline,
    underlinePosition: underlinePosition,
    underlineThickness: underlineThickness,
    strikethroughPosition: strikethroughPosition,
    strikethroughThickness: strikethroughThickness,
  );
}

double _ceilToDevicePixel(double value, double devicePixelRatio) {
  return (value * devicePixelRatio).ceilToDouble() / devicePixelRatio;
}

double _roundToDevicePixel(double value, double devicePixelRatio) {
  return (value * devicePixelRatio).roundToDouble() / devicePixelRatio;
}
