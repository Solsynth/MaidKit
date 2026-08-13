import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kMaidKitUpdateChecksEnabledKey = 'maidkit_update_checks_enabled';
const kMaidKitUpdateChannelKey = 'maidkit_update_channel';
const kMaidKitDefaultUpdateChannel = 'stable';
const kMaidKitDistributionProductId = String.fromEnvironment(
  'DISTRIBUTION_PRODUCT_ID',
  defaultValue: '5260a14a-97f3-431c-9c2a-b174a4de7d97',
);

final maidKitUpdateChecksEnabledProvider =
    AsyncNotifierProvider<MaidKitUpdateChecksEnabledNotifier, bool>(
      MaidKitUpdateChecksEnabledNotifier.new,
    );

class MaidKitUpdateChecksEnabledNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    return await SharedPreferencesAsync().getBool(
          kMaidKitUpdateChecksEnabledKey,
        ) ??
        true;
  }

  Future<void> setEnabled(bool value) async {
    await SharedPreferencesAsync().setBool(
      kMaidKitUpdateChecksEnabledKey,
      value,
    );
    state = AsyncData(value);
  }
}

final maidKitUpdateChannelProvider =
    AsyncNotifierProvider<MaidKitUpdateChannelNotifier, String>(
      MaidKitUpdateChannelNotifier.new,
    );

class MaidKitUpdateChannelNotifier extends AsyncNotifier<String> {
  @override
  Future<String> build() async {
    final channel = await SharedPreferencesAsync().getString(
      kMaidKitUpdateChannelKey,
    );
    return channel?.trim().isNotEmpty == true
        ? channel!.trim()
        : kMaidKitDefaultUpdateChannel;
  }

  Future<void> setChannel(String value) async {
    final channel = value.trim();
    if (channel.isEmpty) return;
    await SharedPreferencesAsync().setString(kMaidKitUpdateChannelKey, channel);
    state = AsyncData(channel);
  }
}
