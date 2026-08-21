import 'package:flutter/widgets.dart';
import 'package:libghostty/libghostty.dart' show TerminalScreen;
import 'package:meta/meta.dart';

/// Scroll controller for [TerminalView].
///
/// On the primary screen, scrolls through the scrollback buffer like
/// a normal [ScrollController]. On the alternate screen (vim, less),
/// scroll gestures are converted to cursor key input instead.
///
/// Created internally by [TerminalView] when not provided. Supply your
/// own to observe or control the scroll position programmatically.
///
/// ```dart
/// final scrollController = TerminalScrollController();
///
/// TerminalView(
///   controller: controller,
///   scrollController: scrollController,
/// );
///
/// // Jump to the top of scrollback.
/// scrollController.jumpTo(0);
/// ```
class TerminalScrollController extends ScrollController {
  var _activeScreen = TerminalScreen.primary;

  TerminalScrollController();

  /// The active terminal screen.
  TerminalScreen get activeScreen => _activeScreen;

  @internal
  set activeScreen(TerminalScreen value) {
    if (_activeScreen == value) return;
    _activeScreen = value;
    for (final position in positions) {
      (position as TerminalScrollPosition).activeScreen = value;
    }
  }

  @override
  TerminalScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return TerminalScrollPosition(
      physics: physics,
      context: context,
      oldPosition: oldPosition,
      activeScreen: _activeScreen,
    );
  }
}

/// Scroll position used by [TerminalScrollController].
///
/// Adapts to the active terminal screen. On the alternate screen,
/// accepts all scroll extents so gestures are never rejected. Saves
/// and restores the primary screen scroll offset across screen switches.
class TerminalScrollPosition extends ScrollPositionWithSingleContext {
  double? _savedPixels;
  TerminalScreen _activeScreen;

  TerminalScrollPosition({
    required super.physics,
    required super.context,
    required this._activeScreen,
    super.oldPosition,
  });

  TerminalScreen get activeScreen => _activeScreen;

  @internal
  set activeScreen(TerminalScreen value) {
    if (_activeScreen == value) return;
    if (value == .alternate && hasPixels) {
      _savedPixels = pixels;
    }
    _activeScreen = value;
    if (value == .primary && _savedPixels != null) {
      correctPixels(_savedPixels!);
      _savedPixels = null;
    }
  }

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    if (_activeScreen == .alternate) {
      return super.applyContentDimensions(
        double.negativeInfinity,
        double.infinity,
      );
    }
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }
}
