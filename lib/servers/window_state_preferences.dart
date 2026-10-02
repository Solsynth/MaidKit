import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

/// Persisted desktop window geometry.
///
/// [bounds] and [maximized] capture the window state the user last left it
/// in. [bounds] is always the *normal* frame — the frame the window falls back
/// to when it is un-maximized — because a maximized window reports the whole
/// screen and restoring that as a size loses the size the user picked.
/// [MaidKitWindowStateListener] keeps both fresh while the session runs, so the
/// next launch restores the same size, position and maximized state.
class MaidKitWindowState {
  const MaidKitWindowState({required this.bounds, required this.maximized});

  final Rect bounds;
  final bool maximized;
}

/// Keys for the geometry state in `SharedPreferencesAsync`.
const _windowBoundsKey = 'maidkit_window_bounds';
const _windowMaximizedKey = 'maidkit_window_maximized';

/// Loads the saved window geometry, or `null` when there is nothing stored or
/// the stored value is malformed. The caller falls back to the default size.
Future<MaidKitWindowState?> loadMaidKitWindowState() async {
  final preferences = SharedPreferencesAsync();
  final bounds = _decodeBounds(await preferences.getString(_windowBoundsKey));
  if (bounds == null) return null;
  return MaidKitWindowState(
    bounds: bounds,
    maximized: await preferences.getBool(_windowMaximizedKey) ?? false,
  );
}

/// Stores [state] so the next launch restores the same window geometry.
Future<void> saveMaidKitWindowState(MaidKitWindowState state) async {
  final preferences = SharedPreferencesAsync();
  await preferences.setString(_windowBoundsKey, _encodeBounds(state.bounds));
  await preferences.setBool(_windowMaximizedKey, state.maximized);
}

String _encodeBounds(Rect bounds) =>
    '${bounds.left},${bounds.top},${bounds.width},${bounds.height}';

Rect? _decodeBounds(String? raw) {
  if (raw == null) return null;
  final parts = raw.split(',');
  if (parts.length != 4) return null;
  final numbers = <double>[];
  for (final part in parts) {
    final value = double.tryParse(part);
    // `double.tryParse` accepts 'NaN' and 'Infinity', but a frame built from
    // them cannot be applied to the native window.
    if (value == null || !value.isFinite) return null;
    numbers.add(value);
  }
  final width = numbers[2];
  final height = numbers[3];
  if (width < 1 || height < 1) return null;
  return Rect.fromLTWH(numbers[0], numbers[1], width, height);
}

/// Snapshot the window geometry right now. Used as a best-effort save when
/// the app is about to terminate through a native close path.
///
/// A minimized window reports the taskbar icon's frame, and a maximized window
/// reports the screen; neither is a frame worth restoring. The minimized frame
/// is skipped and the maximized one keeps the stored normal frame.
Future<void> saveMaidKitWindowStateFromWindow() async {
  // No window_manager implementation in the browser.
  if (kIsWeb) return;
  try {
    // A full-screen window covers the display, which is not a size the user
    // chose either; keep the state that is already stored.
    if (await windowManager.isMinimized()) return;
    if (await windowManager.isFullScreen()) return;
    final maximized = await windowManager.isMaximized();
    final stored = maximized ? await loadMaidKitWindowState() : null;
    await saveMaidKitWindowState(
      MaidKitWindowState(
        bounds: stored?.bounds ?? await windowManager.getBounds(),
        maximized: maximized,
      ),
    );
  } catch (_) {
    // Best-effort; the in-session saves already persisted the geometry.
  }
}

/// Watches the desktop window for geometry changes during the session and
/// records the latest bounds and maximized state, so the window state
/// survives app restarts even when the process is killed without an orderly
/// close.
///
/// The native plugins emit these events as the interaction happens:
/// - Windows: on `WM_EXITSIZEMOVE` after a drag-resize or drag-move;
/// - macOS: on `windowDidEndLiveResize` / `windowDidMove`;
/// - Linux: on the GTK `check-resize` and `configure-event` signals.
/// Events during a live drag are debounced so the state is written once the
/// drag settles. Maximize is tracked as a flag because it changes the frame
/// without a size event here, and the frame size reported while maximized is
/// not meaningful to persist.
class MaidKitWindowStateListener with WindowListener {
  /// [initial] is the state loaded at startup. Its bounds are the normal frame
  /// the window returns to when it is un-maximized, so they are kept while the
  /// window is maximized rather than being replaced by the screen-sized frame.
  MaidKitWindowStateListener({MaidKitWindowState? initial})
    : _normalBounds = initial?.bounds;

  /// The last frame the window had while it was neither maximized, minimized
  /// nor full-screen, or `null` before one has been observed.
  Rect? _normalBounds;
  bool _maximized = false;
  bool _minimized = false;
  bool _fullScreen = false;
  Timer? _saveTimer;

  /// Registers [handler] to run when the window is closed through the native
  /// path (title-bar button or OS close). The hook is fire-and-forget and the
  /// listener lives for the whole app process, so no removal is needed.
  static void onAppClose(Future<void> Function() handler) {
    // window_manager has no web implementation.
    if (kIsWeb) return;
    windowManager.addListener(_MaidKitWindowStateCloseListener(handler));
  }

  /// Starts listening and records the current geometry as a baseline.
  Future<void> start() async {
    if (kIsWeb) return;
    windowManager.addListener(this);
    _maximized = await windowManager.isMaximized();
    _minimized = await windowManager.isMinimized();
    _fullScreen = await windowManager.isFullScreen();
    await _saveCurrentState();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 200), () async {
      _saveTimer = null;
      await _saveCurrentState();
    });
  }

  @override
  void onWindowResized() => _scheduleSave();

  @override
  void onWindowMoved() => _scheduleSave();

  @override
  void onWindowMinimize() {
    _minimized = true;
    _scheduleSave();
  }

  @override
  void onWindowRestore() {
    _minimized = false;
    _scheduleSave();
  }

  @override
  void onWindowEnterFullScreen() {
    _fullScreen = true;
    _scheduleSave();
  }

  @override
  void onWindowLeaveFullScreen() {
    _fullScreen = false;
    _scheduleSave();
  }

  @override
  void onWindowMaximize() {
    _maximized = true;
    _scheduleSave();
  }

  @override
  void onWindowUnmaximize() {
    _maximized = false;
    _scheduleSave();
  }

  Future<void> _saveCurrentState() async {
    try {
      // A minimized window's frame is its taskbar icon, and a full-screen
      // window's frame is the display; neither is the window the user sized.
      if (_minimized || _fullScreen) return;
      final bounds = await windowManager.getBounds();
      if (!_maximized) _normalBounds = bounds;
      await saveMaidKitWindowState(
        MaidKitWindowState(
          bounds: _normalBounds ?? bounds,
          maximized: _maximized,
        ),
      );
    } catch (_) {
      // A missing window manager or a failed preference write must not surface
      // as an unhandled error; the next geometry change retries.
    }
  }
}

/// Fire-and-forget close hook used by [MaidKitWindowStateListener.onAppClose].
class _MaidKitWindowStateCloseListener with WindowListener {
  _MaidKitWindowStateCloseListener(this._handler);

  final Future<void> Function() _handler;

  @override
  void onWindowClose() {
    _handler().catchError((_) {});
  }
}
