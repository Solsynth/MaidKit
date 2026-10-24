import 'package:shared_preferences/shared_preferences.dart';

abstract interface class MetricsRefreshSettings {
  Duration get backgroundInterval;
  Duration get focusedInterval;

  /// Whether host metrics are collected at all. Off means no SSH metric
  /// command and no daemon statistics poll runs anywhere in the app.
  bool get serverMetricsEnabled;

  Future<void> saveBackgroundInterval(Duration value);
  Future<void> saveFocusedInterval(Duration value);
  Future<void> saveServerMetricsEnabled(bool value);
}

class MetricsRefreshPreferences implements MetricsRefreshSettings {
  MetricsRefreshPreferences(
    this._preferences,
    this.backgroundInterval,
    this.focusedInterval,
    this.serverMetricsEnabled,
  );

  static const _backgroundIntervalSecondsKey =
      'background_metrics_refresh_interval_seconds';
  static const _focusedIntervalSecondsKey =
      'focused_detail_refresh_interval_seconds';
  static const _serverMetricsEnabledKey = 'server_metrics_enabled';
  static const defaultBackgroundInterval = Duration(seconds: 30);
  static const defaultFocusedInterval = Duration(seconds: 3);
  static const defaultServerMetricsEnabled = true;

  final SharedPreferencesAsync _preferences;
  @override
  final Duration backgroundInterval;
  @override
  final Duration focusedInterval;
  @override
  final bool serverMetricsEnabled;

  static Future<MetricsRefreshPreferences> load({
    SharedPreferencesAsync? preferences,
  }) async {
    final store = preferences ?? SharedPreferencesAsync();
    final backgroundSeconds = await store.getInt(_backgroundIntervalSecondsKey);
    final focusedSeconds = await store.getInt(_focusedIntervalSecondsKey);
    return MetricsRefreshPreferences(
      store,
      Duration(
        seconds: backgroundSeconds ?? defaultBackgroundInterval.inSeconds,
      ),
      Duration(seconds: focusedSeconds ?? defaultFocusedInterval.inSeconds),
      await store.getBool(_serverMetricsEnabledKey) ??
          defaultServerMetricsEnabled,
    );
  }

  @override
  Future<void> saveBackgroundInterval(Duration value) =>
      _preferences.setInt(_backgroundIntervalSecondsKey, value.inSeconds);

  @override
  Future<void> saveFocusedInterval(Duration value) =>
      _preferences.setInt(_focusedIntervalSecondsKey, value.inSeconds);

  @override
  Future<void> saveServerMetricsEnabled(bool value) =>
      _preferences.setBool(_serverMetricsEnabledKey, value);
}

class InMemoryMetricsRefreshSettings implements MetricsRefreshSettings {
  InMemoryMetricsRefreshSettings({
    this.backgroundInterval =
        MetricsRefreshPreferences.defaultBackgroundInterval,
    this.focusedInterval = MetricsRefreshPreferences.defaultFocusedInterval,
    this.serverMetricsEnabled =
        MetricsRefreshPreferences.defaultServerMetricsEnabled,
  });

  @override
  Duration backgroundInterval;
  @override
  Duration focusedInterval;
  @override
  bool serverMetricsEnabled;

  @override
  Future<void> saveBackgroundInterval(Duration value) async {
    backgroundInterval = value;
  }

  @override
  Future<void> saveFocusedInterval(Duration value) async {
    focusedInterval = value;
  }

  @override
  Future<void> saveServerMetricsEnabled(bool value) async {
    serverMetricsEnabled = value;
  }
}
