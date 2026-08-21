import 'dart:typed_data';
import 'dart:ui';

import 'package:libghostty/libghostty.dart' show Cursor, TerminalColors;

import '../foundation.dart' show CellMetrics, TerminalTheme;
import 'atlas/atlas.dart';

/// Mutable state shared between [TerminalRenderBox] and all painters.
///
/// Written by the render box during state sync (start of paint). Read by
/// painters during the paint phase. Each painter holds a final reference
/// and never mutates this object.
///
/// Contains grid dimensions, device pixel ratio, resolved terminal
/// colors, cursor state, IME preedit state, and faint text opacity.
class TerminalPaintState {
  TerminalTheme theme;
  CellMetrics metrics;

  var rows = 0;
  var cols = 0;
  var blinkVisible = true;

  /// Scale between Flutter's logical-pixel canvas and the physical
  /// pixels libghostty uses for size reports and Kitty graphics.
  var devicePixelRatio = 1.0;

  late int terminalForegroundArgb;
  late int terminalBackgroundArgb;
  final terminalPaletteArgb = Uint32List(256);

  /// Alpha byte (0-255) applied to faint text foregrounds.
  int faintAlpha;

  var viewportOffset = 0;

  var cursor = const Cursor();
  var cursorVisualPosition = Offset.zero;
  var cursorWide = false;
  var cursorFocused = true;
  var cursorColorArgb = 0xFFFFFFFF;
  AtlasEntry? cursorAtlasEntry;
  final cursorGlyphPaint = Paint();

  /// Whether preedit text currently replaces cells at the cursor row.
  ///
  /// Cursor painting reads this to avoid drawing the normal terminal cursor
  /// over the active composing range.
  var preeditActive = false;

  TerminalPaintState(this.theme, this.metrics)
    : faintAlpha = (theme.faintOpacity * 255).ceil() {
    terminalForegroundArgb = theme.foreground.toARGB32();
    terminalBackgroundArgb = theme.background.toARGB32();
    _updateThemePalette();
  }

  void updateTheme(TerminalTheme newTheme) {
    theme = newTheme;
    faintAlpha = (newTheme.faintOpacity * 255).ceil();
    _updateThemePalette();
  }

  /// Updates resolved terminal colors.
  ///
  /// Returns true when any color changed so cached paint data containing
  /// packed ARGB values can be rebuilt.
  bool updateTerminalColors(TerminalColors colors) {
    var changed = false;
    final foreground = colors.foreground.toArgb32;
    final background = colors.background.toArgb32;
    if (terminalForegroundArgb != foreground) {
      terminalForegroundArgb = foreground;
      changed = true;
    }
    if (terminalBackgroundArgb != background) {
      terminalBackgroundArgb = background;
      changed = true;
    }
    final palette = colors.palette;
    for (var i = 0; i < terminalPaletteArgb.length; i++) {
      final color = palette[i].toArgb32;
      if (terminalPaletteArgb[i] == color) continue;
      terminalPaletteArgb[i] = color;
      changed = true;
    }
    return changed;
  }

  void _updateThemePalette() {
    final palette = theme.palette;
    for (var i = 0; i < terminalPaletteArgb.length; i++) {
      terminalPaletteArgb[i] = palette[i].toARGB32();
    }
  }
}
