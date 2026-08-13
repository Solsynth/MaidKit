import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:styled_widget/styled_widget.dart';

import 'package:maid_kit/theme.dart';

import 'container_models.dart';

/// Whether [container] reports a running lifecycle state.
///
/// Paused containers are treated as running so stop/kill/force-remove stay
/// available while start remains disabled.
bool isContainerRunning(ServerContainer container) {
  final state = container.state.toLowerCase();
  return state.contains('running') || state == 'up' || state.contains('paused');
}

/// Whether [container] is paused (cgroups frozen; still exists as running).
bool isContainerPaused(ServerContainer container) {
  return container.state.toLowerCase().contains('paused');
}

/// Compact / table-style list row for a [ServerContainer].
///
/// Used by project detail (with optional live [stats]) and server container
/// management (with optional [trailing] actions). When [wide] is true, CPU /
/// memory / network / block columns are shown; otherwise compact metric text
/// appears under the name when [stats] is present.
class ContainerListTile extends StatelessWidget {
  const ContainerListTile({
    super.key,
    required this.container,
    required this.onOpen,
    this.stats,
    this.wide = false,
    this.trailing,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 12,
    ),
  });

  final ServerContainer container;
  final VoidCallback onOpen;
  final ContainerStats? stats;

  /// When true, shows dedicated metric columns (aligned with a table header).
  final bool wide;

  /// Replaces the default chevron when set (e.g. a popup menu of actions).
  final Widget? trailing;

  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final running = isContainerRunning(container);
    final mono = theme.textTheme.bodySmall?.copyWith(
      fontFamily: MaidKitFonts.mono,
      fontSize: 12,
    );
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: contentPadding,
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Icon(
                    running ? Symbols.play_circle : Symbols.stop_circle,
                    size: 18,
                    color: running ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          container.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          container.image,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (!wide && stats != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            [
                              if (stats!.cpuPercent != null)
                                'CPU ${stats!.cpuPercent!.toStringAsFixed(1)}%',
                              if (stats!.memUsage.isNotEmpty)
                                'Mem ${stats!.memUsage.split('/').first.trim()}',
                            ].join(' · '),
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
                width: 72,
                child: Text(
                  stats?.cpuPercent == null
                      ? '—'
                      : '${stats!.cpuPercent!.toStringAsFixed(1)}%',
                  textAlign: TextAlign.end,
                  style: mono,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 108,
                child: Text(
                  stats == null
                      ? '—'
                      : (stats!.memUsedBytes != null
                            ? formatContainerBytes(stats!.memUsedBytes!)
                            : stats!.memUsage.split('/').first.trim()),
                  textAlign: TextAlign.end,
                  style: mono,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: _IoPairColumn(raw: stats?.netIO ?? '', style: mono),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: _IoPairColumn(raw: stats?.blockIO ?? '', style: mono),
              ),
              const SizedBox(width: 12),
            ],
            SizedBox(
              width: wide ? 100 : 88,
              child: Text(
                container.status,
                textAlign: TextAlign.end,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 4),
            trailing ??
                Icon(
                  Symbols.chevron_right,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
          ],
        ),
      ),
    );
  }
}

/// Formats a byte count with SI-style units (KB/MB/GB/TB).
String formatContainerBytes(int bytes) {
  if (bytes < 1000) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = -1;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  final digits = value >= 100
      ? 0
      : value >= 10
      ? 1
      : 2;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

class _IoPairColumn extends StatelessWidget {
  const _IoPairColumn({required this.raw, required this.style});

  final String raw;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final hasValue = raw.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          hasValue ? (raw.split('/').firstOrNull?.trim() ?? '-') : '-',
          textAlign: TextAlign.end,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
        if (hasValue)
          Text(
            '/ ${raw.split('/').lastOrNull?.trim()}',
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style?.copyWith(fontSize: 10),
          ).opacity(0.75),
      ],
    );
  }
}
