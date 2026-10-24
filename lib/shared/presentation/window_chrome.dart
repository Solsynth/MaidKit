import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'package:maid_kit/servers/window_state_preferences.dart';
import 'package:maid_kit/theme.dart';

/// Whether the app runs inside a native desktop window.
bool get isMaidKitDesktop =>
    !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);

/// Whether the OS draws the window buttons itself, inside the window.
///
/// macOS keeps its traffic lights at the top-left of a full-size content view,
/// so the app only reserves room for them. Windows and Linux get a borderless
/// window, so the app draws the buttons in the title bar band.
bool get usesNativeWindowButtons => !kIsWeb && Platform.isMacOS;

/// Height of the title bar band, in logical points.
///
/// The band sits above the workspace's tabs and is the only place that moves
/// the window. On macOS AppKit keeps its own title bar above a full-size
/// content view and spends any pointer inside it on dragging the window, so
/// the band must stay clear of anything the user has to click or drag — the
/// tabs above all, which drag themselves along the strip. AppKit's own title
/// bar is 28 window points, and even the smallest allowed UI scale leaves this
/// band covering it.
const double kMaidKitTitleBarHeight = 40;

/// Height of the workspace's tab strip row, in logical points.
///
/// This is a row of its own below the title bar band: it holds the tabs and
/// their controls, but never the window drag.
const double kMaidKitTabStripHeight = 40;

/// Width reserved on the leading edge of the title bar for the macOS traffic
/// lights, which the native window places there and the app must not cover.
const double kMaidKitTrafficLightInset = 78 + 8;

/// Whether the app is running as a native desktop window.
///
/// Desktop draws a real title bar band above the workspace; mobile and web
/// have no OS window chrome to merge with, so they draw none.
final desktopWindowProvider = Provider<bool>((ref) => isMaidKitDesktop);

/// Closes the desktop window without a visible teardown stall.
///
/// On Windows, `windowManager.destroy()` only posts WM_QUIT; the window stays
/// on screen while the engines (Flutter, plus WebView2's title-bar engine)
/// shut down and stop pumping messages, which reads as a freeze. Hide first,
/// then quit. On macOS/Linux `destroy()` tears down immediately either way.
///
/// `destroy()` quits the process without emitting a window-close event on
/// Windows and macOS, so the geometry is flushed here while the isolate still
/// runs — that is the only save the in-app close button gets. The flush is
/// bounded so a stalled platform call cannot trap the app on a hidden window.
Future<void> closeMaidKitWindow() async {
  // window_manager has no web implementation; the browser tab owns its own
  // lifetime, so there is no window to hide or destroy.
  if (kIsWeb) return;
  await windowManager.hide();
  await saveMaidKitWindowStateFromWindow().timeout(
    const Duration(milliseconds: 750),
    onTimeout: () {},
  );
  await windowManager.destroy();
}

/// Tells the native window how tall the title bar band is, in points.
///
/// macOS centers the traffic lights in AppKit's title bar; the band the app
/// reserves sits at the window's top edge and holds nothing interactive, so
/// the native window moves the lights onto the band's center line. The height
/// is in *window* points, so it scales with the app's UI scale, which shrinks
/// the logical viewport while leaving the native window alone.
class MaidKitTitleBarHeightReporter extends StatefulWidget {
  const MaidKitTitleBarHeightReporter({
    super.key,
    required this.uiScale,
    required this.child,
  });

  final double uiScale;
  final Widget child;

  @override
  State<MaidKitTitleBarHeightReporter> createState() =>
      _MaidKitTitleBarHeightReporterState();
}

class _MaidKitTitleBarHeightReporterState
    extends State<MaidKitTitleBarHeightReporter> {
  static const _channel = MethodChannel('maidkit/window');

  @override
  void initState() {
    super.initState();
    _report();
  }

  @override
  void didUpdateWidget(MaidKitTitleBarHeightReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uiScale != widget.uiScale) _report();
  }

  void _report() {
    if (!isMaidKitDesktop || !usesNativeWindowButtons) return;
    final scale = widget.uiScale <= 0 ? 1.0 : widget.uiScale;
    // The subtree is scaled down by `scale`, so one logical point of the band
    // covers `scale` window points.
    _channel.invokeMethod<void>(
      'setTitleBarHeight',
      kMaidKitTitleBarHeight * scale,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The window's title bar: the band that moves the window.
///
/// It sits above the workspace's tab strip rather than behind it. macOS gives
/// the top of the window to AppKit before Flutter sees the pointer, so a tab
/// drawn there could be neither pressed nor dragged; a band of its own keeps
/// both jobs separate. The band names the window while no tab strip is on
/// screen (the locked vault, an empty workspace), and on platforms whose
/// window Flutter draws it carries the window buttons too.
class MaidKitTitleBar extends StatelessWidget {
  const MaidKitTitleBar({super.key, this.title, this.trailing = const []});

  /// Label on the leading side. Omitted on macOS, where the traffic lights sit
  /// there and the bar is usually the only chrome the screen has.
  final Widget? title;

  /// Controls drawn just before the window buttons.
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    if (!isMaidKitDesktop) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Material(
      // Same paper as the tab bar beneath it: the two read as one title area
      // even though only the top band moves the window.
      color: scheme.surfaceContainerLowest,
      child: MaidKitWindowDragArea(
        child: SizedBox(
          height: kMaidKitTitleBarHeight,
          child: Row(
            children: [
              if (usesNativeWindowButtons)
                const SizedBox(width: kMaidKitTrafficLightInset),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: usesNativeWindowButtons ? 0 : 12,
                  ),
                  child: DefaultTextStyle.merge(
                    style: Theme.of(context).textTheme.labelLarge!.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: title ?? const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
              ...trailing,
              const MaidKitWindowButtons(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Makes its child drag the native window, and a double tap toggle maximize.
///
/// The window is borderless, so the title bar band is the only place that
/// moves it. Child widgets that own a drag — a tab — stay outside this area,
/// so the two gestures never compete.
class MaidKitWindowDragArea extends StatelessWidget {
  const MaidKitWindowDragArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      isMaidKitDesktop ? DragToMoveArea(child: child) : child;
}

/// The window buttons for platforms whose window is drawn by Flutter.
///
/// macOS keeps its native traffic lights, so this renders nothing there.
class MaidKitWindowButtons extends StatefulWidget {
  const MaidKitWindowButtons({super.key});

  @override
  State<MaidKitWindowButtons> createState() => _MaidKitWindowButtonsState();
}

class _MaidKitWindowButtonsState extends State<MaidKitWindowButtons>
    with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (!isMaidKitDesktop || usesNativeWindowButtons) return;
    windowManager.addListener(this);
    windowManager.isMaximized().then((value) {
      if (mounted) setState(() => _isMaximized = value);
    });
  }

  @override
  void dispose() {
    if (isMaidKitDesktop && !usesNativeWindowButtons) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!isMaidKitDesktop || usesNativeWindowButtons) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WindowButton(
          icon: Symbols.minimize,
          tooltip: 'windowMinimize'.tr(),
          onPressed: windowManager.minimize,
        ),
        _WindowButton(
          icon: _isMaximized ? Symbols.fullscreen_exit : Symbols.fullscreen,
          tooltip: _isMaximized ? 'windowRestore'.tr() : 'windowMaximize'.tr(),
          onPressed: () async {
            if (await windowManager.isMaximized()) {
              await windowManager.restore();
            } else {
              await windowManager.maximize();
            }
          },
        ),
        _WindowButton(
          icon: Symbols.close,
          tooltip: 'windowClose'.tr(),
          // The one place the title bar may raise its voice: the glyph turns
          // into the danger color under the pointer while the surface stays
          // quiet.
          iconHoverColor: scheme.error,
          onPressed: () => unawaited(closeMaidKitWindow()),
        ),
      ],
    );
  }
}

/// One window control: a rounded 32×28 hit area centered in the title bar.
///
/// The buttons no longer fill the strip edge to edge, so they read as controls
/// on the bar instead of segments of it, and their hover surface is the same
/// quiet tonal step the rest of the chrome uses.
class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconHoverColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  /// Ink the glyph takes while the pointer is over the button.
  final Color? iconHoverColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(MaidKitRadius.sm),
          hoverColor: scheme.surfaceContainerHighest,
          child: SizedBox(
            width: 32,
            height: 28,
            child: Icon(
              icon,
              size: 16,
              color: iconHoverColor == null ? scheme.onSurfaceVariant : null,
            ),
          ),
        ),
      ),
    );
  }
}
