import 'package:flutter/services.dart';

/// Which chords the terminal binds to copy, paste and select all.
enum TerminalShortcutMode {
  /// Each renderer's platform defaults: Cmd+C/V/A on Apple platforms,
  /// Ctrl+Shift+C/V/A on Linux, Ctrl+C/V/A on Windows and Android.
  ///
  /// On Windows and Android the plain chords never reach the remote shell:
  /// Ctrl+A selects the buffer instead of reaching screen's prefix, Ctrl+C
  /// copies whenever a selection exists instead of interrupting the program,
  /// and Ctrl+V pastes the host clipboard.
  plain,

  /// Ctrl+Shift+C / V / A for copy, paste and select all, leaving the plain
  /// Ctrl chords to the remote shell.
  ///
  /// Where a renderer already binds the plain chords — Windows and Android —
  /// they are released to the shell, so screen's `Ctrl+A` prefix, Emacs
  /// bindings and `Ctrl+C` interrupts work as they do in a plain terminal.
  /// Apple platforms keep Cmd+C/V/A: it never collides with the shell.
  shifted,
}

/// Clipboard action bound to a shifted-mode chord.
enum TerminalClipboardChord { copy, paste, selectAll }

/// The shifted-mode clipboard chord [event] carries, or null.
///
/// Only Ctrl+Shift+C/V/A is recognized: Meta/Alt chords belong to the window
/// manager or the input method, and the Shift+Insert paste is handled
/// separately.
TerminalClipboardChord? shiftedClipboardChord(KeyEvent event) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return null;
  final keyboard = HardwareKeyboard.instance;
  if (!keyboard.isControlPressed || !keyboard.isShiftPressed) return null;
  if (keyboard.isAltPressed || keyboard.isMetaPressed) return null;
  return switch (event.logicalKey) {
    LogicalKeyboardKey.keyC => TerminalClipboardChord.copy,
    LogicalKeyboardKey.keyV => TerminalClipboardChord.paste,
    LogicalKeyboardKey.keyA => TerminalClipboardChord.selectAll,
    _ => null,
  };
}

/// Whether [event] is a plain Ctrl+C/V/A chord with no other modifier.
///
/// These are the chords renderers bind to their own clipboard actions on
/// Windows and Android, so shifted mode has to release them to the shell.
bool isPlainClipboardChord(KeyEvent event) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
  final keyboard = HardwareKeyboard.instance;
  if (!keyboard.isControlPressed) return false;
  if (keyboard.isShiftPressed ||
      keyboard.isAltPressed ||
      keyboard.isMetaPressed) {
    return false;
  }
  return switch (event.logicalKey) {
    LogicalKeyboardKey.keyC ||
    LogicalKeyboardKey.keyV ||
    LogicalKeyboardKey.keyA => true,
    _ => false,
  };
}
