import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:maid_kit/servers/window_state_preferences.dart';

void main() {
  setUp(() {
    // Route SharedPreferencesAsync to an in-memory store so window geometry
    // can be round-tripped without touching the host platform.
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

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
}
