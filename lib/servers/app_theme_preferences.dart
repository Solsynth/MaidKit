import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class AppThemeSettings {
  Color get seedColor;
  ThemeMode get themeMode;
  bool get compactDashboard;

  Future<void> saveSeedColor(Color color);
  Future<void> saveThemeMode(ThemeMode mode);
  Future<void> saveCompactDashboard(bool compact);
}

class AppThemePreferences implements AppThemeSettings {
  AppThemePreferences(
    this._preferences,
    this.seedColor,
    this.themeMode,
    this.compactDashboard,
  );

  static const _seedColorKey = 'app_theme_seed_color';
  static const _themeModeKey = 'app_theme_mode';
  static const _compactDashboardKey = 'app_dashboard_compact_view';
  static const _defaultSeedColor = Color(0xFF0F766E);

  final SharedPreferencesAsync _preferences;
  @override
  final Color seedColor;
  @override
  final ThemeMode themeMode;
  @override
  final bool compactDashboard;

  static Future<AppThemePreferences> load({
    SharedPreferencesAsync? preferences,
  }) async {
    final store = preferences ?? SharedPreferencesAsync();
    return AppThemePreferences(
      store,
      Color(await store.getInt(_seedColorKey) ?? _defaultSeedColor.toARGB32()),
      _decodeThemeMode(await store.getString(_themeModeKey)),
      await store.getBool(_compactDashboardKey) ?? false,
    );
  }

  static ThemeMode _decodeThemeMode(String? value) =>
      ThemeMode.values.where((mode) => mode.name == value).firstOrNull ??
      ThemeMode.system;

  @override
  Future<void> saveSeedColor(Color color) async {
    await _preferences.setInt(_seedColorKey, color.toARGB32());
  }

  @override
  Future<void> saveThemeMode(ThemeMode mode) =>
      _preferences.setString(_themeModeKey, mode.name);

  @override
  Future<void> saveCompactDashboard(bool compact) =>
      _preferences.setBool(_compactDashboardKey, compact);
}

class InMemoryAppThemeSettings implements AppThemeSettings {
  InMemoryAppThemeSettings({
    this.seedColor = const Color(0xFF0F766E),
    this.themeMode = ThemeMode.system,
    this.compactDashboard = false,
  });

  @override
  Color seedColor;
  @override
  ThemeMode themeMode;
  @override
  bool compactDashboard;

  @override
  Future<void> saveSeedColor(Color color) async => seedColor = color;

  @override
  Future<void> saveThemeMode(ThemeMode mode) async => themeMode = mode;

  @override
  Future<void> saveCompactDashboard(bool compact) async =>
      compactDashboard = compact;
}
