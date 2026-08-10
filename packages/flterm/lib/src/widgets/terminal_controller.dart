import 'package:flutter/foundation.dart' hide Key;
import 'package:libghostty/libghostty.dart';

import '../foundation.dart';
import 'terminal_controller_impl.dart';

/// Manages a terminal instance and bridges it with [TerminalView].
///
/// Create a controller, wire up [onOutput] to your backend, pass the
/// controller to a [TerminalView], and feed backend data into [write].
/// The controller handles input encoding, selection, focus, and all
/// terminal state.
///
/// Dispose when no longer needed.
///
/// ```dart
/// final controller = TerminalController()
///   ..onOutput = (bytes) => pty.write(bytes)
///   ..onBell = () => playSound()
///   ..onTitleChanged = () => updateTitle(controller.title);
///
/// TerminalView(controller: controller);
///
/// pty.onData = (bytes) => controller.write(bytes);
/// controller.sendText('ls -la\n');
/// ```
abstract class TerminalController extends ChangeNotifier
    implements TerminalRenderObserver {
  /// Called with bytes to send to the backend (PTY, SSH, socket).
  ///
  /// Set this before calling [write]. Fires during [write], [sendKey],
  /// [sendText], and [paste].
  ValueChanged<Uint8List>? onOutput;

  /// Called when the terminal receives a BEL character (0x07).
  VoidCallback? onBell;

  /// Called when the terminal title changes. Read [title] for the value.
  VoidCallback? onTitleChanged;

  /// Called when the working directory changes. Read [pwd] for the value.
  VoidCallback? onPwdChanged;

  /// Called when the grid dimensions change. Forward to your backend.
  OnResize? onResize;

  /// Creates a controller with the given [config].
  ///
  /// The terminal is created immediately with dimensions and scrollback
  /// from [config]. Disposed when the controller is disposed.
  factory TerminalController({TerminalConfig config}) = TerminalControllerImpl;

  @internal
  TerminalController.base();

  /// Active screen buffer (primary or alternate).
  ///
  /// Full-screen programs (vim, less, htop) use the alternate screen.
  /// Scrollback is only available on the primary screen.
  TerminalScreen get activeScreen;

  /// Current cursor position in the active viewport.
  Position get cursorPosition;

  /// Current terminal configuration.
  TerminalConfig get config;

  /// Replaces the configuration.
  ///
  /// Applies mode and encoder changes without recreating the terminal.
  /// Screen content, scrollback, and cursor position are preserved.
  set config(TerminalConfig config);

  /// Whether the terminal currently has an active text selection.
  bool get hasSelection;

  /// Current soft keyboard state.
  KeyboardState get keyboardState;

  /// Current mouse tracking mode requested by the terminal program.
  ///
  /// When active, mouse events are encoded and sent to the program
  /// instead of performing selection. Hold Shift to bypass.
  MouseTracking get mouseTracking;

  /// Working directory reported by the shell (OSC 7). Empty if unset.
  String get pwd;

  /// Number of scrollback rows above the viewport.
  int get scrollbackRows;

  /// Scrollbar state: total rows, visible rows, and current offset.
  Scrollbar get scrollbar;

  /// Terminal title set by the running program.
  String get title;

  /// Total rows: viewport plus scrollback.
  int get totalRows;

  /// Virtual modifier keys for on-screen keyboard UIs.
  ///
  /// Merged with physical modifiers when encoding input. Cleared
  /// automatically after [sendKey] or [sendText] produces output.
  ///
  /// ```dart
  /// controller.toggleMod(const Mods.ctrl());
  /// controller.sendKey(Key.c); // Sends Ctrl+C, clears the mod.
  /// ```
  Mods get virtualMods;

  /// Clears scrollback and sends a form feed via [onOutput].
  ///
  /// No-op on the alternate screen.
  void clear();

  /// Clears the current selection.
  void clearSelection();

  /// Clears all virtual modifiers.
  void clearVirtualMods();

  /// Creates a [Formatter] for extracting terminal content.
  ///
  /// Supports plain text, HTML, and VT sequence output via [format].
  /// Set [unwrap] to join soft-wrapped lines, [trim] to strip trailing
  /// whitespace.
  Formatter createFormatter({
    required FormatterFormat format,
    bool unwrap = false,
    bool trim = false,
    FormatterExtra extra = const FormatterExtra(),
  });

  /// Hides the soft keyboard and keeps it hidden.
  ///
  /// Stays hidden until [showKeyboard] is called. Focus changes alone
  /// will not re-show it.
  void disableKeyboard();

  /// Hides the soft keyboard. Re-shows on next focus gain.
  void hideKeyboard();

  /// Returns the live value of a terminal [mode].
  ///
  /// May differ from [config] if the running program changed it.
  bool modeGet(TerminalMode mode);

  /// Sets a terminal [mode] at runtime.
  ///
  /// Not persisted in [config]. May be overwritten when the terminal
  /// restores modes (e.g. exiting the alternate screen).
  void modeSet(TerminalMode mode, {required bool value});

  /// Sends paste data to the terminal via [onOutput].
  ///
  /// Wraps the text in bracketed paste sequences when the terminal
  /// has bracketed paste mode enabled. Scrolls to bottom based on
  /// [TerminalConfig.scrollToBottom] policy.
  void paste(String text);

  /// Requests keyboard focus for the attached [TerminalView].
  void requestFocus();

  /// Scrolls the viewport to the bottom (most recent content).
  void scrollToBottom();

  /// Scrolls the viewport to the top of the scrollback history.
  void scrollToTop();

  /// Selects all terminal content including scrollback.
  void selectAll();

  /// Returns the text within the current selection, or empty string when
  /// there is no selection.
  ///
  /// [format] controls the output encoding:
  /// - [FormatterFormat.plain]: unstyled text, suitable for the clipboard
  ///   (default).
  /// - [FormatterFormat.vt]: VT escape sequences preserving colors, styles,
  ///   and hyperlinks.
  /// - [FormatterFormat.html]: HTML with inline styles.
  ///
  /// In normal selection mode, soft-wrapped lines are joined into a single
  /// line without an inserted newline. In block mode, every row is kept
  /// separate regardless of wrapping.
  String selectedText({FormatterFormat format = .plain});

  /// Selects the inclusive range between two terminal cells.
  ///
  /// Coordinates are interpreted in [pointTag]. Use [PointTag.screen] for
  /// rows counted from the top of scrollback through the active screen, or
  /// [PointTag.viewport] for currently visible rows. When [rectangle] is
  /// true, the endpoints describe opposite corners of a block selection.
  void selectRange({
    required Position start,
    required Position end,
    PointTag pointTag = .screen,
    bool rectangle = false,
  });

  /// Encodes a key press and sends it via [onOutput].
  ///
  /// [mods] are merged with [virtualMods]. Virtual modifiers are cleared
  /// after output is produced.
  void sendKey(Key key, {Mods mods = const Mods.none()});

  /// Sends literal UTF-8 text via [onOutput].
  ///
  /// No key encoding is applied. Use [sendKey] for individual key
  /// presses that need proper escape sequence encoding.
  void sendText(String text);

  /// Shows the soft keyboard and re-enables it if disabled.
  void showKeyboard();

  /// Toggles a virtual modifier on or off.
  void toggleMod(Mods mod);

  /// Removes keyboard focus from the attached [TerminalView].
  void unfocus();

  /// Feeds raw bytes from the backend into the terminal.
  ///
  /// Call this with data received from your PTY, SSH channel, or socket.
  /// The terminal processes the bytes and may call [onOutput] with
  /// response data (e.g. for device attribute queries).
  void write(Uint8List data);
}
