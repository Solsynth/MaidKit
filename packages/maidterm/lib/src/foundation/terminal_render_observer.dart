import 'package:flutter/foundation.dart';

/// Observable focus state for the rendering layer.
///
/// Implemented by [TerminalController] and consumed by painters that need
/// to react to focus changes or selection updates without depending on
/// the full controller API.
///
/// Listeners are notified when [hasFocus] changes, triggering repaint of
/// cursor state.
abstract class TerminalRenderObserver implements Listenable {
  /// Whether the terminal view has keyboard focus.
  ///
  /// Painters use this to adjust cursor rendering: a focused terminal
  /// draws a filled cursor, while an unfocused terminal draws a hollow
  /// block outline.
  bool get hasFocus;
}
