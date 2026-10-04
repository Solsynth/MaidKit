import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'cloud_sync_service.dart';
import 'server_providers.dart';
import 'terminal_tabs_provider.dart';

/// The workspace's account button: the signed-in Solarpass user's picture,
/// opening the MaidCafe cloud console.
///
/// The picture is the "who is signed in" readout — the account overview and
/// the sign-in entry both live on the cloud console, so one tap gets there
/// from anywhere in the workspace. With no account linked the button keeps its
/// slot, drops the picture for a neutral icon, and takes the same route.
class CloudAccountButton extends ConsumerWidget {
  const CloudAccountButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final user = ref.watch(cloudUserProvider).value;
    final avatarUrl = user?.avatarUrl;

    return IconButton(
      tooltip: user == null
          ? 'settingsCloudSignIn'.tr()
          : 'settingsCloudSignedInAs'.tr(args: [accountLabel(user)]),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      onPressed: () =>
          ref.read(terminalTabsProvider.notifier).openMaidCafeCloud(),
      icon: user == null
          ? const Icon(Symbols.account_circle, size: 24)
          : CircleAvatar(
              radius: 12,
              backgroundColor: scheme.primaryContainer,
              foregroundImage: avatarUrl == null
                  ? null
                  : NetworkImage(avatarUrl),
              child: Text(
                user.initials,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
    );
  }
}

/// The display name with the Solar handle beside it when the account has one,
/// so two accounts sharing a display name still read as different people.
String accountLabel(CloudUser user) {
  final handle = user.handle.trim();
  return handle.isEmpty ? user.name : '${user.name} ($handle)';
}
