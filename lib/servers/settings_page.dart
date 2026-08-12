import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:styled_widget/styled_widget.dart';
import 'package:system_fonts/system_fonts.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/agent/agent_personality.dart';
import 'package:maid_kit/agent/local_mcp_server.dart';
import 'package:maid_kit/agent/mcp_review_mode.dart';
import 'package:maid_kit/agent/agent_run_policy.dart';
import 'package:maid_kit/agent/billing_service.dart';
import 'package:maid_kit/agent/personality_service.dart';
import 'package:maid_kit/routing/app_router.gr.dart';
import 'package:maid_kit/shared/presentation/app_scaffold.dart';

import 'database_backup_service.dart';
import 'cloud_sync_service.dart';
import 'connection_export_service.dart';
import 'connection_import_service.dart';
import 'connection_import_sheet.dart';
import 'local_connection_manager.dart';
import 'server_providers.dart';
import 'tailscale_settings_section.dart';
import 'terminal_adapter_preferences.dart';
import 'terminal_color_scheme.dart';
import 'vault_service.dart';
import 'vault_file_storage.dart';

@RoutePage()
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final appSeedColor = ref.watch(appSeedColorProvider);
    final biometricEnabled = ref.watch(biometricUnlockEnabledProvider);
    final adapterOptions = ref.watch(terminalSessionAdapterOptionsProvider);
    final selectedAdapter = ref.watch(selectedTerminalSessionAdapterProvider);
    final cursorAnimationEnabled = ref.watch(cursorAnimationEnabledProvider);
    final brandingEnvironmentEnabled = ref.watch(
      terminalBrandingEnvironmentEnabledProvider,
    );
    final terminalLightTheme = ref.watch(terminalLightThemeProvider);
    final terminalDarkTheme = ref.watch(terminalDarkThemeProvider);
    final connectOnStartup = ref.watch(connectOnStartupProvider);
    final hideServerAddresses = ref.watch(hideServerAddressesProvider);
    final localMachineEnabled = ref.watch(localMachineEnabledProvider);
    final refreshInterval = ref.watch(serverMetricsRefreshIntervalProvider);
    final focusedRefreshInterval = ref.watch(
      focusedServerRefreshIntervalProvider,
    );
    final backgroundImage = ref.watch(maidKitBackgroundImageProvider);
    final backgroundImageEnabled = ref.watch(
      maidKitBackgroundImageEnabledProvider,
    );
    final transparentTerminalBackground = ref.watch(
      transparentTerminalBackgroundEnabledProvider,
    );
    final windowOpacity = ref.watch(maidKitWindowOpacityProvider);
    final activeVaultFile = ref.watch(activeVaultFileProvider);
    final vaultFiles = ref.watch(vaultFilesProvider);
    final vaultLabels = ref.watch(vaultLabelsProvider);
    final cloudUser = ref.watch(cloudUserProvider);
    final runPolicyAsync = ref.watch(agentRunPolicyProvider);
    final agentPersonalityAsync = ref.watch(agentPersonalityProvider);
    final agentPersonalityAgentAsync = ref.watch(agentPersonalityAgentProvider);
    final personalityAgentsAsync = ref.watch(personalityAgentsProvider);
    final billingPolicyAsync = ref.watch(personalityBillingPolicyProvider);

    final selectedAdapterOption = adapterOptions.firstWhere(
      (option) => option.id == selectedAdapter,
      orElse: () => adapterOptions.first,
    );

    return MaidKitAppScaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            children: [
              Text(
                'settingsTitle',
                style: Theme.of(context).textTheme.headlineSmall,
              ).tr(),
              const SizedBox(height: 8),
              Text(
                'settingsDescription',
                style: Theme.of(context).textTheme.bodyLarge,
              ).tr(),
              const SizedBox(height: 32),
              _SettingsSection(
                titleKey: 'settingsAppearance',
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('settingsTheme').tr(),
                          const SizedBox(height: 4),
                          Text(
                            'settingsThemeDescription',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ).tr(),
                          const SizedBox(height: 12),
                          SegmentedButton<ThemeMode>(
                            segments: [
                              ButtonSegment(
                                value: ThemeMode.system,
                                label: Text('settingsThemeSystem'.tr()),
                                icon: const Icon(Symbols.brightness_auto),
                              ),
                              ButtonSegment(
                                value: ThemeMode.light,
                                label: Text('settingsThemeLight'.tr()),
                                icon: const Icon(Symbols.light_mode),
                              ),
                              ButtonSegment(
                                value: ThemeMode.dark,
                                label: Text('settingsThemeDark'.tr()),
                                icon: const Icon(Symbols.dark_mode),
                              ),
                            ],
                            selected: {themeMode},
                            onSelectionChanged: (selection) {
                              ref
                                  .read(themeModeProvider.notifier)
                                  .setThemeMode(selection.first);
                            },
                          ),
                          const SizedBox(height: 16),
                          _SeedColorTile(
                            seedColor: appSeedColor,
                            onEdit: () => _editSeedColor(context, ref),
                          ),
                          const SizedBox(height: 16),
                          const _LanguageSwitcher(),
                        ],
                      ),
                    ),
                    if (!kIsWeb) ...[
                      const SizedBox(height: 24),
                      SwitchListTile(
                        contentPadding: _sectionTilePadding,
                        shape: RoundedRectangleBorder(
                          borderRadius: _sectionTileBorderRadius(
                            _SettingsTilePosition.only,
                          ),
                        ),
                        title: const Text('settingsBackgroundImage').tr(),
                        subtitle: Text(
                          backgroundImage.asData?.value == null
                              ? 'settingsBackgroundImageNone'.tr()
                              : 'settingsBackgroundImageHint'.tr(),
                        ),
                        value: backgroundImageEnabled.asData?.value ?? true,
                        onChanged: backgroundImage.asData?.value == null
                            ? null
                            : (enabled) => setMaidKitBackgroundImageEnabled(
                                ref,
                                enabled,
                              ),
                      ),
                      Padding(
                        padding: _sectionTilePadding,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _selectBackgroundImage(context, ref),
                              icon: const Icon(Symbols.image),
                              label: const Text(
                                'settingsBackgroundImageChoose',
                              ).tr(),
                            ),
                            if (backgroundImage.asData?.value != null)
                              TextButton.icon(
                                onPressed: () =>
                                    _clearBackgroundImage(context, ref),
                                icon: const Icon(Symbols.delete_outline),
                                label: const Text(
                                  'settingsBackgroundImageClear',
                                ).tr(),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: _sectionTilePadding,
                        shape: RoundedRectangleBorder(
                          borderRadius: _sectionTileBorderRadius(
                            _SettingsTilePosition.only,
                          ),
                        ),
                        title: const Text('settingsTerminalTransparent').tr(),
                        subtitle: const Text(
                          'settingsTerminalTransparentHint',
                        ).tr(),
                        value:
                            transparentTerminalBackground.asData?.value ??
                            false,
                        onChanged:
                            backgroundImage.asData?.value == null ||
                                !(backgroundImageEnabled.asData?.value ?? true)
                            ? null
                            : (enabled) =>
                                  setTransparentTerminalBackgroundEnabled(
                                    ref,
                                    enabled,
                                  ),
                      ),
                    ],
                    if (DesktopWindowFrame.isPlatformDesktop) ...[
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'settingsWindowOpacity',
                              style: Theme.of(context).textTheme.titleSmall,
                            ).tr(),
                            const SizedBox(height: 4),
                            Text(
                              'settingsWindowOpacityHint',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ).tr(),
                            Slider(
                              value: windowOpacity.asData?.value ?? 1.0,
                              min: 0.4,
                              max: 1.0,
                              divisions: 12,
                              label:
                                  '${((windowOpacity.asData?.value ?? 1.0) * 100).round()}%',
                              onChanged: (value) =>
                                  setMaidKitWindowOpacity(ref, value),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _SettingsSection(
                titleKey: 'settingsTerminal',
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: selectedAdapterOption.id,
                            decoration: InputDecoration(
                              labelText: 'settingsTerminalRenderer'.tr(),
                            ),
                            items: [
                              for (final option in adapterOptions)
                                DropdownMenuItem(
                                  value: option.id,
                                  child: Text(option.label),
                                ),
                            ],
                            onChanged: adapterOptions.length < 2
                                ? null
                                : (adapterId) async {
                                    if (adapterId != null) {
                                      await ref
                                          .read(
                                            selectedTerminalSessionAdapterProvider
                                                .notifier,
                                          )
                                          .select(adapterId);
                                    }
                                  },
                          ),
                          const SizedBox(height: 8),
                          Text(
                            selectedAdapterOption.description,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'settingsTerminalRendererHint',
                            style: Theme.of(context).textTheme.bodySmall,
                          ).tr(),
                          const SizedBox(height: 16),
                          const _TerminalFontDropdown(),
                          const SizedBox(height: 16),
                          _TerminalThemeTile(
                            mode: Brightness.light,
                            theme: terminalLightTheme,
                            onEdit: () => _editTerminalTheme(
                              context,
                              ref,
                              brightness: Brightness.light,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _TerminalThemeTile(
                            mode: Brightness.dark,
                            theme: terminalDarkTheme,
                            onEdit: () => _editTerminalTheme(
                              context,
                              ref,
                              brightness: Brightness.dark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: _sectionTilePadding,
                      title: const Text('settingsAnimateCursor').tr(),
                      subtitle: const Text('settingsAnimateCursorHint').tr(),
                      value: cursorAnimationEnabled,
                      onChanged: selectedAdapter == 'ghostty'
                          ? (enabled) async {
                              await ref
                                  .read(cursorAnimationEnabledProvider.notifier)
                                  .setEnabled(enabled);
                            }
                          : null,
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: _sectionTilePadding,
                      title: const Text(
                        'settingsTerminalBrandingEnvironment',
                      ).tr(),
                      subtitle: const Text(
                        'settingsTerminalBrandingEnvironmentHint',
                      ).tr(),
                      value: brandingEnvironmentEnabled,
                      onChanged: (enabled) => ref
                          .read(
                            terminalBrandingEnvironmentEnabledProvider.notifier,
                          )
                          .setEnabled(enabled),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _SettingsSection(
                titleKey: 'settingsConnections',
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: _sectionTilePadding,
                      title: const Text('settingsConnectOnStartup').tr(),
                      subtitle: const Text('settingsConnectOnStartupHint').tr(),
                      value: connectOnStartup,
                      onChanged: (value) => ref
                          .read(connectOnStartupProvider.notifier)
                          .setEnabled(value),
                    ),
                    SwitchListTile(
                      contentPadding: _sectionTilePadding,
                      title: const Text('settingsHideServerAddresses').tr(),
                      subtitle: const Text(
                        'settingsHideServerAddressesHint',
                      ).tr(),
                      value: hideServerAddresses,
                      onChanged: (value) => ref
                          .read(hideServerAddressesProvider.notifier)
                          .setEnabled(value),
                    ),
                    if (localMachineSupported) ...[
                      SwitchListTile(
                        contentPadding: _sectionTilePadding,
                        title: const Text('settingsLocalMachine').tr(),
                        subtitle: const Text('settingsLocalMachineHint').tr(),
                        value: localMachineEnabled,
                        onChanged: (value) => ref
                            .read(localMachineEnabledProvider.notifier)
                            .setEnabled(value),
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        children: [
                          const SizedBox(height: 12),
                          _IntervalDropdown(
                            labelKey: 'settingsBackgroundRefreshInterval',
                            helperKey: 'settingsBackgroundRefreshIntervalHint',
                            value: refreshInterval,
                            options: _refreshIntervals,
                            fallback: _refreshIntervals[1],
                            onChanged: (interval) {
                              ref
                                  .read(
                                    serverMetricsRefreshIntervalProvider
                                        .notifier,
                                  )
                                  .setInterval(interval);
                            },
                          ),
                          const SizedBox(height: 16),
                          _IntervalDropdown(
                            labelKey: 'settingsFocusedRefreshInterval',
                            helperKey: 'settingsFocusedRefreshIntervalHint',
                            value: focusedRefreshInterval,
                            options: _focusedRefreshIntervals,
                            fallback: _focusedRefreshIntervals.first,
                            onChanged: (interval) {
                              ref
                                  .read(
                                    focusedServerRefreshIntervalProvider
                                        .notifier,
                                  )
                                  .setInterval(interval);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _SettingsSection(
                titleKey: 'settingsTailscale',
                padding: EdgeInsets.zero,
                child: const TailscaleSettingsSection(),
              ),
              const SizedBox(height: 24),
              _SettingsSection(
                titleKey: 'settingsAgent',
                padding: EdgeInsets.zero,
                child: runPolicyAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(),
                  ),
                  error: (error, _) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(error.toString()),
                  ),
                  data: (policy) => Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('settingsAgentRunPolicy').tr(),
                        const SizedBox(height: 4),
                        Text(
                          'settingsAgentRunPolicyHint',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ).tr(),
                        const SizedBox(height: 12),
                        SegmentedButton<AgentRunPolicy>(
                          showSelectedIcon: false,
                          segments: [
                            for (final mode in AgentRunPolicy.values)
                              ButtonSegment(
                                value: mode,
                                label: Text(mode.labelKey.tr()),
                                tooltip: mode.descriptionKey.tr(),
                              ),
                          ],
                          selected: {policy},
                          onSelectionChanged: (selection) {
                            ref
                                .read(agentRunPolicyProvider.notifier)
                                .setPolicy(selection.first);
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          policy.descriptionKey.tr(),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        agentPersonalityAsync.when(
                          loading: () => const LinearProgressIndicator(),
                          error: (error, _) => Text(error.toString()),
                          data: (personality) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('settingsAgentPersonality').tr(),
                            subtitle: Text(
                              personality.isEmpty
                                  ? 'settingsAgentPersonalityHint'.tr()
                                  : personality,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Symbols.chevron_right),
                            onTap: () => _editAgentPersonality(
                              context,
                              ref,
                              personality,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _SettingsSection(
                titleKey: 'settingsLocalMcpServer',
                padding: EdgeInsets.zero,
                child: const _LocalMcpServerSection(),
              ),
              const SizedBox(height: 24),
              _SettingsSection(
                titleKey: 'settingsSecurity',
                padding: EdgeInsets.zero,
                child: biometricEnabled.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(),
                  ),
                  error: (error, _) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'settingsBiometricError'.tr(args: [error.toString()]),
                    ),
                  ),
                  data: (enabled) => Column(
                    children: [
                      SwitchListTile(
                        contentPadding: _sectionTilePadding,
                        shape: RoundedRectangleBorder(
                          borderRadius: _sectionTileBorderRadius(
                            _SettingsTilePosition.first,
                          ),
                        ),
                        title: const Text('settingsBiometricUnlock').tr(),
                        subtitle: const Text(
                          'settingsBiometricUnlockHint',
                        ).tr(),
                        value: enabled,
                        onChanged: (value) =>
                            _setBiometricUnlock(context, ref, value),
                      ),
                      ListTile(
                        contentPadding: _sectionTilePadding,
                        shape: RoundedRectangleBorder(
                          borderRadius: _sectionTileBorderRadius(
                            _SettingsTilePosition.last,
                          ),
                        ),
                        leading: const Icon(Symbols.password),
                        title: const Text('settingsVaultChangePassword').tr(),
                        subtitle: const Text(
                          'settingsVaultChangePasswordHint',
                        ).tr(),
                        trailing: const Icon(Symbols.chevron_right),
                        onTap: () => _changeVaultPassword(context, ref),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _SettingsSection(
                titleKey: 'settingsAbout',
                padding: EdgeInsets.zero,
                child: ListTile(
                  contentPadding: _sectionTilePadding,
                  shape: RoundedRectangleBorder(
                    borderRadius: _sectionTileBorderRadius(
                      _SettingsTilePosition.only,
                    ),
                  ),
                  leading: const Icon(Symbols.info),
                  title: Text('aboutTitle'.tr()),
                  subtitle: Text('settingsAboutHint'.tr()),
                  trailing: const Icon(Symbols.chevron_right),
                  onTap: () => context.router.push(const AboutRoute()),
                ),
              ),
              const SizedBox(height: 24),
              _SettingsSection(
                titleKey: 'settingsAccount',
                padding: EdgeInsets.zero,
                child: cloudUser.when(
                  loading: () => ListTile(
                    contentPadding: _sectionTilePadding,
                    shape: RoundedRectangleBorder(
                      borderRadius: _sectionTileBorderRadius(
                        _SettingsTilePosition.only,
                      ),
                    ),
                    leading: const CircleAvatar(child: Icon(Symbols.person)),
                    title: const Text('…'),
                  ),
                  error: (_, _) => _cloudLoginTile(context, ref),
                  data: (user) => user == null
                      ? _cloudLoginTile(context, ref)
                      : Column(
                          children: [
                            ListTile(
                              contentPadding: _sectionTilePadding,
                              shape: RoundedRectangleBorder(
                                borderRadius: _sectionTileBorderRadius(
                                  _SettingsTilePosition.only,
                                ),
                              ),
                              leading: _CloudAvatar(user: user),
                              title: Text(user.name),
                              subtitle: user.handle.isEmpty
                                  ? null
                                  : Text(user.handle),
                              trailing: IconButton(
                                icon: const Icon(Symbols.logout),
                                tooltip: 'settingsCloudSignOut'.tr(),
                                onPressed: () =>
                                    _signOutFromCloud(context, ref),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              if (cloudUser.asData?.value != null) ...[
                const SizedBox(height: 24),
                _SettingsSection(
                  titleKey: 'settingsSolarNetworkAi',
                  padding: EdgeInsets.zero,
                  child: billingPolicyAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(16),
                      child: LinearProgressIndicator(),
                    ),
                    error: (error, _) => Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'settingsBillingError'.tr(args: [error.toString()]),
                      ),
                    ),
                    data: (policy) => policy == null
                        ? const SizedBox.shrink()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (policy.blacklisted)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    12,
                                    16,
                                    0,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.errorContainer,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Symbols.warning_amber,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'settingsBillingBlacklisted'.tr(),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  16,
                                  16,
                                  0,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'settingsAgentPersonalityAgent',
                                    ).tr(),
                                    const SizedBox(height: 4),
                                    Text(
                                      'settingsAgentPersonalityAgentHint',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ).tr(),
                                    const SizedBox(height: 12),
                                    agentPersonalityAgentAsync.when(
                                      loading: () =>
                                          const LinearProgressIndicator(),
                                      error: (error, _) =>
                                          Text(error.toString()),
                                      data: (agentId) =>
                                          _PersonalityAgentDropdown(
                                            agentId: agentId,
                                            agents:
                                                personalityAgentsAsync
                                                    .asData
                                                    ?.value ??
                                                const [],
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('settingsBillingUsage').tr(),
                                    const SizedBox(height: 4),
                                    Text(
                                      'settingsBillingUsageHint',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ).tr(),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              ListTile(
                                contentPadding: _sectionTilePadding,
                                shape: RoundedRectangleBorder(
                                  borderRadius: _sectionTileBorderRadius(
                                    _SettingsTilePosition.first,
                                  ),
                                ),
                                title: const Text(
                                  'settingsBillingHourlyGolds',
                                ).tr(),
                                trailing: _UsageTrailing(
                                  usage: policy.hourlyGolds,
                                ),
                              ),
                              ListTile(
                                contentPadding: _sectionTilePadding,
                                shape: RoundedRectangleBorder(
                                  borderRadius: _sectionTileBorderRadius(
                                    _SettingsTilePosition.middle,
                                  ),
                                ),
                                title: const Text(
                                  'settingsBillingHourlyBits',
                                ).tr(),
                                trailing: _UsageTrailing(
                                  usage: policy.hourlyPoints,
                                ),
                              ),
                              ListTile(
                                contentPadding: _sectionTilePadding,
                                shape: RoundedRectangleBorder(
                                  borderRadius: _sectionTileBorderRadius(
                                    _SettingsTilePosition.middle,
                                  ),
                                ),
                                title: const Text(
                                  'settingsBillingDailyGolds',
                                ).tr(),
                                trailing: _UsageTrailing(
                                  usage: policy.dailyGolds,
                                ),
                              ),
                              ListTile(
                                contentPadding: _sectionTilePadding,
                                shape: RoundedRectangleBorder(
                                  borderRadius: _sectionTileBorderRadius(
                                    _SettingsTilePosition.last,
                                  ),
                                ),
                                title: const Text(
                                  'settingsBillingDailyBits',
                                ).tr(),
                                trailing: _UsageTrailing(
                                  usage: policy.dailyPoints,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'settingsBillingSettleHint'.tr(),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodyMedium,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    FilledButton.tonalIcon(
                                      onPressed: () =>
                                          _settleBilling(context, ref),
                                      icon: const Icon(Symbols.payments),
                                      label: const Text(
                                        'settingsBillingSettleNow',
                                      ).tr(),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              _SettingsSection(
                titleKey: 'settingsVaults',
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ...[
                      for (final (index, path) in vaultFiles.indexed)
                        _VaultCloudBindingTile(
                          vaultId: path,
                          position: index == 0
                              ? _SettingsTilePosition.first
                              : _SettingsTilePosition.middle,
                          title:
                              vaultLabels[path] ??
                              ref.read(vaultFileStorageProvider).fileName(path),
                          active: activeVaultFile == path,
                          onSelect: () => ref
                              .read(activeVaultFileProvider.notifier)
                              .select(path),
                          onExport: activeVaultFile == path
                              ? () => _exportDatabase(context, ref)
                              : null,
                          onMove: externalVaultsSupported
                              ? () => _moveVault(context, ref, path)
                              : null,
                          onRename: () => _renameVault(
                            context,
                            ref,
                            path,
                            vaultLabels[path] ??
                                ref
                                    .read(vaultFileStorageProvider)
                                    .fileName(path),
                          ),
                          onDelete: activeVaultFile == path
                              ? null
                              : () => _deleteVault(context, ref, path),
                          onImport: activeVaultFile == path
                              ? () => _importDatabase(context, ref)
                              : null,
                          onSync: activeVaultFile == path
                              ? () => _syncVault(context, ref, path)
                              : null,
                        ),
                    ],
                    ListTile(
                      contentPadding: _sectionTilePadding,
                      shape: RoundedRectangleBorder(
                        borderRadius: _sectionTileBorderRadius(
                          _SettingsTilePosition.last,
                        ),
                      ),
                      leading: const Icon(Symbols.add),
                      title: const Text('settingsVaultCreate').tr(),
                      trailing: const Icon(Symbols.chevron_right),
                      onTap: () => _showVaultOnboarding(context, ref),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _SettingsSection(
                titleKey: 'settingsConnectionsTransfer',
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: _sectionTilePadding,
                      shape: RoundedRectangleBorder(
                        borderRadius: _sectionTileBorderRadius(
                          _SettingsTilePosition.first,
                        ),
                      ),
                      leading: const Icon(Symbols.dns),
                      title: const Text('settingsConnectionsExport').tr(),
                      subtitle: const Text(
                        'settingsConnectionsExportHint',
                      ).tr(),
                      trailing: const Icon(Symbols.chevron_right),
                      onTap: () => _exportConnections(context, ref),
                    ),
                    ListTile(
                      contentPadding: _sectionTilePadding,
                      shape: RoundedRectangleBorder(
                        borderRadius: _sectionTileBorderRadius(
                          _SettingsTilePosition.last,
                        ),
                      ),
                      leading: const Icon(Symbols.upload_file),
                      title: const Text('settingsConnectionsImport').tr(),
                      subtitle: const Text(
                        'settingsConnectionsImportHint',
                      ).tr(),
                      trailing: const Icon(Symbols.chevron_right),
                      onTap: () => _importConnections(context, ref),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectBackgroundImage(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final selection = await FilePicker.pickFiles(
      dialogTitle: 'settingsBackgroundImageChoose'.tr(),
      type: FileType.image,
    );
    final path = selection?.files.singleOrNull?.path;
    if (path == null) return;
    try {
      await saveMaidKitBackgroundImage(ref, File(path));
    } catch (error) {
      if (context.mounted) _showMessage(error.toString());
    }
  }

  Future<void> _editSeedColor(BuildContext context, WidgetRef ref) async {
    final updated = await showDialog<Color>(
      context: context,
      builder: (context) => _ColorEditDialog(
        title: 'settingsThemeAccent'.tr(),
        initialColor: ref.read(appSeedColorProvider),
      ),
    );
    if (updated != null) {
      await ref.read(appSeedColorProvider.notifier).setSeedColor(updated);
    }
  }

  Future<void> _editAgentPersonality(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final controller = TextEditingController(text: current);
    final updated = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('settingsAgentPersonality').tr(),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 5,
            maxLines: 10,
            decoration: InputDecoration(
              hintText: 'settingsAgentPersonalityHint'.tr(),
              alignLabelWithHint: true,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('commonCancel').tr(),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, ''),
            child: const Text('settingsAgentPersonalityClear').tr(),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('commonSave').tr(),
          ),
        ],
      ),
    );
    controller.dispose();
    if (updated == null) return;
    await ref.read(agentPersonalityProvider.notifier).setPersonality(updated);
  }

  Future<void> _settleBilling(BuildContext context, WidgetRef ref) async {
    final accessToken = await ref.read(cloudSyncServiceProvider).accessToken();
    if (accessToken == null) {
      if (context.mounted) _showMessage('settingsCloudSignInRequired'.tr());
      return;
    }
    try {
      await const PersonalityBillingService().settle(
        baseUrl: PersonalityBillingService.productionBaseUrl,
        accessToken: accessToken,
      );
      ref.invalidate(personalityBillingPolicyProvider);
      if (context.mounted) _showMessage('settingsBillingSettleSuccess'.tr());
    } on PersonalityBillingException catch (error) {
      if (context.mounted) _showMessage(error.message);
    } catch (_) {
      if (context.mounted) _showMessage('commonSomethingWentWrong'.tr());
    }
  }

  Future<void> _editTerminalTheme(
    BuildContext context,
    WidgetRef ref, {
    required Brightness brightness,
  }) async {
    final isLight = brightness == Brightness.light;
    final updated = await showDialog<TerminalColorScheme>(
      context: context,
      builder: (context) => _TerminalThemeDialog(
        brightness: brightness,
        initialScheme: isLight
            ? ref.read(terminalLightThemeProvider)
            : ref.read(terminalDarkThemeProvider),
      ),
    );
    if (updated == null) return;
    if (isLight) {
      await ref.read(terminalLightThemeProvider.notifier).save(updated);
    } else {
      await ref.read(terminalDarkThemeProvider.notifier).save(updated);
    }
  }

  Widget _cloudLoginTile(BuildContext context, WidgetRef ref) => ListTile(
    contentPadding: _sectionTilePadding,
    shape: RoundedRectangleBorder(
      borderRadius: _sectionTileBorderRadius(_SettingsTilePosition.only),
    ),
    leading: const CircleAvatar(child: Icon(Symbols.person)),
    title: const Text('settingsCloudSignIn').tr(),
    subtitle: const Text('settingsCloudSignInHint').tr(),
    trailing: FilledButton(
      onPressed: () => _signInToCloud(context, ref),
      child: const Text('settingsCloudSignInAction').tr(),
    ),
    onTap: () => _signInToCloud(context, ref),
  );

  Future<void> _signInToCloud(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(cloudSyncServiceProvider).signIn();
      ref.invalidate(cloudUserProvider);
      ref.invalidate(cloudWorkspacesProvider);
    } on CloudSyncException catch (error) {
      if (context.mounted) _showMessage(error.message);
    } catch (_) {
      if (context.mounted) _showMessage('commonSomethingWentWrong'.tr());
    }
  }

  Future<void> _signOutFromCloud(BuildContext context, WidgetRef ref) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (sheetContext) => SheetScaffold(
        titleText: 'settingsCloudSignOut'.tr(),
        heightFactor: 0.32,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text('settingsCloudSignOutHint'.tr()),
            const SizedBox(height: 20),
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(sheetContext, false),
                  child: const Text('commonCancel').tr(),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  child: const Text('settingsCloudSignOut').tr(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(cloudSyncServiceProvider).signOut();
      ref.invalidate(cloudUserProvider);
      ref.invalidate(cloudWorkspacesProvider);
      for (final vaultId in ref.read(vaultFilesProvider)) {
        ref.invalidate(cloudSyncConfigurationForVaultProvider(vaultId));
      }
      if (context.mounted) _showMessage('settingsCloudSignOutSuccess'.tr());
    } on CloudSyncException catch (error) {
      if (context.mounted) _showMessage(error.message);
    } catch (_) {
      if (context.mounted) _showMessage('commonSomethingWentWrong'.tr());
    }
  }

  Future<void> _clearBackgroundImage(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await clearMaidKitBackgroundImage(ref);
    if (context.mounted) _showMessage('settingsBackgroundImageCleared'.tr());
  }

  Future<void> _setBiometricUnlock(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    final vault = ref.read(vaultServiceProvider);
    try {
      if (enabled) {
        // Prompt once during setup; only persist when authentication succeeds.
        await vault.enableBiometricUnlock();
      } else {
        await vault.disableBiometricUnlock();
      }
    } catch (error) {
      // Leave the switch off if setup fails (e.g. cancelled or unavailable).
      await vault.disableBiometricUnlock();
      if (context.mounted) {
        _showMessage(
          'settingsBiometricSetupFailed'.tr(args: [error.toString()]),
        );
      }
    } finally {
      ref.invalidate(biometricUnlockEnabledProvider);
    }
  }

  Future<void> _changeVaultPassword(BuildContext context, WidgetRef ref) async {
    final password = await _changeVaultPasswordSheet(context);
    if (password == null || !context.mounted) return;
    try {
      await ref.read(vaultServiceProvider).changePassword(password);
      if (context.mounted) {
        _showMessage('settingsVaultPasswordChanged'.tr());
      }
    } catch (error) {
      if (context.mounted) {
        _showMessage('settingsBackupError'.tr(args: [error.toString()]));
      }
    }
  }

  Future<void> _exportDatabase(BuildContext context, WidgetRef ref) async {
    final password = await _backupPasswordSheet(context, confirm: true);
    if (password == null || !context.mounted) return;

    final vault = ref.read(vaultServiceProvider);
    if (!await vault.unlockWithPassword(password)) {
      if (context.mounted) {
        _showMessage('settingsVaultPasswordInvalid'.tr());
      }
      return;
    }
    if (!context.mounted) return;

    final path = await FilePicker.saveFile(
      dialogTitle: 'settingsExportData'.tr(),
      fileName: 'maidkit-${exportFileNamePrefix(ref)}-${exportTimestamp()}.mkb',
      type: FileType.custom,
      allowedExtensions: const ['mkb'],
    );
    if (path == null || !context.mounted) return;

    try {
      final archive = await DatabaseBackupService(
        ref.read(databaseProvider),
        ref.read(vaultServiceProvider),
      ).exportArchive(password);
      await File(path).writeAsString(archive);
      if (context.mounted) _showMessage('settingsExportSuccess'.tr());
    } catch (error) {
      if (context.mounted) {
        _showMessage('settingsBackupError'.tr(args: [error.toString()]));
      }
    }
  }

  Future<void> _importDatabase(BuildContext context, WidgetRef ref) async {
    final selection = await FilePicker.pickFiles(
      dialogTitle: 'settingsImportData'.tr(),
      type: FileType.custom,
      allowedExtensions: const ['mkb'],
    );
    final path = selection?.files.singleOrNull?.path;
    if (path == null || !context.mounted) return;

    final password = await _backupPasswordSheet(context, confirm: false);
    if (password == null || !context.mounted) return;

    final destination = await showModalBottomSheet<_ImportDestination>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (sheetContext) => SheetScaffold(
        titleText: 'settingsImportDestinationTitle'.tr(),
        heightFactor: 0.44,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            RadioGroup<_ImportDestination>(
              groupValue: _ImportDestination.newVault,
              onChanged: (value) {
                if (value != null) Navigator.of(sheetContext).pop(value);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<_ImportDestination>(
                    value: _ImportDestination.newVault,
                    title: const Text('settingsImportNewVault').tr(),
                    subtitle: const Text('settingsImportNewVaultHint').tr(),
                  ),
                  RadioListTile<_ImportDestination>(
                    value: _ImportDestination.replaceCurrent,
                    title: const Text('settingsImportReplaceCurrent').tr(),
                    subtitle: const Text(
                      'settingsImportReplaceCurrentHint',
                    ).tr(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('commonCancel').tr(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (destination == null || !context.mounted) return;

    if (destination == _ImportDestination.replaceCurrent) {
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        useRootNavigator: true,
        builder: (sheetContext) => SheetScaffold(
          titleText: 'settingsImportConfirmTitle'.tr(),
          heightFactor: 0.34,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              const Text('settingsImportConfirmDescription').tr(),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(false),
                    child: const Text('commonCancel').tr(),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                    child: const Text('settingsImportReplaceCurrent').tr(),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      if (confirmed != true || !context.mounted) return;
      await _importIntoCurrentVault(context, ref, path, password);
      return;
    }

    final vaultPassword = await _newVaultPasswordSheet(context);
    if (vaultPassword == null || !context.mounted) return;

    final vaultPath = await ref
        .read(vaultFileStorageProvider)
        .createVaultPath(name: path);

    final database = AppDatabase(filePath: vaultPath);
    final vault = VaultService(database, vaultId: vaultPath);
    try {
      await vault.create(vaultPassword);
      final archive = await File(path).readAsString();
      await DatabaseBackupService(
        database,
        vault,
      ).importArchive(archive, password);
      await ref.read(activeVaultFileProvider.notifier).select(vaultPath);
      if (context.mounted) _showMessage('settingsImportSuccess'.tr());
    } catch (error) {
      if (context.mounted) {
        _showMessage('settingsBackupError'.tr(args: [error.toString()]));
      }
    } finally {
      await database.close();
    }
  }

  Future<void> _importIntoCurrentVault(
    BuildContext context,
    WidgetRef ref,
    String path,
    String password,
  ) async {
    try {
      final archive = await File(path).readAsString();
      await DatabaseBackupService(
        ref.read(databaseProvider),
        ref.read(vaultServiceProvider),
      ).importArchive(archive, password);
      if (context.mounted) _showMessage('settingsImportSuccess'.tr());
    } catch (error) {
      if (context.mounted) {
        _showMessage('settingsBackupError'.tr(args: [error.toString()]));
      }
    }
  }

  Future<void> _exportConnections(BuildContext context, WidgetRef ref) async {
    final format = await showModalBottomSheet<_ConnectionsExportFormat>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (sheetContext) => SheetScaffold(
        titleText: 'settingsConnectionsExportTitle'.tr(),
        heightFactor: 0.5,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            RadioGroup<_ConnectionsExportFormat>(
              groupValue: _ConnectionsExportFormat.jsonRedacted,
              onChanged: (value) {
                if (value != null) Navigator.of(sheetContext).pop(value);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<_ConnectionsExportFormat>(
                    value: _ConnectionsExportFormat.jsonRedacted,
                    title: const Text(
                      'settingsConnectionsFormatJsonRedacted',
                    ).tr(),
                    subtitle: const Text(
                      'settingsConnectionsFormatJsonRedactedHint',
                    ).tr(),
                  ),
                  RadioListTile<_ConnectionsExportFormat>(
                    value: _ConnectionsExportFormat.jsonProtected,
                    title: const Text(
                      'settingsConnectionsFormatJsonProtected',
                    ).tr(),
                    subtitle: const Text(
                      'settingsConnectionsFormatJsonProtectedHint',
                    ).tr(),
                  ),
                  RadioListTile<_ConnectionsExportFormat>(
                    value: _ConnectionsExportFormat.csv,
                    title: const Text('settingsConnectionsFormatCsv').tr(),
                    subtitle: const Text(
                      'settingsConnectionsFormatCsvHint',
                    ).tr(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('commonCancel').tr(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (format == null || !context.mounted) return;

    final extension = switch (format) {
      _ConnectionsExportFormat.csv => 'csv',
      _ => 'json',
    };
    final fileName =
        'maidkit-connections-${exportFileNamePrefix(ref)}-${exportTimestamp()}.$extension';
    String? passphrase;
    if (format == _ConnectionsExportFormat.jsonProtected) {
      passphrase = await _connectionsPasswordSheet(context);
      if (passphrase == null || !context.mounted) return;
    }

    final path = await FilePicker.saveFile(
      dialogTitle: 'settingsConnectionsExportTitle'.tr(),
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: [extension],
    );
    if (path == null || !context.mounted) return;

    try {
      final service = ConnectionExportService(
        ref.read(databaseProvider),
        ref.read(vaultServiceProvider),
      );
      final content = switch (format) {
        _ConnectionsExportFormat.csv => await service.exportCsv(),
        _ => await service.exportJson(passphrase: passphrase),
      };
      await File(path).writeAsString(content);
      if (context.mounted) {
        _showMessage('settingsConnectionsExportSuccess'.tr());
      }
    } on VaultLockedException {
      if (context.mounted) {
        _showMessage('settingsConnectionsVaultLocked'.tr());
      }
    } catch (error) {
      if (context.mounted) {
        _showMessage(
          'settingsConnectionsExportError'.tr(args: [error.toString()]),
        );
      }
    }
  }

  Future<void> _importConnections(BuildContext context, WidgetRef ref) async {
    final selection = await FilePicker.pickFiles(
      dialogTitle: 'settingsConnectionsImportTitle'.tr(),
      type: FileType.any,
      allowMultiple: true,
    );
    final paths =
        selection?.files
            .map((file) => file.path)
            .whereType<String>()
            .where((path) => path.isNotEmpty)
            .toList() ??
        const [];
    if (paths.isEmpty || !context.mounted) return;

    final service = ConnectionImportService(
      ref.read(databaseProvider),
      ref.read(vaultServiceProvider),
    );
    final preview = await service.previewFiles(
      paths,
      requestPassphrase: () => _connectionsImportPasswordSheet(context),
    );
    if (!context.mounted || preview.aborted) return;

    if (preview.isEmpty) {
      if (preview.firstError is ConnectionSecretsPassphraseException) {
        _showMessage('settingsConnectionsImportWrongPassphrase'.tr());
      } else {
        _showMessage(
          'settingsConnectionsImportError'.tr(
            args: [
              preview.firstError?.toString() ??
                  'settingsConnectionsImportEmpty'.tr(),
            ],
          ),
        );
      }
      return;
    }

    final selected = await showModalBottomSheet<List<ImportCandidate>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (sheetContext) =>
          ConnectionImportPreviewSheet(candidates: preview.candidates),
    );
    if (selected == null || selected.isEmpty || !context.mounted) return;

    try {
      final result = await service.import(selected);
      if (context.mounted) {
        _showMessage(
          'settingsConnectionsImportSuccess'.tr(args: ['${result.created}']),
        );
      }
    } on Exception catch (error) {
      if (context.mounted) {
        _showMessage(
          'settingsConnectionsImportError'.tr(args: [error.toString()]),
        );
      }
    }
  }

  Future<String?> _chooseVaultFolder(
    BuildContext context, {
    String? initialDirectory,
  }) async {
    try {
      return await FilePicker.getDirectoryPath(
        dialogTitle: 'settingsVaultChooseFolder'.tr(),
        initialDirectory: initialDirectory,
      );
    } catch (error) {
      if (context.mounted) {
        _showMessage('settingsBackupError'.tr(args: [error.toString()]));
      }
      return null;
    }
  }

  Future<void> _createLocalVault(BuildContext context, WidgetRef ref) async {
    final name = await _chooseVaultNameSheet(context);
    if (name == null || !context.mounted) return;
    final path = await ref
        .read(vaultFileStorageProvider)
        .createVaultPath(name: name);
    try {
      await ref.read(vaultLabelsProvider.notifier).rename(path, name);
      await ref.read(activeVaultFileProvider.notifier).select(path);
    } catch (error) {
      if (context.mounted) {
        _showMessage('settingsBackupError'.tr(args: [error.toString()]));
      }
    }
  }

  Future<void> _createExternalVault(BuildContext context, WidgetRef ref) async {
    if (!externalVaultsSupported) return;
    final name = await _chooseVaultNameSheet(context);
    if (name == null || !context.mounted) return;
    final folder = await _chooseVaultFolder(context);
    if (folder == null || !context.mounted) return;
    final path = await ref
        .read(vaultFileStorageProvider)
        .createVaultPath(name: name, directoryPath: folder);
    try {
      await ref.read(vaultLabelsProvider.notifier).rename(path, name);
      await ref.read(activeVaultFileProvider.notifier).select(path);
    } catch (error) {
      if (context.mounted) {
        _showMessage('settingsBackupError'.tr(args: [error.toString()]));
      }
    }
  }

  Future<void> _renameVault(
    BuildContext context,
    WidgetRef ref,
    String vaultId,
    String currentName,
  ) async {
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (context) => _VaultNameSheet(
        initialValue: currentName,
        titleKey: 'settingsVaultRename',
        actionKey: 'commonSave',
      ),
    );
    if (name != null) {
      await ref.read(vaultLabelsProvider.notifier).rename(vaultId, name);
    }
  }

  Future<void> _moveVault(
    BuildContext context,
    WidgetRef ref,
    String vaultId,
  ) async {
    if (!externalVaultsSupported) return;
    final folder = await _chooseVaultFolder(context);
    if (folder == null || !context.mounted) return;
    try {
      final storage = ref.read(vaultFileStorageProvider);
      final newPath = await storage.moveVault(
        vaultId,
        directoryPath: folder,
        name: storage.fileName(vaultId),
      );
      await VaultService.relocateStoredKeys(
        oldVaultId: vaultId,
        newVaultId: newPath,
      );
      await ref
          .read(cloudSyncServiceForVaultProvider(vaultId))
          .relocateVault(newPath);
      final label = ref.read(vaultLabelsProvider)[vaultId];
      await ref.read(vaultFilesProvider.notifier).forget(vaultId);
      await ref.read(vaultFilesProvider.notifier).remember(newPath);
      await ref.read(vaultLabelsProvider.notifier).remove(vaultId);
      if (label != null) {
        await ref.read(vaultLabelsProvider.notifier).rename(newPath, label);
      }
      if (ref.read(activeVaultFileProvider) == vaultId) {
        await ref.read(activeVaultFileProvider.notifier).select(newPath);
      }
      if (context.mounted) _showMessage('settingsVaultMoveComplete'.tr());
    } catch (error) {
      if (context.mounted) {
        _showMessage('settingsBackupError'.tr(args: [error.toString()]));
      }
    }
  }

  Future<void> _deleteVault(
    BuildContext context,
    WidgetRef ref,
    String vaultId,
  ) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (sheetContext) => SheetScaffold(
        titleText: 'settingsVaultDelete'.tr(),
        heightFactor: 0.34,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const Text('settingsVaultDeleteHint').tr(),
            const SizedBox(height: 20),
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(false),
                  child: const Text('commonCancel').tr(),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  child: const Text('commonDelete').tr(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    if (ref.read(activeVaultFileProvider) == vaultId) {
      await ref.read(activeVaultFileProvider.notifier).select(null);
    }
    await ref.read(vaultFileStorageProvider).deleteVault(vaultId);
    await ref.read(vaultFilesProvider.notifier).forget(vaultId);
    await ref.read(vaultLabelsProvider.notifier).remove(vaultId);
  }

  Future<void> _showVaultOnboarding(BuildContext context, WidgetRef ref) async {
    final choice = await showModalBottomSheet<_VaultOnboardingChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (sheetContext) => SheetScaffold(
        titleText: 'settingsVaultCreate'.tr(),
        heightFactor: 0.58,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            ListTile(
              leading: const Icon(Symbols.lock),
              title: const Text('settingsVaultCreateLocal').tr(),
              subtitle: const Text('settingsVaultCreateLocalHint').tr(),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_VaultOnboardingChoice.local),
            ),
            if (externalVaultsSupported)
              ListTile(
                leading: const Icon(Symbols.folder_open),
                title: const Text('settingsVaultCreateExternal').tr(),
                subtitle: const Text('settingsVaultCreateExternalHint').tr(),
                onTap: () => Navigator.of(
                  sheetContext,
                ).pop(_VaultOnboardingChoice.external),
              ),
            ListTile(
              leading: const Icon(Symbols.cloud_download),
              title: const Text('settingsVaultDownloadCloud').tr(),
              subtitle: const Text('settingsVaultDownloadCloudHint').tr(),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_VaultOnboardingChoice.cloud),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('commonCancel').tr(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (choice == _VaultOnboardingChoice.local && context.mounted) {
      await _createLocalVault(context, ref);
    } else if (choice == _VaultOnboardingChoice.external && context.mounted) {
      await _createExternalVault(context, ref);
    } else if (choice == _VaultOnboardingChoice.cloud && context.mounted) {
      await _downloadCloudVault(context, ref);
    }
  }

  Future<void> _downloadCloudVault(BuildContext context, WidgetRef ref) async {
    try {
      final accountService = ref.read(cloudSyncServiceProvider);
      final workspaces = await accountService.signInAndListWorkspaces();
      if (!context.mounted) return;
      final workspace = await _chooseCloudWorkspace(context, workspaces);
      if (workspace == null || !context.mounted) return;
      final blobs = await accountService.listVaultBlobs(workspace);
      if (!context.mounted) return;
      final blob = await _chooseCloudVault(context, blobs);
      if (blob == null || !context.mounted) return;
      final name = await _chooseVaultNameSheet(
        context,
        initialValue: workspace.name,
      );
      if (name == null || !context.mounted) return;

      // Cloud downloads use MaidKit's private storage. External storage is
      // available only through the explicit external-vault flow above.
      final path = await ref
          .read(vaultFileStorageProvider)
          .createVaultPath(name: name);
      final sync = ref.read(cloudSyncServiceForVaultProvider(path));
      await sync.enable(workspace, existingBlob: blob);
      ref.invalidate(cloudSyncConfigurationForVaultProvider(path));
      await ref.read(activeVaultFileProvider.notifier).select(path);
    } on CloudSyncException catch (error) {
      if (context.mounted) _showMessage(error.message);
    } catch (error) {
      if (context.mounted) {
        _showMessage('settingsBackupError'.tr(args: [error.toString()]));
      }
    }
  }

  Future<CloudWorkspace?> _chooseCloudWorkspace(
    BuildContext context,
    List<CloudWorkspace> workspaces,
  ) => showModalBottomSheet<CloudWorkspace>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    builder: (sheetContext) => SheetScaffold(
      titleText: 'vaultCloudWorkspaceTitle'.tr(),
      heightFactor: 0.6,
      child: workspaces.isEmpty
          ? ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [const Text('settingsCloudSyncNoWorkspaces').tr()],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                for (final workspace in workspaces)
                  ListTile(
                    title: Text(workspace.name),
                    onTap: () => Navigator.of(sheetContext).pop(workspace),
                  ),
              ],
            ),
    ),
  );

  Future<CloudVaultBlob?> _chooseCloudVault(
    BuildContext context,
    List<CloudVaultBlob> blobs,
  ) => showModalBottomSheet<CloudVaultBlob>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    builder: (sheetContext) => SheetScaffold(
      titleText: 'settingsVaultDownloadCloud'.tr(),
      heightFactor: 0.6,
      child: blobs.isEmpty
          ? ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [const Text('settingsVaultNoCloudVaults').tr()],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                for (final blob in blobs)
                  ListTile(
                    leading: const Icon(Symbols.lock),
                    title: Text(
                      'settingsVaultCloudVault'.tr(
                        args: [blob.revision.toString()],
                      ),
                    ),
                    subtitle: Text(blob.id),
                    onTap: () => Navigator.of(sheetContext).pop(blob),
                  ),
              ],
            ),
    ),
  );

  Future<void> _syncVault(
    BuildContext context,
    WidgetRef ref,
    String vaultId,
  ) async {
    try {
      final vault = ref.read(vaultServiceProvider);
      var password = await vault.syncPassphrase();
      if (password == null) {
        if (!context.mounted) return;
        final entered = await _syncPasswordSheet(context);
        if (entered == null || !context.mounted) return;
        if (!await vault.unlockWithPassword(entered)) {
          if (context.mounted) {
            _showMessage('settingsVaultPasswordInvalid'.tr());
          }
          return;
        }
        password = entered;
      }
      final syncPassword = password;
      if (context.mounted) {
        showSnackBar('settingsVaultSyncStarted'.tr());
      }
      final backup = DatabaseBackupService(ref.read(databaseProvider), vault);
      final service = ref.read(cloudSyncServiceForVaultProvider(vaultId));
      final archive = await backup.exportArchive(syncPassword);
      await service.sync(
        archive: archive,
        applyArchive: (archive) => backup.importArchive(archive, syncPassword),
        compareAndMergeArchive:
            ({required localArchive, required remoteArchive}) =>
                backup.compareAndMergeArchives(
                  localArchive: localArchive,
                  remoteArchive: remoteArchive,
                  password: syncPassword,
                ),
        contentFingerprint: backup.contentFingerprint,
      );
      ref.invalidate(cloudSyncConfigurationForVaultProvider(vaultId));
      if (context.mounted) {
        showSnackBar('settingsVaultSyncComplete'.tr());
      }
    } on CloudSyncException catch (error) {
      if (context.mounted) showSnackBar(error.message);
    } catch (error) {
      if (context.mounted) {
        showSnackBar('settingsBackupError'.tr(args: [error.toString()]));
      }
    }
  }
}

enum _ImportDestination { newVault, replaceCurrent }

enum _ConnectionsExportFormat { jsonRedacted, jsonProtected, csv }

enum _VaultOnboardingChoice { local, external, cloud }

enum _VaultTileAction { changeCloudBinding, move, rename, delete }

enum _SettingsTilePosition { only, first, middle, last }

const _sectionTilePadding = EdgeInsets.symmetric(horizontal: 16);

String _usageLabel(BillingUsage? usage) {
  if (usage == null) return '—';
  final max = usage.max;
  return max == null
      ? _formatUsage(usage.used)
      : '${_formatUsage(usage.used)} / ${_formatUsage(max)}';
}

String _formatUsage(double value) {
  if (value == value.roundToDouble()) return value.round().toString();
  return value.toStringAsFixed(2);
}

class _UsageTrailing extends StatelessWidget {
  const _UsageTrailing({required this.usage});

  final BillingUsage? usage;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_usageLabel(usage)),
        const SizedBox(width: 6),
        _UsageRing(usage: usage),
      ],
    );
  }
}

class _UsageRing extends StatelessWidget {
  const _UsageRing({required this.usage});

  final BillingUsage? usage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final used = usage?.used ?? 0;
    final max = usage?.max;
    final progress = (max == null || max <= 0)
        ? 0.0
        : (used / max).clamp(0.0, 1.0);
    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: progress,
            strokeWidth: 3,
            strokeCap: StrokeCap.round,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
          Center(
            child: Text(
              max == null ? '—' : '${(progress * 100).round()}%',
              style: theme.textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}

BorderRadius _sectionTileBorderRadius(_SettingsTilePosition position) {
  const radius = Radius.circular(12);
  return BorderRadius.only(
    topLeft:
        position == _SettingsTilePosition.only ||
            position == _SettingsTilePosition.first
        ? radius
        : Radius.zero,
    topRight:
        position == _SettingsTilePosition.only ||
            position == _SettingsTilePosition.first
        ? radius
        : Radius.zero,
    bottomLeft:
        position == _SettingsTilePosition.only ||
            position == _SettingsTilePosition.last
        ? radius
        : Radius.zero,
    bottomRight:
        position == _SettingsTilePosition.only ||
            position == _SettingsTilePosition.last
        ? radius
        : Radius.zero,
  );
}

Future<String?> _backupPasswordSheet(
  BuildContext context, {
  required bool confirm,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  useRootNavigator: true,
  builder: (context) => _BackupPasswordSheet(confirm: confirm),
);

Future<String?> _syncPasswordSheet(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (context) => const _BackupPasswordSheet(
        confirm: false,
        titleKey: 'settingsVaultSyncPasswordTitle',
        hintKey: 'settingsVaultSyncPasswordHint',
        actionKey: 'settingsVaultSyncNow',
      ),
    );

Future<String?> _connectionsPasswordSheet(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (context) => const _BackupPasswordSheet(
        confirm: true,
        titleKey: 'settingsConnectionsPasswordTitle',
        hintKey: 'settingsConnectionsPasswordHint',
        actionKey: 'settingsConnectionsExportAction',
      ),
    );

Future<String?> _connectionsImportPasswordSheet(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (context) => const _BackupPasswordSheet(
        confirm: false,
        titleKey: 'settingsConnectionsImportPasswordTitle',
        hintKey: 'settingsConnectionsImportPasswordHint',
        actionKey: 'settingsConnectionsImportAction',
      ),
    );

Future<String?> _newVaultPasswordSheet(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (context) => const _BackupPasswordSheet(
        confirm: true,
        titleKey: 'settingsImportNewVaultPasswordTitle',
        hintKey: 'settingsImportNewVaultPasswordHint',
        actionKey: 'vaultCreateAction',
      ),
    );

Future<String?> _changeVaultPasswordSheet(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (context) => const _BackupPasswordSheet(
        confirm: true,
        titleKey: 'settingsVaultChangePassword',
        hintKey: 'settingsVaultChangePasswordHint',
        actionKey: 'commonSave',
      ),
    );

Future<String?> _chooseVaultNameSheet(
  BuildContext context, {
  String? initialValue,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  useRootNavigator: true,
  builder: (context) =>
      _VaultNameSheet(initialValue: initialValue ?? 'settingsVaultCreate'.tr()),
);

class _VaultNameSheet extends StatefulWidget {
  const _VaultNameSheet({
    required this.initialValue,
    this.titleKey = 'settingsVaultName',
    this.actionKey = 'commonContinue',
  });

  final String initialValue;
  final String titleKey;
  final String actionKey;

  @override
  State<_VaultNameSheet> createState() => _VaultNameSheetState();
}

class _VaultNameSheetState extends State<_VaultNameSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => SheetScaffold(
    titleText: widget.titleKey.tr(),
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(labelText: 'settingsVaultName'.tr()),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('commonCancel').tr(),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _submit,
              child: Text(widget.actionKey.tr()),
            ),
          ],
        ),
      ],
    ),
  );
}

class _BackupPasswordSheet extends StatefulWidget {
  const _BackupPasswordSheet({
    required this.confirm,
    this.titleKey,
    this.hintKey,
    this.actionKey,
  });

  final bool confirm;
  final String? titleKey;
  final String? hintKey;
  final String? actionKey;

  @override
  State<_BackupPasswordSheet> createState() => _BackupPasswordSheetState();
}

class _BackupPasswordSheetState extends State<_BackupPasswordSheet> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SheetScaffold(
    titleText:
        (widget.titleKey ??
                (widget.confirm
                    ? 'settingsExportPasswordTitle'
                    : 'settingsImportPasswordTitle'))
            .tr(),
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text(
          (widget.hintKey ??
                  (widget.confirm
                      ? 'settingsExportVaultPasswordHint'
                      : 'settingsImportVaultPasswordHint'))
              .tr(),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _password,
          autofocus: true,
          obscureText: true,
          decoration: InputDecoration(labelText: 'vaultPasswordLabel'.tr()),
        ),
        if (widget.confirm) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _confirmation,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'vaultConfirmPasswordLabel'.tr(),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('commonCancel').tr(),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                if (widget.confirm && _password.text != _confirmation.text) {
                  showSnackBar('vaultPasswordsDontMatch'.tr());
                  return;
                }
                Navigator.of(context).pop(_password.text);
              },
              child: Text(
                widget.confirm
                    ? (widget.actionKey ?? 'settingsExportData').tr()
                    : (widget.actionKey ?? 'settingsImportData').tr(),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

void _showMessage(String message) {
  showSnackBar(message);
}

class _CloudAvatar extends StatelessWidget {
  const _CloudAvatar({required this.user});

  final CloudUser user;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    foregroundImage: user.avatarUrl == null
        ? null
        : NetworkImage(user.avatarUrl!),
    child: Text(user.initials),
  );
}

class _VaultCloudBindingTile extends ConsumerWidget {
  const _VaultCloudBindingTile({
    required this.vaultId,
    required this.title,
    required this.position,
    required this.active,
    required this.onSelect,
    this.onExport,
    this.onImport,
    this.onSync,
    this.onMove,
    this.onRename,
    this.onDelete,
  });

  final String vaultId;
  final String title;
  final _SettingsTilePosition position;
  final bool active;
  final Future<void> Function() onSelect;
  final Future<void> Function()? onExport;
  final Future<void> Function()? onImport;
  final Future<void> Function()? onSync;
  final Future<void> Function()? onMove;
  final Future<void> Function()? onRename;
  final Future<void> Function()? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final binding = ref.watch(cloudSyncConfigurationForVaultProvider(vaultId));
    final external =
        ref.watch(vaultExternalPathProvider(vaultId)).asData?.value ?? false;
    final configuration = binding.asData?.value;
    final workspace = configuration == null
        ? 'settingsVaultWorkspaceUnbound'.tr()
        : 'settingsVaultWorkspaceBound'.tr(args: [configuration.workspaceName]);
    final syncStatus = configuration == null
        ? 'settingsVaultSyncDisabled'.tr()
        : 'settingsVaultLastSync'.tr(
            args: [
              configuration.lastSyncedAt == null
                  ? 'settingsVaultNotYet'.tr()
                  : DateFormat.yMMMd().add_jm().format(
                      configuration.lastSyncedAt!,
                    ),
            ],
          );
    final tileBorderRadius = _sectionTileBorderRadius(position);
    return Material(
      color: active ? Theme.of(context).colorScheme.secondaryContainer : null,
      borderRadius: tileBorderRadius,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            contentPadding: _sectionTilePadding,
            shape: RoundedRectangleBorder(borderRadius: tileBorderRadius),
            leading: const Icon(Symbols.lock),
            title: Text(title),
            subtitle: Text(
              external
                  ? '$workspace\n$syncStatus\n$vaultId'
                  : '$workspace\n$syncStatus',
            ),
            isThreeLine: external,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PopupMenuButton<_VaultTileAction>(
                  onSelected: (action) {
                    if (action == _VaultTileAction.changeCloudBinding) {
                      _bindWorkspace(context, ref);
                    }
                    if (action == _VaultTileAction.move) onMove?.call();
                    if (action == _VaultTileAction.rename) onRename?.call();
                    if (action == _VaultTileAction.delete) onDelete?.call();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _VaultTileAction.changeCloudBinding,
                      child: Text('settingsVaultChangeCloudBinding'.tr()),
                    ),
                    if (onMove != null)
                      PopupMenuItem(
                        value: _VaultTileAction.move,
                        child: Text('settingsVaultMove'.tr()),
                      ),
                    if (onRename != null)
                      PopupMenuItem(
                        value: _VaultTileAction.rename,
                        child: Text('settingsVaultRename'.tr()),
                      ),
                    if (onDelete != null)
                      PopupMenuItem(
                        value: _VaultTileAction.delete,
                        child: Text('settingsVaultDelete'.tr()),
                      ),
                  ],
                ),
                const SizedBox(width: 8),
                const Icon(Symbols.chevron_right),
              ],
            ),
            onTap: () => onSelect(),
          ),
          if (active)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: onExport == null ? null : () => onExport!(),
                    icon: const Icon(Symbols.file_download),
                    label: const Text('settingsExportData').tr(),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: onImport == null ? null : () => onImport!(),
                    icon: const Icon(Symbols.file_upload),
                    label: const Text('settingsImportData').tr(),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: configuration == null || onSync == null
                        ? null
                        : () => onSync!(),
                    icon: const Icon(Symbols.sync),
                    label: const Text('settingsVaultSyncNow').tr(),
                  ),
                ],
              ),
            ).alignment(.centerLeft),
        ],
      ),
    );
  }

  Future<void> _bindWorkspace(BuildContext context, WidgetRef ref) async {
    try {
      final service = ref.read(cloudSyncServiceForVaultProvider(vaultId));
      final workspaces = await service.signInAndListWorkspaces();
      if (!context.mounted) return;
      final selected = ref
          .read(cloudSyncConfigurationForVaultProvider(vaultId))
          .asData
          ?.value;
      final workspace = await showModalBottomSheet<CloudWorkspace>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        useRootNavigator: true,
        builder: (sheetContext) => SheetScaffold(
          title: Text(title),
          heightFactor: 0.6,
          child: workspaces.isEmpty
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [const Text('settingsCloudSyncNoWorkspaces').tr()],
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    for (final workspace in workspaces)
                      ListTile(
                        title: Text(workspace.name),
                        trailing: selected?.workspaceId == workspace.id
                            ? const Icon(Symbols.check)
                            : null,
                        onTap: () => Navigator.of(sheetContext).pop(workspace),
                      ),
                  ],
                ),
        ),
      );
      if (workspace == null) return;
      await service.enable(workspace);
      ref.invalidate(cloudSyncConfigurationForVaultProvider(vaultId));
      ref.invalidate(cloudUserProvider);
    } on CloudSyncException catch (error) {
      if (context.mounted) showSnackBar(error.message);
    } catch (_) {
      if (context.mounted) showSnackBar('commonSomethingWentWrong'.tr());
    }
  }
}

class _PersonalityAgentDropdown extends ConsumerWidget {
  const _PersonalityAgentDropdown({
    required this.agentId,
    required this.agents,
  });

  final String agentId;
  final List<PersonalityAgent> agents;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = <String>{
      agentId,
      for (final agent in agents)
        if (agent.id.isNotEmpty) agent.id,
    };
    final selected = options.contains(agentId) ? agentId : options.first;
    return DropdownButtonFormField<String>(
      initialValue: selected,
      decoration: InputDecoration(
        labelText: 'settingsAgentPersonalityAgentLabel'.tr(),
        helperText: 'settingsAgentPersonalityAgentFieldHint'.tr(
          args: [AgentPersonalityAgentPreferences.defaultAgentId],
        ),
      ),
      items: [
        for (final id in options)
          DropdownMenuItem(
            value: id,
            child: Text(
              agents
                      .where((agent) => agent.id == id)
                      .firstOrNull
                      ?.displayName ??
                  id,
            ),
          ),
      ],
      onChanged: (id) {
        if (id == null) return;
        ref.read(agentPersonalityAgentProvider.notifier).setAgentId(id);
      },
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.titleKey,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final String titleKey;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titleKey, style: Theme.of(context).textTheme.titleMedium).tr(),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(padding: padding, child: child),
        ),
      ],
    );
  }
}

/// Toggle and configuration for the in-app MCP server that exposes
/// MaidKit's resources to other agents on this machine.
class _LocalMcpServerSection extends ConsumerStatefulWidget {
  const _LocalMcpServerSection();

  @override
  ConsumerState<_LocalMcpServerSection> createState() =>
      _LocalMcpServerSectionState();
}

class _LocalMcpServerSectionState
    extends ConsumerState<_LocalMcpServerSection> {
  final _portController = TextEditingController();
  bool _portPrefilled = false;
  String? _portError;

  @override
  void dispose() {
    _portController.dispose();
    super.dispose();
  }

  void _copyUrl() {
    final url = ref.read(localMcpServerProvider).value?.url;
    if (url == null) return;
    Clipboard.setData(ClipboardData(text: url));
    showSnackBar('settingsLocalMcpServerCopied'.tr());
  }

  Future<void> _applyPort(String value) async {
    final port = int.tryParse(value.trim());
    if (port == null || port < 1024 || port > 65535) {
      setState(() => _portError = 'settingsLocalMcpServerPortInvalid'.tr());
      return;
    }
    setState(() => _portError = null);
    await ref.read(localMcpServerProvider.notifier).setPort(port);
  }

  @override
  Widget build(BuildContext context) {
    final localMcp = ref.watch(localMcpServerProvider);
    return localMcp.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(error.toString()),
      ),
      data: (state) {
        if (!_portPrefilled) {
          _portPrefilled = true;
          _portController.text = '${state.port}';
        }
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('settingsLocalMcpServerEnabled').tr(),
                subtitle: const Text('settingsLocalMcpServerHint').tr(),
                value: state.enabled,
                onChanged: (value) =>
                    ref.read(localMcpServerProvider.notifier).setEnabled(value),
              ),
              if (state.enabled) ...[
                const SizedBox(height: 4),
                _statusRow(state, scheme),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Symbols.link, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SelectableText(
                        state.url,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontFamily: 'IBM Plex Mono',
                          color: scheme.primary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'settingsLocalMcpServerCopy'.tr(),
                      visualDensity: VisualDensity.compact,
                      onPressed: _copyUrl,
                      icon: const Icon(Symbols.content_copy),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      'settingsLocalMcpServerPort'.tr(),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 140,
                      child: TextField(
                        controller: _portController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          isDense: true,
                          errorText: _portError,
                          errorMaxLines: 2,
                        ),
                        onSubmitted: _applyPort,
                        onChanged: (_) {
                          if (_portError != null) {
                            setState(() => _portError = null);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'settingsMcpReviewMode',
                  style: Theme.of(context).textTheme.titleSmall,
                ).tr(),
                const SizedBox(height: 4),
                Text(
                  'settingsMcpReviewModeHint',
                  style: Theme.of(context).textTheme.bodyMedium,
                ).tr(),
                const SizedBox(height: 12),
                ref
                    .watch(mcpReviewModeProvider)
                    .when(
                      loading: () => const LinearProgressIndicator(),
                      error: (error, _) => Text(error.toString()),
                      data: (mode) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SegmentedButton<McpReviewMode>(
                            showSelectedIcon: false,
                            segments: [
                              for (final reviewMode in McpReviewMode.values)
                                ButtonSegment(
                                  value: reviewMode,
                                  label: Text(reviewMode.labelKey.tr()),
                                  tooltip: reviewMode.descriptionKey.tr(),
                                ),
                            ],
                            selected: {mode},
                            onSelectionChanged: (selection) {
                              ref
                                  .read(mcpReviewModeProvider.notifier)
                                  .setMode(selection.first);
                            },
                          ),
                          const SizedBox(height: 8),
                          Text(
                            mode.descriptionKey.tr(),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                const SizedBox(height: 16),
                Text(
                  'settingsLocalMcpServerConfigTitle',
                  style: Theme.of(context).textTheme.titleSmall,
                ).tr(),
                const SizedBox(height: 4),
                Text(
                  'settingsLocalMcpServerConfigHint',
                  style: Theme.of(context).textTheme.bodyMedium,
                ).tr(),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    '"mcpServers": {\n'
                    '  "maidkit": {\n'
                    '    "url": "${state.url}"\n'
                    '  }\n'
                    '}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'IBM Plex Mono',
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _statusRow(LocalMcpServerState state, ColorScheme scheme) {
    final (color, labelKey) = switch (state.status) {
      LocalMcpServerStatus.running => (
        scheme.primary,
        'settingsLocalMcpServerStatusRunning',
      ),
      LocalMcpServerStatus.failed => (
        scheme.error,
        'settingsLocalMcpServerStatusFailed',
      ),
      LocalMcpServerStatus.stopped => (
        scheme.onSurfaceVariant,
        'settingsLocalMcpServerStatusStopped',
      ),
    };
    return Row(
      children: [
        Icon(Symbols.circle, size: 10, color: color),
        const SizedBox(width: 8),
        Text(labelKey.tr(), style: Theme.of(context).textTheme.bodyMedium),
        if (state.error != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              state.error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
        ],
      ],
    );
  }
}

class _IntervalDropdown extends StatelessWidget {
  const _IntervalDropdown({
    required this.labelKey,
    required this.helperKey,
    required this.value,
    required this.options,
    required this.fallback,
    required this.onChanged,
  });

  final String labelKey;
  final String helperKey;
  final Duration value;
  final List<Duration> options;
  final Duration fallback;
  final ValueChanged<Duration> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<Duration>(
      initialValue: options.contains(value) ? value : fallback,
      decoration: InputDecoration(
        labelText: labelKey.tr(),
        helperText: helperKey.tr(),
      ),
      items: [
        for (final interval in options)
          DropdownMenuItem(
            value: interval,
            child: Text(_formatInterval(interval)),
          ),
      ],
      onChanged: (interval) {
        if (interval != null) onChanged(interval);
      },
    );
  }
}

const _refreshIntervals = [
  Duration(seconds: 15),
  Duration(seconds: 30),
  Duration(minutes: 1),
  Duration(minutes: 2),
  Duration(minutes: 5),
];

const _focusedRefreshIntervals = [
  Duration(seconds: 3),
  Duration(seconds: 5),
  Duration(seconds: 10),
  Duration(seconds: 15),
  Duration(seconds: 30),
];

String _formatInterval(Duration interval) {
  if (interval.inMinutes >= 1) {
    return 'settingsIntervalMinutes'.tr(args: ['${interval.inMinutes}']);
  }
  return 'settingsIntervalSeconds'.tr(args: ['${interval.inSeconds}']);
}

String _languageDisplayName(Locale locale) {
  switch ('${locale.languageCode}-${locale.countryCode}') {
    case 'en-US':
      return 'English (US)';
    case 'zh-CN':
      return '简体中文';
    case 'zh-TW':
      return '繁體中文';
    default:
      return '${locale.languageCode}-${locale.countryCode}';
  }
}

class _LanguageSwitcher extends StatelessWidget {
  const _LanguageSwitcher();

  @override
  Widget build(BuildContext context) {
    final currentLocale = context.locale;
    final supportedLocales = context.supportedLocales;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'settingsDisplayLanguage'.tr(),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 2),
              Text(
                _languageDisplayName(currentLocale),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        DropdownButton<Locale?>(
          value: supportedLocales.contains(currentLocale)
              ? currentLocale
              : null,
          underline: const SizedBox.shrink(),
          items: [
            for (final locale in supportedLocales)
              DropdownMenuItem<Locale?>(
                value: locale,
                child: Text(_languageDisplayName(locale)),
              ),
            DropdownMenuItem<Locale?>(
              value: null,
              child: Text('languageFollowSystem'.tr()),
            ),
          ],
          onChanged: (Locale? value) {
            if (value != null) {
              context.setLocale(value);
            } else {
              context.resetLocale();
            }
          },
        ),
      ],
    );
  }
}

class _TerminalFontDropdown extends HookConsumerWidget {
  const _TerminalFontDropdown();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fonts = ref.watch(availableTerminalFontsProvider);
    final monoOnly = ref.watch(monospaceTerminalFontsOnlyProvider);
    final current = ref.watch(terminalFontFamilyProvider);

    final all = fonts.value ?? const <TerminalFontOption>[];
    final filtered = <TerminalFontOption>[
      for (final option in all)
        if (!monoOnly || option.label.toLowerCase().contains('mono')) option,
    ];
    if (!filtered.any((option) => option.family == current)) {
      filtered.insert(0, TerminalFontOption(label: current, family: current));
    }

    final loaded = useState<Set<String>>(const {});
    useEffect(
      () {
        var cancelled = false;
        final missing = filtered
            .map((option) => option.family)
            .where((family) => !loaded.value.contains(family))
            .toList();
        if (missing.isEmpty) return null;

        Future<void> loadMissingFonts() async {
          for (final family in missing) {
            if (cancelled) return;
            try {
              await SystemFonts().loadFont(family);
            } on Object {
              // Bundled or unavailable fonts need no engine loading.
            }
            if (cancelled) return;
            loaded.value = {...loaded.value, family};
          }
        }

        unawaited(loadMissingFonts());
        return () => cancelled = true;
      },
      [
        monoOnly,
        filtered.map((option) => option.family).join(','),
        fonts.value,
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownMenu<String>(
              width: constraints.maxWidth,
              enableFilter: true,
              initialSelection: current,
              label: Text('settingsTerminalFont'.tr()),
              onSelected: (family) {
                if (family != null) {
                  ref
                      .read(terminalFontFamilyProvider.notifier)
                      .setFontFamily(family);
                }
              },
              dropdownMenuEntries: [
                for (final option in filtered)
                  DropdownMenuEntry(
                    value: option.family,
                    label: option.label,
                    labelWidget: Text(
                      option.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: option.family),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'settingsTerminalFontHint',
                    style: Theme.of(context).textTheme.bodySmall,
                  ).tr(),
                ),
                const SizedBox(width: 8),
                Text(
                  'settingsTerminalFontMonospaceOnly'.tr(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(width: 4),
                Switch(
                  value: monoOnly,
                  onChanged: (value) => ref
                      .read(monospaceTerminalFontsOnlyProvider.notifier)
                      .setEnabled(value),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _SeedColorTile extends StatelessWidget {
  const _SeedColorTile({required this.seedColor, required this.onEdit});

  final Color seedColor;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: seedColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
      ),
      title: const Text('settingsThemeAccent').tr(),
      subtitle: const Text('settingsThemeAccentHint').tr(),
      trailing: IconButton(
        tooltip: 'settingsThemeEdit'.tr(),
        onPressed: onEdit,
        icon: const Icon(Symbols.edit),
      ),
      onTap: onEdit,
    );
  }
}

class _TerminalThemeTile extends StatelessWidget {
  const _TerminalThemeTile({
    required this.mode,
    required this.theme,
    required this.onEdit,
  });

  final Brightness mode;
  final TerminalColorScheme theme;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final titleKey = mode == Brightness.light
        ? 'settingsTerminalThemeLight'
        : 'settingsTerminalThemeDark';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _TerminalPalettePreview(theme: theme),
      title: Text(titleKey.tr()),
      subtitle: const Text('settingsTerminalThemeHint').tr(),
      trailing: IconButton(
        tooltip: 'settingsTerminalThemeEdit'.tr(),
        onPressed: onEdit,
        icon: const Icon(Symbols.edit),
      ),
      onTap: onEdit,
    );
  }
}

class _TerminalPalettePreview extends StatelessWidget {
  const _TerminalPalettePreview({required this.theme, this.large = false});

  final TerminalColorScheme theme;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: large ? 120 : 64,
      height: large ? 88 : 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Aa',
            style: TextStyle(
              color: theme.foreground,
              fontSize: large ? 16 : 11,
              height: 1,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: GridView.count(
              crossAxisCount: 8,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              mainAxisSpacing: 1,
              crossAxisSpacing: 1,
              children: [
                for (final color in theme.ansiColors)
                  Container(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TerminalThemeDialog extends StatefulWidget {
  const _TerminalThemeDialog({
    required this.brightness,
    required this.initialScheme,
  });

  final Brightness brightness;
  final TerminalColorScheme initialScheme;

  @override
  State<_TerminalThemeDialog> createState() => _TerminalThemeDialogState();
}

class _TerminalThemeDialogState extends State<_TerminalThemeDialog> {
  static const _ansiBaseLabels = [
    'terminalColorBlack',
    'terminalColorRed',
    'terminalColorGreen',
    'terminalColorYellow',
    'terminalColorBlue',
    'terminalColorMagenta',
    'terminalColorCyan',
    'terminalColorWhite',
  ];

  late TerminalColorScheme _scheme;

  @override
  void initState() {
    super.initState();
    _scheme = widget.initialScheme;
  }

  Future<void> _editColor(
    String label,
    Color current,
    ValueChanged<Color> apply,
  ) async {
    final updated = await showDialog<Color>(
      context: context,
      builder: (context) =>
          _ColorEditDialog(title: label, initialColor: current),
    );
    if (updated != null) setState(() => apply(updated));
  }

  void _setAnsi(int index, Color color) {
    final ansi = List<Color>.of(_scheme.ansiColors);
    ansi[index] = color;
    _scheme = _scheme.copyWith(ansiColors: ansi);
  }

  void _save() => Navigator.of(context).pop(_scheme);

  @override
  Widget build(BuildContext context) {
    final titleKey = widget.brightness == Brightness.light
        ? 'settingsTerminalThemeLight'
        : 'settingsTerminalThemeDark';
    final presetId = TerminalColorSchemes.all
        .where((scheme) => scheme.id == _scheme.id)
        .firstOrNull
        ?.id;

    return AlertDialog(
      title: Text(titleKey.tr()),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: presetId ?? 'custom',
                decoration: InputDecoration(
                  labelText: 'settingsTerminalThemePreset'.tr(),
                ),
                items: [
                  for (final scheme in TerminalColorSchemes.all)
                    DropdownMenuItem(
                      value: scheme.id,
                      child: Text(scheme.label),
                    ),
                  DropdownMenuItem(
                    value: 'custom',
                    child: Text('settingsTerminalThemeCustom'.tr()),
                  ),
                ],
                onChanged: (id) {
                  if (id == null || id == 'custom') return;
                  setState(() => _scheme = TerminalColorSchemes.byId(id));
                },
              ),
              const SizedBox(height: 16),
              Center(
                child: _TerminalPalettePreview(theme: _scheme, large: true),
              ),
              const SizedBox(height: 16),
              _TerminalColorRow(
                label: 'settingsTerminalThemeBackground'.tr(),
                color: _scheme.background,
                onTap: () => _editColor(
                  'settingsTerminalThemeBackground'.tr(),
                  _scheme.background,
                  (color) => _scheme = _scheme.copyWith(background: color),
                ),
              ),
              _TerminalColorRow(
                label: 'settingsTerminalThemeForeground'.tr(),
                color: _scheme.foreground,
                onTap: () => _editColor(
                  'settingsTerminalThemeForeground'.tr(),
                  _scheme.foreground,
                  (color) => _scheme = _scheme.copyWith(foreground: color),
                ),
              ),
              _TerminalColorRow(
                label: 'settingsTerminalThemeCursor'.tr(),
                color: _scheme.cursor,
                onTap: () => _editColor(
                  'settingsTerminalThemeCursor'.tr(),
                  _scheme.cursor,
                  (color) => _scheme = _scheme.copyWith(cursor: color),
                ),
              ),
              _TerminalColorRow(
                label: 'settingsTerminalThemeSelection'.tr(),
                color: _scheme.selection,
                onTap: () => _editColor(
                  'settingsTerminalThemeSelection'.tr(),
                  _scheme.selection,
                  (color) => _scheme = _scheme.copyWith(selection: color),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'settingsTerminalThemeNormal'.tr(),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (var i = 0; i < 8; i++)
                _TerminalColorRow(
                  label: _ansiBaseLabels[i].tr(),
                  color: _scheme.ansiColors[i],
                  onTap: () => _editColor(
                    _ansiBaseLabels[i].tr(),
                    _scheme.ansiColors[i],
                    (color) => _setAnsi(i, color),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'settingsTerminalThemeBright'.tr(),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (var i = 0; i < 8; i++)
                _TerminalColorRow(
                  label: 'terminalColorBright'.tr(
                    args: [_ansiBaseLabels[i].tr()],
                  ),
                  color: _scheme.ansiColors[i + 8],
                  onTap: () => _editColor(
                    'terminalColorBright'.tr(args: [_ansiBaseLabels[i].tr()]),
                    _scheme.ansiColors[i + 8],
                    (color) => _setAnsi(i + 8, color),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('commonCancel'.tr()),
        ),
        FilledButton(onPressed: _save, child: Text('settingsThemeSave'.tr())),
      ],
    );
  }
}

class _TerminalColorRow extends StatelessWidget {
  const _TerminalColorRow({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      title: Text(label),
      trailing: Text(
        _hexFor(color),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      onTap: onTap,
    );
  }
}

class _ColorEditDialog extends StatefulWidget {
  const _ColorEditDialog({required this.title, required this.initialColor});

  final String title;
  final Color initialColor;

  @override
  State<_ColorEditDialog> createState() => _ColorEditDialogState();
}

class _ColorEditDialogState extends State<_ColorEditDialog> {
  late final TextEditingController _hexController;
  late int _red;
  late int _green;
  late int _blue;
  String? _colorError;

  @override
  void initState() {
    super.initState();
    final color = widget.initialColor;
    _red = color.r.toInt();
    _green = color.g.toInt();
    _blue = color.b.toInt();
    _hexController = TextEditingController(text: _hexFor(_color));
  }

  Color get _color => Color.fromARGB(255, _red, _green, _blue);

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _updateFromHex(String value) {
    final color = _colorFromHex(value);
    setState(() {
      _colorError = color == null ? 'settingsThemeInvalidColor'.tr() : null;
      if (color != null) {
        _red = color.r.toInt();
        _green = color.g.toInt();
        _blue = color.b.toInt();
      }
    });
  }

  void _updateColor(void Function() update) {
    setState(() {
      update();
      _colorError = null;
      _hexController.text = _hexFor(_color);
    });
  }

  void _save() {
    final color = _colorFromHex(_hexController.text);
    if (color == null) {
      setState(() => _colorError = 'settingsThemeInvalidColor'.tr());
      return;
    }
    Navigator.of(context).pop(color);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _color,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _hexController,
                      maxLength: 7,
                      onChanged: _updateFromHex,
                      decoration: InputDecoration(
                        labelText: 'settingsThemeColor'.tr(),
                        hintText: '#0F766E',
                        errorText: _colorError,
                        counterText: '',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'settingsThemeColorHint'.tr(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              _ColorChannelSlider(
                label: 'R',
                value: _red,
                onChanged: (value) => _updateColor(() => _red = value),
              ),
              _ColorChannelSlider(
                label: 'G',
                value: _green,
                onChanged: (value) => _updateColor(() => _green = value),
              ),
              _ColorChannelSlider(
                label: 'B',
                value: _blue,
                onChanged: (value) => _updateColor(() => _blue = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('commonCancel'.tr()),
        ),
        FilledButton(onPressed: _save, child: Text('settingsThemeSave'.tr())),
      ],
    );
  }
}

class _ColorChannelSlider extends StatelessWidget {
  const _ColorChannelSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 20, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 255,
            divisions: 255,
            label: '$value',
            onChanged: (value) => onChanged(value.round()),
          ),
        ),
        SizedBox(width: 28, child: Text('$value')),
      ],
    );
  }
}

String _hexFor(Color color) =>
    '#${color.r.toInt().toRadixString(16).padLeft(2, '0').toUpperCase()}${color.g.toInt().toRadixString(16).padLeft(2, '0').toUpperCase()}${color.b.toInt().toRadixString(16).padLeft(2, '0').toUpperCase()}';

Color? _colorFromHex(String value) {
  final hex = value.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
  return Color(int.parse('FF$hex', radix: 16));
}
