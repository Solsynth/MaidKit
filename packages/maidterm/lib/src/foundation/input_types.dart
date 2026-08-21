/// Soft keyboard visibility state on mobile platforms.
///
/// Managed by [TerminalController] and driven by focus events and explicit
/// API calls. On desktop platforms where a physical keyboard is always
/// present, this state has no visible effect.
///
/// ```dart
/// if (controller.keyboardState == KeyboardState.disabled) {
///   controller.showKeyboard();
/// }
/// ```
enum KeyboardState {
  /// Keyboard visible, text input active.
  showing,

  /// Keyboard hidden, re-shows on next focus gain.
  hidden,

  /// Keyboard hidden, stays hidden until [TerminalController.showKeyboard].
  disabled,
}

/// Controls when the mouse cursor hides during terminal interaction.
///
/// Passed to [TerminalView.mouseAutoHide] to configure cursor visibility
/// behavior.
enum MouseAutoHide {
  /// Keeps the system cursor visible at all times.
  never,

  /// Hides the cursor after a keystroke and restores it on mouse movement.
  onInput,
}
