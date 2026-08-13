import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class AppThemeSettings {
  Color get seedColor;

  Future<void> saveSeedColor(Color color);
}

class AppThemePreferences implements AppThemeSettings {
  AppThemePreferences(this._preferences, this.seedColor);

  static const _seedColorKey = 'app_theme_seed_color';
  static const _defaultSeedColor = Color(0xFF0F766E);

  final SharedPreferencesAsync _preferences;
  @override
  final Color seedColor;

  static Future<AppThemePreferences> load({
    SharedPreferencesAsync? preferences,
  }) async {
    final store = preferences ?? SharedPreferencesAsync();
    return AppThemePreferences(
      store,
      Color(await store.getInt(_seedColorKey) ?? _defaultSeedColor.toARGB32()),
    );
  }

  @override
  Future<void> saveSeedColor(Color color) async {
    await _preferences.setInt(_seedColorKey, color.toARGB32());
  }
}

class InMemoryAppThemeSettings implements AppThemeSettings {
  InMemoryAppThemeSettings({this.seedColor = const Color(0xFF0F766E)});

  @override
  Color seedColor;

  @override
  Future<void> saveSeedColor(Color color) async => seedColor = color;
}
