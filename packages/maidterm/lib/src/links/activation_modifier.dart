/// Modifier key policy for pointer activation gestures.
enum ActivationModifier {
  /// Uses the primary modifier for the current platform.
  ///
  /// This is Cmd on Apple platforms and Ctrl elsewhere.
  primary,

  /// Activates without requiring a modifier.
  none,

  /// Requires the Alt or Option key.
  alt,

  /// Requires the Ctrl key.
  control,

  /// Requires the Cmd, Windows, or Super key.
  meta,

  /// Requires the Shift key.
  shift,
}
