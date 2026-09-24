import 'package:shared_preferences/shared_preferences.dart';

/// Settings for restoring the last workspace on startup.
abstract interface class WorkspaceRestoreSettings {
  bool get restoreWorkspaceOnStartup;

  Future<void> saveRestoreWorkspaceOnStartup(bool value);
}

class WorkspaceRestorePreferences implements WorkspaceRestoreSettings {
  WorkspaceRestorePreferences(
    this._preferences,
    this.restoreWorkspaceOnStartup,
  );

  static const _restoreWorkspaceOnStartupKey = 'restore_workspace_on_startup';

  final SharedPreferencesAsync _preferences;
  @override
  final bool restoreWorkspaceOnStartup;

  static Future<WorkspaceRestorePreferences> load({
    SharedPreferencesAsync? preferences,
  }) async {
    final store = preferences ?? SharedPreferencesAsync();
    return WorkspaceRestorePreferences(
      store,
      await store.getBool(_restoreWorkspaceOnStartupKey) ?? false,
    );
  }

  @override
  Future<void> saveRestoreWorkspaceOnStartup(bool value) =>
      _preferences.setBool(_restoreWorkspaceOnStartupKey, value);
}

class InMemoryWorkspaceRestoreSettings implements WorkspaceRestoreSettings {
  InMemoryWorkspaceRestoreSettings([this.restoreWorkspaceOnStartup = false]);

  @override
  bool restoreWorkspaceOnStartup;

  @override
  Future<void> saveRestoreWorkspaceOnStartup(bool value) async {
    restoreWorkspaceOnStartup = value;
  }
}
