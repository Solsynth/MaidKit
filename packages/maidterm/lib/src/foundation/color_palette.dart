import 'dart:collection';

import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

import 'generate_256_color.dart';

void _validateAnsi(List<Color> ansiColors) {
  if (ansiColors.length != 16) {
    throw ArgumentError.value(
      ansiColors.length,
      'ansiColors',
      'must contain exactly 16 colors',
    );
  }
}

/// Standard xterm extended palette: 6×6×6 RGB cube (16–231) + 24-step
/// grayscale ramp (232–255). Indices 0–15 pass through from [ansiColors].
List<Color> _xtermCube(List<Color> ansiColors) {
  final colors = List<Color>.filled(256, const Color(0xFF000000));
  for (var i = 0; i < 16; i++) {
    colors[i] = ansiColors[i];
  }
  var idx = 16;
  for (var r = 0; r < 6; r++) {
    for (var g = 0; g < 6; g++) {
      for (var b = 0; b < 6; b++) {
        colors[idx++] = Color.fromARGB(
          255,
          r == 0 ? 0 : r * 40 + 55,
          g == 0 ? 0 : g * 40 + 55,
          b == 0 ? 0 : b * 40 + 55,
        );
      }
    }
  }
  for (var i = 0; i < 24; i++) {
    final v = i * 10 + 8;
    colors[idx++] = Color.fromARGB(255, v, v, v);
  }
  return colors;
}

/// The default background, foreground, and 256-color palette for a terminal.
///
/// Indices 0–15 hold the 16 ANSI base colors. Indices 16–255 hold the
/// extended palette produced by one of two modes:
///
/// - Default constructor: the standard xterm 6×6×6 RGB cube (16–231) plus
///   a 24-step grayscale ramp (232–255), matching mainstream terminal
///   defaults.
/// - [ColorPalette.generated]: indices 16–255 are derived from
///   [background], [foreground], and the 16 base colors via CIELAB
///   interpolation so the extended palette adapts to the theme.
///
/// ```dart
/// final palette = ColorPalette(
///   ansiColors: const [Color(0xFF1D1F21), /* ...14 more... */ Color(0xFFEAEAEA)],
///   background: const Color(0xFF1D1F21),
///   foreground: const Color(0xFFC5C8C6),
/// );
/// final red = palette[1];
/// ```
@immutable
final class ColorPalette {
  /// Default canvas color used by cells with no explicit background.
  final Color background;

  /// Default text color used by cells with no explicit foreground.
  final Color foreground;

  final bool _generated;
  final bool _harmonious;
  final List<Color> _colors;

  /// Builds a palette with the xterm cube for indices 16–255.
  ///
  /// [ansiColors] must contain exactly 16 entries.
  factory ColorPalette({
    required List<Color> ansiColors,
    required Color background,
    required Color foreground,
  }) {
    _validateAnsi(ansiColors);
    return ColorPalette._(
      background: background,
      foreground: foreground,
      colors: List<Color>.unmodifiable(_xtermCube(ansiColors)),
      generated: false,
      harmonious: false,
    );
  }

  /// Builds a palette whose indices 16–255 are CIELAB-interpolated from
  /// [ansiColors], [background], and [foreground] so they blend with the
  /// theme rather than clash with the fixed xterm cube.
  ///
  /// When [harmonious] is true, the cube orientation follows the theme's
  /// own dark→light direction instead of being forced dark→light; useful
  /// for light themes.
  ///
  /// [ansiColors] must contain exactly 16 entries.
  factory ColorPalette.generated({
    required List<Color> ansiColors,
    required Color background,
    required Color foreground,
    bool harmonious = false,
  }) {
    _validateAnsi(ansiColors);
    return ColorPalette._(
      background: background,
      foreground: foreground,
      colors: List<Color>.unmodifiable(
        generate256Color(
          base: ansiColors,
          background: background,
          foreground: foreground,
          harmonious: harmonious,
        ),
      ),
      generated: true,
      harmonious: harmonious,
    );
  }

  const ColorPalette._({
    required this._colors,
    required this.background,
    required this.foreground,
    required this._generated,
    required this._harmonious,
  }) : assert(_colors.length == 256, 'palette must contain exactly 256 colors');

  /// The 16 ANSI base colors (indices 0–15) supplied at construction.
  List<Color> get ansiColors => UnmodifiableListView(_colors.take(16));

  @override
  int get hashCode =>
      Object.hash(background, foreground, Object.hashAll(_colors));

  @override
  bool operator ==(Object other) {
    if (other is! ColorPalette) return false;
    if (background != other.background) return false;
    if (foreground != other.foreground) return false;
    for (var i = 0; i < 256; i++) {
      if (_colors[i] != other._colors[i]) return false;
    }
    return true;
  }

  /// Returns the [Color] at the given palette [index] (0–255).
  Color operator [](int index) => _colors[index];

  /// Returns a copy of this palette with the given fields replaced.
  ///
  /// Preserves the construction mode: if this palette was built via
  /// [ColorPalette.generated], the copy is generated too (with the same
  /// [harmonious] setting). Otherwise the copy uses the xterm cube.
  ColorPalette copyWith({
    List<Color>? ansiColors,
    Color? background,
    Color? foreground,
  }) {
    final newAnsi = ansiColors ?? this.ansiColors;
    final newBg = background ?? this.background;
    final newFg = foreground ?? this.foreground;
    if (_generated) {
      return ColorPalette.generated(
        ansiColors: newAnsi,
        background: newBg,
        foreground: newFg,
        harmonious: _harmonious,
      );
    }
    return ColorPalette(
      ansiColors: newAnsi,
      background: newBg,
      foreground: newFg,
    );
  }

  /// Linearly interpolates between two palettes.
  ///
  /// [background], [foreground], and each of the 256 entries are interpolated
  /// independently via [Color.lerp]. Used by `TerminalTheme.lerp` for animated
  /// theme transitions; the per-entry lerp avoids regenerating the extended
  /// palette every frame.
  ///
  /// The resulting palette is not tagged as generated even if both inputs
  /// were; lerp always produces a plain palette whose [copyWith] uses the
  /// xterm cube.
  static ColorPalette? lerp(ColorPalette? begin, ColorPalette? end, double t) {
    if (identical(begin, end)) return begin;
    if (begin == null || end == null) return t < 0.5 ? begin : end;
    return ColorPalette._(
      background: Color.lerp(begin.background, end.background, t)!,
      foreground: Color.lerp(begin.foreground, end.foreground, t)!,
      colors: List<Color>.unmodifiable(
        List<Color>.generate(256, (i) => Color.lerp(begin[i], end[i], t)!),
      ),
      generated: false,
      harmonious: false,
    );
  }
}
