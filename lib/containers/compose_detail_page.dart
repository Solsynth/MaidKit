import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:styled_widget/styled_widget.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/routing/app_router.gr.dart';
import 'package:maid_kit/servers/server_connection_actions.dart';
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/ssh_connection_manager.dart';
import 'package:maid_kit/shared/presentation/ansi_log_view.dart';
import 'package:maid_kit/theme.dart';
import 'compose_project_actions.dart';
import 'container_list_tile.dart';
import 'container_models.dart';

/// Detail view for a linked Compose project: stack identity, lifecycle
/// actions, live per-service status, merged logs, and the compose file itself.
@RoutePage()
class ComposeDetailPage extends ConsumerStatefulWidget {
  const ComposeDetailPage({
    super.key,
    required this.server,
    required this.runtime,
    required this.scope,
    required this.projectName,
    required this.directory,
  });

  final Server server;
  final ContainerRuntime runtime;
  final ContainerScope scope;
  final String projectName;
  final String directory;

  @override
  ConsumerState<ComposeDetailPage> createState() => _ComposeDetailPageState();
}

class _ComposeDetailPageState extends ConsumerState<ComposeDetailPage> {
  List<ServerContainer>? _containers;
  Object? _containersError;
  var _loadingContainers = false;
  List<ContainerStats> _stats = const [];

  String? _logs;
  Object? _logsError;
  var _loadingLogs = false;
  var _followingLogs = false;
  var _logTail = 300;
  var _logTimestamps = false;
  LogFollowHandle? _logFollow;
  var _logFollowGeneration = 0;
  final _pendingLogChunks = StringBuffer();
  Timer? _logFlushTimer;

  (String source, String fileName)? _composeFile;
  Object? _composeFileError;
  var _loadingComposeFile = false;

  Timer? _refreshTimer;
  late final FocusedServerNotifier _focusedServerNotifier;
  var _actionBusy = false;

  @override
  void initState() {
    super.initState();
    _focusedServerNotifier = ref.read(focusedServerIdProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusedServerNotifier.focus(widget.server.id);
      unawaited(_bootstrap());
    });
    _startRefreshTimer(ref.read(focusedServerRefreshIntervalProvider));
    ref.listenManual<Duration>(focusedServerRefreshIntervalProvider, (
      _,
      interval,
    ) {
      _startRefreshTimer(interval);
    });
    ref.listenManual(sessionsProvider, (previous, next) {
      final was = _connected(previous?.asData?.value);
      final now = _connected(next.asData?.value);
      if (now && !was) unawaited(_bootstrap());
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _logFlushTimer?.cancel();
    _logFollowGeneration++;
    final follow = _logFollow;
    _logFollow = null;
    unawaited(follow?.cancel() ?? Future<void>.value());
    // Riverpod forbids mutating providers during dispose / tree finalization.
    final serverId = widget.server.id;
    final focused = _focusedServerNotifier;
    Future.microtask(() => focused.clear(serverId));
    super.dispose();
  }

  bool _connected(List<SshSessionInfo>? sessions) {
    if (sessions == null) return false;
    return sessions.any(
      (session) =>
          session.serverId == widget.server.id &&
          session.status == SessionStatus.connected,
    );
  }

  void _startRefreshTimer(Duration interval) {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(interval, (_) {
      if (!mounted) return;
      if (!_connected(ref.read(sessionsProvider).asData?.value)) return;
      unawaited(_loadContainers());
    });
  }

  Future<String?> _sudoPassword() async {
    final credential = await ref
        .read(serverRepositoryProvider)
        .credentialFor(widget.server);
    return credential.type == CredentialType.password
        ? credential.password
        : null;
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      _loadContainers(),
      _startLogFollow(),
      _loadComposeFile(),
    ]);
  }

  Future<void> _loadContainers() async {
    setState(() {
      _loadingContainers = true;
      _containersError = null;
    });
    try {
      final environments = await ref
          .read(connectionManagerProvider)
          .listContainers(
            widget.server.id,
            sshUserIsRoot: widget.server.username == 'root',
            sudoPassword: await _sudoPassword(),
          );
      final containers = [
        for (final environment in environments)
          ...environment.containers.where(
            (item) => item.composeProject == widget.projectName,
          ),
      ];
      if (!mounted) return;
      setState(() {
        _containers = containers;
        _loadingContainers = false;
        _containersError = null;
      });
      await _loadStats(containers);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (_containers == null) _containersError = error;
        _loadingContainers = false;
      });
    }
  }

  Future<void> _loadStats(List<ServerContainer> containers) async {
    final ids = [for (final container in containers) container.id];
    if (ids.isEmpty) {
      if (mounted) setState(() => _stats = const []);
      return;
    }
    try {
      final samples = await ref
          .read(connectionManagerProvider)
          .listContainerStats(
            widget.server.id,
            runtime: widget.runtime,
            scope: widget.scope,
            containerIds: ids,
            sudoPassword: await _sudoPassword(),
          );
      if (!mounted) return;
      setState(() => _stats = samples);
    } catch (_) {
      // Stats are best-effort; tiles fall back to "—" when unavailable.
    }
  }

  /// Stats id may be the full or short container id; match either way.
  ContainerStats? _statsFor(ServerContainer container) {
    for (final sample in _stats) {
      if (container.id == sample.id ||
          container.id.endsWith(sample.id) ||
          sample.id.endsWith(container.id)) {
        return sample;
      }
    }
    return null;
  }

  Future<void> _loadComposeFile() async {
    setState(() {
      _loadingComposeFile = true;
      _composeFileError = null;
    });
    try {
      final file = await ref
          .read(connectionManagerProvider)
          .readComposeFile(
            widget.server.id,
            scope: widget.scope,
            directory: widget.directory,
            sudoPassword: await _sudoPassword(),
          );
      if (!mounted) return;
      setState(() {
        _composeFile = file;
        _composeFileError = null;
        _loadingComposeFile = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _composeFileError = error;
        _loadingComposeFile = false;
      });
    }
  }

  Future<void> _stopLogFollow() async {
    _logFollowGeneration++;
    _logFlushTimer?.cancel();
    _logFlushTimer = null;
    _pendingLogChunks.clear();
    final follow = _logFollow;
    _logFollow = null;
    if (mounted) setState(() => _followingLogs = false);
    await follow?.cancel();
  }

  void _appendLogChunk(String chunk, int generation) {
    if (!mounted || generation != _logFollowGeneration) return;
    _pendingLogChunks.write(chunk);
    _logFlushTimer ??= Timer(const Duration(milliseconds: 50), () {
      _logFlushTimer = null;
      if (!mounted || generation != _logFollowGeneration) return;
      final delta = _pendingLogChunks.toString();
      _pendingLogChunks.clear();
      if (delta.isEmpty) return;
      setState(() {
        _logs = (_logs ?? '') + delta;
        _loadingLogs = false;
        _logsError = null;
      });
    });
  }

  Future<void> _startLogFollow() async {
    await _stopLogFollow();
    if (!mounted) return;
    final generation = ++_logFollowGeneration;
    setState(() {
      _logs = '';
      _logsError = null;
      _loadingLogs = true;
      _followingLogs = false;
    });
    try {
      final handle = await ref
          .read(connectionManagerProvider)
          .followComposeProjectLogs(
            widget.server.id,
            runtime: widget.runtime,
            scope: widget.scope,
            projectName: widget.projectName,
            directory: widget.directory,
            tail: _logTail,
            timestamps: _logTimestamps,
            sudoPassword: await _sudoPassword(),
            onChunk: (chunk) => _appendLogChunk(chunk, generation),
          );
      if (!mounted || generation != _logFollowGeneration) {
        await handle.cancel();
        return;
      }
      _logFollow = handle;
      setState(() {
        _followingLogs = true;
        _loadingLogs = false;
      });
      unawaited(
        handle.done.then((_) {
          if (!mounted || generation != _logFollowGeneration) return;
          _logFlushTimer?.cancel();
          _logFlushTimer = null;
          if (_pendingLogChunks.isNotEmpty) {
            final delta = _pendingLogChunks.toString();
            _pendingLogChunks.clear();
            setState(() {
              _logs = (_logs ?? '') + delta;
              _followingLogs = false;
            });
          } else {
            setState(() => _followingLogs = false);
          }
        }),
      );
    } catch (error) {
      if (!mounted || generation != _logFollowGeneration) return;
      setState(() {
        _logsError = error;
        _loadingLogs = false;
        _followingLogs = false;
      });
    }
  }

  Future<void> _connect() async {
    final connected = await connectForStatistics(context, ref, widget.server);
    if (connected && mounted) await _bootstrap();
  }

  Future<void> _runAction(ComposeProjectAction action) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await runComposeProjectActionWithTerminal(
        ref: ref,
        serverId: widget.server.id,
        serverName: widget.server.name,
        runtime: widget.runtime,
        scope: widget.scope,
        projectName: widget.projectName,
        directory: widget.directory,
        action: action,
        sudoPassword: await _sudoPassword(),
      );
      if (!mounted) return;
      showStyledSnackBar(
        title: 'composeDetailActionSuccess'.tr(args: [action.label]),
        message: widget.projectName,
        icon: Symbols.check_circle,
        accentColor: Theme.of(context).colorScheme.primary,
      );
      await _loadContainers();
    } catch (error) {
      if (!mounted) return;
      showStyledSnackBar(
        title: 'composeDetailActionError'.tr(args: [action.label]),
        message: error.toString(),
        icon: Symbols.error,
        accentColor: Theme.of(context).colorScheme.error,
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _runContainerAction(
    ServerContainer container,
    ContainerAction action,
  ) async {
    try {
      await ref
          .read(connectionManagerProvider)
          .runContainerAction(
            widget.server.id,
            runtime: widget.runtime,
            scope: widget.scope,
            containerId: container.id,
            action: action,
            sudoPassword: await _sudoPassword(),
          );
      if (!mounted) return;
      showStyledSnackBar(
        title: 'deploymentContainerSuccess'.tr(args: [action.pastLabel]),
        message: container.name,
        icon: Symbols.check_circle,
        accentColor: Theme.of(context).colorScheme.primary,
      );
      await _loadContainers();
    } catch (error) {
      if (!mounted) return;
      showStyledSnackBar(
        title: 'deploymentActionFailed'.tr(),
        message: error.toString(),
        icon: Symbols.error,
        accentColor: Theme.of(context).colorScheme.error,
      );
    }
  }

  Future<void> _openContainer(ServerContainer container) async {
    await context.router.push(
      ContainerDetailRoute(
        server: widget.server,
        runtime: widget.runtime,
        scope: widget.scope,
        containerId: container.id,
        containerName: container.name,
      ),
    );
    if (mounted) await _loadContainers();
  }

  Future<void> _copy(String value, {required String title}) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    showStyledSnackBar(
      title: title,
      message: 'commonCopiedToClipboard'.tr(),
      icon: Symbols.content_copy,
      accentColor: Theme.of(context).colorScheme.primary,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(sessionsProvider).asData?.value ?? const [];
    final session = sessions
        .where((item) => item.serverId == widget.server.id)
        .firstOrNull;
    final connected = session?.status == SessionStatus.connected;
    final containers = _containers;
    final runningCount = containers == null
        ? 0
        : containers.where(isContainerRunning).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.projectName),
        actions: [
          IconButton(
            tooltip: 'commonRefresh'.tr(),
            onPressed: connected && !_actionBusy
                ? () => unawaited(_bootstrap())
                : null,
            icon: const Icon(Symbols.refresh),
          ),
          PopupMenuButton<String>(
            enabled: connected && !_actionBusy,
            onSelected: (value) {
              switch (value) {
                case 'start':
                  unawaited(_runAction(ComposeProjectAction.up));
                case 'stop':
                  unawaited(_runAction(ComposeProjectAction.stop));
                case 'restart':
                  unawaited(_runAction(ComposeProjectAction.restart));
                case 'pull':
                  unawaited(_runAction(ComposeProjectAction.pull));
                case 'recreate':
                  unawaited(_runAction(ComposeProjectAction.recreate));
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'start',
                child: Text('deploymentQuickActionStart'.tr()),
              ),
              PopupMenuItem(
                value: 'stop',
                child: Text('deploymentQuickActionStop'.tr()),
              ),
              PopupMenuItem(
                value: 'restart',
                child: Text('deploymentQuickActionRestart'.tr()),
              ),
              PopupMenuItem(
                value: 'pull',
                child: Text('deploymentQuickActionPull'.tr()),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'recreate',
                child: Text('composeDetailForceRecreate'.tr()),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: !connected && containers == null
          ? _EmptyBody(
              icon: Symbols.link_off,
              message: session?.error ?? 'composeDetailConnectToInspect'.tr(),
              actionLabel: 'commonConnect'.tr(),
              onAction: _connect,
            )
          : _ComposeDetailWorkspace(
              overview: _ComposeOverviewPanel(
                server: widget.server,
                runtime: widget.runtime,
                scope: widget.scope,
                projectName: widget.projectName,
                directory: widget.directory,
                connected: connected,
                containers: containers,
                loading: _loadingContainers && containers == null,
                error: _containersError,
                runningCount: runningCount,
                actionBusy: _actionBusy,
                onConnect: _connect,
                onRefresh: () => unawaited(_bootstrap()),
                onAction: (action) => unawaited(_runAction(action)),
              ),
              tabs: _ComposeDetailTabs(
                containers: containers ?? const [],
                containersLoading: _loadingContainers && containers == null,
                containersError: _containersError,
                statsFor: _statsFor,
                logs: _logs,
                logsError: _logsError,
                loadingLogs: _loadingLogs,
                followingLogs: _followingLogs,
                logTail: _logTail,
                logTimestamps: _logTimestamps,
                composeFile: _composeFile,
                composeFileError: _composeFileError,
                loadingComposeFile: _loadingComposeFile && _composeFile == null,
                onRefreshContainers: () => unawaited(_loadContainers()),
                onRefreshLogs: () => unawaited(_startLogFollow()),
                onLogTailChanged: (value) {
                  setState(() => _logTail = value);
                  unawaited(_startLogFollow());
                },
                onLogTimestampsChanged: (value) {
                  setState(() => _logTimestamps = value);
                  unawaited(_startLogFollow());
                },
                onRefreshComposeFile: () => unawaited(_loadComposeFile()),
                onOpenContainer: _openContainer,
                onContainerAction: _runContainerAction,
                onCopy: _copy,
              ),
            ),
    );
  }
}

class _ComposeDetailWorkspace extends StatelessWidget {
  const _ComposeDetailWorkspace({required this.overview, required this.tabs});

  final Widget overview;
  final Widget tabs;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _PanelSurface(padding: const EdgeInsets.all(16), child: overview),
              const SizedBox(height: 16),
              SizedBox(height: 560, child: _PanelSurface(child: tabs)),
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
                child: _PanelSurface(child: tabs),
              ),
            ),
          ],
        ).padding(horizontal: 24);
      },
    );
  }
}

class _PanelSurface extends StatelessWidget {
  const _PanelSurface({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  static const _radius = BorderRadius.all(Radius.circular(12));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: _radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: _radius,
        ),
        child: padding == null
            ? child
            : Padding(padding: padding!, child: child),
      ),
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
      label,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _ComposeOverviewPanel extends StatelessWidget {
  const _ComposeOverviewPanel({
    required this.server,
    required this.runtime,
    required this.scope,
    required this.projectName,
    required this.directory,
    required this.connected,
    required this.containers,
    required this.loading,
    required this.error,
    required this.runningCount,
    required this.actionBusy,
    required this.onConnect,
    required this.onRefresh,
    required this.onAction,
  });

  final Server server;
  final ContainerRuntime runtime;
  final ContainerScope scope;
  final String projectName;
  final String directory;
  final bool connected;
  final List<ServerContainer>? containers;
  final bool loading;
  final Object? error;
  final int runningCount;
  final bool actionBusy;
  final Future<void> Function() onConnect;
  final VoidCallback onRefresh;
  final ValueChanged<ComposeProjectAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = containers?.length ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel('composeDetailOverview'.tr()),
        const SizedBox(height: 12),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (containers == null && error != null)
          Text(
            'deploymentStackLoadError'.tr(args: [error.toString()]),
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
          )
        else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                runningCount > 0 ? Symbols.play_circle : Symbols.stop_circle,
                color: runningCount > 0
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(projectName, style: theme.textTheme.titleMedium),
                    if (directory.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        directory,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: MaidKitFonts.mono,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: runningCount > 0
                            ? scheme.secondaryContainer
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        runningCount > 0
                            ? 'composeDetailRunning'.tr()
                            : 'composeDetailStopped'.tr(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: runningCount > 0
                              ? scheme.onSecondaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _KeyValue(label: 'containerFieldServer'.tr(), value: server.name),
          _KeyValue(label: 'containerFieldRuntime'.tr(), value: runtime.name),
          _KeyValue(
            label: 'containerFieldScope'.tr(),
            value: scope == ContainerScope.root
                ? 'commonSystem'.tr()
                : 'commonUser'.tr(),
          ),
          _KeyValue(
            label: 'composeDetailFieldProject'.tr(),
            value: projectName,
            mono: true,
          ),
          if (directory.isNotEmpty)
            _KeyValue(
              label: 'composeDetailFieldDirectory'.tr(),
              value: directory,
              mono: true,
            ),
          _KeyValue(label: 'composeDetailFieldServices'.tr(), value: '$total'),
          _KeyValue(
            label: 'composeDetailFieldRunning'.tr(),
            value: '$runningCount',
          ),
        ],
        if (!connected) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onConnect,
            icon: const Icon(Symbols.link, size: 18),
            label: const Text('commonConnect').tr(),
          ),
        ] else ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: actionBusy
                    ? null
                    : () => onAction(ComposeProjectAction.up),
                icon: const Icon(Symbols.play_arrow, size: 18),
                label: const Text('deploymentQuickActionStart').tr(),
              ),
              OutlinedButton.icon(
                onPressed: actionBusy
                    ? null
                    : () => onAction(ComposeProjectAction.stop),
                icon: const Icon(Symbols.stop, size: 18),
                label: const Text('deploymentQuickActionStop').tr(),
              ),
              OutlinedButton.icon(
                onPressed: actionBusy
                    ? null
                    : () => onAction(ComposeProjectAction.restart),
                icon: const Icon(Symbols.restart_alt, size: 18),
                label: const Text('deploymentQuickActionRestart').tr(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Symbols.refresh, size: 18),
            label: Text('commonRefresh'.tr()),
          ),
        ],
      ],
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({
    required this.label,
    required this.value,
    this.mono = false,
  });

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: mono ? MaidKitFonts.mono : null,
                fontSize: mono ? 12 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposeDetailTabs extends StatelessWidget {
  const _ComposeDetailTabs({
    required this.containers,
    required this.containersLoading,
    required this.containersError,
    required this.statsFor,
    required this.logs,
    required this.logsError,
    required this.loadingLogs,
    required this.followingLogs,
    required this.logTail,
    required this.logTimestamps,
    required this.composeFile,
    required this.composeFileError,
    required this.loadingComposeFile,
    required this.onRefreshContainers,
    required this.onRefreshLogs,
    required this.onLogTailChanged,
    required this.onLogTimestampsChanged,
    required this.onRefreshComposeFile,
    required this.onOpenContainer,
    required this.onContainerAction,
    required this.onCopy,
  });

  final List<ServerContainer> containers;
  final bool containersLoading;
  final Object? containersError;
  final ContainerStats? Function(ServerContainer) statsFor;
  final String? logs;
  final Object? logsError;
  final bool loadingLogs;
  final bool followingLogs;
  final int logTail;
  final bool logTimestamps;
  final (String source, String fileName)? composeFile;
  final Object? composeFileError;
  final bool loadingComposeFile;
  final VoidCallback onRefreshContainers;
  final VoidCallback onRefreshLogs;
  final ValueChanged<int> onLogTailChanged;
  final ValueChanged<bool> onLogTimestampsChanged;
  final VoidCallback onRefreshComposeFile;
  final ValueChanged<ServerContainer> onOpenContainer;
  final void Function(ServerContainer, ContainerAction) onContainerAction;
  final Future<void> Function(String value, {required String title}) onCopy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerColor: scheme.outlineVariant,
            tabs: [
              Tab(
                icon: const Icon(Symbols.deployed_code, size: 18),
                text: 'composeDetailServices'.tr(),
              ),
              Tab(
                icon: const Icon(Symbols.terminal, size: 18),
                text: 'containerLogs'.tr(),
              ),
              Tab(
                icon: const Icon(Symbols.description, size: 18),
                text: 'composeDetailComposeFile'.tr(),
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _ServicesPane(
                  containers: containers,
                  loading: containersLoading,
                  error: containersError,
                  statsFor: statsFor,
                  onRefresh: onRefreshContainers,
                  onOpen: onOpenContainer,
                  onAction: onContainerAction,
                ),
                _ComposeLogsPane(
                  logs: logs,
                  error: logsError,
                  loading: loadingLogs,
                  following: followingLogs,
                  tail: logTail,
                  timestamps: logTimestamps,
                  onRefresh: onRefreshLogs,
                  onTailChanged: onLogTailChanged,
                  onTimestampsChanged: onLogTimestampsChanged,
                  onCopy: onCopy,
                ),
                _ComposeFilePane(
                  file: composeFile,
                  error: composeFileError,
                  loading: loadingComposeFile,
                  onRefresh: onRefreshComposeFile,
                  onCopy: onCopy,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServicesPane extends StatelessWidget {
  const _ServicesPane({
    required this.containers,
    required this.loading,
    required this.error,
    required this.statsFor,
    required this.onRefresh,
    required this.onOpen,
    required this.onAction,
  });

  final List<ServerContainer> containers;
  final bool loading;
  final Object? error;
  final ContainerStats? Function(ServerContainer) statsFor;
  final VoidCallback onRefresh;
  final ValueChanged<ServerContainer> onOpen;
  final void Function(ServerContainer, ContainerAction) onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
          child: Row(
            children: [
              Text(
                'composeDetailServices'.tr(),
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(width: 8),
              Text(
                '${containers.length}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'deploymentRefreshContainers'.tr(),
                onPressed: onRefresh,
                icon: const Icon(Symbols.refresh, size: 18),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : error != null && containers.isEmpty
              ? _EmptyBody(
                  icon: Symbols.error_outline,
                  message: 'deploymentStackLoadError'.tr(
                    args: [error.toString()],
                  ),
                  actionLabel: 'commonRetry'.tr(),
                  onAction: () async => onRefresh(),
                )
              : containers.isEmpty
              ? _EmptyBody(
                  icon: Symbols.inventory_2,
                  message: 'deploymentNoComposeContainers'.tr(),
                  actionLabel: 'commonRefresh'.tr(),
                  onAction: () async => onRefresh(),
                )
              : ListView.separated(
                  itemCount: containers.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: scheme.outlineVariant),
                  itemBuilder: (context, index) {
                    final container = containers[index];
                    final running = isContainerRunning(container);
                    return ContainerListTile(
                      container: container,
                      wide: true,
                      stats: statsFor(container),
                      contentPadding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
                      onOpen: () => onOpen(container),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'deploymentContainerActions'.tr(),
                        onSelected: (value) {
                          switch (value) {
                            case 'start':
                              onAction(container, ContainerAction.start);
                            case 'stop':
                              onAction(container, ContainerAction.stop);
                            case 'restart':
                              onAction(container, ContainerAction.restart);
                            case 'logs':
                              onOpen(container);
                          }
                        },
                        itemBuilder: (_) => [
                          if (running)
                            PopupMenuItem(
                              value: 'stop',
                              child: Text('deploymentQuickActionStop'.tr()),
                            )
                          else
                            PopupMenuItem(
                              value: 'start',
                              child: Text('deploymentQuickActionStart'.tr()),
                            ),
                          PopupMenuItem(
                            value: 'restart',
                            child: Text('deploymentQuickActionRestart'.tr()),
                          ),
                          PopupMenuItem(
                            value: 'logs',
                            child: Text('deploymentQuickActionLogs'.tr()),
                          ),
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

class _ComposeLogsPane extends StatelessWidget {
  const _ComposeLogsPane({
    required this.logs,
    required this.error,
    required this.loading,
    required this.following,
    required this.tail,
    required this.timestamps,
    required this.onRefresh,
    required this.onTailChanged,
    required this.onTimestampsChanged,
    required this.onCopy,
  });

  final String? logs;
  final Object? error;
  final bool loading;
  final bool following;
  final int tail;
  final bool timestamps;
  final VoidCallback onRefresh;
  final ValueChanged<int> onTailChanged;
  final ValueChanged<bool> onTimestampsChanged;
  final Future<void> Function(String value, {required String title}) onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasSession = logs != null || loading || following || error != null;
    final showTerminal =
        following ||
        (logs != null && logs!.isNotEmpty) ||
        (logs != null && error == null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Text('containerLast'.tr(), style: theme.textTheme.labelLarge),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: tail,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 100, child: Text('100')),
                  DropdownMenuItem(value: 300, child: Text('300')),
                  DropdownMenuItem(value: 1000, child: Text('1000')),
                ],
                onChanged: (value) {
                  if (value != null) onTailChanged(value);
                },
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('containerTimestamps').tr(),
                selected: timestamps,
                onSelected: onTimestampsChanged,
                visualDensity: VisualDensity.compact,
              ),
              if (following) ...[
                const SizedBox(width: 8),
                Chip(
                  avatar: Icon(
                    Symbols.sensors,
                    size: 16,
                    color: scheme.primary,
                  ),
                  label: const Text('containerLive').tr(),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: scheme.outlineVariant),
                  padding: EdgeInsets.zero,
                  labelPadding: const EdgeInsets.only(right: 8),
                ),
              ],
              const Spacer(),
              IconButton(
                tooltip: 'containerCopyLogs'.tr(),
                onPressed: logs == null || logs!.isEmpty
                    ? null
                    : () => onCopy(logs!, title: 'containerLogsCopied'.tr()),
                icon: const Icon(Symbols.content_copy),
              ),
              IconButton(
                tooltip: following
                    ? 'containerRestartLiveStream'.tr()
                    : 'containerFollowLogs'.tr(),
                onPressed: onRefresh,
                icon: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Symbols.refresh),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(
          child: loading && !hasSession
              ? const Center(child: CircularProgressIndicator())
              : error != null && logs == null
              ? _EmptyBody(
                  icon: Symbols.error_outline,
                  message: 'containerLogsError'.tr(args: [error.toString()]),
                  actionLabel: 'commonRetry'.tr(),
                  onAction: () async => onRefresh(),
                )
              : showTerminal
              ? MediaQuery.removePadding(
                  context: context,
                  child: AnsiLogView(text: logs ?? '', streaming: true),
                )
              : _EmptyBody(
                  icon: Symbols.terminal,
                  message: 'containerNoLogsYet'.tr(),
                  actionLabel: 'containerFollowLogs'.tr(),
                  onAction: () async => onRefresh(),
                ),
        ),
      ],
    );
  }
}

class _ComposeFilePane extends StatelessWidget {
  const _ComposeFilePane({
    required this.file,
    required this.error,
    required this.loading,
    required this.onRefresh,
    required this.onCopy,
  });

  final (String source, String fileName)? file;
  final Object? error;
  final bool loading;
  final VoidCallback onRefresh;
  final Future<void> Function(String value, {required String title}) onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  file == null ? 'composeDetailComposeFile'.tr() : file!.$2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge,
                ),
              ),
              IconButton(
                tooltip: 'containerCopyLogs'.tr(),
                onPressed: file == null
                    ? null
                    : () => onCopy(
                        file!.$1,
                        title: 'composeDetailFileCopied'.tr(),
                      ),
                icon: const Icon(Symbols.content_copy),
              ),
              IconButton(
                tooltip: 'commonRefresh'.tr(),
                onPressed: onRefresh,
                icon: const Icon(Symbols.refresh, size: 18),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : error != null && file == null
              ? _EmptyBody(
                  icon: Symbols.error_outline,
                  message: 'composeDetailComposeFileError'.tr(
                    args: [error.toString()],
                  ),
                  actionLabel: 'commonRetry'.tr(),
                  onAction: () async => onRefresh(),
                )
              : file == null
              ? _EmptyBody(
                  icon: Symbols.description,
                  message: 'composeDetailNoComposeFile'.tr(),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          file!.$1,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: MaidKitFonts.mono,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;

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
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
