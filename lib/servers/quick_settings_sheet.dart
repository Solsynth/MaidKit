import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'server_providers.dart';

/// Quick-access settings sheet opened from the workspace rail's gear button.
/// Deliberately small: account status, appearance, and a single path to the
/// full settings tab.
Future<void> showQuickSettingsSheet(
  BuildContext context, {
  required VoidCallback onOpenSettings,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (sheetContext) =>
      _QuickSettingsSheet(onOpenSettings: onOpenSettings),
);

class _QuickSettingsSheet extends ConsumerWidget {
  const _QuickSettingsSheet({required this.onOpenSettings});

  /// Switches the workspace to the full settings tab. Called after the sheet
  /// pops so tab navigation runs from the rail's own context.
  final VoidCallback onOpenSettings;

  void _openSettings(BuildContext context) {
    Navigator.of(context).pop();
    onOpenSettings();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeModeProvider);
    final user = ref.watch(cloudUserProvider).asData?.value;

    return SheetScaffold(
      titleText: 'tabSettings'.tr(),
      heightFactor: 0.42,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: colorScheme.surfaceContainerHighest,
              foregroundImage: user?.avatarUrl == null
                  ? null
                  : NetworkImage(user!.avatarUrl!),
              child: user == null
                  ? const Icon(Symbols.person)
                  : Text(
                      user.initials,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
            ),
            title: Text(user?.name ?? 'settingsCloudSignIn'.tr()),
            subtitle: user == null
                ? Text('settingsCloudSignInHint'.tr())
                : (user.handle.isEmpty ? null : Text(user.handle)),
            trailing: const Icon(Symbols.chevron_right, size: 20),
            onTap: () => _openSettings(context),
          ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'settingsTheme'.tr(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
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
          const Divider(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Symbols.tune),
            title: Text('openAllSettings'.tr()),
            trailing: const Icon(Symbols.chevron_right, size: 20),
            onTap: () => _openSettings(context),
          ),
        ],
      ),
    );
  }
}
