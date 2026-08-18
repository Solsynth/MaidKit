import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class AppThemeSettings {
  Color get seedColor;
  ThemeMode get themeMode;
  bool get compactDashboard;
  double get uiScale;

  Future<void> saveSeedColor(Color color);
  Future<void> saveThemeMode(ThemeMode mode);
  Future<void> saveCompactDashboard(bool compact);
  Future<void> saveUiScale(double scale);
}

class AppThemePreferences implements AppThemeSettings {
  AppThemePreferences(
    this._preferences,
    this.seedColor,
    this.themeMode,
    this.compactDashboard,
    this.uiScale,
  );

  static const _seedColorKey = 'app_theme_seed_color';
  static const _themeModeKey = 'app_theme_mode';
  static const _compactDashboardKey = 'app_dashboard_compact_view';
  static const _uiScaleKey = 'app_ui_scale';
  static const _defaultSeedColor = Color(0xFF0F766E);
  static const defaultUiScale = 1.0;
  static const minUiScale = 0.75;
  static const maxUiScale = 2.0;
  static const uiScaleDivisions = 10;

  final SharedPreferencesAsync _preferences;
  @override
  final Color seedColor;
  @override
  final ThemeMode themeMode;
  @override
  final bool compactDashboard;
  @override
  final double uiScale;

  static Future<AppThemePreferences> load({
    SharedPreferencesAsync? preferences,
  }) async {
    final store = preferences ?? SharedPreferencesAsync();
    return AppThemePreferences(
      store,
      Color(await store.getInt(_seedColorKey) ?? _defaultSeedColor.toARGB32()),
      _decodeThemeMode(await store.getString(_themeModeKey)),
      await store.getBool(_compactDashboardKey) ?? false,
      _normalizeUiScale(await store.getDouble(_uiScaleKey)),
    );
  }

  static ThemeMode _decodeThemeMode(String? value) =>
      ThemeMode.values.where((mode) => mode.name == value).firstOrNull ??
      ThemeMode.system;

  static double _normalizeUiScale(double? value) {
    if (value == null || !value.isFinite) return defaultUiScale;
    return value.clamp(minUiScale, maxUiScale).toDouble();
  }

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

  @override
  Future<void> saveUiScale(double scale) =>
      _preferences.setDouble(_uiScaleKey, _normalizeUiScale(scale));
}

class InMemoryAppThemeSettings implements AppThemeSettings {
  InMemoryAppThemeSettings({
    this.seedColor = const Color(0xFF0F766E),
    this.themeMode = ThemeMode.system,
    this.compactDashboard = false,
    this.uiScale = AppThemePreferences.defaultUiScale,
  });

  @override
  Color seedColor;
  @override
  ThemeMode themeMode;
  @override
  bool compactDashboard;
  @override
  double uiScale;

  @override
  Future<void> saveSeedColor(Color color) async => seedColor = color;

  @override
  Future<void> saveThemeMode(ThemeMode mode) async => themeMode = mode;

  @override
  Future<void> saveCompactDashboard(bool compact) async =>
      compactDashboard = compact;

  @override
  Future<void> saveUiScale(double scale) async {
    uiScale = scale
        .clamp(AppThemePreferences.minUiScale, AppThemePreferences.maxUiScale)
        .toDouble();
  }
}
