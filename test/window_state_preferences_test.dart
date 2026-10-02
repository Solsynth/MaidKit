import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:window_manager/window_manager.dart';

import 'package:maid_kit/servers/window_state_preferences.dart';

const _windowManagerChannel = MethodChannel('window_manager');
const _methodCodec = StandardMethodCodec();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Rect windowBounds;
  late bool windowMaximized;
  late bool windowMinimized;
  late bool windowFullScreen;

  setUp(() {
    // Route SharedPreferencesAsync to an in-memory store so window geometry
    // can be round-tripped without touching the host platform.
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    windowBounds = const Rect.fromLTWH(100, 100, 900, 700);
    windowMaximized = false;
    windowMinimized = false;
    windowFullScreen = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowManagerChannel, (call) async {
          switch (call.method) {
            case 'isMaximized':
              return windowMaximized;
            case 'isMinimized':
              return windowMinimized;
            case 'isFullScreen':
              return windowFullScreen;
            case 'getBounds':
              return {
                'x': windowBounds.left,
                'y': windowBounds.top,
                'width': windowBounds.width,
                'height': windowBounds.height,
              };
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowManagerChannel, null);
  });

  /// Delivers a native window event exactly like the platform plugin does.
  Future<void> emitWindowEvent(String eventName) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          _windowManagerChannel.name,
          _methodCodec.encodeMethodCall(
            MethodCall('onEvent', {'eventName': eventName}),
          ),
          (_) {},
        );
  }

  /// The listener debounces geometry events before writing them.
  Future<void> settleDebounce() =>
      Future<void>.delayed(const Duration(milliseconds: 400));

  test('round-trips window bounds and maximized state', () async {
    await saveMaidKitWindowState(
      const MaidKitWindowState(
        bounds: Rect.fromLTWH(24, 16, 1400, 900),
        maximized: true,
      ),
    );

    final restored = await loadMaidKitWindowState();

    expect(restored, isNotNull);
    expect(restored!.bounds, const Rect.fromLTWH(24, 16, 1400, 900));
    expect(restored.maximized, isTrue);
  });

  test('saving a non-maximized state keeps the flag false', () async {
    await saveMaidKitWindowState(
      const MaidKitWindowState(
        bounds: Rect.fromLTWH(0, 0, 800, 600),
        maximized: false,
      ),
    );

    final restored = await loadMaidKitWindowState();

    expect(restored, isNotNull);
    expect(restored!.maximized, isFalse);
  });

  test('returns null when no state was stored yet', () async {
    expect(await loadMaidKitWindowState(), isNull);
  });

  test('treats malformed or degenerate stored bounds as absent', () async {
    final store = SharedPreferencesAsync();
    await store.setString('maidkit_window_bounds', 'not,a,valid,rect');

    expect(await loadMaidKitWindowState(), isNull);

    await store.setString('maidkit_window_bounds', '0,0,0,600');

    expect(await loadMaidKitWindowState(), isNull);

    await store.setString('maidkit_window_bounds', '0,0,800,0');

    expect(await loadMaidKitWindowState(), isNull);
  });

  test('treats non-finite stored bounds as absent', () async {
    final store = SharedPreferencesAsync();

    await store.setString('maidkit_window_bounds', 'NaN,NaN,NaN,NaN');
    expect(await loadMaidKitWindowState(), isNull);

    await store.setString('maidkit_window_bounds', 'Infinity,0,800,600');
    expect(await loadMaidKitWindowState(), isNull);

    await store.setString('maidkit_window_bounds', '0,0,Infinity,600');
    expect(await loadMaidKitWindowState(), isNull);
  });

  test('keeps fractional bounds accurate after a round-trip', () async {
    await saveMaidKitWindowState(
      const MaidKitWindowState(
        bounds: Rect.fromLTWH(100.5, 200.25, 1024.75, 768.5),
        maximized: false,
      ),
    );

    final restored = await loadMaidKitWindowState();

    expect(restored, isNotNull);
    expect(
      restored!.bounds,
      const Rect.fromLTWH(100.5, 200.25, 1024.75, 768.5),
    );
  });

  group('MaidKitWindowStateListener', () {
    late MaidKitWindowStateListener listener;

    setUp(() async {
      listener = MaidKitWindowStateListener();
      await listener.start();
    });

    tearDown(() {
      windowManager.removeListener(listener);
    });

    test('records the starting geometry as a baseline', () async {
      final restored = await loadMaidKitWindowState();

      expect(restored!.bounds, const Rect.fromLTWH(100, 100, 900, 700));
      expect(restored.maximized, isFalse);
    });

    test('persists the geometry once a resize settles', () async {
      windowBounds = const Rect.fromLTWH(200, 150, 1200, 800);

      await emitWindowEvent('resized');
      await settleDebounce();

      final restored = await loadMaidKitWindowState();

      expect(restored!.bounds, const Rect.fromLTWH(200, 150, 1200, 800));
    });

    test('persists a move without waiting for a resize', () async {
      windowBounds = const Rect.fromLTWH(12, 34, 900, 700);

      await emitWindowEvent('moved');
      await settleDebounce();

      final restored = await loadMaidKitWindowState();

      expect(restored!.bounds, const Rect.fromLTWH(12, 34, 900, 700));
    });

    test('keeps the normal frame while the window is maximized', () async {
      windowMaximized = true;
      windowBounds = const Rect.fromLTWH(0, 33, 1512, 949);

      await emitWindowEvent('maximize');
      await settleDebounce();

      final maximized = await loadMaidKitWindowState();

      expect(maximized!.maximized, isTrue);
      // The screen-sized maximized frame must not replace the frame the user
      // chose, otherwise un-maximizing after a relaunch loses the size.
      expect(maximized.bounds, const Rect.fromLTWH(100, 100, 900, 700));
    });

    test('records the un-maximized frame again', () async {
      windowMaximized = true;
      await emitWindowEvent('maximize');
      await settleDebounce();

      windowMaximized = false;
      windowBounds = const Rect.fromLTWH(40, 60, 1100, 750);
      await emitWindowEvent('unmaximize');
      await settleDebounce();

      final restored = await loadMaidKitWindowState();

      expect(restored!.maximized, isFalse);
      expect(restored.bounds, const Rect.fromLTWH(40, 60, 1100, 750));
    });

    test('ignores the iconic frame of a minimized window', () async {
      windowMinimized = true;
      windowBounds = const Rect.fromLTWH(-32000, -32000, 160, 31);

      await emitWindowEvent('minimize');
      await settleDebounce();

      final restored = await loadMaidKitWindowState();

      expect(restored!.bounds, const Rect.fromLTWH(100, 100, 900, 700));
    });

    test('persists the frame again after the window is restored', () async {
      windowMinimized = true;
      await emitWindowEvent('minimize');
      await settleDebounce();

      windowMinimized = false;
      windowBounds = const Rect.fromLTWH(300, 200, 1000, 640);
      await emitWindowEvent('restore');
      await settleDebounce();

      final restored = await loadMaidKitWindowState();

      expect(restored!.bounds, const Rect.fromLTWH(300, 200, 1000, 640));
    });

    test('ignores the frame of a full-screen window', () async {
      windowFullScreen = true;
      windowBounds = const Rect.fromLTWH(0, 0, 1512, 982);

      await emitWindowEvent('enter-full-screen');
      await emitWindowEvent('resized');
      await settleDebounce();

      final restored = await loadMaidKitWindowState();

      expect(restored!.bounds, const Rect.fromLTWH(100, 100, 900, 700));
    });

    test('records the frame again after leaving full-screen', () async {
      windowFullScreen = true;
      await emitWindowEvent('enter-full-screen');
      await settleDebounce();

      windowFullScreen = false;
      windowBounds = const Rect.fromLTWH(60, 40, 1280, 800);
      await emitWindowEvent('leave-full-screen');
      await settleDebounce();

      final restored = await loadMaidKitWindowState();

      expect(restored!.bounds, const Rect.fromLTWH(60, 40, 1280, 800));
    });
  });

  group('saveMaidKitWindowStateFromWindow', () {
    test('stores the live frame of a normal window', () async {
      await saveMaidKitWindowStateFromWindow();

      final restored = await loadMaidKitWindowState();

      expect(restored!.bounds, const Rect.fromLTWH(100, 100, 900, 700));
      expect(restored.maximized, isFalse);
    });

    test('does not overwrite the chosen frame with a maximized one', () async {
      await saveMaidKitWindowState(
        const MaidKitWindowState(
          bounds: Rect.fromLTWH(100, 100, 900, 700),
          maximized: false,
        ),
      );
      windowMaximized = true;
      windowBounds = const Rect.fromLTWH(0, 33, 1512, 949);

      await saveMaidKitWindowStateFromWindow();

      final restored = await loadMaidKitWindowState();

      expect(restored!.maximized, isTrue);
      expect(restored.bounds, const Rect.fromLTWH(100, 100, 900, 700));
    });

    test('skips the iconic frame of a minimized window', () async {
      await saveMaidKitWindowState(
        const MaidKitWindowState(
          bounds: Rect.fromLTWH(100, 100, 900, 700),
          maximized: false,
        ),
      );
      windowMinimized = true;
      windowBounds = const Rect.fromLTWH(-32000, -32000, 160, 31);

      await saveMaidKitWindowStateFromWindow();

      final restored = await loadMaidKitWindowState();

      expect(restored!.bounds, const Rect.fromLTWH(100, 100, 900, 700));
    });

    test('skips the frame of a full-screen window', () async {
      await saveMaidKitWindowState(
        const MaidKitWindowState(
          bounds: Rect.fromLTWH(100, 100, 900, 700),
          maximized: false,
        ),
      );
      windowFullScreen = true;
      windowBounds = const Rect.fromLTWH(0, 0, 1512, 982);

      await saveMaidKitWindowStateFromWindow();

      final restored = await loadMaidKitWindowState();

      expect(restored!.bounds, const Rect.fromLTWH(100, 100, 900, 700));
      expect(restored.maximized, isFalse);
    });
  });
}
