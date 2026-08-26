import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maid_kit/servers/app_theme_preferences.dart';
import 'package:maid_kit/servers/server_providers.dart';

void main() {
  test('saves the app accent seed color', () async {
    final settings = InMemoryAppThemeSettings();
    final container = ProviderContainer(
      overrides: [appThemeSettingsProvider.overrideWithValue(settings)],
    );
    addTearDown(container.dispose);
    const color = Color(0xFF2563EB);

    await container.read(appSeedColorProvider.notifier).setSeedColor(color);

    expect(settings.seedColor, color);
    expect(container.read(appSeedColorProvider), color);
  });

  test('restores and saves the theme mode', () async {
    final settings = InMemoryAppThemeSettings(themeMode: ThemeMode.dark);
    final container = ProviderContainer(
      overrides: [appThemeSettingsProvider.overrideWithValue(settings)],
    );
    addTearDown(container.dispose);

    expect(container.read(themeModeProvider), ThemeMode.dark);

    await container
        .read(themeModeProvider.notifier)
        .setThemeMode(ThemeMode.light);

    expect(settings.themeMode, ThemeMode.light);
    expect(container.read(themeModeProvider), ThemeMode.light);
  });

  testWidgets('preserves Flutter brightness notifications for system themes', (
    tester,
  ) async {
    final dispatcher = tester.platformDispatcher;
    final frameworkCallback = dispatcher.onPlatformBrightnessChanged;
    expect(frameworkCallback, isNotNull);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(platformBrightnessProvider);

    // MaterialApp's system ThemeMode depends on the framework callback to
    // refresh the root MediaQuery when the OS appearance changes.
    expect(dispatcher.onPlatformBrightnessChanged, same(frameworkCallback));
  });

  test('restores and saves the compact dashboard preference', () async {
    final settings = InMemoryAppThemeSettings(compactDashboard: true);
    final container = ProviderContainer(
      overrides: [appThemeSettingsProvider.overrideWithValue(settings)],
    );
    addTearDown(container.dispose);

    expect(container.read(dashboardCompactViewProvider), isTrue);

    await container
        .read(dashboardCompactViewProvider.notifier)
        .setCompact(false);

    expect(settings.compactDashboard, isFalse);
    expect(container.read(dashboardCompactViewProvider), isFalse);
  });

  test('restores and saves the application UI font family', () async {
    final settings = InMemoryAppThemeSettings(uiFontFamily: 'Arial');
    final container = ProviderContainer(
      overrides: [appThemeSettingsProvider.overrideWithValue(settings)],
    );
    addTearDown(container.dispose);

    expect(container.read(appUiFontFamilyProvider), 'Arial');

    await container
        .read(appUiFontFamilyProvider.notifier)
        .setFontFamily('Georgia');

    expect(settings.uiFontFamily, 'Georgia');
    expect(container.read(appUiFontFamilyProvider), 'Georgia');
  });

  test('falls back to the default UI font when blank', () async {
    final settings = InMemoryAppThemeSettings(uiFontFamily: 'Arial');
    final container = ProviderContainer(
      overrides: [appThemeSettingsProvider.overrideWithValue(settings)],
    );
    addTearDown(container.dispose);

    await container.read(appUiFontFamilyProvider.notifier).setFontFamily('   ');

    expect(settings.uiFontFamily, AppThemePreferences.defaultUiFontFamily);
    expect(
      container.read(appUiFontFamilyProvider),
      AppThemePreferences.defaultUiFontFamily,
    );
  });
}
