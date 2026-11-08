import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:styled_widget/styled_widget.dart';
import 'package:super_context_menu/super_context_menu.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/containers/container_management_tab.dart';
import 'package:maid_kit/containers/image_management_tab.dart';
import 'package:maid_kit/shared/presentation/app_context_menu.dart';
import 'package:maid_kit/shared/presentation/empty_state.dart';
import 'package:maid_kit/shared/presentation/maidkit_alert.dart';
import 'package:maid_kit/theme.dart';
import 'activity_tab.dart';
import 'maidcafe_server_tab.dart';
import 'maidcafe_service.dart';
import 'maidcafe_stream.dart';
import 'maidcafe_session_registry.dart';
import 'crontab_tab.dart';
import 'database_management_tab.dart';
import 'firewall_tab.dart';
import 'package_management_tab.dart';
import 'port_forwarding_tab.dart';
import 'privacy_preferences.dart';
import 'runtime_monitoring_tab.dart';
import 'server_connection_actions.dart';
import 'server_models.dart';
import 'server_providers.dart';
import 'session_lookup.dart';
import 'systemd_tab.dart';
import 'terminal_tabs_provider.dart';
import 'web_server_tab.dart';

class ServerDetailPage extends ConsumerStatefulWidget {
  const ServerDetailPage({
    super.key,
    required this.server,
    this.initialTab = 0,
    this.initialComposeProject,
    this.embedded = false,
  });

  final Server server;
  final int initialTab;
  final String? initialComposeProject;
  final bool embedded;

  @override
  ConsumerState<ServerDetailPage> createState() => _ServerDetailPageState();
}

class _ServerDetailPageState extends ConsumerState<ServerDetailPage> {
  static const _processesTabIndex = 1;
  static const _runtimesTabIndex = 2;
  static const _tabCount = 13;

  AsyncValue<List<ServerProcess>> _processes = const AsyncValue.data([]);
  Timer? _refreshTimer;
  late final FocusedServerNotifier _focusedServerNotifier;
  var _refreshing = false;
  var _hasLoadedProcesses = false;
  late int _activeTabIndex;
  late final MaidCafeSessionRegistry _sessionRegistry;
  MaidCafeStreamSession? _maidCafeStream;
  StreamSubscription<MaidCafeStreamEvent>? _processesSubscription;
  var _processesSseActive = false;
  var _processesSseAttempted = false;

  /// Last `processes` event timestamp and the daemon's announced cadence,
  /// used to detect a stream that stays connected but stops delivering data.
  DateTime _lastProcessesEvent = DateTime.fromMillisecondsSinceEpoch(0);
  int _processesSseIntervalSeconds = 10;

  AsyncValue<RuntimeSnapshot> _runtimeSnapshot = AsyncValue.data(
    RuntimeSnapshot(
      groups: const [],
      collectedAt: DateTime.fromMillisecondsSinceEpoch(0),
    ),
  );
  StreamSubscription<MaidCafeStreamEvent>? _runtimesSubscription;
  var _runtimesSseActive = false;
  var _runtimesSseAttempted = false;
  var _hasLoadedRuntimes = false;
  RuntimeDataSource? _runtimesDataSource;

  /// Last `runtimes` event timestamp and the daemon's announced cadence,
  /// used to detect a stream that stays connected but stops delivering data.
  DateTime _lastRuntimesEvent = DateTime.fromMillisecondsSinceEpoch(0);
  int _runtimesSseIntervalSeconds = 10;

  @override
  void initState() {
    super.initState();
    _activeTabIndex = widget.initialTab.clamp(0, _tabCount - 1);
    // Everything initialized below feeds the SSH-collected tabs (processes,
    // runtimes, metrics refresh). A browser only shows the MaidCafe daemon tab,
    // which manages its own daemon session.
    if (kIsWeb) return;
    _sessionRegistry = ref.read(maidCafeSessionRegistryProvider);
    _sessionRegistry.retain(widget.server);
    _focusedServerNotifier = ref.read(focusedServerIdProvider.notifier);
    // Lazy-load processes only when the Processes tab is open so a 3s metrics
    // tick does not keep spawning remote `ps` while the user is elsewhere.
    if (_activeTabIndex == _processesTabIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _startProcessesSse();
        await _loadProcesses();
      });
    }
    if (_activeTabIndex == _runtimesTabIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _startRuntimesSse();
        await _loadRuntimes();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusedServerNotifier.focus(widget.server.id);
      }
    });
    _startRefreshTimer(ref.read(focusedServerRefreshIntervalProvider));
    ref.listenManual<Duration>(focusedServerRefreshIntervalProvider, (
      _,
      interval,
    ) {
      _startRefreshTimer(interval);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _closeProcessesSse();
    _closeRuntimesSse();
    // The web branch never initialized the SSH-backed collaborators.
    if (kIsWeb) {
      super.dispose();
      return;
    }
    _sessionRegistry.release(widget.server);
    // Riverpod forbids mutating providers during dispose / tree finalization.
    final serverId = widget.server.id;
    final focused = _focusedServerNotifier;
    Future.microtask(() => focused.clear(serverId));
    super.dispose();
  }

  void _startRefreshTimer(Duration interval) {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(interval, (_) => _refresh());
  }

  /// Whether a failed daemon read can fall back to SSH here. The daemon leads
  /// the processes and runtimes tabs and their streams; SSH is what answers
  /// when it has no route or is too old for the endpoint.
  bool get _sshFallback => sshFallbackAvailable(widget.server);

  void _onTabChanged(int index) {
    final openedProcesses =
        index == _processesTabIndex && _activeTabIndex != _processesTabIndex;
    final openedRuntimes =
        index == _runtimesTabIndex && _activeTabIndex != _runtimesTabIndex;
    _activeTabIndex = index;
    if (openedProcesses) {
      // Reopening the tab is a manual ask: allow a fresh stream attempt.
      _processesSseAttempted = false;
      unawaited(_startProcessesSse());
      unawaited(_loadProcesses());
    }
    if (openedRuntimes) {
      // Reopening the tab is a manual ask: allow a fresh stream attempt.
      _runtimesSseAttempted = false;
      unawaited(_startRuntimesSse());
      unawaited(_loadRuntimes());
    }
  }

  Future<void> _loadProcesses({bool force = false}) async {
    // While SSE is authoritative the daemon cadence owns freshness. A manual
    // refresh (force) always fetches: the stream can be silent even while
    // the connection looks alive.
    if (_processesSseActive && !force) return;
    if (!_hasLoadedProcesses) {
      setState(() => _processes = const AsyncValue.loading());
    }
    // The daemon leads: its table costs the host no exec, and SSH answers
    // only when it has no route or predates /api/v1/processes.
    final session = await _ensureMaidCafeStream();
    if (session != null) {
      try {
        final snapshot = parseMaidCafeProcesses(await session.processes());
        if (mounted) {
          setState(() {
            _hasLoadedProcesses = true;
            _processes = AsyncValue.data(snapshot.processes);
          });
        }
        return;
      } catch (_) {
        // Old daemon without /api/v1/processes: fall back to SSH.
        if (!_sshFallback) rethrow;
      }
    }
    try {
      final processes = await ref
          .read(connectionManagerProvider)
          .listProcesses(widget.server.id);
      if (mounted) {
        setState(() {
          _hasLoadedProcesses = true;
          _processes = AsyncValue.data(processes);
        });
      }
    } catch (error, stackTrace) {
      if (mounted && !_hasLoadedProcesses) {
        setState(() => _processes = AsyncValue.error(error, stackTrace));
      }
    }
  }

  /// Manual refresh: always fetch (the stream may be silent), and re-arm the
  /// MaidCafe path when it was previously unavailable.
  Future<void> _refreshProcesses() async {
    if (!_processesSseActive) {
      _processesSseAttempted = false;
      _maidCafeStream = null;
      _sessionRegistry.invalidate(widget.server);
    }
    await _loadProcesses(force: true);
  }

  Future<void> _loadRuntimes({bool force = false}) async {
    // While SSE is authoritative the daemon cadence owns freshness. A manual
    // refresh (force) always fetches: the stream can be silent even while
    // the connection looks alive.
    if (_runtimesSseActive && !force) return;
    if (!_hasLoadedRuntimes) {
      setState(() => _runtimeSnapshot = const AsyncValue.loading());
    }
    // As in _loadProcesses the daemon leads, and SSH collection runs only on
    // tab open and manual refresh — it jstats every JVM on the host.
    final session = await _ensureMaidCafeStream();
    if (session != null) {
      try {
        final snapshot = parseMaidCafeRuntimes(await session.runtimes());
        if (mounted) {
          setState(() {
            _hasLoadedRuntimes = true;
            _runtimesDataSource = RuntimeDataSource.daemon;
            _runtimeSnapshot = AsyncValue.data(snapshot);
          });
        }
        return;
      } catch (_) {
        // Old daemon without /api/v1/runtimes: fall back to SSH.
        if (!_sshFallback) rethrow;
      }
    }
    try {
      final snapshot = await ref
          .read(connectionManagerProvider)
          .refreshRuntimeMetrics(widget.server.id);
      if (mounted && snapshot != null) {
        setState(() {
          _hasLoadedRuntimes = true;
          _runtimesDataSource = RuntimeDataSource.ssh;
          _runtimeSnapshot = AsyncValue.data(snapshot);
        });
      }
    } catch (error, stackTrace) {
      if (mounted && !_hasLoadedRuntimes) {
        setState(() => _runtimeSnapshot = AsyncValue.error(error, stackTrace));
      }
    }
  }

  /// Manual refresh: always fetch (the stream may be silent), and re-arm the
  /// MaidCafe path when it was previously unavailable. SSH collection runs
  /// jstat per JVM, so this only ever runs on tab open and manual refresh.
  Future<void> _refreshRuntimes() async {
    if (!_runtimesSseActive) {
      _runtimesSseAttempted = false;
      _maidCafeStream = null;
      _sessionRegistry.invalidate(widget.server);
    }
    await _loadRuntimes(force: true);
  }

  /// Opens a MaidCafe session with the same credential flow the Activity tab
  /// uses, then subscribes to `runtimes` events.
  Future<void> _startRuntimesSse() async {
    if (_runtimesSubscription != null || _runtimesSseAttempted) return;
    final session = await _ensureMaidCafeStream();
    if (session == null || !mounted) return;
    try {
      final events = session.openStream(
        events: const {MaidCafeStreamEventType.runtimes},
      );
      final subscription = events.listen(
        _onRuntimesEvent,
        onError: (Object error, StackTrace stackTrace) {
          _runtimesSseAttempted = true;
          _closeRuntimesSse();
        },
        onDone: () {
          _runtimesSseAttempted = true;
          _closeRuntimesSse();
        },
      );
      _runtimesSubscription = subscription;
    } catch (_) {
      _runtimesSseAttempted = true;
      _closeRuntimesSse();
    }
  }

  void _onRuntimesEvent(MaidCafeStreamEvent event) {
    if (!mounted) return;
    if (event.type == MaidCafeStreamEventType.hello) {
      _lastRuntimesEvent = DateTime.now();
      final intervals = event.data['intervals'];
      if (intervals is Map) {
        final seconds = intervals['runtimes'];
        if (seconds is num && seconds > 0) {
          _runtimesSseIntervalSeconds = seconds.toInt();
        }
      }
      return;
    }
    if (event.type != MaidCafeStreamEventType.runtimes) return;
    _lastRuntimesEvent = DateTime.now();
    final snapshot = parseMaidCafeRuntimes(event.data);
    setState(() {
      _runtimesSseActive = true;
      _hasLoadedRuntimes = true;
      _runtimesDataSource = RuntimeDataSource.daemon;
      _runtimeSnapshot = AsyncValue.data(snapshot);
    });
  }

  void _closeRuntimesSse() {
    final subscription = _runtimesSubscription;
    _runtimesSubscription = null;
    _runtimesSseActive = false;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    final metricsEnabled = ref.read(serverMetricsEnabledProvider);
    final manager = ref.read(connectionManagerProvider);
    _refreshing = true;
    try {
      // Statistics: the daemon leads whenever this client has a route to it —
      // a published endpoint, or a forward through the session below — and the
      // overview reads whatever it publishes. Skipping this while a session is
      // live is what used to leave a MaidCafe-backed host on SSH numbers. The
      // refresh is not forced, so a daemon that failed waits out its backoff
      // rather than being dialled on every focused interval.
      final collector = ref.read(maidCafeStatsCollectorProvider);
      if (metricsEnabled && collector.canServe(widget.server)) {
        await ref
            .read(maidCafeStatsSchedulerProvider)
            .refreshServer(widget.server);
      }
      // Statistics and system information come from the session; the
      // statistics probe stands aside while the daemon answers with numbers,
      // because a second exec would collect a copy nothing reads. Without a
      // session there is nothing here to refresh.
      if (metricsEnabled && manager.clientFor(widget.server.id) != null) {
        await manager.refreshServerInfo(widget.server);
      }
      if (_activeTabIndex == _processesTabIndex) {
        if (_processesSseActive) {
          final silence = DateTime.now().difference(_lastProcessesEvent);
          final timeoutSeconds = _processesSseIntervalSeconds * 3 >= 15
              ? _processesSseIntervalSeconds * 3
              : 15;
          if (silence > Duration(seconds: timeoutSeconds)) {
            // The stream stays connected (heartbeats) but stopped delivering
            // data — the daemon collector may be disabled or failing. Fall
            // back to on-demand fetches instead of freezing the list.
            _processesSseAttempted = true;
            _closeProcessesSse();
          }
        }
        if (_processesSubscription == null) {
          unawaited(_startProcessesSse());
        }
        await _loadProcesses();
      }
      if (_activeTabIndex == _runtimesTabIndex) {
        if (_runtimesSseActive) {
          final silence = DateTime.now().difference(_lastRuntimesEvent);
          final timeoutSeconds = _runtimesSseIntervalSeconds * 3 >= 15
              ? _runtimesSseIntervalSeconds * 3
              : 15;
          if (silence > Duration(seconds: timeoutSeconds)) {
            // The stream stays connected (heartbeats) but stopped delivering
            // data — the daemon collector may be disabled or failing. Fall
            // back to on-demand fetches instead of freezing the cards.
            _runtimesSseAttempted = true;
            _closeRuntimesSse();
          }
        }
        if (_runtimesSubscription == null) {
          unawaited(_startRuntimesSse());
        }
        // No _loadRuntimes() on the tick: SSH collection runs jstat per JVM
        // and must not repeat every refresh interval. The SSH fallback only
        // runs on tab open and manual refresh.
      }
    } finally {
      _refreshing = false;
    }
  }

  /// Opens a MaidCafe session with the same credential flow the Activity tab
  /// uses, then subscribes to `processes` events.
  Future<void> _startProcessesSse() async {
    if (_processesSubscription != null || _processesSseAttempted) return;
    final session = await _ensureMaidCafeStream();
    if (session == null || !mounted) return;
    try {
      final events = session.openStream(
        events: const {MaidCafeStreamEventType.processes},
        // The daemon defaults to its configured processesLimit (50); ask for
        // the complete table so the tab is never silently truncated.
        processesLimit: 0,
      );
      final subscription = events.listen(
        _onProcessesEvent,
        onError: (Object error, StackTrace stackTrace) {
          _processesSseAttempted = true;
          _closeProcessesSse();
        },
        onDone: () {
          _processesSseAttempted = true;
          _closeProcessesSse();
        },
      );
      _processesSubscription = subscription;
    } catch (_) {
      _processesSseAttempted = true;
      _closeProcessesSse();
    }
  }

  Future<MaidCafeStreamSession?> _ensureMaidCafeStream() async {
    final cached = _maidCafeStream;
    if (cached != null && !cached.isClosed) return cached;
    _maidCafeStream = null;
    final session = await _sessionRegistry.sessionFor(widget.server);
    if (session != null) {
      _maidCafeStream = session;
      if (!identical(session, cached)) {
        _processesSseAttempted = false;
      }
    }
    return session;
  }

  void _onProcessesEvent(MaidCafeStreamEvent event) {
    if (!mounted) return;
    if (event.type == MaidCafeStreamEventType.hello) {
      _lastProcessesEvent = DateTime.now();
      final intervals = event.data['intervals'];
      if (intervals is Map) {
        final seconds = intervals['processes'];
        if (seconds is num && seconds > 0) {
          _processesSseIntervalSeconds = seconds.toInt();
        }
      }
      return;
    }
    if (event.type != MaidCafeStreamEventType.processes) return;
    _lastProcessesEvent = DateTime.now();
    final snapshot = parseMaidCafeProcesses(event.data);
    setState(() {
      _processesSseActive = true;
      _hasLoadedProcesses = true;
      _processes = AsyncValue.data(snapshot.processes);
    });
  }

  void _closeProcessesSse() {
    final subscription = _processesSubscription;
    _processesSubscription = null;
    _processesSseActive = false;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
  }

  Future<void> _connect() async {
    if (widget.server.connectionType != ServerConnectionType.ssh.name) {
      await openTerminalFor(context, ref, widget.server);
      return;
    }
    final connected = await connectForStatistics(context, ref, widget.server);
    if (connected && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(sessionsProvider).asData?.value ?? const [];
    final session = sessionForServer(sessions, widget.server.id);
    final connected = session?.status == SessionStatus.connected;
    // Statistics come from the MaidCafe daemon whenever it answers: it costs
    // the host no exec, and it is the only statistics route a browser has.
    // The connected session still owns the connection itself; its readings
    // are the fallback for a host whose daemon does not answer. With the
    // app-wide switch off nothing is collected, so no reading is shown.
    final metricsEnabled = ref.watch(serverMetricsEnabledProvider);
    final daemonStats = metricsEnabled
        ? ref.watch(maidCafeStatsProvider)[widget.server.id]
        : null;

    final refreshInterval = ref.watch(focusedServerRefreshIntervalProvider);

    final workspace = _DetailWorkspace(
      server: widget.server,
      session: session,
      connected: connected,
      metricsEnabled: metricsEnabled,
      stats: metricsEnabled
          ? daemonStats?.stats ?? (connected ? session?.stats : null)
          : null,
      systemInfo: metricsEnabled ? session?.systemInfo : null,
      statsSourceLabel: daemonStats != null
          ? 'serversStatsSourceDaemon'.tr()
          : null,
      processes: _processes,
      runtimes: _runtimeSnapshot,
      runtimesDataSource: _runtimesDataSource,
      refreshInterval: refreshInterval,
      onConnect: _connect,
      onRefreshProcesses: _refreshProcesses,
      onRefreshRuntimes: _refreshRuntimes,
      onTabChanged: _onTabChanged,
      initialTab: widget.initialTab,
      initialComposeProject: widget.initialComposeProject,
    );
    if (widget.embedded) return workspace;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.server.name),
        actions: [
          IconButton(
            tooltip: 'detailRefreshDetails'.tr(),
            onPressed: connected || daemonStats != null ? _refresh : null,
            icon: const Icon(Symbols.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: workspace,
    );
  }
}

/// Shared surface used by overview and inspector so both columns read as one
/// Material 3 layout rather than a freeform left rail and a carded right pane.
class _PanelSurface extends StatelessWidget {
  const _PanelSurface({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(MaidKitRadius.md),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label.tr(),
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _DetailWorkspace extends StatelessWidget {
  const _DetailWorkspace({
    required this.server,
    required this.session,
    required this.connected,
    required this.processes,
    required this.runtimes,
    required this.runtimesDataSource,
    required this.refreshInterval,
    required this.onConnect,
    required this.onRefreshProcesses,
    required this.onRefreshRuntimes,
    required this.onTabChanged,
    required this.initialTab,
    required this.initialComposeProject,
    required this.metricsEnabled,
    this.stats,
    this.systemInfo,
    this.statsSourceLabel,
  });

  final Server server;
  final SshSessionInfo? session;
  final bool connected;
  final AsyncValue<List<ServerProcess>> processes;
  final AsyncValue<RuntimeSnapshot> runtimes;
  final RuntimeDataSource? runtimesDataSource;
  final Duration refreshInterval;
  final Future<void> Function() onConnect;
  final Future<void> Function() onRefreshProcesses;
  final Future<void> Function() onRefreshRuntimes;
  final ValueChanged<int> onTabChanged;
  final int initialTab;
  final String? initialComposeProject;

  /// Whether the app-wide metrics switch is on. Off means the overview shows
  /// no readings, since none are collected.
  final bool metricsEnabled;

  /// Host figures for the overview, already resolved to whichever route
  /// answered: the daemon when the server runs one on a reachable address, the
  /// SSH session otherwise. Passed in rather than read off [session] so the
  /// overview does not care which transport produced them.
  final ServerStats? stats;
  final ServerSystemInfo? systemInfo;

  /// Names the transport behind [stats] when it is not the SSH default.
  final String? statsSourceLabel;

  @override
  Widget build(BuildContext context) {
    final overview = _OverviewPanel(
      server: server,
      session: session,
      metricsEnabled: metricsEnabled,
      stats: stats,
      systemInfo: systemInfo,
      statsSourceLabel: statsSourceLabel,
      onConnect: onConnect,
    );
    final inspector = _InspectorTabs(
      connected: connected,
      connectionError: session?.error,
      processes: processes,
      runtimes: runtimes,
      runtimesDataSource: runtimesDataSource,
      server: server,
      refreshInterval: refreshInterval,
      onConnect: onConnect,
      onRefreshProcesses: onRefreshProcesses,
      onRefreshRuntimes: onRefreshRuntimes,
      onTabChanged: onTabChanged,
      initialTab: initialTab,
      initialComposeProject: initialComposeProject,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _PanelSurface(padding: const EdgeInsets.all(16), child: overview),
              const SizedBox(height: 16),
              SizedBox(height: 560, child: _PanelSurface(child: inspector)),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 360,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                children: [
                  _PanelSurface(
                    padding: const EdgeInsets.all(16),
                    child: overview,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: _PanelSurface(child: inspector),
              ),
            ),
          ],
        ).padding(horizontal: 24);
      },
    );
  }
}

/// The left rail: what the host *is*, not what it is doing right now. Live
/// readings live in the inspector's Activity tab, next to the charts that
/// plot them, so one number is never printed twice on one screen.
class _OverviewPanel extends StatelessWidget {
  const _OverviewPanel({
    required this.server,
    required this.session,
    required this.metricsEnabled,
    required this.onConnect,
    this.stats,
    this.systemInfo,
    this.statsSourceLabel,
  });

  final Server server;
  final SshSessionInfo? session;

  /// Off hides the specification list: those figures are not collected, so
  /// the panel says that instead.
  final bool metricsEnabled;
  final ServerStats? stats;
  final ServerSystemInfo? systemInfo;
  final Future<void> Function() onConnect;

  /// Names the transport behind [stats] when it is not the SSH default.
  final String? statsSourceLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('detailOverview'),
        const SizedBox(height: 12),
        _ServerIdentity(server: server, session: session),
        const SizedBox(height: 20),
        if (!metricsEnabled)
          MaidKitEmptyState(
            icon: Symbols.visibility_off,
            title: 'serversMetricsDisabled'.tr(),
            compact: true,
          )
        else
          _ServerSpecifications(
            stats: stats,
            systemInfo: systemInfo,
            sourceLabel: statsSourceLabel,
          ),
        const SizedBox(height: 20),
        _ServerQuickActions(
          server: server,
          connected: session?.status == SessionStatus.connected,
          onConnect: onConnect,
        ),
      ],
    );
  }
}

/// Static host specifications. Totals only; usage belongs to the charts.
class _ServerSpecifications extends StatelessWidget {
  const _ServerSpecifications({
    required this.stats,
    required this.systemInfo,
    this.sourceLabel,
  });

  final ServerStats? stats;
  final ServerSystemInfo? systemInfo;

  /// Where the totals came from, when that is not a plain SSH session.
  final String? sourceLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final stats = this.stats;
    final memoryTotalKb = stats?.memoryTotalKb;
    // Root volume first, the collector's own ordering.
    final rootDisks = (stats?.disks ?? const <DiskUsage>[]).where(
      (disk) => disk.mount == '/',
    );
    final disk =
        rootDisks.firstOrNull ??
        (stats?.disks.isNotEmpty == true ? stats!.disks.first : null);
    final diskTotalKb = disk?.totalKb ?? stats?.diskTotalKb;
    final diskUsedKb =
        disk?.usedKb ??
        (stats?.diskTotalKb == null || stats?.diskAvailableKb == null
            ? null
            : stats!.diskTotalKb! - stats.diskAvailableKb!);
    final diskRatio = _ratio(diskUsedKb, diskTotalKb);
    final systemLabel = [
      systemInfo?.distribution,
      systemInfo?.kernel,
    ].whereType<String>().where((part) => part.isNotEmpty).join(' · ');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(MaidKitRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'detailSpecifications',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ).tr(),
                if (sourceLabel != null) ...[
                  const Spacer(),
                  Flexible(
                    child: Text(
                      sourceLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            _SpecificationRow(
              icon: Symbols.memory,
              label: 'detailCpu',
              value: stats?.cpuCount == null
                  ? '—'
                  : 'detailCpuCount'.tr(args: ['${stats!.cpuCount}']),
            ),
            const SizedBox(height: 10),
            _SpecificationRow(
              icon: Symbols.developer_board,
              label: 'detailMemory',
              value: memoryTotalKb == null ? '—' : _formatKb(memoryTotalKb),
            ),
            const SizedBox(height: 10),
            _SpecificationRow(
              icon: Symbols.storage,
              label: 'detailRootDisk',
              value: diskTotalKb == null
                  ? '—'
                  : diskUsedKb == null
                  ? _formatKb(diskTotalKb)
                  : '${_formatKb(diskUsedKb)} / ${_formatKb(diskTotalKb)}',
            ),
            if (diskRatio != null) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(MaidKitRadius.xs),
                child: LinearProgressIndicator(
                  value: diskRatio,
                  minHeight: 4,
                  backgroundColor: scheme.surfaceContainerHighest,
                  color: diskRatio >= 0.9
                      ? scheme.error
                      : diskRatio >= 0.75
                      ? scheme.tertiary
                      : scheme.primary,
                ),
              ),
            ],
            if (systemLabel.isNotEmpty) ...[
              const SizedBox(height: 10),
              _SpecificationRow(
                icon: Symbols.terminal,
                label: 'detailSystem',
                value: systemLabel,
                multiline: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The rail's actions: the two surfaces a server is actually used through.
class _ServerQuickActions extends ConsumerWidget {
  const _ServerQuickActions({
    required this.server,
    required this.connected,
    required this.onConnect,
  });

  final Server server;
  final bool connected;
  final Future<void> Function() onConnect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.tonalIcon(
          onPressed: () => openTerminalFor(context, ref, server),
          icon: const Icon(Symbols.terminal, size: 18),
          label: Text('sessionsNewTerminal'.tr()),
        ),
        OutlinedButton.icon(
          onPressed: () => ref
              .read(terminalTabsProvider.notifier)
              .openFileManagement(server),
          icon: const Icon(Symbols.folder_open, size: 18),
          label: Text('serverFileManagementLabel'.tr()),
        ),
        if (!connected)
          OutlinedButton.icon(
            onPressed: onConnect,
            icon: const Icon(Symbols.link, size: 18),
            label: Text('commonConnect'.tr()),
          ),
      ],
    );
  }
}

class _SpecificationRow extends StatelessWidget {
  const _SpecificationRow({
    required this.icon,
    required this.label,
    required this.value,
    this.multiline = false,
  });

  final IconData icon;
  final String label;
  final String value;

  /// Values like `distribution · kernel` are allowed to wrap: clipping them
  /// would hide the version that identifies the host.
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: multiline
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: muted),
        const SizedBox(width: 12),
        SizedBox(
          width: 72,
          child: Text(
            label.tr(),
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '—' : value,
            maxLines: multiline ? 2 : 1,
            overflow: multiline ? TextOverflow.fade : TextOverflow.ellipsis,
            softWrap: multiline,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class _InspectorTabs extends StatefulWidget {
  const _InspectorTabs({
    required this.connected,
    required this.connectionError,
    required this.processes,
    required this.runtimes,
    required this.runtimesDataSource,
    required this.server,
    required this.refreshInterval,
    required this.onConnect,
    required this.onRefreshProcesses,
    required this.onRefreshRuntimes,
    required this.onTabChanged,
    required this.initialTab,
    required this.initialComposeProject,
  });

  final bool connected;
  final String? connectionError;
  final AsyncValue<List<ServerProcess>> processes;
  final AsyncValue<RuntimeSnapshot> runtimes;
  final RuntimeDataSource? runtimesDataSource;
  final Server server;
  final Duration refreshInterval;
  final Future<void> Function() onConnect;
  final Future<void> Function() onRefreshProcesses;
  final Future<void> Function() onRefreshRuntimes;
  final ValueChanged<int> onTabChanged;
  final int initialTab;
  final String? initialComposeProject;

  @override
  State<_InspectorTabs> createState() => _InspectorTabsState();
}

class _InspectorTabsState extends State<_InspectorTabs> {
  static const _tabCount = 13;

  /// Index of the MaidCafe daemon tab — the one surface whose daemon can be
  /// reached from a browser (over the cloud relay / WebSocket).
  static const _maidCafeTabIndex = 12;

  /// Index of the containers tab. Its list, detail reads and update actions go
  /// through the daemon whenever there is no SSH session to use instead, which
  /// is what a browser has (see `docs/WEB_SUPPORT.md`).
  static const _containersTabIndex = 6;

  /// Tabs visible on this platform. Every other tab collects its data over
  /// SSH, which a browser does not have.
  static final List<int> _visibleTabIndices = kIsWeb
      ? const <int>[_containersTabIndex, _maidCafeTabIndex]
      : List<int>.generate(_tabCount, (index) => index);

  /// The tabs a host is watched through, kept on one quiet strip: metrics,
  /// processes, runtimes and the services actually running there.
  static const List<int> _primaryTabIndices = [0, 1, 2, 3, 4, 5, 6];

  /// The occasional surfaces. They sit behind a single overflow control so
  /// the strip stays put in a narrow pane instead of being scrolled sideways
  /// out of sight.
  static const List<int> _overflowTabIndices = [7, 8, 9, 10, 11, 12];

  late int _activeTab;

  /// Tabs that have been opened at least once. Each stays mounted afterwards,
  /// so returning to a tab keeps its scrollback, its chart history, and its
  /// already-fetched data instead of starting over.
  late final Set<int> _mounted = {_activeTab};

  @override
  void initState() {
    super.initState();
    final requested = widget.initialTab.clamp(0, _tabCount - 1);
    _activeTab = _visibleTabIndices.contains(requested)
        ? requested
        : _visibleTabIndices.first;
    _mounted.add(_activeTab);
  }

  void _select(int index) {
    if (index == _activeTab) return;
    setState(() {
      _mounted.add(index);
      _activeTab = index;
    });
    widget.onTabChanged(index);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tabStrip(context),
        Expanded(
          child: IndexedStack(
            index: _visibleTabIndices.indexOf(_activeTab),
            sizing: StackFit.expand,
            children: [
              for (final index in _visibleTabIndices)
                _mounted.contains(index)
                    ? _tabView(index)
                    : const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }

  /// One left-aligned row: the primary tabs, the selected overflow tab when
  /// one is open, and the overflow menu on the trailing edge.
  Widget _tabStrip(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primary = [
      for (final index in _primaryTabIndices)
        if (_visibleTabIndices.contains(index)) index,
    ];
    final overflow = [
      for (final index in _overflowTabIndices)
        if (_visibleTabIndices.contains(index)) index,
    ];
    final activeIsOverflow = overflow.contains(_activeTab);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final index in primary)
                    _InspectorTabButton(
                      icon: _tabLabel(index).icon,
                      label: _tabLabel(index).label,
                      selected: _activeTab == index,
                      onPressed: () => _select(index),
                    ),
                  if (activeIsOverflow)
                    _InspectorTabButton(
                      icon: _tabLabel(_activeTab).icon,
                      label: _tabLabel(_activeTab).label,
                      selected: true,
                      onPressed: () => _select(_activeTab),
                    ),
                ],
              ),
            ),
          ),
          if (overflow.isNotEmpty)
            PopupMenuButton<int>(
              tooltip: 'detailMoreSections'.tr(),
              icon: const Icon(Symbols.more_horiz, size: 18),
              onSelected: _select,
              itemBuilder: (context) => [
                for (final index in overflow)
                  PopupMenuItem<int>(
                    value: index,
                    child: Row(
                      children: [
                        Icon(
                          _tabLabel(index).icon,
                          size: 18,
                          color: _activeTab == index
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Text(_tabLabel(index).label),
                      ],
                    ),
                  ),
              ],
            ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  ({IconData icon, String label}) _tabLabel(int index) => switch (index) {
    0 => (icon: Symbols.monitoring, label: 'detailActivity'.tr()),
    1 => (icon: Symbols.terminal, label: 'detailProcesses'.tr()),
    2 => (icon: Symbols.code_blocks, label: 'detailRuntimes'.tr()),
    3 => (icon: Symbols.settings_applications, label: 'detailServices'.tr()),
    4 => (icon: Symbols.language, label: 'detailWebServers'.tr()),
    5 => (icon: Symbols.database, label: 'detailDatabases'.tr()),
    6 => (icon: Symbols.deployed_code, label: 'detailContainers'.tr()),
    7 => (icon: Symbols.image, label: 'detailImages'.tr()),
    8 => (icon: Symbols.schedule, label: 'detailCrontab'.tr()),
    9 => (icon: Symbols.inventory_2, label: 'detailPackages'.tr()),
    10 => (icon: Symbols.shield, label: 'detailFirewall'.tr()),
    11 => (icon: Symbols.swap_horiz, label: 'detailPortForwarding'.tr()),
    _ => (icon: Symbols.local_cafe, label: 'maidCafeTitle'.tr()),
  };

  Widget _tabView(int index) => switch (index) {
    0 => ActivityTab(
      server: widget.server,
      connected: widget.connected,
      connectionError: widget.connectionError,
      onConnect: widget.onConnect,
      refreshInterval: widget.refreshInterval,
    ),
    1 =>
      widget.connected
          ? _ProcessTable(
              server: widget.server,
              processes: widget.processes,
              onRefresh: widget.onRefreshProcesses,
            )
          : _ConnectionPrompt(
              message: widget.connectionError ?? 'detailConnectToCollect'.tr(),
              onConnect: widget.onConnect,
            ),
    2 => RuntimeMonitoringTab(
      server: widget.server,
      connected: widget.connected,
      connectionError: widget.connectionError,
      onConnect: widget.onConnect,
      snapshot: widget.runtimes,
      onRefresh: widget.onRefreshRuntimes,
      dataSource: widget.runtimesDataSource,
    ),
    3 => SystemdTab(
      server: widget.server,
      connected: widget.connected,
      connectionError: widget.connectionError,
      onConnect: widget.onConnect,
    ),
    4 => WebServerTab(
      server: widget.server,
      connected: widget.connected,
      connectionError: widget.connectionError,
      onConnect: widget.onConnect,
    ),
    5 => DatabaseManagementTab(
      server: widget.server,
      connected: widget.connected,
      connectionError: widget.connectionError,
      onConnect: widget.onConnect,
    ),
    6 => ContainerManagementTab(
      server: widget.server,
      connected: widget.connected,
      connectionError: widget.connectionError,
      onConnect: widget.onConnect,
      refreshInterval: widget.refreshInterval,
      focusComposeProject: widget.initialComposeProject,
    ),
    7 => ImageManagementTab(
      server: widget.server,
      connected: widget.connected,
      connectionError: widget.connectionError,
      onConnect: widget.onConnect,
      refreshInterval: widget.refreshInterval,
    ),
    8 => CrontabTab(
      server: widget.server,
      connected: widget.connected,
      connectionError: widget.connectionError,
      onConnect: widget.onConnect,
    ),
    9 => PackageManagementTab(
      server: widget.server,
      connected: widget.connected,
      connectionError: widget.connectionError,
      onConnect: widget.onConnect,
    ),
    10 => FirewallTab(
      server: widget.server,
      connected: widget.connected,
      connectionError: widget.connectionError,
      onConnect: widget.onConnect,
    ),
    11 => PortForwardingTab(server: widget.server, connected: widget.connected),
    _ => MaidCafeServerTab(
      server: widget.server,
      connected: widget.connected,
      connectionError: widget.connectionError,
      onConnect: widget.onConnect,
    ),
  };
}

/// One entry in the inspector strip. Selected entries take the primary color
/// and a 2px rule, which is the whole affordance: no pills, no tab surfaces.
class _InspectorTabButton extends StatelessWidget {
  const _InspectorTabButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? scheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerIdentity extends ConsumerWidget {
  const _ServerIdentity({required this.server, required this.session});

  final Server server;
  final SshSessionInfo? session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final connected = session?.status == SessionStatus.connected;
    final hideAddresses = ref.watch(hideServerAddressesProvider);
    final metricsEnabled = ref.watch(serverMetricsEnabledProvider);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Symbols.dns,
          size: 22,
          fill: connected ? 1 : 0,
          color: connected ? scheme.primary : scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                serverAddressLabel(server, hideAddresses: hideAddresses),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _StatusChip(connected: connected, status: session?.status),
                  if (session?.networkLatency case final latency?)
                    if (connected)
                      Text(
                        '${latency.inMilliseconds} ms',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: latency.inMilliseconds >= 250
                              ? scheme.error
                              : latency.inMilliseconds >= 100
                              ? scheme.tertiary
                              : scheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  if (metricsEnabled && session?.stats?.updatedAt != null)
                    Text(
                      'detailUpdated'.tr(
                        args: [_formatTimestamp(session!.stats!.updatedAt)],
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.connected, required this.status});

  final bool connected;
  final SessionStatus? status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color, bg) = switch (status) {
      SessionStatus.connected => (
        'commonConnected'.tr(),
        scheme.onSecondaryContainer,
        scheme.secondaryContainer,
      ),
      SessionStatus.connecting => (
        'commonConnecting'.tr(),
        scheme.onTertiaryContainer,
        scheme.tertiaryContainer,
      ),
      SessionStatus.failed => (
        'commonFailed'.tr(),
        scheme.onErrorContainer,
        scheme.errorContainer,
      ),
      _ => (
        'commonNotConnected'.tr(),
        scheme.onSurfaceVariant,
        scheme.surfaceContainerHighest,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(MaidKitRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: connected ? scheme.primary : color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _ConnectionPrompt extends StatelessWidget {
  const _ConnectionPrompt({required this.message, required this.onConnect});

  final String message;
  final Future<void> Function() onConnect;

  @override
  Widget build(BuildContext context) => MaidKitEmptyState(
    icon: Symbols.link_off,
    title: message,
    action: FilledButton.tonalIcon(
      onPressed: onConnect,
      icon: const Icon(Symbols.link, size: 18),
      label: Text('detailConnectForMetrics'.tr()),
    ),
  );
}

class _ProcessTable extends StatelessWidget {
  const _ProcessTable({
    required this.server,
    required this.processes,
    required this.onRefresh,
  });

  final Server server;
  final AsyncValue<List<ServerProcess>> processes;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => processes.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (error, _) => MaidKitEmptyState(
      icon: Symbols.error_outline,
      iconColor: Theme.of(context).colorScheme.error.withValues(alpha: 0.7),
      title: 'detailCouldNotRetrieveProcesses'.tr(args: ['$error']),
      action: OutlinedButton(
        onPressed: onRefresh,
        child: Text('commonRetry'.tr()),
      ),
    ),
    data: (items) => items.isEmpty
        ? MaidKitEmptyState(
            icon: Symbols.terminal,
            title: 'detailNoProcessesAvailable'.tr(),
            action: OutlinedButton(
              onPressed: onRefresh,
              child: Text('commonRefresh'.tr()),
            ),
          )
        : _ProcessList(server: server, items: items, onRefresh: onRefresh),
  );
}

enum _ProcessSort { pid, user, cpu, mem, rss, command }

class _ProcessList extends ConsumerStatefulWidget {
  const _ProcessList({
    required this.server,
    required this.items,
    required this.onRefresh,
  });

  final Server server;
  final List<ServerProcess> items;
  final Future<void> Function() onRefresh;

  @override
  ConsumerState<_ProcessList> createState() => _ProcessListState();
}

class _ProcessListState extends ConsumerState<_ProcessList> {
  // Null = preserve the server's order (ps --sort=-%cpu). A local default
  // sort would reorder on every rebuild (unstable ties) and disagree with the
  // daemon's ordering; the client only re-sorts when the user picks a column.
  _ProcessSort? _sort;
  var _ascending = false;
  var _killingPid = false;
  final _filterController = TextEditingController();
  var _query = '';

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  void _clearFilter() {
    _filterController.clear();
    setState(() => _query = '');
  }

  void _toggleSort(_ProcessSort column) {
    setState(() {
      if (_sort == column) {
        _ascending = !_ascending;
      } else {
        _sort = column;
        // Perf columns default high→low; identity columns low→high.
        _ascending = switch (column) {
          _ProcessSort.cpu || _ProcessSort.mem || _ProcessSort.rss => false,
          _ProcessSort.pid || _ProcessSort.user || _ProcessSort.command => true,
        };
      }
    });
  }

  /// The rows to render: the filter applies first (pid/user/command match,
  /// case-insensitive), then the user's column sort. With no filter and no
  /// sort the server's list is returned without copying, so a full table
  /// costs nothing to rebuild on every SSE frame.
  List<ServerProcess> get _visible {
    final query = _query.trim().toLowerCase();
    var items = widget.items;
    if (query.isNotEmpty) {
      items = items
          .where(
            (p) =>
                p.command.toLowerCase().contains(query) ||
                p.user.toLowerCase().contains(query) ||
                '${p.pid}'.contains(query),
          )
          .toList(growable: false);
    }
    final sort = _sort;
    if (sort == null) return items;
    final copy = [...items];
    int compare(ServerProcess a, ServerProcess b) {
      final result = switch (sort) {
        _ProcessSort.pid => a.pid.compareTo(b.pid),
        _ProcessSort.user => a.user.toLowerCase().compareTo(
          b.user.toLowerCase(),
        ),
        _ProcessSort.cpu => a.cpuPercent.compareTo(b.cpuPercent),
        _ProcessSort.mem => a.memoryPercent.compareTo(b.memoryPercent),
        _ProcessSort.rss => a.rssKb.compareTo(b.rssKb),
        _ProcessSort.command => a.command.toLowerCase().compareTo(
          b.command.toLowerCase(),
        ),
      };
      return _ascending ? result : -result;
    }

    copy.sort(compare);
    return copy;
  }

  /// Kills [process] over the retained SSH session, with the sudo password the
  /// run needs. It serves a host whose daemon has no route, and the daemon
  /// succeeds it when the native op is unavailable.
  Future<void> _killProcessOverSsh(ServerProcess process) async {
    final credential = await ref
        .read(serverRepositoryProvider)
        .credentialFor(widget.server);
    final sudoPassword = credential.type == CredentialType.password
        ? credential.password
        : null;
    await ref
        .read(connectionManagerProvider)
        .killProcess(
          widget.server.id,
          pid: process.pid,
          sshUserIsRoot: widget.server.username == 'root',
          sudoPassword: sudoPassword,
        );
  }

  Future<void> _killProcess(ServerProcess process) async {
    if (_killingPid) return;
    final approved = await showMaidKitConfirmAlert(
      'detailKillProcessMessage'.tr(args: [process.command, '${process.pid}']),
      'detailKillProcessConfirm'.tr(args: [process.command]),
      icon: Symbols.dangerous,
      isDanger: true,
    );
    if (!approved || !mounted) return;

    setState(() => _killingPid = true);
    try {
      // The daemon runs the kill when it has a route: it refuses pids <= 1 and
      // elevates through sudo -n when needed, and a failure surfaces instead of
      // being replayed over SSH.
      final session = await ref
          .read(maidCafeSessionRegistryProvider)
          .sessionFor(widget.server);
      if (session != null) {
        final result = await session.killProcess(
          process.pid,
          invokedBy: ref.read(cloudUserProvider).asData?.value?.handle,
        );
        result.ensureSuccess();
      } else {
        await _killProcessOverSsh(process);
      }
      if (!mounted) return;
      showStyledSnackBar(
        title: 'detailKillProcessSuccess'.tr(args: ['${process.pid}']),
        message: process.command,
        icon: Symbols.check_circle,
        accentColor: Theme.of(context).colorScheme.primary,
      );
      await widget.onRefresh();
    } catch (error) {
      if (!mounted) return;
      showStyledSnackBar(
        title: 'detailKillProcessError'.tr(args: ['$error']),
        message: '${process.command} (pid ${process.pid})',
        icon: Symbols.error,
        accentColor: Theme.of(context).colorScheme.error,
      );
    } finally {
      if (mounted) setState(() => _killingPid = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = _visible;
    final filtering = _query.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Text(
                filtering
                    ? 'detailProcessFilteredCount'.tr(
                        args: ['${items.length}', '${widget.items.length}'],
                      )
                    : 'detailProcessCount'.tr(args: ['${items.length}']),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    controller: _filterController,
                    onChanged: (value) => setState(() => _query = value),
                    style: theme.textTheme.bodySmall,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'detailFilterProcesses'.tr(),
                      prefixIcon: const Icon(Symbols.search, size: 16),
                      suffixIcon: filtering
                          ? IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Symbols.close, size: 16),
                              onPressed: _clearFilter,
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(MaidKitRadius.sm),
                        borderSide: BorderSide(color: scheme.outlineVariant),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(MaidKitRadius.sm),
                        borderSide: BorderSide(color: scheme.outlineVariant),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'detailRefreshProcesses'.tr(),
                visualDensity: VisualDensity.compact,
                onPressed: widget.onRefresh,
                icon: const Icon(Symbols.refresh),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 640;
              return Column(
                children: [
                  _ProcessHeaderRow(
                    wide: wide,
                    sort: _sort,
                    ascending: _ascending,
                    onSort: _toggleSort,
                  ),
                  Divider(height: 1, color: scheme.outlineVariant),
                  Expanded(
                    child: ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: scheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                      itemBuilder: (context, index) => _ProcessRow(
                        process: items[index],
                        wide: wide,
                        killEnabled: !_killingPid && items[index].pid > 1,
                        onKill: () => _killProcess(items[index]),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ProcessHeaderRow extends StatelessWidget {
  const _ProcessHeaderRow({
    required this.wide,
    required this.sort,
    required this.ascending,
    required this.onSort,
  });

  final bool wide;
  final _ProcessSort? sort;
  final bool ascending;
  final ValueChanged<_ProcessSort> onSort;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: _SortHeader(
              label: 'detailPid',
              active: sort == _ProcessSort.pid,
              ascending: ascending,
              onTap: () => onSort(_ProcessSort.pid),
            ),
          ),
          SizedBox(
            width: 88,
            child: _SortHeader(
              label: 'commonUser',
              active: sort == _ProcessSort.user,
              ascending: ascending,
              onTap: () => onSort(_ProcessSort.user),
            ),
          ),
          if (wide) ...[
            SizedBox(
              width: 64,
              child: _SortHeader(
                label: 'detailCpu',
                active: sort == _ProcessSort.cpu,
                ascending: ascending,
                alignEnd: true,
                onTap: () => onSort(_ProcessSort.cpu),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 64,
              child: _SortHeader(
                label: 'detailMemory',
                active: sort == _ProcessSort.mem,
                ascending: ascending,
                alignEnd: true,
                onTap: () => onSort(_ProcessSort.mem),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 72,
              child: _SortHeader(
                label: 'detailRss',
                active: sort == _ProcessSort.rss,
                ascending: ascending,
                alignEnd: true,
                onTap: () => onSort(_ProcessSort.rss),
              ),
            ),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: _SortHeader(
              label: 'detailCommand',
              active: sort == _ProcessSort.command,
              ascending: ascending,
              onTap: () => onSort(_ProcessSort.command),
            ),
          ),
        ],
      ),
    );
  }
}

class _SortHeader extends StatelessWidget {
  const _SortHeader({
    required this.label,
    required this.active,
    required this.ascending,
    required this.onTap,
    this.alignEnd = false,
  });

  final String label;
  final bool active;
  final bool ascending;
  final VoidCallback onTap;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = active ? scheme.primary : scheme.onSurfaceVariant;
    final style = theme.textTheme.labelMedium?.copyWith(color: color);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(MaidKitRadius.xs),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: alignEnd
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                label.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            if (active) ...[
              const SizedBox(width: 2),
              Icon(
                ascending ? Symbols.arrow_upward : Symbols.arrow_downward,
                size: 14,
                color: color,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProcessRow extends StatelessWidget {
  const _ProcessRow({
    required this.process,
    required this.wide,
    required this.killEnabled,
    required this.onKill,
  });

  final ServerProcess process;
  final bool wide;
  final bool killEnabled;
  final VoidCallback onKill;

  Menu _menu() => Menu(
    children: [
      MenuAction(
        title: 'detailKillProcess'.tr(),
        image: MenuImage.icon(Symbols.dangerous),
        attributes: MenuActionAttributes(
          destructive: true,
          disabled: !killEnabled,
        ),
        callback: onKill,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mono = theme.textTheme.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return AppContextMenuRegion(
      menuBuilder: _menu,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            SizedBox(width: 64, child: Text('${process.pid}', style: mono)),
            SizedBox(
              width: 88,
              child: Text(
                process.user,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (wide) ...[
              SizedBox(
                width: 64,
                child: Text(
                  '${process.cpuPercent.toStringAsFixed(1)}%',
                  textAlign: TextAlign.end,
                  style: mono,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 64,
                child: Text(
                  '${process.memoryPercent.toStringAsFixed(1)}%',
                  textAlign: TextAlign.end,
                  style: mono,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 72,
                child: Text(
                  _formatKb(process.rssKb),
                  textAlign: TextAlign.end,
                  style: mono,
                ),
              ),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    process.command,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (!wide) ...[
                    const SizedBox(height: 2),
                    Text(
                      'CPU ${process.cpuPercent.toStringAsFixed(1)}% · '
                      'Mem ${process.memoryPercent.toStringAsFixed(1)}% · '
                      'RSS ${_formatKb(process.rssKb)}',
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
    );
  }
}

String _formatKb(int value) {
  const kbPerGb = 1024 * 1024;
  return value >= kbPerGb
      ? '${(value / kbPerGb).toStringAsFixed(1)} GB'
      : '${(value / 1024).toStringAsFixed(0)} MB';
}

double? _ratio(int? value, int? total) =>
    value == null || total == null || total == 0
    ? null
    : (value / total).clamp(0, 1);

String _formatTimestamp(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
