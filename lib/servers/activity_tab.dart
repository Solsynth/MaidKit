import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'activity_models.dart';
import 'server_providers.dart';

/// Live host performance graphs (btop-inspired) for a single connected server.
class ActivityTab extends ConsumerStatefulWidget {
  const ActivityTab({
    super.key,
    required this.server,
    required this.connected,
    required this.connectionError,
    required this.onConnect,
    required this.refreshInterval,
  });

  final Server server;
  final bool connected;
  final String? connectionError;
  final Future<void> Function() onConnect;
  final Duration refreshInterval;

  @override
  ConsumerState<ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends ConsumerState<ActivityTab> {
  static const _historyLimit = 60;

  final List<ActivitySample> _history = [];
  ActivityCounters? _previous;
  Timer? _timer;
  var _loading = false;
  var _hasSample = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
    }
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(ActivityTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connected &&
        (!oldWidget.connected || oldWidget.server.id != widget.server.id)) {
      _history.clear();
      _previous = null;
      _hasSample = false;
      _error = null;
      _poll();
    }
    if (oldWidget.refreshInterval != widget.refreshInterval) {
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.refreshInterval, (_) => _poll());
  }

  Future<void> _poll() async {
    if (!mounted || !widget.connected || _loading) return;
    _loading = true;
    try {
      final counters = await ref
          .read(connectionManagerProvider)
          .collectActivityCounters(widget.server.id);
      final sample = counters.toSample(previous: _previous);
      _previous = counters;
      if (!mounted) return;
      setState(() {
        _hasSample = true;
        _error = null;
        // First sample often has no CPU/net rates; still keep it for memory/load.
        _history.add(sample);
        while (_history.length > _historyLimit) {
          _history.removeAt(0);
        }
      });
    } catch (error) {
      if (mounted && !_hasSample) {
        setState(() => _error = error.toString());
      }
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.connected) {
      return _ActivityEmpty(
        icon: Symbols.link_off,
        message: widget.connectionError ?? 'activityConnectToStream'.tr(),
        actionLabel: 'detailConnectForMetrics'.tr(),
        onAction: widget.onConnect,
        filled: true,
      );
    }
    if (_error != null && _history.isEmpty) {
      return _ActivityEmpty(
        icon: Symbols.error_outline,
        message: 'activityError'.tr(args: [_error!]),
        actionLabel: 'commonRetry'.tr(),
        onAction: _poll,
      );
    }
    if (_history.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final latest = _history.last;
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
          child: Row(
            children: [
              Text(
                'activityLiveActivity'.tr(),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              if (latest.uptime != null)
                Text(
                  'activityUptime'.tr(args: [_formatUptime(latest.uptime!)]),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              const Spacer(),
              IconButton(
                tooltip: 'activityRefreshNow'.tr(),
                visualDensity: VisualDensity.compact,
                onPressed: _poll,
                icon: const Icon(Symbols.refresh),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            children: [
              _SummaryRow(sample: latest),
              const SizedBox(height: 12),
              _ChartCard(
                title: 'detailCpu'.tr(),
                subtitle: latest.cpuPercent == null
                    ? (latest.cpuCount == null
                          ? '—'
                          : '${latest.cpuCount} cores · load ${latest.load1?.toStringAsFixed(2) ?? '—'}')
                    : '${latest.cpuPercent!.toStringAsFixed(1)}% · '
                          'load ${latest.load1?.toStringAsFixed(2) ?? '—'} '
                          '(${latest.cpuCount ?? '—'} cores)',
                color: scheme.primary,
                child: _PercentLineChart(
                  history: _history,
                  color: scheme.primary,
                  valueOf: (s) => s.cpuPercent ?? s.loadPercent,
                  maxY: 100,
                ),
              ),
              const SizedBox(height: 8),
              _ChartCard(
                title: 'detailMemory'.tr(),
                subtitle: _memSubtitle(latest),
                color: scheme.tertiary,
                footer: _hasSwap(latest) ? _SwapFooter(sample: latest) : null,
                child: _PercentLineChart(
                  history: _history,
                  color: scheme.tertiary,
                  valueOf: (s) => s.memoryPercent,
                  maxY: 100,
                ),
              ),
              const SizedBox(height: 8),
              _ChartCard(
                title: 'activityNetwork'.tr(),
                // Cool teal for RX vs warm amber for TX — primary/secondary from
                // the seed are too close in hue to read as separate series.
                color: _netRxColor(scheme),
                subtitleWidget: _NetSubtitle(
                  sample: latest,
                  rxColor: _netRxColor(scheme),
                  txColor: _netTxColor(scheme),
                ),
                child: _NetworkLineChart(
                  history: _history,
                  rxColor: _netRxColor(scheme),
                  txColor: _netTxColor(scheme),
                ),
              ),
              const SizedBox(height: 8),
              _DiskCard(sample: latest),
            ],
          ),
        ),
      ],
    );
  }

  bool _hasSwap(ActivitySample s) =>
      s.swapTotalKb != null && s.swapTotalKb! > 0;

  String _memSubtitle(ActivitySample s) {
    if (s.memoryUsedKb == null || s.memoryTotalKb == null) return '—';
    return '${_formatKb(s.memoryUsedKb!)} / ${_formatKb(s.memoryTotalKb!)}'
        '${s.memoryPercent == null ? '' : ' · ${s.memoryPercent!.toStringAsFixed(0)}%'}';
  }
}

/// Download (RX) — cool teal, distinct from warm TX.
Color _netRxColor(ColorScheme scheme) => scheme.brightness == Brightness.dark
    ? const Color(0xFF2DD4BF)
    : const Color(0xFF0F766E);

/// Upload (TX) — warm amber, high hue contrast against RX teal.
Color _netTxColor(ColorScheme scheme) => scheme.brightness == Brightness.dark
    ? const Color(0xFFFBBF24)
    : const Color(0xFFD97706);

class _NetSubtitle extends StatelessWidget {
  const _NetSubtitle({
    required this.sample,
    required this.rxColor,
    required this.txColor,
  });

  final ActivitySample sample;
  final Color rxColor;
  final Color txColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    if (sample.netRxBps == null && sample.netTxBps == null) {
      return Text(
        'activityWaitingForRateSample'.tr(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
        style: theme.textTheme.labelSmall?.copyWith(color: muted),
      );
    }
    final base = theme.textTheme.labelSmall;
    return Text.rich(
      TextSpan(
        style: base?.copyWith(color: muted),
        children: [
          TextSpan(
            text: '↓ ${_formatBps(sample.netRxBps)}',
            style: TextStyle(color: rxColor, fontWeight: FontWeight.w600),
          ),
          const TextSpan(text: '  '),
          TextSpan(
            text: '↑ ${_formatBps(sample.netTxBps)}',
            style: TextStyle(color: txColor, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.end,
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.sample});

  final ActivitySample sample;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 520;
        final tiles = [
          _StatTile(
            label: 'detailCpu'.tr(),
            value: sample.cpuPercent == null
                ? '—'
                : '${sample.cpuPercent!.toStringAsFixed(0)}%',
            detail: sample.load1 == null
                ? null
                : 'load ${sample.load1!.toStringAsFixed(2)}',
          ),
          _StatTile(
            label: 'detailMemory'.tr(),
            value: sample.memoryPercent == null
                ? '—'
                : '${sample.memoryPercent!.toStringAsFixed(0)}%',
            detail: sample.memoryUsedKb == null
                ? null
                : _formatKb(sample.memoryUsedKb!),
          ),
          _StatTile(
            label: 'detailRootDisk'.tr(),
            value: sample.diskPercent == null
                ? '—'
                : '${sample.diskPercent!.toStringAsFixed(0)}%',
            detail: sample.diskUsedKb == null
                ? null
                : _formatKb(sample.diskUsedKb!),
          ),
          _StatTile(
            label: 'activityNetworkDown'.tr(),
            value: _formatBps(sample.netRxBps),
            detail: sample.netTxBps == null
                ? null
                : '↑ ${_formatBps(sample.netTxBps)}',
          ),
        ];
        if (wide) {
          return Row(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: tiles[i]),
              ],
            ],
          );
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tile in tiles)
              SizedBox(width: (constraints.maxWidth - 8) / 2, child: tile),
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.detail});

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(value, style: theme.textTheme.titleMedium),
            if (detail != null) ...[
              const SizedBox(height: 2),
              Text(
                detail!,
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
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.color,
    required this.child,
    this.subtitle,
    this.subtitleWidget,
    this.footer,
  }) : assert(
         subtitle != null || subtitleWidget != null,
         'Provide subtitle or subtitleWidget',
       );

  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final Color color;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final trailing =
        subtitleWidget ??
        Text(
          subtitle!,
          textAlign: TextAlign.end,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleSmall),
                const Spacer(),
                Flexible(child: trailing),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(height: 120, child: child),
            if (footer != null) ...[const SizedBox(height: 8), footer!],
          ],
        ),
      ),
    );
  }
}

/// Compact root-disk usage — not a time-series chart, so no empty chart area.
class _DiskCard extends StatelessWidget {
  const _DiskCard({required this.sample});

  final ActivitySample sample;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = ((sample.diskPercent ?? 0) / 100).clamp(0.0, 1.0);
    final subtitle = sample.diskUsedKb == null || sample.diskTotalKb == null
        ? '—'
        : '${_formatKb(sample.diskUsedKb!)} / ${_formatKb(sample.diskTotalKb!)}'
              '${sample.diskPercent == null ? '' : ' · ${sample.diskPercent!.toStringAsFixed(0)}%'}';

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: scheme.outline,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text('detailRootDisk'.tr(), style: theme.textTheme.titleSmall),
                const Spacer(),
                Flexible(
                  child: Text(
                    subtitle,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHighest,
                color: progress >= 0.9
                    ? scheme.error
                    : progress >= 0.75
                    ? scheme.tertiary
                    : scheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Swap belongs with memory, not root disk.
class _SwapFooter extends StatelessWidget {
  const _SwapFooter({required this.sample});

  final ActivitySample sample;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = ((sample.swapPercent ?? 0) / 100).clamp(0.0, 1.0);
    final used = sample.swapUsedKb;
    final total = sample.swapTotalKb;
    final label = used == null || total == null
        ? 'detailSwap'.tr(args: ['—', '—'])
        : 'detailSwap'.tr(args: [_formatKb(used), _formatKb(total)]);
    final percent = sample.swapPercent == null
        ? ''
        : ' · ${sample.swapPercent!.toStringAsFixed(0)}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$label$percent',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: scheme.surfaceContainerHighest,
            color: scheme.tertiary.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }
}

class _PercentLineChart extends StatelessWidget {
  const _PercentLineChart({
    required this.history,
    required this.color,
    required this.valueOf,
    required this.maxY,
  });

  final List<ActivitySample> history;
  final Color color;
  final double? Function(ActivitySample) valueOf;
  final double maxY;

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    for (var i = 0; i < history.length; i++) {
      final value = valueOf(history[i]);
      if (value == null) continue;
      spots.add(FlSpot(i.toDouble(), value.clamp(0, maxY)));
    }
    if (spots.isEmpty) {
      return Center(
        child: Text(
          'activityCollectingSamples'.tr(),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: math.max(history.length - 1, 1).toDouble(),
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (value) => FlLine(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: maxY / 2,
              getTitlesWidget: (value, meta) => Text(
                '${value.toInt()}%',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => scheme.inverseSurface,
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            getTooltipItems: (touched) => touched
                .map(
                  (spot) => LineTooltipItem(
                    '${spot.y.toStringAsFixed(1)}%',
                    TextStyle(
                      color: scheme.onInverseSurface,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            color: color,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }
}

class _NetworkLineChart extends StatelessWidget {
  const _NetworkLineChart({
    required this.history,
    required this.rxColor,
    required this.txColor,
  });

  final List<ActivitySample> history;
  final Color rxColor;
  final Color txColor;

  @override
  Widget build(BuildContext context) {
    final rxSpots = <FlSpot>[];
    final txSpots = <FlSpot>[];
    var maxRate = 1.0;
    for (var i = 0; i < history.length; i++) {
      final sample = history[i];
      if (sample.netRxBps != null) {
        final kbps = sample.netRxBps! / 1024;
        rxSpots.add(FlSpot(i.toDouble(), kbps));
        maxRate = math.max(maxRate, kbps);
      }
      if (sample.netTxBps != null) {
        final kbps = sample.netTxBps! / 1024;
        txSpots.add(FlSpot(i.toDouble(), kbps));
        maxRate = math.max(maxRate, kbps);
      }
    }
    if (rxSpots.isEmpty && txSpots.isEmpty) {
      return Center(
        child: Text(
          'activityCollectingNetworkRates'.tr(),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final maxY = maxRate * 1.15;
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: math.max(history.length - 1, 1).toDouble(),
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (value, meta) {
                if (value == meta.max || value == meta.min) {
                  return const SizedBox.shrink();
                }
                return Text(
                  _shortRate(value * 1024),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => scheme.inverseSurface,
            maxContentWidth: 160,
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            fitInsideHorizontally: true,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final isTx = spot.bar.color == txColor;
                // Chart y is KiB/s; convert back to B/s for shared formatter.
                final bps = spot.y * 1024;
                final prefix = isTx ? '↑' : '↓';
                final seriesColor = isTx ? txColor : rxColor;
                return LineTooltipItem(
                  '$prefix ${_formatBps(bps)}',
                  TextStyle(
                    color: seriesColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          if (rxSpots.isNotEmpty)
            LineChartBarData(
              spots: rxSpots,
              isCurved: true,
              curveSmoothness: 0.2,
              color: rxColor,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: rxColor.withValues(alpha: 0.08),
              ),
            ),
          if (txSpots.isNotEmpty)
            LineChartBarData(
              spots: txSpots,
              isCurved: true,
              curveSmoothness: 0.2,
              color: txColor,
              barWidth: 2,
              dotData: const FlDotData(show: false),
            ),
        ],
      ),
      duration: Duration.zero,
    );
  }

  String _shortRate(double bps) {
    if (bps < 1024) return '${bps.toStringAsFixed(0)}B';
    if (bps < 1024 * 1024) return '${(bps / 1024).toStringAsFixed(0)}K';
    return '${(bps / (1024 * 1024)).toStringAsFixed(1)}M';
  }
}

class _ActivityEmpty extends StatelessWidget {
  const _ActivityEmpty({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.filled = false,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              if (filled)
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Symbols.link),
                  label: Text(actionLabel!),
                )
              else
                OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatKb(int value) {
  const kbPerGb = 1024 * 1024;
  return value >= kbPerGb
      ? '${(value / kbPerGb).toStringAsFixed(1)} GB'
      : '${(value / 1024).toStringAsFixed(0)} MB';
}

String _formatBps(double? bps) {
  if (bps == null) return '—';
  if (bps < 1024) return '${bps.toStringAsFixed(0)} B/s';
  if (bps < 1024 * 1024) return '${(bps / 1024).toStringAsFixed(1)} KB/s';
  if (bps < 1024 * 1024 * 1024) {
    return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
  return '${(bps / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB/s';
}

String _formatUptime(Duration uptime) {
  if (uptime.inSeconds == 0) return '—';
  final days = uptime.inDays;
  final hours = uptime.inHours.remainder(24);
  final minutes = uptime.inMinutes.remainder(60);
  if (days > 0) return '${days}d ${hours}h';
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}
