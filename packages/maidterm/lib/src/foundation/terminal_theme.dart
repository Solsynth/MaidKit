import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:libghostty/libghostty.dart';

import 'color_palette.dart';
import 'dynamic_color.dart';

/// Default dark ANSI palette using the Tomorrow Night color scheme.
const _darkAnsiColors = [
  Color(0xFF1D1F21), // 0: black
  Color(0xFFCC6666), // 1: red
  Color(0xFFB5BD68), // 2: green
  Color(0xFFF0C674), // 3: yellow
  Color(0xFF81A2BE), // 4: blue
  Color(0xFFB294BB), // 5: magenta
  Color(0xFF8ABEB7), // 6: cyan
  Color(0xFFC5C8C6), // 7: white
  Color(0xFF666666), // 8: bright black
  Color(0xFFD54E53), // 9: bright red
  Color(0xFFB9CA4A), // 10: bright green
  Color(0xFFE7C547), // 11: bright yellow
  Color(0xFF7AA6DA), // 12: bright blue
  Color(0xFFC397D8), // 13: bright magenta
  Color(0xFF70C0B1), // 14: bright cyan
  Color(0xFFEAEAEA), // 15: bright white
];

const _defaultFontFamilyFallback = [
  'JetBrains Mono',
  'Menlo',
  'Consolas',
  'Ubuntu Mono',
  'DejaVu Sans Mono',
  'Courier New',
  'Apple Color Emoji',
  'Noto Color Emoji',
  'Noto Emoji',
  'Segoe UI Emoji',
];

const _lightAnsiColors = [
  Color(0xFF383A42), // 0: black
  Color(0xFFE45649), // 1: red
  Color(0xFF50A14F), // 2: green
  Color(0xFFC18401), // 3: yellow
  Color(0xFF0184BC), // 4: blue
  Color(0xFFA626A4), // 5: magenta
  Color(0xFF0997B3), // 6: cyan
  Color(0xFFA0A1A7), // 7: white
  Color(0xFF4F525E), // 8: bright black
  Color(0xFFE06C75), // 9: bright red
  Color(0xFF98C379), // 10: bright green
  Color(0xFFE5C07B), // 11: bright yellow
  Color(0xFF61AFEF), // 12: bright blue
  Color(0xFFC678DD), // 13: bright magenta
  Color(0xFF56B6C2), // 14: bright cyan
  Color(0xFFFFFFFF), // 15: bright white
];

/// The visual style of the terminal cursor.
///
/// ```dart
/// const cursor = CursorTheme(shape: CursorShape.bar);
/// ```
@immutable
final class CursorTheme {
  /// Cursor shape: block, underline, bar, or block-hollow.
  final CursorShape shape;

  /// Cursor fill color. When null, defaults to the terminal foreground.
  /// See [DynamicColor] for per-cell variants.
  final DynamicColor? color;

  /// Character color under a block cursor. When null, defaults to the
  /// terminal background. See [DynamicColor] for per-cell variants.
  final DynamicColor? text;

  /// Time between blink state toggles.
  final Duration blinkInterval;

  /// Cursor opacity from 0.0 (invisible) to 1.0 (fully opaque).
  final double opacity;

  const CursorTheme({
    this.shape = CursorShape.block,
    this.color,
    this.text,
    this.blinkInterval = const Duration(milliseconds: 600),
    this.opacity = 1.0,
  });

  @override
  int get hashCode => Object.hash(shape, color, text, blinkInterval, opacity);

  @override
  bool operator ==(Object other) =>
      other is CursorTheme &&
      other.shape == shape &&
      other.color == color &&
      other.text == text &&
      other.blinkInterval == blinkInterval &&
      other.opacity == opacity;

  @override
  String toString() =>
      'CursorTheme(shape: $shape, color: $color, text: $text, '
      'blinkInterval: $blinkInterval, opacity: $opacity)';

  /// Linearly interpolates between two cursor themes.
  ///
  /// Non-interpolable fields ([shape], [color], [text]) snap at `t >= 0.5`.
  static CursorTheme? lerp(CursorTheme? a, CursorTheme? b, double t) {
    if (identical(a, b)) return a;
    if (a == null || b == null) return t < 0.5 ? a : b;
    return CursorTheme(
      shape: t < 0.5 ? a.shape : b.shape,
      color: t < 0.5 ? a.color : b.color,
      text: t < 0.5 ? a.text : b.text,
      blinkInterval: Duration(
        microseconds: lerpDouble(
          a.blinkInterval.inMicroseconds.toDouble(),
          b.blinkInterval.inMicroseconds.toDouble(),
          t,
        )!.round(),
      ),
      opacity: lerpDouble(a.opacity, b.opacity, t)!,
    );
  }
}

/// Visual properties for hyperlinks in a single interaction state.
///
/// ```dart
/// const style = HyperlinkStyle(underline: UnderlineStyle.single);
/// ```
@immutable
final class HyperlinkStyle {
  /// Underline decoration for hyperlinked cells.
  ///
  /// Only applied when the cell has no explicit underline of its own.
  final UnderlineStyle underline;

  /// Explicit underline color. When null, the text foreground color is used.
  final Color? underlineColor;

  /// Override text color for hyperlinked cells. When null, the cell's
  /// resolved foreground color is used.
  final Color? textColor;

  const HyperlinkStyle({
    this.underline = .none,
    this.underlineColor,
    this.textColor,
  });

  @override
  int get hashCode => Object.hash(underline, underlineColor, textColor);

  @override
  bool operator ==(Object other) =>
      other is HyperlinkStyle &&
      other.underline == underline &&
      other.underlineColor == underlineColor &&
      other.textColor == textColor;

  @override
  String toString() =>
      'HyperlinkStyle(underline: $underline, '
      'underlineColor: $underlineColor, textColor: $textColor)';

  static HyperlinkStyle? lerp(HyperlinkStyle? a, HyperlinkStyle? b, double t) {
    if (identical(a, b)) return a;
    if (a == null || b == null) return t < 0.5 ? a : b;
    return HyperlinkStyle(
      underline: t < 0.5 ? a.underline : b.underline,
      underlineColor: Color.lerp(a.underlineColor, b.underlineColor, t),
      textColor: Color.lerp(a.textColor, b.textColor, t),
    );
  }
}

/// Hyperlink appearance for idle and highlighted states.
///
/// ```dart
/// const theme = HyperlinkTheme(
///   highlighted: HyperlinkStyle(underline: UnderlineStyle.single),
/// );
/// ```
@immutable
final class HyperlinkTheme {
  /// Appearance when the hyperlink is not highlighted.
  ///
  /// Non-empty idle styling keeps visible links styled outside hover. This can
  /// be expensive for high-throughput terminals because visible text must be
  /// scanned after content changes. Leave this as `HyperlinkStyle()` for best
  /// throughput.
  final HyperlinkStyle idle;

  /// Appearance when the hyperlink is highlighted.
  final HyperlinkStyle highlighted;

  const HyperlinkTheme({
    this.idle = const HyperlinkStyle(),
    this.highlighted = const HyperlinkStyle(underline: .single),
  });

  @override
  int get hashCode => Object.hash(idle, highlighted);

  @override
  bool operator ==(Object other) =>
      other is HyperlinkTheme &&
      other.idle == idle &&
      other.highlighted == highlighted;

  @override
  String toString() => 'HyperlinkTheme(idle: $idle, highlighted: $highlighted)';

  static HyperlinkTheme? lerp(HyperlinkTheme? a, HyperlinkTheme? b, double t) {
    if (identical(a, b)) return a;
    if (a == null || b == null) return t < 0.5 ? a : b;
    return HyperlinkTheme(
      idle: HyperlinkStyle.lerp(a.idle, b.idle, t)!,
      highlighted: HyperlinkStyle.lerp(a.highlighted, b.highlighted, t)!,
    );
  }
}

/// Selection highlight colors. See [DynamicColor] for per-cell variants.
@immutable
final class SelectionTheme {
  /// Selection highlight fill. When null, uses the terminal foreground.
  final DynamicColor? background;

  /// Color of selected text. When null, selected text keeps its original
  /// foreground.
  final DynamicColor? foreground;

  const SelectionTheme({this.background, this.foreground});

  @override
  int get hashCode => Object.hash(background, foreground);

  @override
  bool operator ==(Object other) =>
      other is SelectionTheme &&
      other.background == background &&
      other.foreground == foreground;

  @override
  String toString() =>
      'SelectionTheme(background: $background, foreground: $foreground)';

  /// Linearly interpolates between two selection themes.
  ///
  /// [background] and [foreground] snap at `t >= 0.5` since DynamicColor
  /// variants don't interpolate meaningfully.
  static SelectionTheme? lerp(SelectionTheme? a, SelectionTheme? b, double t) {
    if (identical(a, b)) return a;
    if (a == null || b == null) return t < 0.5 ? a : b;
    return SelectionTheme(
      background: t < 0.5 ? a.background : b.background,
      foreground: t < 0.5 ? a.foreground : b.foreground,
    );
  }
}

/// Visual configuration for a terminal.
///
/// **Terminal-configuring properties** (pushed to the terminal on creation
/// and theme change via the renderer):
/// - [palette]: background, foreground, and the 256-color palette
/// - [cursor].color: cursor color
///
/// **Rendering-only properties** (used by Flutter painters directly):
/// - [fontSize], [fontFamily], [fontFamilyFallback]: text layout
/// - [selection]: selection highlight colors
/// - [hyperlink]: idle and highlighted hyperlink styling
/// - [cursor].shape: initial cursor shape (terminal programs may override)
/// - [cursor].blinkInterval, [cursor].opacity: cursor animation
/// - [boldIsBright], [boldColor], [faintOpacity], [minimumContrast]: text
///   rendering
/// - [backgroundOpacity], [backgroundOpacityCells]: transparent background
///
/// ```dart
/// final theme = TerminalTheme.dark();
/// final fg = theme.resolveColor(cell.foreground, isForeground: true);
/// ```
@immutable
final class TerminalTheme {
  /// Background, foreground, and the 256-color palette as a single bundle.
  /// See [ColorPalette] for how indices 16–255 are produced.
  final ColorPalette palette;

  /// Cursor appearance settings.
  final CursorTheme cursor;

  /// Duration used to ease the cursor between adjacent terminal cells.
  ///
  /// A zero duration keeps cursor movement immediate, which is the default.
  final Duration cursorMotionDuration;

  /// Hyperlink appearance for idle and highlighted states.
  final HyperlinkTheme hyperlink;

  /// Font family name for rendering terminal text.
  final String fontFamily;

  /// Fallback font families tried when a glyph is missing from [fontFamily].
  ///
  /// Defaults to common monospace fonts followed by platform emoji fonts. Emoji
  /// fonts are kept last so text-like glyphs, including digits and symbols,
  /// stay grid-aligned when a monospace fallback can render them.
  final List<String> fontFamilyFallback;

  /// Font size in logical pixels.
  final double fontSize;

  /// Base font weight for regular (non-bold) terminal text.
  final FontWeight fontWeight;

  /// Selection highlight colors.
  final SelectionTheme selection;

  /// When true, bold text uses bright palette colors (indices 8-15).
  final bool boldIsBright;

  /// Explicit color for bold text. When non-null, takes precedence over
  /// [boldIsBright]: bold cells render in this color regardless of their
  /// original foreground.
  final Color? boldColor;

  /// Opacity multiplier for faint (dim) text, from 0.0 to 1.0.
  final double faintOpacity;

  /// Minimum contrast ratio between foreground and background colors.
  /// A value of 1.0 disables contrast enforcement.
  final double minimumContrast;

  /// Opacity multiplier for the default terminal background, from 0.0
  /// (fully transparent) to 1.0 (fully opaque).
  ///
  /// Only applies to cells that use the default background. Cells with an
  /// explicit background color stay opaque unless [backgroundOpacityCells]
  /// is also true; inverse cells and the selection highlight always stay
  /// opaque. Requires a host surface that allows transparency (a
  /// translucent Flutter window, or placement over other widgets) for
  /// the effect to be visible.
  final double backgroundOpacity;

  /// Whether [backgroundOpacity] also applies to cells with an explicit
  /// (non-default) background color.
  ///
  /// Off by default: terminal apps like Neovim and tmux often repaint the
  /// grid with the theme background color, and making those cells
  /// translucent leaks the host surface through the editor chrome.
  final bool backgroundOpacityCells;

  /// [backgroundOpacity] precomputed as an alpha byte in 0 to 255, for
  /// alpha scaling in the per-cell hot loop of the frame builder.
  final int backgroundOpacityAlpha;

  TerminalTheme({
    required this.palette,
    this.cursor = const CursorTheme(),
    this.cursorMotionDuration = Duration.zero,
    this.hyperlink = const HyperlinkTheme(),
    this.fontSize = 14.0,
    this.fontWeight = FontWeight.normal,
    this.fontFamily = 'JetBrains Mono',
    this.fontFamilyFallback = _defaultFontFamilyFallback,
    this.selection = const SelectionTheme(),
    this.boldIsBright = false,
    this.boldColor,
    this.faintOpacity = 0.5,
    this.minimumContrast = 1.0,
    this.backgroundOpacity = 1.0,
    this.backgroundOpacityCells = false,
  }) : assert(fontSize > 0, 'fontSize must be positive'),
       assert(
         backgroundOpacity >= 0.0 && backgroundOpacity <= 1.0,
         'backgroundOpacity must be >= 0.0 && <= 1.0',
       ),
       backgroundOpacityAlpha = (backgroundOpacity * 255).round();

  /// A dark-background terminal theme using the Tomorrow Night color scheme.
  factory TerminalTheme.dark() => TerminalTheme(
    palette: ColorPalette(
      ansiColors: _darkAnsiColors,
      background: const Color(0xFF1D1F21),
      foreground: const Color(0xFFC5C8C6),
    ),
  );

  /// A light-background terminal theme using the Atom One Light color scheme.
  factory TerminalTheme.light() => TerminalTheme(
    palette: ColorPalette(
      ansiColors: _lightAnsiColors,
      background: const Color(0xFFFAFAFA),
      foreground: const Color(0xFF383A42),
    ),
  );

  /// Default background color when a cell uses [DefaultColor].
  ///
  /// Shorthand for `palette.background`.
  Color get background => palette.background;

  /// Default foreground color when a cell uses [DefaultColor].
  ///
  /// Shorthand for `palette.foreground`.
  Color get foreground => palette.foreground;

  @override
  int get hashCode => Object.hash(
    palette,
    cursor,
    cursorMotionDuration,
    hyperlink,
    fontSize,
    fontWeight,
    fontFamily,
    Object.hashAll(fontFamilyFallback),
    selection,
    boldIsBright,
    boldColor,
    faintOpacity,
    minimumContrast,
    backgroundOpacity,
    backgroundOpacityCells,
  );

  @override
  bool operator ==(Object other) =>
      other is TerminalTheme &&
      other.palette == palette &&
      other.cursor == cursor &&
      other.cursorMotionDuration == cursorMotionDuration &&
      other.hyperlink == hyperlink &&
      other.fontSize == fontSize &&
      other.fontWeight == fontWeight &&
      other.fontFamily == fontFamily &&
      listEquals(other.fontFamilyFallback, fontFamilyFallback) &&
      other.selection == selection &&
      other.boldIsBright == boldIsBright &&
      other.boldColor == boldColor &&
      other.faintOpacity == faintOpacity &&
      other.minimumContrast == minimumContrast &&
      other.backgroundOpacity == backgroundOpacity &&
      other.backgroundOpacityCells == backgroundOpacityCells;

  /// Returns a copy of this theme with the given fields replaced.
  ///
  /// To change colors, build a new [palette] (often via
  /// `palette.copyWith(...)`) and pass it here.
  TerminalTheme copyWith({
    ColorPalette? palette,
    CursorTheme? cursor,
    Duration? cursorMotionDuration,
    HyperlinkTheme? hyperlink,
    double? fontSize,
    FontWeight? fontWeight,
    String? fontFamily,
    List<String>? fontFamilyFallback,
    SelectionTheme? selection,
    bool? boldIsBright,
    Color? boldColor,
    double? faintOpacity,
    double? minimumContrast,
    double? backgroundOpacity,
    bool? backgroundOpacityCells,
  }) => TerminalTheme(
    palette: palette ?? this.palette,
    cursor: cursor ?? this.cursor,
    cursorMotionDuration: cursorMotionDuration ?? this.cursorMotionDuration,
    hyperlink: hyperlink ?? this.hyperlink,
    fontSize: fontSize ?? this.fontSize,
    fontWeight: fontWeight ?? this.fontWeight,
    fontFamily: fontFamily ?? this.fontFamily,
    fontFamilyFallback: fontFamilyFallback ?? this.fontFamilyFallback,
    selection: selection ?? this.selection,
    boldIsBright: boldIsBright ?? this.boldIsBright,
    boldColor: boldColor ?? this.boldColor,
    faintOpacity: faintOpacity ?? this.faintOpacity,
    minimumContrast: minimumContrast ?? this.minimumContrast,
    backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
    backgroundOpacityCells:
        backgroundOpacityCells ?? this.backgroundOpacityCells,
  );

  /// Resolves a [CellColor] to a Flutter [Color] using this theme's palette.
  ///
  /// For [DefaultColor], returns [foreground] or [background] based on
  /// [isForeground]. For [PaletteColor], looks up the index in [palette].
  /// For [RgbColor], converts directly.
  ///
  /// The theme palette matches the terminal palette at theme-change time.
  /// OSC 4 individual entry overrides are not reflected until the next
  /// theme update.
  Color resolveColor(CellColor color, {required bool isForeground}) {
    return switch (color) {
      DefaultColor() => isForeground ? foreground : background,
      RgbColor(:final r, :final g, :final b) => Color.fromARGB(255, r, g, b),
      PaletteColor(:final index) => palette[index],
    };
  }

  @override
  String toString() =>
      'TerminalTheme(foreground: $foreground, '
      'background: $background, fontFamily: $fontFamily, fontSize: $fontSize)';

  /// Linearly interpolates between two terminal themes.
  ///
  /// Non-interpolable fields ([fontFamily]) snap at `t >= 0.5`.
  static TerminalTheme? lerp(TerminalTheme? a, TerminalTheme? b, double t) {
    if (identical(a, b)) return a;
    if (a == null || b == null) return t < 0.5 ? a : b;
    return TerminalTheme(
      palette: ColorPalette.lerp(a.palette, b.palette, t)!,
      cursor: CursorTheme.lerp(a.cursor, b.cursor, t)!,
      cursorMotionDuration: t < 0.5
          ? a.cursorMotionDuration
          : b.cursorMotionDuration,
      hyperlink: HyperlinkTheme.lerp(a.hyperlink, b.hyperlink, t)!,
      fontSize: lerpDouble(a.fontSize, b.fontSize, t)!,
      fontWeight: FontWeight.lerp(a.fontWeight, b.fontWeight, t)!,
      fontFamily: t < 0.5 ? a.fontFamily : b.fontFamily,
      fontFamilyFallback: t < 0.5 ? a.fontFamilyFallback : b.fontFamilyFallback,
      selection: SelectionTheme.lerp(a.selection, b.selection, t)!,
      boldIsBright: t < 0.5 ? a.boldIsBright : b.boldIsBright,
      boldColor: Color.lerp(a.boldColor, b.boldColor, t),
      faintOpacity: lerpDouble(a.faintOpacity, b.faintOpacity, t)!,
      minimumContrast: lerpDouble(a.minimumContrast, b.minimumContrast, t)!,
      backgroundOpacity: lerpDouble(
        a.backgroundOpacity,
        b.backgroundOpacity,
        t,
      )!,
      backgroundOpacityCells: t < 0.5
          ? a.backgroundOpacityCells
          : b.backgroundOpacityCells,
    );
  }
}
