import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'server_models.dart';

abstract interface class PrivacySettings {
  bool get hideServerAddresses;

  Future<void> saveHideServerAddresses(bool value);
}

class PrivacyPreferences implements PrivacySettings {
  PrivacyPreferences(this._preferences, this.hideServerAddresses);

  static const _hideServerAddressesKey = 'hide_server_addresses';

  final SharedPreferencesAsync _preferences;
  @override
  final bool hideServerAddresses;

  static Future<PrivacyPreferences> load({
    SharedPreferencesAsync? preferences,
  }) async {
    final store = preferences ?? SharedPreferencesAsync();
    return PrivacyPreferences(
      store,
      await store.getBool(_hideServerAddressesKey) ?? false,
    );
  }

  @override
  Future<void> saveHideServerAddresses(bool value) =>
      _preferences.setBool(_hideServerAddressesKey, value);
}

class InMemoryPrivacySettings implements PrivacySettings {
  InMemoryPrivacySettings([this.hideServerAddresses = false]);

  @override
  bool hideServerAddresses;

  @override
  Future<void> saveHideServerAddresses(bool value) async {
    hideServerAddresses = value;
  }
}

/// The address line shown next to a server's name. When address hiding is on
/// (screen recording / streaming), only the username is displayed so no IP
/// ever appears on screen. Serial servers show the local device path instead.
String serverAddressLabel(Server server, {required bool hideAddresses}) {
  if (server.connectionType == ServerConnectionType.serial.name) {
    return decodeSerialConfig(server.serialConfig)?.device ?? server.host;
  }
  if (server.connectionType == ServerConnectionType.maidcafe.name) {
    // The daemon endpoint is this server's address; the SSH host is unused by
    // that transport. Address hiding applies to it like any other address.
    return hideAddresses
        ? server.username
        : (server.maidCafeTerminalUrl ?? server.host);
  }
  return hideAddresses
      ? server.username
      : '${server.username}@${server.host}:${server.port}';
}
