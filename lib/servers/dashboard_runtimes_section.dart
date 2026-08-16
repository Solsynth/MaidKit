import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'maidcafe_service.dart';
import 'maidcafe_session_registry.dart';
import 'runtime_monitoring_tab.dart';
import 'server_models.dart';
import 'server_providers.dart';

/// Dashboard section aggregating every server's pinned runtime / watched
/// process. One tile per (server, pinned name); snapshots are collected per
/// server on a slow cadence (60s), daemon-first with SSH fallback, matching
/// the Runtimes tab's channel selection. Hidden when nothing is pinned.
class DashboardRuntimesSection extends ConsumerStatefulWidget {
  const DashboardRuntimesSection({super.key});

  @override
  ConsumerState<DashboardRuntimesSection> createState() =>
      _DashboardRuntimesSectionState();
}

class _DashboardRuntimesSectionState
    extends ConsumerState<DashboardRuntimesSection> {
  static const _refreshInterval = Duration(seconds: 60);

  late final MaidCafeSessionRegistry _sessionRegistry;
  final Map<int, AsyncValue<RuntimeSnapshot?>> _snapshots = {};
  final Map<int, Server> _retained = {};
  Timer? _timer;
  var _refreshing = false;

  @override
  void initState() {
    super.initState();
    _sessionRegistry = ref.read(maidCafeSessionRegistryProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _timer = Timer.periodic(_refreshInterval, (_) => _refresh());
    ref.listen(pinnedRuntimeConfigsProvider, (_, _) {
      // A pin was added or removed elsewhere: re-collect so the section
      // reflects the change without waiting for the next tick.
      _refresh();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final server in _retained.values) {
      _sessionRegistry.release(server);
    }
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final pinned =
          ref.read(pinnedRuntimeConfigsProvider).value ??
          const <RuntimeWatchConfig>[];
      final serverIds = pinned.map((config) => config.serverId).toSet();
      final servers = ref.watch(serversProvider).value ?? const <Server>[];
      final serversById = {for (final server in servers) server.id: server};
      final sessions =
          ref.read(sessionsProvider).asData?.value ?? const <SshSessionInfo>[];
      final connectedIds = {
        for (final session in sessions)
          if (session.status == SessionStatus.connected) session.serverId,
      };
      _snapshots.removeWhere((id, _) => !serverIds.contains(id));
      for (final id in serverIds) {
        final server = serversById[id];
        if (server == null) continue;
        if (!connectedIds.contains(id)) {
          if (mounted) {
            setState(() => _snapshots[id] = const AsyncValue.data(null));
          }
          continue;
        }
        if (!_retained.containsKey(id)) {
          _retained[id] = server;
          _sessionRegistry.retain(server);
        }
        if (!_snapshots.containsKey(id) && mounted) {
          setState(() => _snapshots[id] = const AsyncValue.loading());
        }
        final snapshot = await _collect(server);
        if (mounted) {
          setState(() => _snapshots[id] = AsyncValue.data(snapshot));
        }
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<RuntimeSnapshot?> _collect(Server server) async {
    final session = await _sessionRegistry.sessionFor(server);
    if (session != null) {
      try {
        return parseMaidCafeRuntimes(await session.runtimes());
      } catch (_) {
        // Old daemon without /api/v1/runtimes: fall back to SSH.
      }
    }
    return ref.read(connectionManagerProvider).refreshRuntimeMetrics(server.id);
  }

  @override
  Widget build(BuildContext context) {
    final pinned =
        ref.watch(pinnedRuntimeConfigsProvider).value ??
        const <RuntimeWatchConfig>[];
    if (pinned.isEmpty) return const SizedBox.shrink();
    final servers = ref.watch(serversProvider).value ?? const <Server>[];
    final serversById = {for (final server in servers) server.id: server};
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: DecoratedBox(
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
              Row(
                children: [
                  Icon(Symbols.code_blocks, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'dashboardRuntimes'.tr(),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'runtimeRefresh'.tr(),
                    onPressed: _refresh,
                    icon: const Icon(Symbols.refresh, size: 18),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final config in pinned)
                    SizedBox(
                      width: 300,
                      child: _DashboardRuntimeTile(
                        config: config,
                        serverName: serversById[config.serverId]?.name ?? '',
                        snapshot: _snapshots[config.serverId],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One (server, pinned runtime/watched name) tile.
class _DashboardRuntimeTile extends StatelessWidget {
  const _DashboardRuntimeTile({
    required this.config,
    required this.serverName,
    required this.snapshot,
  });

  final RuntimeWatchConfig config;
  final String serverName;
  final AsyncValue<RuntimeSnapshot?>? snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final kind = RuntimeKindFromWire(config.runtime);
    final identity = kind == null
        ? (label: config.runtime, icon: Symbols.visibility)
        : runtimeIdentity(kind);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(identity.icon, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    identity.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                if (serverName.isNotEmpty)
                  Flexible(
                    child: Text(
                      serverName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _buildBody(context, theme, scheme),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ThemeData theme, ColorScheme scheme) {
    final snap = snapshot;
    if (snap == null || snap.isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(8),
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (snap.hasError) {
      return Text(
        '—',
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      );
    }
    return _tileBody(context, snap.value);
  }

  Widget _tileBody(BuildContext context, RuntimeSnapshot? snapshot) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (snapshot == null) {
      return Row(
        children: [
          Icon(Symbols.link_off, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'dashboardRuntimeNotConnected'.tr(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }
    final processes = _matchingProcesses(snapshot);
    if (processes == null) {
      return Text(
        'runtimeNotDetected'.tr(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      );
    }
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
          child: _DashboardStat(
            label: 'runtimeProcessCount',
            value: '${processes.length}',
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _DashboardStat(
            label: 'runtimeCpuTotal',
            value: '${cpuTotal.toStringAsFixed(1)}%',
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _DashboardStat(
            label: 'runtimeRssTotal',
            value: _formatKb(rssTotal),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _DashboardStat(
            label: 'runtimeThreads',
            value: threadCount == 0 ? '—' : '$threadTotal',
          ),
        ),
      ],
    );
  }

  /// Returns the pinned name's processes from a runtime group or watched
  /// group, or null when the snapshot has no such group.
  List<RuntimeProcessInfo>? _matchingProcesses(RuntimeSnapshot snapshot) {
    final kind = RuntimeKindFromWire(config.runtime);
    if (kind != null) {
      for (final group in snapshot.groups) {
        if (group.kind == kind) return group.processes;
      }
      return null;
    }
    for (final group in snapshot.watched) {
      if (group.name == config.runtime) return group.processes;
    }
    return null;
  }
}

class _DashboardStat extends StatelessWidget {
  const _DashboardStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.tr(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

String _formatKb(int value) {
  const kbPerGb = 1024 * 1024;
  return value >= kbPerGb
      ? '${(value / kbPerGb).toStringAsFixed(1)} GB'
      : '${(value / 1024).toStringAsFixed(0)} MB';
}
