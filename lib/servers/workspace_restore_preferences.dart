import 'package:shared_preferences/shared_preferences.dart';

/// Settings for restoring the last workspace on startup.
abstract interface class WorkspaceRestoreSettings {
  bool get restoreWorkspaceOnStartup;

  Future<void> saveRestoreWorkspaceOnStartup(bool value);

  /// The save time of the saved workspace the user dismissed from the
  /// dashboard, or null while the offer is still open.
  DateTime? get dismissedSnapshotAt;

  Future<void> saveDismissedSnapshotAt(DateTime? value);
}

class WorkspaceRestorePreferences implements WorkspaceRestoreSettings {
  WorkspaceRestorePreferences(
    this._preferences,
    this.restoreWorkspaceOnStartup,
    this.dismissedSnapshotAt,
  );

  static const _restoreWorkspaceOnStartupKey = 'restore_workspace_on_startup';
  static const _dismissedSnapshotAtKey = 'dismissed_workspace_snapshot_at';

  final SharedPreferencesAsync _preferences;
  @override
  final bool restoreWorkspaceOnStartup;
  @override
  final DateTime? dismissedSnapshotAt;

  static Future<WorkspaceRestorePreferences> load({
    SharedPreferencesAsync? preferences,
  }) async {
    final store = preferences ?? SharedPreferencesAsync();
    final dismissedAt = await store.getInt(_dismissedSnapshotAtKey);
    return WorkspaceRestorePreferences(
      store,
      await store.getBool(_restoreWorkspaceOnStartupKey) ?? false,
      dismissedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(dismissedAt),
    );
  }

  @override
  Future<void> saveRestoreWorkspaceOnStartup(bool value) =>
      _preferences.setBool(_restoreWorkspaceOnStartupKey, value);

  @override
  Future<void> saveDismissedSnapshotAt(DateTime? value) async {
    if (value == null) {
      await _preferences.remove(_dismissedSnapshotAtKey);
      return;
    }
    await _preferences.setInt(
      _dismissedSnapshotAtKey,
      value.millisecondsSinceEpoch,
    );
  }
}

class InMemoryWorkspaceRestoreSettings implements WorkspaceRestoreSettings {
  InMemoryWorkspaceRestoreSettings([
    this.restoreWorkspaceOnStartup = false,
    this.dismissedSnapshotAt,
  ]);

  @override
  bool restoreWorkspaceOnStartup;

  @override
  DateTime? dismissedSnapshotAt;

  @override
  Future<void> saveRestoreWorkspaceOnStartup(bool value) async {
    restoreWorkspaceOnStartup = value;
  }

  @override
  Future<void> saveDismissedSnapshotAt(DateTime? value) async {
    dismissedSnapshotAt = value;
  }
}
