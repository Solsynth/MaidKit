import 'package:flutter/gestures.dart' show kDoubleTapSlop, kDoubleTapTimeout;
import 'package:flutter/widgets.dart' show Offset;
import 'package:libghostty/libghostty.dart'
    show
        GridRef,
        Position,
        Selection,
        SelectionGesture,
        SelectionGestureBehavior,
        SelectionGestureEvent,
        SelectionGestureGeometry,
        Terminal;
import 'package:meta/meta.dart';

import '../foundation.dart';

@internal
final class SelectionGestureDriver {
  final SelectionGesture _gesture;
  final SelectionGestureEvent _drag = .drag();
  final SelectionGestureEvent _press = .press();
  final SelectionGestureEvent _release = .release();
  final SelectionGestureEvent _autoscroll = .autoscrollTick();
  final _pressClock = Stopwatch()..start();
  List<int>? _wordBoundaryCodepoints;

  SelectionGestureDriver(Terminal terminal)
    : _gesture = SelectionGesture(terminal);

  SelectionGestureBehavior get behavior => _gesture.state.behavior;

  Selection? autoscroll({
    required Position cell,
    required Offset localPosition,
    required bool rectangle,
    required SelectionGestureGeometry geometry,
  }) {
    _autoscroll
      ..setViewport(cell)
      ..setPosition(localPosition.dx, localPosition.dy)
      ..setRectangle(value: rectangle)
      ..setGeometry(geometry);
    _setWordBoundaryCodepoints(_autoscroll);
    return _gesture.apply(_autoscroll);
  }

  void dispose() {
    _release.dispose();
    _autoscroll.dispose();
    _drag.dispose();
    _press.dispose();
    _gesture.dispose();
  }

  Selection? drag({
    required GridRef ref,
    required Offset localPosition,
    required bool rectangle,
    required SelectionGestureGeometry geometry,
  }) {
    _drag
      ..setRef(ref)
      ..setPosition(localPosition.dx, localPosition.dy)
      ..setRectangle(value: rectangle)
      ..setGeometry(geometry);
    _setWordBoundaryCodepoints(_drag);
    return _gesture.apply(_drag);
  }

  Selection? press({
    required GridRef ref,
    required Offset localPosition,
    required TerminalGestureSettings settings,
  }) {
    _wordBoundaryCodepoints = settings.wordBoundaries?.runes.toList(
      growable: false,
    );
    _press
      ..setRef(ref)
      ..setPosition(localPosition.dx, localPosition.dy)
      ..setBehaviors(settings.selectionBehaviors)
      ..setRepeatDistance(kDoubleTapSlop)
      ..setRepeatIntervalNs(kDoubleTapTimeout.inMicroseconds * 1000)
      ..setTimeNs(_pressClock.elapsedMicroseconds * 1000);
    _setWordBoundaryCodepoints(_press);
    return _gesture.apply(_press);
  }

  Selection? release(GridRef? ref) {
    _release.setRef(ref);
    return _gesture.apply(_release);
  }

  void reset() {
    _wordBoundaryCodepoints = null;
    _gesture.reset();
  }

  void _setWordBoundaryCodepoints(SelectionGestureEvent event) {
    final codepoints = _wordBoundaryCodepoints;
    if (codepoints == null) {
      event.clear(.wordBoundaryCodepoints);
      return;
    }
    event.setWordBoundaryCodepoints(codepoints);
  }
}
