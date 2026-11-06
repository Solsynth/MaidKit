import 'package:shared_preferences/shared_preferences.dart';

/// Whether terminals run inside tmux, and what closing one does.
///
/// Both switches are app-wide: tmux is how a terminal survives its transport,
/// so it belongs to the client rather than to a single server.
abstract interface class TmuxSettings {
  /// Open every terminal inside a tmux session.
  bool get tmuxEnabled;

  /// Closing a tmux terminal detaches from the session instead of killing it.
  bool get detachOnClose;

  Future<void> saveTmuxEnabled(bool value);
  Future<void> saveDetachOnClose(bool value);
}

class TmuxPreferences implements TmuxSettings {
  TmuxPreferences(this._preferences, this.tmuxEnabled, this.detachOnClose);

  static const _tmuxEnabledKey = 'tmux_enabled';
  static const _detachOnCloseKey = 'tmux_detach_on_close';
  static const defaultTmuxEnabled = true;
  static const defaultDetachOnClose = true;

  final SharedPreferencesAsync _preferences;

  @override
  final bool tmuxEnabled;
  @override
  final bool detachOnClose;

  static Future<TmuxPreferences> load({
    SharedPreferencesAsync? preferences,
  }) async {
    final store = preferences ?? SharedPreferencesAsync();
    return TmuxPreferences(
      store,
      await store.getBool(_tmuxEnabledKey) ?? defaultTmuxEnabled,
      await store.getBool(_detachOnCloseKey) ?? defaultDetachOnClose,
    );
  }

  @override
  Future<void> saveTmuxEnabled(bool value) =>
      _preferences.setBool(_tmuxEnabledKey, value);

  @override
  Future<void> saveDetachOnClose(bool value) =>
      _preferences.setBool(_detachOnCloseKey, value);
}

/// The provider default: both switches on, changes kept in memory.
class InMemoryTmuxSettings implements TmuxSettings {
  InMemoryTmuxSettings({
    this.tmuxEnabled = TmuxPreferences.defaultTmuxEnabled,
    this.detachOnClose = TmuxPreferences.defaultDetachOnClose,
  });

  @override
  bool tmuxEnabled;
  @override
  bool detachOnClose;

  @override
  Future<void> saveTmuxEnabled(bool value) async {
    tmuxEnabled = value;
  }

  @override
  Future<void> saveDetachOnClose(bool value) async {
    detachOnClose = value;
  }
}
