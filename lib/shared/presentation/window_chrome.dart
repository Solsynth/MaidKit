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

/// Whether the app runs inside a native desktop window.
bool get isMaidKitDesktop =>
    !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);

/// Whether the OS draws the window buttons itself, inside the window.
///
/// macOS keeps its traffic lights at the top-left of a full-size content view,
/// so the app only reserves room for them. Windows and Linux get a borderless
/// window, so the app draws the buttons in the pane tab strip.
bool get usesNativeWindowButtons => !kIsWeb && Platform.isMacOS;

/// Height of the window title bar. The top pane tab strip fills exactly this,
/// which is what merges the two bars into one.
const double kMaidKitTitleBarHeight = 40;

/// Leading room the macOS traffic lights need on the title bar.
const double kMaidKitTrafficLightInset = 78;

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

/// Tells the native window how tall the merged title bar is, in points.
///
/// macOS centers its traffic lights in AppKit's 28 pt title bar, so the native
/// window has to know where the strip's center line actually is. The height is
/// in *window* points, so it scales with the app's UI scale, which shrinks the
/// logical viewport while leaving the native window alone.
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
    // The subtree is scaled down by `scale`, so one logical title bar point
    // covers `scale` window points.
    _channel.invokeMethod<void>(
      'setTitleBarHeight',
      kMaidKitTitleBarHeight * scale,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A standalone window title bar.
///
/// The workspace merges its pane tab strip into the title bar, so this is only
/// for screens that have no strip to merge: the locked vault, and a workspace
/// with no panes left. It keeps the window draggable and closable in both.
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
      color: scheme.surface,
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
/// The window is borderless, so the title bar is the only place that moves it.
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
          // The one place the strip may raise its voice: the close button
          // turns into the platform's danger color under the pointer.
          hoverColor: scheme.error,
          onPressed: () => unawaited(closeMaidKitWindow()),
        ),
      ],
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.hoverColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? hoverColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        hoverColor: hoverColor,
        child: SizedBox(
          width: 44,
          height: kMaidKitTitleBarHeight,
          child: Icon(
            icon,
            size: 16,
            color: hoverColor == null ? scheme.onSurfaceVariant : null,
          ),
        ),
      ),
    );
  }
}
