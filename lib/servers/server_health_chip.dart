import 'package:easy_localization/easy_localization.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'server_models.dart';

/// The color a health band reads in, using the app's existing status
/// vocabulary: primary while healthy, tertiary (warning) when degraded, error
/// when critical.
Color serverHealthStatusColor(ServerHealthStatus status, ColorScheme scheme) =>
    switch (status) {
      ServerHealthStatus.healthy => scheme.primary,
      ServerHealthStatus.degraded => scheme.tertiary,
      ServerHealthStatus.critical => scheme.error,
    };

/// The translated name of a health band, for surfaces that name it in words
/// rather than only coloring it.
String serverHealthStatusLabel(ServerHealthStatus status) => switch (status) {
  ServerHealthStatus.healthy => 'healthStatusHealthy'.tr(),
  ServerHealthStatus.degraded => 'healthStatusDegraded'.tr(),
  ServerHealthStatus.critical => 'healthStatusCritical'.tr(),
};

/// A compact readout of a MaidCafe host's health: the daemon's score in its
/// band's color, with the band named in the tooltip.
///
/// A null [health] renders nothing at all, so a route that cannot score health
/// (the SSH collectors) and a daemon older than the health feature show no
/// health affordance rather than an empty one.
///
/// [stale] marks a reading that no longer describes the host — the cloud's
/// heartbeat rule — and renders it in the neutral outline color, so a stale
/// number is never read as a live one.
class ServerHealthChip extends StatelessWidget {
  const ServerHealthChip({
    super.key,
    required this.health,
    this.stale = false,
    this.compact = false,
  });

  final ServerHealth? health;
  final bool stale;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final value = health;
    if (value == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = stale
        ? scheme.onSurfaceVariant
        : serverHealthStatusColor(value.status, scheme);
    final score = '${value.score}';
    final band = serverHealthStatusLabel(value.status);
    return Tooltip(
      message: stale
          ? 'healthChipStale'.tr(args: [score, band])
          : 'healthChipLive'.tr(args: [score, band]),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 6 : 8,
            vertical: compact ? 1 : 3,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Symbols.monitor_heart,
                size: compact ? 12 : 14,
                color: color,
              ),
              const SizedBox(width: 4),
              Text(
                score,
                style:
                    (compact
                            ? theme.textTheme.labelSmall
                            : theme.textTheme.labelMedium)
                        ?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
