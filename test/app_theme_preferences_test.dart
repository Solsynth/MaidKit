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
  test('restores and saves the application UI scale', () async {
    final settings = InMemoryAppThemeSettings(uiScale: 1.25);
    final container = ProviderContainer(
      overrides: [appThemeSettingsProvider.overrideWithValue(settings)],
    );
    addTearDown(container.dispose);

    expect(container.read(appUiScaleProvider), 1.25);

    await container
        .read(appUiScaleProvider.notifier)
        .setScale(AppThemePreferences.maxUiScale + 1);

    expect(settings.uiScale, AppThemePreferences.maxUiScale);
    expect(container.read(appUiScaleProvider), AppThemePreferences.maxUiScale);
  });
}
