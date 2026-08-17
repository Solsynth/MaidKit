import 'package:shared_preferences/shared_preferences.dart';

/// How file transfers handle a destination entry that already exists.
enum TransferConflictMode {
  /// Keep the current behavior: write to `name (1).ext` instead of touching
  /// the existing entry.
  rename,

  /// Replace the existing destination entry.
  overwrite,

  /// Prompt the user per conflict while the transfer runs.
  ask,
}

abstract interface class TransferConflictSettings {
  TransferConflictMode get conflictMode;

  Future<void> saveConflictMode(TransferConflictMode value);
}

class TransferConflictPreferences implements TransferConflictSettings {
  TransferConflictPreferences(this._preferences, this.conflictMode);

  static const _conflictModeKey = 'transfer_conflict_mode';

  final SharedPreferencesAsync _preferences;
  @override
  final TransferConflictMode conflictMode;

  static Future<TransferConflictPreferences> load({
    SharedPreferencesAsync? preferences,
  }) async {
    final store = preferences ?? SharedPreferencesAsync();
    final raw = await store.getString(_conflictModeKey);
    final mode = TransferConflictMode.values.firstWhere(
      (mode) => mode.name == raw,
      orElse: () => TransferConflictMode.rename,
    );
    return TransferConflictPreferences(store, mode);
  }

  @override
  Future<void> saveConflictMode(TransferConflictMode value) =>
      _preferences.setString(_conflictModeKey, value.name);
}

class InMemoryTransferConflictSettings implements TransferConflictSettings {
  InMemoryTransferConflictSettings([
    this.conflictMode = TransferConflictMode.rename,
  ]);

  @override
  TransferConflictMode conflictMode;

  @override
  Future<void> saveConflictMode(TransferConflictMode value) async {
    conflictMode = value;
  }
}
