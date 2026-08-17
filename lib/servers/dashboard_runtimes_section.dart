import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'maidcafe_service.dart';
import 'maidcafe_session_registry.dart';
import 'maidcafe_stream.dart';
import 'runtime_monitoring_tab.dart';
import 'server_models.dart';
import 'server_providers.dart';

/// Dashboard section aggregating every server's pinned runtime / watched
/// process. One tile per (server, pinned name). Live data streams over the
/// MaidCafe SSE `runtimes` channel per pinned server; servers without a
/// daemon (or whose stream died) fall back to one-shot/SSH on a slow tick.
/// Hidden when nothing is pinned.
class DashboardRuntimesSection extends ConsumerStatefulWidget {
  const DashboardRuntimesSection({super.key});

  @override
  ConsumerState<DashboardRuntimesSection> createState() =>
      _DashboardRuntimesSectionState();
}

class _DashboardRuntimesSectionState
    extends ConsumerState<DashboardRuntimesSection> {
  static const _fallbackInterval = Duration(seconds: 60);

  late final MaidCafeSessionRegistry _sessionRegistry;
  final Map<int, AsyncValue<RuntimeSnapshot?>> _snapshots = {};
  final Map<int, Server> _retained = {};
  final Map<int, StreamSubscription<MaidCafeStreamEvent>> _subscriptions = {};
  final Map<int, int> _sseIntervalSeconds = {};
  final Map<int, DateTime> _lastSseEvent = {};
  Timer? _timer;
  var _refreshing = false;

  @override
  void initState() {
    super.initState();
    _sessionRegistry = ref.read(maidCafeSessionRegistryProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _timer = Timer.periodic(_fallbackInterval, (_) => _refresh());
    ref.listenManual(pinnedRuntimeConfigsProvider, (_, _) {
      // A pin was added or removed elsewhere: re-arm subscriptions so the
      // section reflects the change without waiting for the next tick.
      _refresh();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final subscription in _subscriptions.values) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
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
      // Drop subscriptions for servers that are no longer pinned.
      for (final id in _subscriptions.keys.toList()) {
        if (!serverIds.contains(id)) {
          await _endSubscription(id);
        }
      }
      for (final id in serverIds) {
        final server = serversById[id];
        if (server == null) continue;
        if (!connectedIds.contains(id)) {
          await _endSubscription(id);
          if (mounted) {
            setState(() => _snapshots[id] = const AsyncValue.data(null));
          }
          continue;
        }
        if (!_retained.containsKey(id)) {
          _retained[id] = server;
          _sessionRegistry.retain(server);
        }
        if (_subscriptions[id] == null) {
          await _subscribe(server);
        } else if (_isStale(id)) {
          // The stream stays connected but stopped delivering data: re-arm.
          await _endSubscription(id);
          await _subscribe(server);
        }
        // No daemon channel (or the stream failed again): one-shot/SSH on
        // the slow tick. Refresh whenever the subscription is down — the
        // existing snapshot must not freeze the tile after a stream death —
        // but keep the old data on screen while a refresh is in flight.
        if (_subscriptions[id] == null && mounted) {
          if (!_snapshots.containsKey(id)) {
            setState(() => _snapshots[id] = const AsyncValue.loading());
          }
          try {
            final snapshot = await _collect(server);
            if (mounted) {
              setState(() => _snapshots[id] = AsyncValue.data(snapshot));
            }
          } catch (_) {
            // The SSH client can drop between the connected check above and
            // this collect; land on "no data" instead of wedging the loader
            // (and rethrowing out of the timer callback).
            if (mounted) {
              setState(() => _snapshots[id] = const AsyncValue.data(null));
            }
          }
        }
      }
    } finally {
      _refreshing = false;
    }
  }

  bool _isStale(int serverId) {
    final last = _lastSseEvent[serverId];
    if (last == null) return true;
    final cadence = _sseIntervalSeconds[serverId] ?? 10;
    final timeout = cadence * 3 >= 15 ? cadence * 3 : 15;
    return DateTime.now().difference(last) > Duration(seconds: timeout);
  }

  /// Opens a MaidCafe SSE stream for [server]'s `runtimes` events so tiles
  /// update at the daemon's collection cadence. Old daemons without the
  /// event reject the request; the one-shot/SSH fallback covers them.
  Future<void> _subscribe(Server server) async {
    if (!mounted || _subscriptions.containsKey(server.id)) return;
    final session = await _sessionRegistry.sessionFor(server);
    if (session == null || !mounted) return;
    try {
      final events = session.openStream(
        events: const {MaidCafeStreamEventType.runtimes},
      );
      final subscription = events.listen(
        (event) => _onRuntimesEvent(server.id, event),
        onError: (Object error, StackTrace stackTrace) {
          _endSubscription(server.id);
        },
        onDone: () => _endSubscription(server.id),
      );
      _subscriptions[server.id] = subscription;
    } catch (_) {
      // Old daemon or stream failure: fall back to one-shot/SSH.
    }
  }

  void _onRuntimesEvent(int serverId, MaidCafeStreamEvent event) {
    if (!mounted) return;
    if (event.type == MaidCafeStreamEventType.hello) {
      _lastSseEvent[serverId] = DateTime.now();
      final intervals = event.data['intervals'];
      if (intervals is Map) {
        final seconds = intervals['runtimes'];
        if (seconds is num && seconds > 0) {
          _sseIntervalSeconds[serverId] = seconds.toInt();
        }
      }
      return;
    }
    if (event.type != MaidCafeStreamEventType.runtimes) return;
    _lastSseEvent[serverId] = DateTime.now();
    final snapshot = parseMaidCafeRuntimes(event.data);
    setState(() {
      _snapshots[serverId] = AsyncValue.data(snapshot);
    });
  }

  Future<void> _endSubscription(int serverId) async {
    final subscription = _subscriptions.remove(serverId);
    if (subscription != null) {
      await subscription.cancel();
    }
    _lastSseEvent.remove(serverId);
    _sseIntervalSeconds.remove(serverId);
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
      child: Card(
        margin: .zero,
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
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
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
    final isPidPin = config.runtime.startsWith('pid:');
    final pid = isPidPin ? int.tryParse(config.runtime.substring(4)) : null;
    final identity = pid != null
        ? (label: 'PID $pid', icon: Symbols.push_pin)
        : kind == null
        ? (label: config.runtime, icon: Symbols.visibility)
        : runtimeIdentity(kind);
    final processes = pid != null
        ? _matchingProcess(pid)
        : _matchingProcesses();
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
            _buildBody(context, theme, scheme, isPidPin, processes),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
    bool isPidPin,
    List<RuntimeProcessInfo>? processes,
  ) {
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
    if (snap.value == null) {
      // Server not connected: the snapshot is intentionally null.
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
    if (processes == null) {
      return Text(
        isPidPin
            ? 'dashboardProcessNotRunning'.tr()
            : 'runtimeNotDetected'.tr(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      );
    }
    return _tileBody(context, processes);
  }

  Widget _tileBody(BuildContext context, List<RuntimeProcessInfo> processes) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final command = processes.length == 1 ? processes.first.command : null;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (command != null && command.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              command,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        Row(
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
        ),
      ],
    );
  }

  /// Returns the pinned pid's process row from any runtime or watched group,
  /// or null when the process is not in the snapshot.
  List<RuntimeProcessInfo>? _matchingProcess(int pid) {
    final snap = snapshot?.value;
    if (snap == null) return null;
    for (final group in snap.groups) {
      for (final process in group.processes) {
        if (process.pid == pid) return [process];
      }
    }
    for (final group in snap.watched) {
      for (final process in group.processes) {
        if (process.pid == pid) return [process];
      }
    }
    return null;
  }

  /// Returns the pinned name's processes from a runtime group or watched
  /// group, or null when the snapshot has no such group.
  List<RuntimeProcessInfo>? _matchingProcesses() {
    final snap = snapshot?.value;
    if (snap == null) return null;
    final kind = RuntimeKindFromWire(config.runtime);
    if (kind != null) {
      for (final group in snap.groups) {
        if (group.kind == kind) return group.processes;
      }
      return null;
    }
    for (final group in snap.watched) {
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
