import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:solsynth_express/solsynth_express.dart';

import '../services/update_preferences.dart';

class MaidKitUpdateSettingsSection extends ConsumerStatefulWidget {
  const MaidKitUpdateSettingsSection({super.key});

  @override
  ConsumerState<MaidKitUpdateSettingsSection> createState() =>
      _MaidKitUpdateSettingsSectionState();
}

class _MaidKitUpdateSettingsSectionState
    extends ConsumerState<MaidKitUpdateSettingsSection> {
  late final Future<List<DistributionChannel>> _channelsFuture;
  Future<DistributionReleaseInfo?>? _latestReleaseFuture;
  String? _latestReleaseKey;

  @override
  void initState() {
    super.initState();
    _channelsFuture = UpdateService(
      apiBaseUrl: kMaidKitDistributionApiBaseUrl,
      productId: kMaidKitDistributionProductId,
    ).fetchChannels();
  }

  @override
  Widget build(BuildContext context) {
    final enabled =
        ref.watch(maidKitUpdateChecksEnabledProvider).asData?.value ?? true;
    final channel =
        ref.watch(maidKitUpdateChannelProvider).asData?.value ??
        kMaidKitDefaultUpdateChannel;
    final locale = context.locale.languageCode;
    final latestKey = '$enabled:$channel';
    if (_latestReleaseKey != latestKey) {
      _latestReleaseKey = latestKey;
      _latestReleaseFuture = enabled
          ? UpdateService(
              apiBaseUrl: kMaidKitDistributionApiBaseUrl,
              channel: channel,
              productId: kMaidKitDistributionProductId,
              enabled: true,
            ).fetchLatestRelease()
          : Future.value(null);
    }

    return Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('settingsUpdateChecks').tr(),
          subtitle: const Text('settingsUpdateChecksHint').tr(),
          value: enabled,
          onChanged: (value) => ref
              .read(maidKitUpdateChecksEnabledProvider.notifier)
              .setEnabled(value),
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<DistributionChannel>>(
          future: _channelsFuture,
          builder: (context, snapshot) {
            final remoteChannels = snapshot.data ?? const [];
            final channels = <String>{
              kMaidKitDefaultUpdateChannel,
              channel,
              ...remoteChannels.map((item) => item.name),
            }.toList();
            return DropdownButtonFormField<String>(
              initialValue: channel,
              decoration: InputDecoration(
                labelText: 'settingsUpdateChannel'.tr(),
                helperText: 'settingsUpdateChannelHint'.tr(),
                border: InputBorder.none,
              ),
              items: [
                for (final item in channels)
                  DropdownMenuItem(
                    value: item,
                    child: Text(_channelLabel(item, remoteChannels, locale)),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                ref
                    .read(maidKitUpdateChannelProvider.notifier)
                    .setChannel(value);
              },
            );
          },
        ),
        const SizedBox(height: 8),
        FutureBuilder<DistributionReleaseInfo?>(
          future: _latestReleaseFuture,
          builder: (context, snapshot) {
            if (!enabled) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('settingsUpdateLatestRelease').tr(),
                subtitle: const Text('settingsUpdateChecksDisabledHint').tr(),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                title: Text('settingsUpdateLatestRelease'),
              );
            }
            final release = snapshot.data;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('settingsUpdateLatestRelease'.tr()),
              subtitle: Text(
                release == null
                    ? 'checkForUpdatesHint'.tr()
                    : '${release.name} (${release.tagName})',
              ),
              trailing: release == null
                  ? null
                  : const Icon(Icons.chevron_right),
              onTap: release == null
                  ? null
                  : () => UpdateService(
                      apiBaseUrl: kMaidKitDistributionApiBaseUrl,
                      channel: channel,
                      productId: kMaidKitDistributionProductId,
                      enabled: true,
                    ).showUpdateSheet(context, release),
            );
          },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () async {
              await UpdateService(
                apiBaseUrl: kMaidKitDistributionApiBaseUrl,
                channel: channel,
                productId: kMaidKitDistributionProductId,
                enabled: true,
              ).checkForUpdates(context);
            },
            icon: const Icon(Icons.update),
            label: const Text('checkForUpdates').tr(),
          ),
        ),
      ],
    );
  }

  String _channelLabel(
    String channel,
    List<DistributionChannel> remoteChannels,
    String locale,
  ) {
    if (channel == kMaidKitDefaultUpdateChannel) {
      return 'settingsUpdateChannelStable'.tr();
    }
    for (final item in remoteChannels) {
      if (item.name == channel) return item.label(locale);
    }
    return channel;
  }
}
