// The 256-color palette generation in this file is a direct Dart translation
// of Ghostty's terminal color implementation:
// https://github.com/ghostty-org/ghostty/blob/main/src/terminal/color.zig

import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Generates a 256-color palette from 16 ANSI base colors plus the terminal
/// [background] and [foreground].
///
/// The fixed xterm cube uses fully-saturated colors that clash with custom
/// themes and exhibit inconsistent perceived brightness across hues. This
/// function instead derives indices 16–255 from the theme's own colors so
/// programs can use the richer 256-color range without their own theme
/// configuration, and light/dark switching works automatically.
///
/// The 216-color cube (16–231) is built via trilinear interpolation in
/// CIELAB space over the 8 base anchors. The anchors map to the 8 corners
/// of a 6×6×6 RGB cube:
///
/// ```text
///   R=0 edge: bg      → base[1] (red)
///   R=5 edge: base[6] → fg
///   G=0 edge: bg/base[6] (via R) → base[2]/base[4] (green/blue via R)
///   G=5 edge: base[1]/fg (via R) → base[3]/base[5] (yellow/magenta via R)
/// ```
///
/// For each R slice, four corner colors (c0–c3) are interpolated along R,
/// then for each G row two edge colors (c4–c5) blend along G, and each B
/// cell finally interpolates along B. CIELAB interpolation keeps brightness
/// transitions perceptually uniform across hues.
///
/// The 24-step grayscale ramp (232–255) is a CIELAB interpolation from
/// background to foreground, excluding the pure endpoints already at cube
/// corners (0,0,0) and (5,5,5). The interpolation parameter runs 1/25..24/25.
///
/// [base] must contain exactly 16 entries.
/// [skip] preserves the listed indices as-is (left at their value from
/// [base]); non-listed indices are generated.
/// [harmonious] keeps the cube orientation matching the theme's own
/// dark→light direction; when false (default) the cube always runs
/// dark→light regardless of theme brightness.
List<Color> generate256Color({
  required List<Color> base,
  required Color background,
  required Color foreground,
  bool harmonious = false,
  Set<int>? skip,
}) {
  if (base.length != 16) {
    throw ArgumentError.value(
      base.length,
      'base',
      'must contain exactly 16 colors',
    );
  }

  final base8 = <_Lab>[
    _Lab.fromColor(background),
    _Lab.fromColor(base[1]),
    _Lab.fromColor(base[2]),
    _Lab.fromColor(base[3]),
    _Lab.fromColor(base[4]),
    _Lab.fromColor(base[5]),
    _Lab.fromColor(base[6]),
    _Lab.fromColor(foreground),
  ];

  // For a light theme with [harmonious] off, swap bg and fg so the cube
  // still runs dark→light (index 16 is darker than 231) regardless of which
  // of bg/fg is actually brighter.
  final isLightTheme = base8[7].l < base8[0].l;
  if (isLightTheme && !harmonious) {
    final tmp = base8[0];
    base8[0] = base8[7];
    base8[7] = tmp;
  }

  final result = List<Color>.filled(256, const Color(0xFF000000));
  for (var i = 0; i < 16; i++) {
    result[i] = base[i];
  }

  var idx = 16;
  for (var ri = 0; ri < 6; ri++) {
    final tr = ri / 5.0;
    final c0 = _Lab.lerp(tr, base8[0], base8[1]);
    final c1 = _Lab.lerp(tr, base8[2], base8[3]);
    final c2 = _Lab.lerp(tr, base8[4], base8[5]);
    final c3 = _Lab.lerp(tr, base8[6], base8[7]);
    for (var gi = 0; gi < 6; gi++) {
      final tg = gi / 5.0;
      final c4 = _Lab.lerp(tg, c0, c1);
      final c5 = _Lab.lerp(tg, c2, c3);
      for (var bi = 0; bi < 6; bi++) {
        if (skip == null || !skip.contains(idx)) {
          result[idx] = _Lab.lerp(bi / 5.0, c4, c5).toColor();
        }
        idx++;
      }
    }
  }

  for (var i = 0; i < 24; i++) {
    if (skip == null || !skip.contains(idx)) {
      final t = (i + 1) / 25.0;
      result[idx] = _Lab.lerp(t, base8[0], base8[7]).toColor();
    }
    idx++;
  }

  return result;
}

class _Lab {
  final double l;
  final double a;
  final double b;

  const _Lab(this.l, this.a, this.b);

  factory _Lab.fromColor(Color color) {
    // Step 1: sRGB channels in [0, 1] (Flutter's Color.r/g/b are already 0..1).
    var r = color.r;
    var g = color.g;
    var b = color.b;

    // Step 2: inverse sRGB companding (gamma correction) from sRGB to linear.
    r = r > 0.04045 ? math.pow((r + 0.055) / 1.055, 2.4).toDouble() : r / 12.92;
    g = g > 0.04045 ? math.pow((g + 0.055) / 1.055, 2.4).toDouble() : g / 12.92;
    b = b > 0.04045 ? math.pow((b + 0.055) / 1.055, 2.4).toDouble() : b / 12.92;

    // Step 3: linear RGB to CIE XYZ (D65), normalized by Xn=0.95047,
    // Zn=1.08883 (Yn=1.0 implicit).
    var x = (r * 0.4124564 + g * 0.3575761 + b * 0.1804375) / 0.95047;
    var y = r * 0.2126729 + g * 0.7151522 + b * 0.0721750;
    var z = (r * 0.0193339 + g * 0.1191920 + b * 0.9503041) / 1.08883;

    // Step 4: CIE f(t) nonlinear transform; cube root above ε≈0.008856,
    // linear approximation below to avoid instability near zero.
    x = x > 0.008856
        ? math.pow(x, 1.0 / 3.0).toDouble()
        : 7.787 * x + 16.0 / 116.0;
    y = y > 0.008856
        ? math.pow(y, 1.0 / 3.0).toDouble()
        : 7.787 * y + 16.0 / 116.0;
    z = z > 0.008856
        ? math.pow(z, 1.0 / 3.0).toDouble()
        : 7.787 * z + 16.0 / 116.0;

    // Step 5: final CIELAB. L* lightness 0..100, a* green–red, b* blue–yellow.
    return _Lab(116.0 * y - 16.0, 500.0 * (x - y), 200.0 * (y - z));
  }

  factory _Lab.lerp(double t, _Lab a, _Lab b) {
    return _Lab(
      a.l + t * (b.l - a.l),
      a.a + t * (b.a - a.a),
      a.b + t * (b.b - a.b),
    );
  }

  Color toColor() {
    // Step 1: recover f(Y), f(X), f(Z) by inverting the CIELAB formulas.
    final fy = (l + 16.0) / 116.0;
    final fx = a / 500.0 + fy;
    final fz = fy - b / 200.0;

    // Step 2: inverse CIE f(t); cube above ε, linear inverse below.
    // Scale by D65 white-point references.
    final x3 = fx * fx * fx;
    final y3 = fy * fy * fy;
    final z3 = fz * fz * fz;
    final xf = (x3 > 0.008856 ? x3 : (fx - 16.0 / 116.0) / 7.787) * 0.95047;
    final yf = y3 > 0.008856 ? y3 : (fy - 16.0 / 116.0) / 7.787;
    final zf = (z3 > 0.008856 ? z3 : (fz - 16.0 / 116.0) / 7.787) * 1.08883;

    // Step 3: CIE XYZ to linear RGB (inverse of sRGB→XYZ matrix, D65).
    var r = xf * 3.2404542 - yf * 1.5371385 - zf * 0.4985314;
    var g = -xf * 0.9692660 + yf * 1.8760108 + zf * 0.0415560;
    var bl = xf * 0.0556434 - yf * 0.2040259 + zf * 1.0572252;

    // Step 4: sRGB companding (gamma) back to sRGB.
    r = r > 0.0031308
        ? 1.055 * math.pow(r, 1.0 / 2.4).toDouble() - 0.055
        : 12.92 * r;
    g = g > 0.0031308
        ? 1.055 * math.pow(g, 1.0 / 2.4).toDouble() - 0.055
        : 12.92 * g;
    bl = bl > 0.0031308
        ? 1.055 * math.pow(bl, 1.0 / 2.4).toDouble() - 0.055
        : 12.92 * bl;

    // Step 5: clamp, scale to [0, 255], round to 8-bit sRGB.
    return Color.fromARGB(
      255,
      (r.clamp(0.0, 1.0) * 255.0).round(),
      (g.clamp(0.0, 1.0) * 255.0).round(),
      (bl.clamp(0.0, 1.0) * 255.0).round(),
    );
  }
}
