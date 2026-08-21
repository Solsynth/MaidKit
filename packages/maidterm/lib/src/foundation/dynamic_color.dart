import 'dart:ui';

import 'package:meta/meta.dart';

/// A color that resolves at paint time against a specific cell.
///
/// Some theme fields (cursor, selection) may want to use the underlying
/// cell's own foreground or background instead of a fixed RGB value, so a
/// cursor on a red cell looks different from a cursor on a green cell.
/// `DynamicColor` encodes that choice.
///
/// ```dart
/// const cursor = CursorTheme(
///   color: DynamicColor.cellForeground(),
///   text: DynamicColor.cellBackground(),
/// );
/// ```
@immutable
sealed class DynamicColor {
  const DynamicColor();

  /// Resolves to the cell's own background at paint time.
  const factory DynamicColor.cellBackground() = _CellBackground;

  /// Resolves to the cell's own foreground at paint time.
  const factory DynamicColor.cellForeground() = _CellForeground;

  /// A fixed RGB color.
  const factory DynamicColor.fixed(Color color) = _FixedColor;

  /// The underlying [Color] if this is `DynamicColor.fixed(...)`, otherwise
  /// null. Use for APIs that only accept a fixed RGB value.
  Color? get fixedColor => null;

  /// Resolves this color against the given cell's foreground and background.
  Color resolve({required Color cellForeground, required Color cellBackground});
}

final class _CellBackground extends DynamicColor {
  const _CellBackground();

  @override
  int get hashCode => (_CellBackground).hashCode;

  @override
  bool operator ==(Object other) => other is _CellBackground;

  @override
  Color resolve({
    required Color cellForeground,
    required Color cellBackground,
  }) => cellBackground;

  @override
  String toString() => 'DynamicColor.cellBackground()';
}

final class _CellForeground extends DynamicColor {
  const _CellForeground();

  @override
  int get hashCode => (_CellForeground).hashCode;

  @override
  bool operator ==(Object other) => other is _CellForeground;

  @override
  Color resolve({
    required Color cellForeground,
    required Color cellBackground,
  }) => cellForeground;

  @override
  String toString() => 'DynamicColor.cellForeground()';
}

final class _FixedColor extends DynamicColor {
  final Color color;

  const _FixedColor(this.color);

  @override
  Color? get fixedColor => color;

  @override
  int get hashCode => Object.hash(_FixedColor, color);

  @override
  bool operator ==(Object other) =>
      other is _FixedColor && other.color == color;

  @override
  Color resolve({
    required Color cellForeground,
    required Color cellBackground,
  }) => color;

  @override
  String toString() => 'DynamicColor.fixed($color)';
}
