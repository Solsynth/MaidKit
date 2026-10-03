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
class ContainerUpdateBadge extends StatelessWidget {
  const ContainerUpdateBadge({super.key, required this.status});

  final ContainerUpdateStatus status;

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
    return Tooltip(message: detail, child: badge);
  }
}
