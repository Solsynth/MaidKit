import 'package:libghostty/libghostty.dart';

/// Callback for terminal grid resize events.
///
/// Fires when the [TerminalView] layout changes and produces a different
/// number of character [cols] and [rows]. [pixelWidth] and [pixelHeight] are
/// the viewport size in **physical** pixels (logical cell metrics scaled by
/// the device pixel ratio, rounded) — matching what a native terminal reports
/// through `TIOCGWINSZ`'s `ws_xpixel`/`ws_ypixel`. Set on
/// [TerminalController.onResize] to forward size changes to the backend
/// (PTY, SSH, etc.) so remote clients can size graphics correctly.
///
/// ```dart
/// controller.onResize =
///     (cols, rows, pixelWidth, pixelHeight) => pty.resize(cols, rows);
/// ```
typedef OnResize =
    void Function(int cols, int rows, int pixelWidth, int pixelHeight);

/// Mouse event data from the gesture detector to the controller.
///
/// Carries the raw pixel coordinates and the semantic action/button so
/// the controller can encode mouse reports for the terminal. Pixel
/// coordinates are relative to the terminal grid origin (after padding).
///
/// ```dart
/// final event = (
///   action: MouseAction.press,
///   button: MouseButton.left,
///   pixelX: offset.dx,
///   pixelY: offset.dy,
/// );
/// controller.handleMouseEvent(event);
/// ```
typedef TerminalMouseEvent = ({
  MouseAction action,
  MouseButton button,
  double pixelX,
  double pixelY,
});
