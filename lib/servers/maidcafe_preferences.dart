import 'package:shared_preferences/shared_preferences.dart';

import 'maidcafe_service.dart';

abstract interface class MaidCafeSettings {
  String get cloudUrl;

  Future<void> saveCloudUrl(String value);

  String? get workspaceId;

  Future<void> saveWorkspaceId(String? value);
}

class MaidCafePreferences implements MaidCafeSettings {
  MaidCafePreferences(this._preferences, this.cloudUrl, {this.workspaceId});

  static const cloudUrlKey = 'maidcafe_cloud_url';
  static const workspaceIdKey = 'maidcafe_cloud_workspace_id';

  final SharedPreferencesAsync _preferences;

  @override
  String cloudUrl;

  @override
  String? workspaceId;

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
      workspaceId: await store.getString(workspaceIdKey),
    );
  }

  @override
  Future<void> saveCloudUrl(String value) async {
    final normalized = normalizeMaidCafeCloudUrl(value);
    await _preferences.setString(cloudUrlKey, normalized);
    cloudUrl = normalized;
  }

  @override
  Future<void> saveWorkspaceId(String? value) async {
    if (value == null) {
      await _preferences.remove(workspaceIdKey);
    } else {
      await _preferences.setString(workspaceIdKey, value);
    }
    workspaceId = value;
  }
}

class InMemoryMaidCafeSettings implements MaidCafeSettings {
  InMemoryMaidCafeSettings({
    String cloudUrl = maidCafeDefaultCloudUrl,
    this.workspaceId,
  }) : cloudUrl = normalizeMaidCafeCloudUrl(cloudUrl);

  @override
  String cloudUrl;

  @override
  String? workspaceId;

  @override
  Future<void> saveCloudUrl(String value) async {
    cloudUrl = normalizeMaidCafeCloudUrl(value);
  }

  @override
  Future<void> saveWorkspaceId(String? value) async {
    workspaceId = value;
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
