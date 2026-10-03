import 'package:easy_localization/easy_localization.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'container_models.dart';

/// The update badge for one container.
///
/// It renders only when the daemon has an update to report: the registry
/// publishes an image the container is not running ([ContainerUpdateStatus
/// .outdated] is true), or the local image store already holds a newer image
/// and a recreate applies it without downloading anything
/// ([ContainerUpdateStatus.restartRequired]). An unanswered check — a null
/// [ContainerUpdateStatus.outdated] — draws nothing rather than claiming the
/// container is current.
///
/// Nothing here reads a registry: every answer comes from the daemon's own
/// cache, which is what makes it cheap enough for a list row.
///
/// When [onAction] is set the badge is also where the update is acted on: a tap
/// offers the daemon's two verbs (`pull`, `update`), so a user who notices the
/// badge does not have to find the same options in a menu elsewhere. Without it
/// — a container whose daemon route is not open — the badge stays a label.
class ContainerUpdateBadge extends StatelessWidget {
  const ContainerUpdateBadge({super.key, required this.status, this.onAction});

  final ContainerUpdateStatus status;

  /// Runs one daemon verb for this container: `pull` fetches the image the
  /// container was created from without touching what is running, `update`
  /// pulls and then recreates a compose-managed container on it. Null hides
  /// the affordance entirely.
  final Future<void> Function(String verb)? onAction;

  /// Asks which verb to run. It is a sheet rather than a menu so the image
  /// being updated stays on screen while the choice is made.
  Future<void> _askAndRun(BuildContext context) async {
    final action = onAction;
    if (action == null) return;
    final verb = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Symbols.upgrade),
              title: Text(status.name.isEmpty ? status.container : status.name),
              subtitle: status.image.isEmpty
                  ? null
                  : Text(
                      status.image,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              enabled: false,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Symbols.upgrade),
              title: Text('containerUpdate'.tr()),
              onTap: () => Navigator.of(context).pop('update'),
            ),
            ListTile(
              leading: const Icon(Symbols.download),
              title: Text('containerPull'.tr()),
              onTap: () => Navigator.of(context).pop('pull'),
            ),
          ],
        ),
      ),
    );
    if (verb != null) await action(verb);
  }

  @override
  Widget build(BuildContext context) {
    if (!status.hasUpdate) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label =
        (status.restartRequired && status.outdated != true
                ? 'containerRestartToUpdate'
                : 'containerUpdateAvailable')
            .tr();
    final color = scheme.tertiaryContainer;
    final onColor = scheme.onTertiaryContainer;
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.upgrade, size: 14, color: onColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(color: onColor),
            ),
          ),
        ],
      ),
    );
    final detail = status.image.isEmpty ? label : '${status.image}\n$label';
    if (onAction == null) return Tooltip(message: detail, child: badge);
    return Tooltip(
      message: detail,
      child: InkWell(
        onTap: () => _askAndRun(context),
        borderRadius: BorderRadius.circular(6),
        child: badge,
      ),
    );
  }
}
