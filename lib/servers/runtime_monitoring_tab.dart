import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'server_models.dart';
import 'server_providers.dart';

/// Runtimes tab on the server detail page: per-runtime cards (java/dotnet/
/// python) with process summaries and Java JVM/GC detail, plus per-runtime
/// enable toggles persisted in Drift. The snapshot arrives via the MaidCafe
/// SSE/one-shot channel or the direct-SSH fallback; the page owns that
/// plumbing, this tab only renders.
class RuntimeMonitoringTab extends ConsumerStatefulWidget {
  const RuntimeMonitoringTab({
    super.key,
    required this.server,
    required this.connected,
    this.connectionError,
    required this.onConnect,
    required this.snapshot,
    required this.onRefresh,
  });

  final Server server;
  final bool connected;
  final String? connectionError;
  final Future<void> Function() onConnect;
  final AsyncValue<RuntimeSnapshot> snapshot;
  final Future<void> Function() onRefresh;

  @override
  ConsumerState<RuntimeMonitoringTab> createState() =>
      _RuntimeMonitoringTabState();
}

class _RuntimeMonitoringTabState extends ConsumerState<RuntimeMonitoringTab> {
  String _runtimeLabel(RuntimeKind kind) => switch (kind) {
    RuntimeKind.java => 'Java',
    RuntimeKind.dotnet => '.NET',
    RuntimeKind.python => 'Python',
  };

  Future<void> _setRuntimeEnabled(RuntimeKind kind, bool enabled) {
    return ref
        .read(serverRepositoryProvider)
        .setRuntimeEnabled(widget.server.id, kind, enabled);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.connected) {
      return _RuntimeEmptyPanel(
        icon: Symbols.link_off,
        message: widget.connectionError ?? 'detailConnectToCollect'.tr(),
        actionLabel: 'detailConnectForMetrics'.tr(),
        actionIcon: Symbols.link,
        onAction: widget.onConnect,
        filledAction: true,
      );
    }
    final configs =
        ref.watch(runtimeWatchConfigsProvider(widget.server.id)).value ??
        const <RuntimeWatchConfig>[];
    final enabledByKind = <RuntimeKind, bool>{
      for (final kind in RuntimeKind.values) kind: true,
    };
    for (final config in configs) {
      final kind = RuntimeKindFromWire(config.runtime);
      if (kind != null) enabledByKind[kind] = config.enabled;
    }
    final enabledKinds = RuntimeKind.values
        .where((kind) => enabledByKind[kind] ?? true)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final kind in RuntimeKind.values)
                      _RuntimeToggle(
                        label: _runtimeLabel(kind),
                        enabled: enabledByKind[kind] ?? true,
                        onChanged: (value) => _setRuntimeEnabled(kind, value),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'runtimeRefresh'.tr(),
                onPressed: widget.onRefresh,
                icon: const Icon(Symbols.refresh),
              ),
            ],
          ),
        ),
        Expanded(
          child: widget.snapshot.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _RuntimeEmptyPanel(
              icon: Symbols.error_outline,
              message: 'detailCouldNotRetrieveRuntimes'.tr(args: ['$error']),
              actionLabel: 'commonRetry'.tr(),
              onAction: widget.onRefresh,
            ),
            data: (snapshot) {
              final byKind = {
                for (final group in snapshot.groups) group.kind: group,
              };
              final cards = [
                for (final kind in enabledKinds)
                  if (byKind[kind] != null)
                    _RuntimeCard(
                      group: byKind[kind]!,
                      onRefresh: widget.onRefresh,
                    ),
              ];
              if (cards.isEmpty) {
                return _RuntimeEmptyPanel(
                  icon: Symbols.code_blocks,
                  message: 'runtimeNoDetectedRuntimes'.tr(),
                  actionLabel: 'commonRefresh'.tr(),
                  onAction: widget.onRefresh,
                );
              }
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final card in cards) SizedBox(width: 440, child: card),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One compact enable/disable switch in the header row.
class _RuntimeToggle extends StatelessWidget {
  const _RuntimeToggle({
    required this.label,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 2),
        Switch(
          value: enabled,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }
}

/// One runtime's card: availability state, summary tiles, per-process rows and
/// (java only) JDK badge + JVM rows.
class _RuntimeCard extends StatelessWidget {
  const _RuntimeCard({required this.group, required this.onRefresh});

  final RuntimeGroup group;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RuntimeCardHeader(group: group),
            const SizedBox(height: 10),
            _RuntimeSummaryTiles(group: group),
            const SizedBox(height: 10),
            if (!group.available)
              _RuntimeUnavailable(group: group)
            else ...[
              _ProcessHeaderRow(),
              const SizedBox(height: 4),
              for (final process in group.processes)
                _RuntimeProcessRow(process: process),
            ],
            if (group.java != null) ...[
              const SizedBox(height: 12),
              _JavaSection(java: group.java!, onRefresh: onRefresh),
            ],
          ],
        ),
      ),
    );
  }
}

class _RuntimeCardHeader extends StatelessWidget {
  const _RuntimeCardHeader({required this.group});

  final RuntimeGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final icon = switch (group.kind) {
      RuntimeKind.java => Symbols.coffee,
      RuntimeKind.dotnet => Symbols.deployed_code,
      RuntimeKind.python => Symbols.code,
    };
    final label = switch (group.kind) {
      RuntimeKind.java => 'Java',
      RuntimeKind.dotnet => '.NET',
      RuntimeKind.python => 'Python',
    };
    return Row(
      children: [
        Icon(icon, size: 20, color: scheme.primary),
        const SizedBox(width: 8),
        Text(label, style: theme.textTheme.titleSmall),
        const Spacer(),
        if (group.available)
          Icon(Symbols.check_circle, size: 18, color: scheme.primary)
        else
          Icon(
            Symbols.remove_circle_outline,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
      ],
    );
  }
}

/// Summary row: process count, Σcpu%, ΣRSS, Σthreads.
class _RuntimeSummaryTiles extends StatelessWidget {
  const _RuntimeSummaryTiles({required this.group});

  final RuntimeGroup group;

  @override
  Widget build(BuildContext context) {
    final processes = group.processes;
    final cpuTotal = processes.fold<double>(
      0,
      (sum, process) => sum + process.cpuPercent,
    );
    final rssTotal = processes.fold<int>(
      0,
      (sum, process) => sum + process.rssKb,
    );
    var threadTotal = 0;
    var threadCount = 0;
    for (final process in processes) {
      if (process.threads != null) {
        threadTotal += process.threads!;
        threadCount++;
      }
    }
    return Row(
      children: [
        Expanded(
          child: _RuntimeStatTile(
            label: 'runtimeProcessCount',
            value: '${processes.length}',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _RuntimeStatTile(
            label: 'runtimeCpuTotal',
            value: '${cpuTotal.toStringAsFixed(1)}%',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _RuntimeStatTile(
            label: 'runtimeRssTotal',
            value: _formatKb(rssTotal),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _RuntimeStatTile(
            label: 'runtimeThreads',
            value: threadCount == 0 ? '—' : '$threadTotal',
          ),
        ),
      ],
    );
  }
}

class _RuntimeUnavailable extends StatelessWidget {
  const _RuntimeUnavailable({required this.group});

  final RuntimeGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Symbols.info, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                group.processes.isEmpty
                    ? 'runtimeNotDetected'.tr()
                    : 'runtimeUnavailable'.tr(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        if (group.error != null) ...[
          const SizedBox(height: 2),
          Text(
            group.error!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _ProcessHeaderRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Row(
      children: [
        SizedBox(width: 56, child: Text('detailPid'.tr(), style: style)),
        Expanded(child: Text('detailCommand'.tr(), style: style)),
        SizedBox(
          width: 64,
          child: Text(
            'detailCpu'.tr(),
            textAlign: TextAlign.right,
            style: style,
          ),
        ),
        SizedBox(
          width: 72,
          child: Text(
            'detailRss'.tr(),
            textAlign: TextAlign.right,
            style: style,
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(
            'runtimeThreads'.tr(),
            textAlign: TextAlign.right,
            style: style,
          ),
        ),
      ],
    );
  }
}

class _RuntimeProcessRow extends StatelessWidget {
  const _RuntimeProcessRow({required this.process});

  final RuntimeProcessInfo process;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 56, child: Text('${process.pid}', style: style)),
          Expanded(
            child: Text(
              process.command,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              '${process.cpuPercent.toStringAsFixed(1)}%',
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
          SizedBox(
            width: 72,
            child: Text(
              _formatKb(process.rssKb),
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(
              process.threads?.toString() ?? '—',
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

/// JDK badge plus per-JVM rows (pid, main class, old-gen %, YGC/FGC, GCT).
class _JavaSection extends StatelessWidget {
  const _JavaSection({required this.java, required this.onRefresh});

  final JavaRuntimeInfo java;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              java.jdkAvailable ? Symbols.verified : Symbols.error_outline,
              size: 16,
              color: java.jdkAvailable
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                java.jdkAvailable
                    ? 'runtimeJdkAvailable'.tr()
                    : 'runtimeJdkUnavailable'.tr(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (java.jdkError != null)
              Tooltip(
                message: java.jdkError!,
                child: Icon(
                  Symbols.info,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        if (!java.jdkAvailable && java.jdkError != null) ...[
          const SizedBox(height: 2),
          Text(
            java.jdkError!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        if (java.jvms.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 56,
                child: Text(
                  'detailPid'.tr(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'runtimeJvmMainClass'.tr(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final jvm in java.jvms) _JvmRow(jvm: jvm),
        ],
      ],
    );
  }
}

class _JvmRow extends StatelessWidget {
  const _JvmRow({required this.jvm});

  final JavaJvmInfo jvm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 56,
                child: Text(
                  '${jvm.pid}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  jvm.mainClass?.isNotEmpty == true ? jvm.mainClass! : '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium,
                ),
              ),
              if (jvm.error != null)
                Tooltip(
                  message: jvm.error!,
                  child: Icon(
                    Symbols.error_outline,
                    size: 16,
                    color: scheme.error,
                  ),
                ),
            ],
          ),
          if (jvm.error != null) ...[
            const SizedBox(height: 4),
            Text(
              jvm.error!,
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.error),
            ),
          ] else if (jvm.oldPercent != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _RuntimeStatTile(
                    compact: true,
                    label: 'runtimeOldGen',
                    value: '${jvm.oldPercent!.toStringAsFixed(1)}%',
                    progress: (jvm.oldPercent! / 100).clamp(0.0, 1.0),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _RuntimeStatTile(
                    compact: true,
                    label: 'runtimeGcCount',
                    value: '${jvm.ygc ?? 0} / ${jvm.fgc ?? 0}',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _RuntimeStatTile(
                    compact: true,
                    label: 'runtimeGcTime',
                    value: jvm.gctSeconds == null
                        ? '—'
                        : '${jvm.gctSeconds!.toStringAsFixed(2)}s',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Tile layout copied from `servers_page.dart` `_StatTile` (private there).
class _RuntimeStatTile extends StatelessWidget {
  const _RuntimeStatTile({
    required this.label,
    required this.value,
    this.compact = false,
    this.progress,
  });

  final String label;
  final String value;
  final bool compact;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 8 : 10,
          compact ? 7 : 10,
          compact ? 8 : 10,
          compact ? 7 : 10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.tr(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: compact ? 2 : 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (compact ? textTheme.titleSmall : textTheme.titleMedium)
                  ?.copyWith(
                    color: colorScheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
            if (progress != null) ...[
              SizedBox(height: compact ? 4 : 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: colorScheme.onSurface.withValues(
                    alpha: 0.08,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Connection/empty/error placeholder, mirroring the page's `_EmptyPanel`.
class _RuntimeEmptyPanel extends StatelessWidget {
  const _RuntimeEmptyPanel({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.filledAction = false,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;
  final IconData? actionIcon;
  final bool filledAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final content = Column(
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
          if (filledAction)
            FilledButton.icon(
              onPressed: onAction,
              icon: Icon(actionIcon ?? Symbols.refresh),
              label: Text(actionLabel!),
            )
          else
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ],
    );
    return Center(
      child: Padding(padding: const EdgeInsets.all(24), child: content),
    );
  }
}

String _formatKb(int value) {
  const kbPerGb = 1024 * 1024;
  return value >= kbPerGb
      ? '${(value / kbPerGb).toStringAsFixed(1)} GB'
      : '${(value / 1024).toStringAsFixed(0)} MB';
}
