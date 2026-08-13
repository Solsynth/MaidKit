import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
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
import 'package:maid_kit/shared/presentation/maidkit_alert.dart';
import 'activity_tab.dart';
import 'maidcafe_server_tab.dart';
import 'crontab_tab.dart';
import 'firewall_tab.dart';
import 'package_management_tab.dart';
import 'port_forwarding_tab.dart';
import 'privacy_preferences.dart';
import 'server_connection_actions.dart';
import 'server_models.dart';
import 'server_providers.dart';
import 'systemd_tab.dart';
import 'web_server_tab.dart';

@RoutePage()
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
  static const _tabCount = 11;

  AsyncValue<List<ServerProcess>> _processes = const AsyncValue.data([]);
  Timer? _refreshTimer;
  late final FocusedServerNotifier _focusedServerNotifier;
  var _refreshing = false;
  var _hasLoadedProcesses = false;
  late int _activeTabIndex;

  @override
  void initState() {
    super.initState();
    _activeTabIndex = widget.initialTab.clamp(0, _tabCount - 1);
    _focusedServerNotifier = ref.read(focusedServerIdProvider.notifier);
    // Lazy-load processes only when the Processes tab is open so a 3s metrics
    // tick does not keep spawning remote `ps` while the user is elsewhere.
    if (_activeTabIndex == _processesTabIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadProcesses());
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

  void _onTabChanged(int index) {
    final openedProcesses =
        index == _processesTabIndex && _activeTabIndex != _processesTabIndex;
    _activeTabIndex = index;
    if (openedProcesses) {
      unawaited(_loadProcesses());
    }
  }

  Future<void> _loadProcesses() async {
    if (!_hasLoadedProcesses) {
      setState(() => _processes = const AsyncValue.loading());
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

  Future<void> _refresh() async {
    if (_refreshing) return;
    final manager = ref.read(connectionManagerProvider);
    if (manager.clientFor(widget.server.id) == null) return;
    _refreshing = true;
    try {
      await manager.refreshServerInfo(widget.server);
      if (_activeTabIndex == _processesTabIndex) {
        await _loadProcesses();
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _connect() async {
    if (widget.server.connectionType == ServerConnectionType.serial.name) {
      await openSerialTerminalSession(context, ref, widget.server);
      return;
    }
    final connected = await connectForStatistics(context, ref, widget.server);
    if (connected && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(sessionsProvider).asData?.value ?? const [];
    final session = sessions
        .where((item) => item.serverId == widget.server.id)
        .firstOrNull;
    final connected = session?.status == SessionStatus.connected;
    final refreshInterval = ref.watch(focusedServerRefreshIntervalProvider);

    final workspace = _DetailWorkspace(
      server: widget.server,
      session: session,
      connected: connected,
      processes: _processes,
      refreshInterval: refreshInterval,
      onConnect: _connect,
      onRefreshProcesses: _loadProcesses,
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
            onPressed: connected ? _refresh : null,
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
        borderRadius: BorderRadius.circular(12),
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
    required this.refreshInterval,
    required this.onConnect,
    required this.onRefreshProcesses,
    required this.onTabChanged,
    required this.initialTab,
    required this.initialComposeProject,
  });

  final Server server;
  final SshSessionInfo? session;
  final bool connected;
  final AsyncValue<List<ServerProcess>> processes;
  final Duration refreshInterval;
  final Future<void> Function() onConnect;
  final Future<void> Function() onRefreshProcesses;
  final ValueChanged<int> onTabChanged;
  final int initialTab;
  final String? initialComposeProject;

  @override
  Widget build(BuildContext context) {
    final overview = _OverviewPanel(server: server, session: session);
    final inspector = _InspectorTabs(
      connected: connected,
      connectionError: session?.error,
      processes: processes,
      server: server,
      refreshInterval: refreshInterval,
      onConnect: onConnect,
      onRefreshProcesses: onRefreshProcesses,
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

class _OverviewPanel extends StatelessWidget {
  const _OverviewPanel({required this.server, required this.session});

  final Server server;
  final SshSessionInfo? session;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('detailOverview'),
        const SizedBox(height: 12),
        _ServerIdentity(server: server, session: session),
        const SizedBox(height: 16),
        _ServerSpecifications(
          stats: session?.stats,
          systemInfo: session?.systemInfo,
        ),
        const SizedBox(height: 24),
        const _SectionLabel('detailPerformance'),
        const SizedBox(height: 12),
        _MetricGrid(stats: session?.stats),
      ],
    );
  }
}

class _ServerSpecifications extends StatelessWidget {
  const _ServerSpecifications({required this.stats, required this.systemInfo});

  final ServerStats? stats;
  final ServerSystemInfo? systemInfo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final specs = [
      _SpecItem(
        icon: Symbols.memory,
        label: 'detailCpu',
        value: stats?.cpuCount == null ? '—' : '${stats!.cpuCount} cores',
      ),
      _SpecItem(
        icon: Symbols.developer_board,
        label: 'detailMemory',
        value: stats?.memoryTotalKb == null
            ? '—'
            : _formatKb(stats!.memoryTotalKb!),
      ),
      _SpecItem(
        icon: Symbols.storage,
        label: 'detailRootDisk',
        value: stats?.diskTotalKb == null
            ? '—'
            : _formatKb(stats!.diskTotalKb!),
      ),
      _SpecItem(
        icon: Symbols.terminal,
        label: 'detailSystem',
        value: [
          systemInfo?.distribution,
          systemInfo?.kernel,
        ].whereType<String>().join(' · '),
      ),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'detailSpecifications',
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ).tr(),
            const SizedBox(height: 12),
            for (final spec in specs) ...[
              _SpecificationRow(spec: spec),
              if (spec != specs.last) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _SpecItem {
  const _SpecItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}

class _SpecificationRow extends StatelessWidget {
  const _SpecificationRow({required this.spec});

  final _SpecItem spec;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(spec.icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        SizedBox(
          width: 72,
          child: Text(
            spec.label.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            spec.value.isEmpty ? '—' : spec.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
    required this.server,
    required this.refreshInterval,
    required this.onConnect,
    required this.onRefreshProcesses,
    required this.onTabChanged,
    required this.initialTab,
    required this.initialComposeProject,
  });

  final bool connected;
  final String? connectionError;
  final AsyncValue<List<ServerProcess>> processes;
  final Server server;
  final Duration refreshInterval;
  final Future<void> Function() onConnect;
  final Future<void> Function() onRefreshProcesses;
  final ValueChanged<int> onTabChanged;
  final int initialTab;
  final String? initialComposeProject;

  @override
  State<_InspectorTabs> createState() => _InspectorTabsState();
}

class _InspectorTabsState extends State<_InspectorTabs>
    with SingleTickerProviderStateMixin {
  static const _tabCount = 11;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabCount,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, _tabCount - 1),
    );
    _tabController.addListener(_handleTabChange);
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_handleTabChange)
      ..dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    widget.onTabChanged(_tabController.index);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          dividerColor: scheme.outlineVariant,
          tabs: [
            Tab(
              icon: Icon(Symbols.monitoring, size: 18),
              text: 'detailActivity'.tr(),
            ),
            Tab(
              icon: Icon(Symbols.terminal, size: 18),
              text: 'detailProcesses'.tr(),
            ),
            Tab(
              icon: Icon(Symbols.settings_applications, size: 18),
              text: 'detailServices'.tr(),
            ),
            Tab(
              icon: Icon(Symbols.language, size: 18),
              text: 'detailWebServers'.tr(),
            ),
            Tab(
              icon: Icon(Symbols.deployed_code, size: 18),
              text: 'detailContainers'.tr(),
            ),
            Tab(icon: Icon(Symbols.image, size: 18), text: 'detailImages'.tr()),
            Tab(
              icon: Icon(Symbols.schedule, size: 18),
              text: 'detailCrontab'.tr(),
            ),
            Tab(
              icon: Icon(Symbols.inventory_2, size: 18),
              text: 'detailPackages'.tr(),
            ),
            Tab(
              icon: Icon(Symbols.shield, size: 18),
              text: 'detailFirewall'.tr(),
            ),
            Tab(
              icon: Icon(Symbols.swap_horiz, size: 18),
              text: 'detailPortForwarding'.tr(),
            ),
            Tab(
              icon: Icon(Symbols.cloud, size: 18),
              text: 'detailMaidCafe'.tr(),
            ),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              ActivityTab(
                server: widget.server,
                connected: widget.connected,
                connectionError: widget.connectionError,
                onConnect: widget.onConnect,
                refreshInterval: widget.refreshInterval,
              ),
              widget.connected
                  ? _ProcessTable(
                      server: widget.server,
                      processes: widget.processes,
                      onRefresh: widget.onRefreshProcesses,
                    )
                  : _ConnectionPrompt(
                      message:
                          widget.connectionError ??
                          'detailConnectToCollect'.tr(),
                      onConnect: widget.onConnect,
                    ),
              SystemdTab(
                server: widget.server,
                connected: widget.connected,
                connectionError: widget.connectionError,
                onConnect: widget.onConnect,
              ),
              WebServerTab(
                server: widget.server,
                connected: widget.connected,
                connectionError: widget.connectionError,
                onConnect: widget.onConnect,
              ),
              ContainerManagementTab(
                server: widget.server,
                connected: widget.connected,
                connectionError: widget.connectionError,
                onConnect: widget.onConnect,
                refreshInterval: widget.refreshInterval,
                focusComposeProject: widget.initialComposeProject,
              ),
              ImageManagementTab(
                server: widget.server,
                connected: widget.connected,
                connectionError: widget.connectionError,
                onConnect: widget.onConnect,
                refreshInterval: widget.refreshInterval,
              ),
              CrontabTab(
                server: widget.server,
                connected: widget.connected,
                connectionError: widget.connectionError,
                onConnect: widget.onConnect,
              ),
              PackageManagementTab(
                server: widget.server,
                connected: widget.connected,
                connectionError: widget.connectionError,
                onConnect: widget.onConnect,
              ),
              FirewallTab(
                server: widget.server,
                connected: widget.connected,
                connectionError: widget.connectionError,
                onConnect: widget.onConnect,
              ),
              PortForwardingTab(
                server: widget.server,
                connected: widget.connected,
              ),
              MaidCafeServerTab(server: widget.server),
            ],
          ),
        ),
      ],
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
                  if (session?.stats?.updatedAt != null)
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
        borderRadius: BorderRadius.circular(8),
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
  Widget build(BuildContext context) => _EmptyPanel(
    icon: Symbols.link_off,
    message: message,
    actionLabel: 'detailConnectForMetrics'.tr(),
    onAction: onConnect,
    actionIcon: Symbols.link,
    filledAction: true,
  );
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.stats});

  final ServerStats? stats;

  @override
  Widget build(BuildContext context) {
    if (stats == null) {
      return _EmptyPanel(
        icon: Symbols.monitoring,
        message: 'detailMetricsCollecting'.tr(),
        compact: true,
      );
    }
    final memoryUsed =
        stats!.memoryTotalKb == null || stats!.memoryAvailableKb == null
        ? null
        : stats!.memoryTotalKb! - stats!.memoryAvailableKb!;
    final diskUsed =
        stats!.diskTotalKb == null || stats!.diskAvailableKb == null
        ? null
        : stats!.diskTotalKb! - stats!.diskAvailableKb!;
    final swapUsed = stats!.swapTotalKb == null || stats!.swapFreeKb == null
        ? null
        : stats!.swapTotalKb! - stats!.swapFreeKb!;
    return Column(
      children: [
        _MetricCard(
          icon: Symbols.speed,
          label: 'detailLoadAverage',
          value: _loadLabel(stats!),
          detail: stats!.cpuCount == null
              ? null
              : 'detailCpuCount'.tr(args: ['${stats!.cpuCount}']),
        ),
        const SizedBox(height: 8),
        for (final gpu in stats!.gpus) ...[
          _MetricCard(
            icon: Symbols.developer_board,
            label: 'detailGpu',
            value: gpu.utilizationPercent == null
                ? '—'
                : '${gpu.utilizationPercent!.toStringAsFixed(0)}%',
            detail: [
              gpu.name,
              if (gpu.memoryUsedKb != null && gpu.memoryTotalKb != null)
                '${_formatKb(gpu.memoryUsedKb!)} / ${_formatKb(gpu.memoryTotalKb!)}',
              if (gpu.temperatureC != null)
                '${gpu.temperatureC!.toStringAsFixed(0)}°C',
            ].join(' · '),
            progress: _ratio(gpu.memoryUsedKb, gpu.memoryTotalKb),
          ),
          const SizedBox(height: 8),
        ],
        _MetricCard(
          icon: Symbols.memory,
          label: 'detailMemory',
          value: memoryUsed == null ? '—' : _formatKb(memoryUsed),
          detail: stats!.memoryTotalKb == null
              ? null
              : 'detailOf'.tr(args: [_formatKb(stats!.memoryTotalKb!)]),
          progress: _ratio(memoryUsed, stats!.memoryTotalKb),
        ),
        const SizedBox(height: 8),
        _MetricCard(
          icon: Symbols.storage,
          label: 'detailRootDisk',
          value: diskUsed == null ? '—' : _formatKb(diskUsed),
          detail: stats!.diskTotalKb == null
              ? null
              : 'detailOf'.tr(args: [_formatKb(stats!.diskTotalKb!)]),
          progress: _ratio(diskUsed, stats!.diskTotalKb),
        ),
        const SizedBox(height: 8),
        _MetricCard(
          icon: Symbols.timer,
          label: 'detailUptime',
          value: _formatUptime(stats!.uptime),
          detail: swapUsed == null || stats!.swapTotalKb == null
              ? null
              : 'detailSwap'.tr(
                  args: [_formatKb(swapUsed), _formatKb(stats!.swapTotalKb!)],
                ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    this.detail,
    this.progress,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? detail;
  final double? progress;

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
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label.tr(),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(value, style: theme.textTheme.titleSmall),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(value: progress, minHeight: 4),
              ),
            ],
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail!,
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
    error: (error, _) => _EmptyPanel(
      icon: Symbols.error_outline,
      message: 'detailCouldNotRetrieveProcesses'.tr(args: ['$error']),
      actionLabel: 'commonRetry'.tr(),
      onAction: onRefresh,
    ),
    data: (items) => items.isEmpty
        ? _EmptyPanel(
            icon: Symbols.terminal,
            message: 'detailNoProcessesAvailable'.tr(),
            actionLabel: 'commonRefresh'.tr(),
            onAction: onRefresh,
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
  // Default to highest CPU first so cost hotspots surface immediately.
  _ProcessSort _sort = _ProcessSort.cpu;
  var _ascending = false;
  var _killingPid = false;

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

  List<ServerProcess> get _sorted {
    final items = [...widget.items];
    int compare(ServerProcess a, ServerProcess b) {
      final result = switch (_sort) {
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

    items.sort(compare);
    return items;
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
    final items = _sorted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Text(
                'detailProcessCount'.tr(args: ['${items.length}']),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
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
  final _ProcessSort sort;
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
      borderRadius: BorderRadius.circular(4),
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

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.filledAction = false,
    this.compact = false,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;
  final IconData? actionIcon;
  final bool filledAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: compact ? 24 : 32, color: scheme.onSurfaceVariant),
        SizedBox(height: compact ? 8 : 12),
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
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: content,
      );
    }
    return Center(
      child: Padding(padding: const EdgeInsets.all(24), child: content),
    );
  }
}

double? _ratio(int? value, int? total) =>
    value == null || total == null || total == 0
    ? null
    : (value / total).clamp(0, 1);

String _loadLabel(ServerStats stats) => [
  stats.loadAverage,
  stats.loadAverage5,
  stats.loadAverage15,
].map((value) => value?.toStringAsFixed(2) ?? '—').join(' · ');

String _formatKb(int value) {
  const kbPerGb = 1024 * 1024;
  return value >= kbPerGb
      ? '${(value / kbPerGb).toStringAsFixed(1)} GB'
      : '${(value / 1024).toStringAsFixed(0)} MB';
}

String _formatUptime(Duration? uptime) {
  if (uptime == null || uptime.inSeconds == 0) return '—';
  final days = uptime.inDays;
  final hours = uptime.inHours.remainder(24);
  final minutes = uptime.inMinutes.remainder(60);
  if (days > 0) return '${days}d ${hours}h';
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}

String _formatTimestamp(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
