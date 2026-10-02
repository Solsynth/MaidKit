import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'maidcafe_stats.dart';
import 'maidcafe_stream.dart';
import 'server_health_chip.dart';

/// The daemon's overview of host health, read straight from
/// `GET /api/v1/health`.
///
/// Every other surface shows only the score that rides each metric sample; this
/// card is where that number is explained — which dimensions the daemon
/// measured, against which thresholds, which ones crossed one, and which ones
/// it left out because they do not apply to the host.
class MaidCafeHealthSection extends StatefulWidget {
  const MaidCafeHealthSection({super.key, required this.session});

  final MaidCafeStreamSession session;

  @override
  State<MaidCafeHealthSection> createState() => _MaidCafeHealthSectionState();
}

class _MaidCafeHealthSectionState extends State<MaidCafeHealthSection> {
  MaidCafeHealthReport? _report;
  var _loading = true;
  String? _error;

  /// A daemon older than the health feature answers its 404 for the route
  /// itself, which says something about the daemon rather than about this
  /// read: it is not an error the user can retry away.
  var _unsupported = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(MaidCafeHealthSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _unsupported = false;
    });
    try {
      final response = await widget.session.healthReport();
      final report = parseMaidCafeHealthReport(response);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _report = report;
        _error = report == null ? 'commonSomethingWentWrong'.tr() : null;
      });
    } on MaidCafeRouteMissingException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _unsupported = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final report = _report;
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'detailHealth'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'commonRefresh'.tr(),
                  visualDensity: VisualDensity.compact,
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Symbols.refresh, size: 18),
                ),
              ],
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(right: 8, top: 8),
                child: LinearProgressIndicator(minHeight: 2),
              )
            else if (_unsupported)
              _note(
                scheme,
                theme,
                Symbols.help,
                'maidCafeHealthUnsupported'.tr(),
              )
            else if (_error != null)
              _note(scheme, theme, Symbols.error, _error!)
            else if (report != null)
              _reportBody(report),
          ],
        ),
      ),
    );
  }

  Widget _note(
    ColorScheme scheme,
    ThemeData theme,
    IconData icon,
    String message,
  ) => Padding(
    padding: const EdgeInsets.only(right: 8, top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _reportBody(MaidCafeHealthReport report) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final health = report.health;
    final issues = report.issues;
    final evaluatedAt = report.evaluatedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 8, top: 4),
          child: Row(
            children: [
              Text(
                '${health.score}',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: serverHealthStatusColor(health.status, scheme),
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'maidCafeHealthOutOf'.tr(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      serverHealthStatusLabel(health.status),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: serverHealthStatusColor(health.status, scheme),
                      ),
                    ),
                    Text(
                      issues.isEmpty
                          ? 'maidCafeHealthAllWithinThresholds'.tr()
                          : 'maidCafeHealthIssueCount'.tr(
                              args: ['${issues.length}'],
                            ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (evaluatedAt != null)
                Tooltip(
                  message: 'maidCafeHealthEvaluatedAt'.tr(
                    args: [
                      DateFormat(
                        'yyyy-MM-dd HH:mm:ss',
                      ).format(evaluatedAt.toLocal()),
                    ],
                  ),
                  child: Text(
                    DateFormat('HH:mm:ss').format(evaluatedAt.toLocal()),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.outline,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Divider(color: scheme.outlineVariant, height: 20),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final check in report.checks) _checkRow(check)],
          ),
        ),
      ],
    );
  }

  Widget _checkRow(MaidCafeHealthCheck check) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final skipped = check.skipped;
    final crossed = !skipped && check.status != MaidCafeHealthCheckStatus.ok;
    final color = skipped
        ? scheme.onSurfaceVariant
        : _checkColor(check.status, scheme);
    final label = [
      _checkLabel(check.name),
      if (check.detail.isNotEmpty) check.detail,
    ].join(' · ');
    final note = skipped
        ? 'maidCafeHealthNotApplicable'.tr()
        : crossed
        ? 'maidCafeHealthThresholds'.tr(
            args: [
              formatMaidCafeHealthValue(check.unit, check.warn),
              formatMaidCafeHealthValue(check.unit, check.crit),
            ],
          )
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                if (note != null)
                  Text(
                    note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            skipped ? '—' : formatMaidCafeHealthValue(check.unit, check.value),
            style: theme.textTheme.labelMedium?.copyWith(
              color: crossed ? color : scheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  /// The color a scored dimension reads in. Unlike the headline band an `ok`
  /// dimension is deliberately quiet: only a dimension above its warning
  /// threshold is worth coloring across seven rows.
  Color _checkColor(MaidCafeHealthCheckStatus status, ColorScheme scheme) =>
      switch (status) {
        MaidCafeHealthCheckStatus.ok => scheme.onSurfaceVariant,
        MaidCafeHealthCheckStatus.warning => scheme.tertiary,
        MaidCafeHealthCheckStatus.critical => scheme.error,
      };

  /// The dimension's name in the reader's language. A dimension this build does
  /// not know — a daemon newer than the app — keeps its wire name instead of
  /// being dropped.
  String _checkLabel(String name) => switch (name) {
    'cpu' => 'maidCafeHealthCheckCpu'.tr(),
    'memory' => 'maidCafeHealthCheckMemory'.tr(),
    'swap' => 'maidCafeHealthCheckSwap'.tr(),
    'disk' => 'maidCafeHealthCheckDisk'.tr(),
    'load' => 'maidCafeHealthCheckLoad'.tr(),
    'process_memory' => 'maidCafeHealthCheckProcessMemory'.tr(),
    'webhooks' => 'maidCafeHealthCheckWebhooks'.tr(),
    _ => name,
  };
}
