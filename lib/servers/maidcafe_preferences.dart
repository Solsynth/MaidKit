import 'package:shared_preferences/shared_preferences.dart';

import 'maidcafe_service.dart';

abstract interface class MaidCafeSettings {
  String get cloudUrl;

  Future<void> saveCloudUrl(String value);
}

class MaidCafePreferences implements MaidCafeSettings {
  MaidCafePreferences(this._preferences, this.cloudUrl);

  static const cloudUrlKey = 'maidcafe_cloud_url';

  final SharedPreferencesAsync _preferences;

  @override
  String cloudUrl;

  static Future<MaidCafePreferences> load({
    SharedPreferencesAsync? preferences,
  }) async {
    final store = preferences ?? SharedPreferencesAsync();
    final storedCloudUrl = await store.getString(cloudUrlKey);
    return MaidCafePreferences(
      store,
      _loadOrDefault(
        storedCloudUrl,
        normalizeMaidCafeCloudUrl,
        maidCafeDefaultCloudUrl,
      ),
    );
  }

  @override
  Future<void> saveCloudUrl(String value) async {
    final normalized = normalizeMaidCafeCloudUrl(value);
    await _preferences.setString(cloudUrlKey, normalized);
    cloudUrl = normalized;
  }
}

class InMemoryMaidCafeSettings implements MaidCafeSettings {
  InMemoryMaidCafeSettings({String cloudUrl = maidCafeDefaultCloudUrl})
    : cloudUrl = normalizeMaidCafeCloudUrl(cloudUrl);

  @override
  String cloudUrl;

  @override
  Future<void> saveCloudUrl(String value) async {
    cloudUrl = normalizeMaidCafeCloudUrl(value);
  }
}

String _loadOrDefault(
  String? value,
  String Function(String) normalize,
  String fallback,
) {
  if (value == null) return fallback;
  try {
    return normalize(value);
  } on MaidCafeException {
    return fallback;
  }
}
