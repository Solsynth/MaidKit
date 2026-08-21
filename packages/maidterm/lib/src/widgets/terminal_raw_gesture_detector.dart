import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// Gesture detector that recognizes taps, mouse drags, and touch long presses.
///
/// Drag is restricted to mouse devices, long press to touch devices.
///
/// ```dart
/// TerminalRawGestureDetector(
///   onTapDown: (details) => handleTapDown(details),
///   onTapUp: (details) => handleTapUp(details),
///   onDragStart: (details) => handleDragStart(details),
///   child: Container(),
/// )
/// ```
@internal
class TerminalRawGestureDetector extends StatelessWidget {
  final Widget child;

  /// Fires when a tap begins.
  final GestureTapDownCallback? onTapDown;

  /// Fires when a tap ends.
  final GestureTapUpCallback? onTapUp;

  /// Fires when a mouse drag begins.
  final GestureDragStartCallback? onDragStart;

  /// Fires as the mouse drag continues.
  final GestureDragUpdateCallback? onDragUpdate;

  /// Fires when a mouse drag ends or is cancelled.
  final VoidCallback? onDragEnd;

  /// Fires when a touch long press begins.
  final GestureLongPressStartCallback? onLongPressStart;

  /// Fires as a touch long press moves.
  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;

  /// Fires when a touch long press ends.
  final VoidCallback? onLongPressUp;

  const TerminalRawGestureDetector({
    super.key,
    required this.child,
    this.onTapDown,
    this.onTapUp,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressUp,
  });

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              () => TapGestureRecognizer(debugOwner: this),
              (instance) => instance
                ..onTapDown = onTapDown
                ..onTapUp = onTapUp,
            ),
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(
                debugOwner: this,
                supportedDevices: const {PointerDeviceKind.touch},
              ),
              (instance) => instance
                ..onLongPressStart = onLongPressStart?.call
                ..onLongPressMoveUpdate = onLongPressMoveUpdate
                ..onLongPressUp = onLongPressUp,
            ),
        PanGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
              () => PanGestureRecognizer(
                debugOwner: this,
                supportedDevices: const {PointerDeviceKind.mouse},
              ),
              (instance) {
                instance
                  ..dragStartBehavior = .down
                  ..onStart = onDragStart
                  ..onUpdate = onDragUpdate
                  ..onEnd = (_) => onDragEnd?.call();
                instance.onCancel = () => onDragEnd?.call();
              },
            ),
      },
      child: child,
    );
  }
}
