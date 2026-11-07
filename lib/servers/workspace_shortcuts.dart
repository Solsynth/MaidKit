import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'session_layout.dart';

/// Whether the platform prints command chords with the Cmd glyph.
bool get usesCommandGlyph =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

/// Whether [event] carries this platform's command modifier.
///
/// Apple platforms use Cmd, everything else Ctrl — the same split the window
/// shell's Cmd/Ctrl+W draws. Never "either modifier": Ctrl+D is a shell's
/// end-of-input, so a Mac must not lose it to a pane split. Option/Alt is
/// excluded too, since those chords belong to the input method.
bool isCommandChord(KeyEvent event) {
  final keyboard = HardwareKeyboard.instance;
  if (keyboard.isAltPressed) return false;
  return usesCommandGlyph ? keyboard.isMetaPressed : keyboard.isControlPressed;
}

/// The pane split [event] asks for, or null when it is not a split chord.
///
/// Cmd/Ctrl+D splits the focused pane to the right; the same chord with Shift
/// splits below it.
///
/// Both the window shell and the terminal ask this. A focused terminal would
/// otherwise encode the chord for the remote shell (Ctrl+D is its
/// end-of-input) and keep the event, so a split that only lived in the window
/// shell would never fire from a terminal.
SessionSplitAxis? splitShortcutAxis(KeyEvent event) {
  if (event is! KeyDownEvent) return null;
  if (event.logicalKey != LogicalKeyboardKey.keyD) return null;
  if (!isCommandChord(event)) return null;
  return HardwareKeyboard.instance.isShiftPressed
      ? SessionSplitAxis.vertical
      : SessionSplitAxis.horizontal;
}

/// Whether [event] asks for an empty workspace tab.
///
/// Cmd/Ctrl+T, the chord every browser and editor uses for "new tab". The
/// terminal asks this before its renderer sees the key: on platforms where
/// Ctrl is the command modifier, Ctrl+T would otherwise be encoded as `^T`
/// and swallowed by the remote shell.
bool isNewTabShortcut(KeyEvent event) {
  if (event is! KeyDownEvent) return false;
  if (event.logicalKey != LogicalKeyboardKey.keyT) return false;
  if (HardwareKeyboard.instance.isShiftPressed) return false;
  return isCommandChord(event);
}

/// Which way Ctrl+Tab asks to walk the workspace's tabs.
///
/// Ctrl+Tab is the chord browsers and editors use to step through their tabs;
/// holding it with Shift walks back. Ctrl is the modifier on every platform,
/// not this platform's command chord: on Apple platforms Cmd+Tab belongs to
/// the system's application switcher and never reaches the app. Repeats count,
/// so a held chord keeps cycling.
///
/// Returns 1 for the next tab, -1 for the previous one, 0 when [event] is not
/// this chord.
int tabCycleStep(KeyEvent event) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return 0;
  if (event.logicalKey != LogicalKeyboardKey.tab) return 0;
  final keyboard = HardwareKeyboard.instance;
  if (keyboard.isAltPressed || !keyboard.isControlPressed) return 0;
  return keyboard.isShiftPressed ? -1 : 1;
}

/// The one-based tab position Cmd/Ctrl+1…9 asks for, or null.
///
/// The number counts the workspace tabs in bar order: the shortcut picks the
/// tab the bar would show there, not a pane. A position past the last tab
/// selects nothing.
int? tabPositionShortcut(KeyEvent event) {
  if (event is! KeyDownEvent) return null;
  final keyboard = HardwareKeyboard.instance;
  if (keyboard.isShiftPressed || keyboard.isAltPressed) return null;
  if (!isCommandChord(event)) return null;
  for (var position = 1; position <= 9; position++) {
    if (event.logicalKey == _tabDigitKey(position)) return position;
  }
  return null;
}

LogicalKeyboardKey _tabDigitKey(int position) => switch (position) {
  1 => LogicalKeyboardKey.digit1,
  2 => LogicalKeyboardKey.digit2,
  3 => LogicalKeyboardKey.digit3,
  4 => LogicalKeyboardKey.digit4,
  5 => LogicalKeyboardKey.digit5,
  6 => LogicalKeyboardKey.digit6,
  7 => LogicalKeyboardKey.digit7,
  8 => LogicalKeyboardKey.digit8,
  _ => LogicalKeyboardKey.digit9,
};

/// How a command chord prints in menus on this platform.
///
/// `⌘D` / `⇧⌘D` on Apple platforms, `Ctrl+D` / `Ctrl+Shift+D` elsewhere.
String commandChordLabel(String key, {bool shift = false}) {
  if (usesCommandGlyph) return '${shift ? '⇧' : ''}⌘$key';
  return 'Ctrl+${shift ? 'Shift+' : ''}$key';
}

/// The chord that opens an empty workspace tab.
String newTabShortcutLabel() => commandChordLabel('T');

/// The chord that splits the focused pane along [axis].
String splitShortcutLabel(SessionSplitAxis axis) =>
    commandChordLabel('D', shift: axis == SessionSplitAxis.vertical);

/// The chord that steps the workspace's tab selection, forwards or back.
String tabCycleShortcutLabel({bool backwards = false}) => usesCommandGlyph
    ? '⌃${backwards ? '⇧' : ''}⇥'
    : 'Ctrl+${backwards ? 'Shift+' : ''}Tab';

/// The chord that selects the tab at a one-based [position].
String tabPositionShortcutLabel(int position) => commandChordLabel('$position');
