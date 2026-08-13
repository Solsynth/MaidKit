import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/theme.dart';

import 'container_models.dart';

/// Compact / table-style list row for a [ServerContainerImage].
///
/// Mirrors [ContainerListTile]: name + secondary line on the left, optional
/// wide metric columns, and a status-sized trailing column (size) with either
/// a chevron or a custom [trailing] control (e.g. remove menu).
class ContainerImageListTile extends StatelessWidget {
  const ContainerImageListTile({
    super.key,
    required this.image,
    this.onOpen,
    this.wide = false,
    this.trailing,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 12,
    ),
  });

  final ServerContainerImage image;
  final VoidCallback? onOpen;
  final bool wide;
  final Widget? trailing;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mono = theme.textTheme.bodySmall?.copyWith(
      fontFamily: MaidKitFonts.mono,
      fontSize: 12,
    );
    final title = image.reference;
    final subtitle = image.id;
    final mutedIcon = image.unused || image.isDangling;

    final row = Padding(
      padding: contentPadding,
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(
                  image.isDangling ? Symbols.broken_image : Symbols.image,
                  size: 18,
                  color: mutedIcon ? scheme.onSurfaceVariant : scheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          if (image.unused) ...[
                            const SizedBox(width: 8),
                            _UnusedLabel(dangling: image.isDangling),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontFamily: MaidKitFonts.mono,
                        ),
                      ),
                      if (!wide && image.created.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          image.created,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (wide) ...[
            SizedBox(
              width: 88,
              child: Text(
                image.size.isEmpty ? '—' : image.size,
                textAlign: TextAlign.end,
                style: mono,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: Text(
                image.created.isEmpty ? '—' : image.created,
                textAlign: TextAlign.end,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ] else
            SizedBox(
              width: 88,
              child: Text(
                image.size.isEmpty ? '—' : image.size,
                textAlign: TextAlign.end,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFamily: MaidKitFonts.mono,
                ),
              ),
            ),
          if (trailing != null) ...[
            const SizedBox(width: 4),
            trailing!,
          ] else if (onOpen != null) ...[
            const SizedBox(width: 4),
            Icon(
              Symbols.chevron_right,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );

    if (onOpen == null) return row;
    return InkWell(onTap: onOpen, child: row);
  }
}

class _UnusedLabel extends StatelessWidget {
  const _UnusedLabel({required this.dangling});

  final bool dangling;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = dangling
        ? 'imagesPruneDanglingLabel'.tr()
        : 'imagesPruneUnusedLabel'.tr();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onTertiaryContainer,
        ),
      ),
    );
  }
}
