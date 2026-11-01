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
