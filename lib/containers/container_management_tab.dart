import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:super_context_menu/super_context_menu.dart';

import 'package:easy_localization/easy_localization.dart';
import 'container_list_tile.dart';
import 'container_models.dart';
import 'container_runtime_install.dart';
import 'project_repository.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/routing/app_router.gr.dart';
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/shared/presentation/app_context_menu.dart';
import 'package:maid_kit/shared/presentation/maidkit_alert.dart';

/// A reusable container-management surface for a single server. Its data is
/// scoped by runtime (Docker/Podman) and by user/root environment so it can be
/// reused by a future multi-server overview without depending on a route page.
class ContainerManagementTab extends ConsumerStatefulWidget {
  const ContainerManagementTab({
    super.key,
    required this.server,
    required this.connected,
    required this.connectionError,
    required this.onConnect,
    required this.refreshInterval,
    this.focusComposeProject,
  });

  final Server server;
  final bool connected;
  final String? connectionError;
  final Future<void> Function() onConnect;
  final Duration refreshInterval;
  final String? focusComposeProject;

  @override
  ConsumerState<ContainerManagementTab> createState() =>
      _ContainerManagementTabState();
}

class _ContainerManagementTabState
    extends ConsumerState<ContainerManagementTab> {
  AsyncValue<List<ContainerEnvironment>> _environments = const AsyncValue.data(
    [],
  );
  Timer? _refreshTimer;
  var _loading = false;
  var _hasLoadedEnvironments = false;

  @override
  void initState() {
    super.initState();
    if (widget.connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    _startRefreshTimer();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(ContainerManagementTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connected &&
        (!oldWidget.connected || oldWidget.server.id != widget.server.id)) {
      _load();
    }
    if (oldWidget.refreshInterval != widget.refreshInterval) {
      _startRefreshTimer();
    }
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(widget.refreshInterval, (_) => _load());
  }

  Future<void> _load() async {
    if (!mounted || !widget.connected || _loading) return;
    _loading = true;
    if (!_hasLoadedEnvironments) {
      setState(() => _environments = const AsyncValue.loading());
    }
    try {
      final environments = await ref
          .read(connectionManagerProvider)
          .listContainers(
            widget.server.id,
            sshUserIsRoot: widget.server.username == 'root',
            sudoPassword: await _storedSudoPassword(),
          );
      if (mounted) {
        setState(() {
          _hasLoadedEnvironments = true;
          _environments = AsyncValue.data(environments);
        });
      }
    } catch (error, stackTrace) {
      if (mounted && !_hasLoadedEnvironments) {
        setState(() => _environments = AsyncValue.error(error, stackTrace));
      }
    } finally {
      _loading = false;
    }
  }

  /// The SSH password is supplied to sudo only through SSH stdin. Private-key
  /// connections intentionally keep using non-interactive passwordless sudo.
  Future<String?> _storedSudoPassword() async {
    final credential = await ref
        .read(serverRepositoryProvider)
        .credentialFor(widget.server);
    return credential.type == CredentialType.password
        ? credential.password
        : null;
  }

  Future<bool> _confirmAction(
    ServerContainer container,
    ContainerAction action, {
    required bool forceRemove,
  }) async {
    final title = switch (action) {
      ContainerAction.stop => 'containerStopConfirm'.tr(args: [container.name]),
      ContainerAction.restart => 'containerRestartConfirm'.tr(
        args: [container.name],
      ),
      ContainerAction.kill => 'containerKillConfirm'.tr(args: [container.name]),
      ContainerAction.remove =>
        forceRemove
            ? 'containerForceDeleteConfirm'.tr(args: [container.name])
            : 'containerDeleteConfirm'.tr(args: [container.name]),
      _ => 'containerGenericConfirm'.tr(),
    };
    final message = switch (action) {
      ContainerAction.stop => 'containerStopMessage'.tr(),
      ContainerAction.restart => 'containerRestartMessage'.tr(),
      ContainerAction.kill => 'containerKillMessage'.tr(),
      ContainerAction.remove when forceRemove =>
        'containerForceDeleteMessage'.tr(),
      ContainerAction.remove => 'containerDeleteMessage'.tr(),
      _ => 'containerGenericConfirm'.tr(),
    };
    final destructive =
        action == ContainerAction.kill || action == ContainerAction.remove;

    return showMaidKitConfirmAlert(message, title, isDanger: destructive);
  }

  Future<void> _runAction(
    ContainerEnvironment environment,
    ServerContainer container,
    ContainerAction action,
  ) async {
    final running = isContainerRunning(container);
    final forceRemove = action == ContainerAction.remove && running;
    if (action.requiresConfirmation) {
      final approved = await _confirmAction(
        container,
        action,
        forceRemove: forceRemove,
      );
      if (!approved || !mounted) return;
    }
    try {
      await ref
          .read(connectionManagerProvider)
          .runContainerAction(
            widget.server.id,
            runtime: environment.runtime,
            scope: environment.scope,
            containerId: container.id,
            action: action,
            force: forceRemove,
            sudoPassword: await _storedSudoPassword(),
          );
      if (!mounted) return;
      showStyledSnackBar(
        title: 'containerActionSuccess'.tr(args: [action.pastLabel]),
        message: container.name,
        icon: Symbols.check_circle,
        accentColor: Theme.of(context).colorScheme.primary,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      showStyledSnackBar(
        title: 'containerActionError'.tr(args: [action.label.toLowerCase()]),
        message: error.toString(),
        icon: Symbols.error,
        accentColor: Theme.of(context).colorScheme.error,
      );
    }
  }

  Future<void> _installRuntime() async {
    final runtime = await chooseContainerRuntimeToInstall(context);
    if (runtime == null || !mounted) return;
    try {
      await installContainerRuntime(
        ref: ref,
        server: widget.server,
        runtime: runtime,
        sudoPassword: await _storedSudoPassword(),
      );
      if (!mounted) return;
      showStyledSnackBar(
        title: 'runtimeInstallSuccess'.tr(args: [runtime.name]),
        message: 'runtimeInstallRefreshing'.tr(),
        icon: Symbols.check_circle,
        accentColor: Theme.of(context).colorScheme.primary,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      showStyledSnackBar(
        title: 'runtimeInstallError'.tr(args: [runtime.name]),
        message: error.toString(),
        icon: Symbols.error,
        accentColor: Theme.of(context).colorScheme.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.connected) {
      return _ContainerEmptyPanel(
        icon: Symbols.link_off,
        message: widget.connectionError ?? 'containersConnectToManage'.tr(),
        actionLabel: 'commonConnect'.tr(),
        onAction: widget.onConnect,
        filledAction: true,
        actionIcon: Symbols.link,
      );
    }
    return _environments.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ContainerEmptyPanel(
        icon: Symbols.error_outline,
        message: 'containersLoadError'.tr(args: [error.toString()]),
        actionLabel: 'commonRetry'.tr(),
        onAction: _load,
      ),
      data: (environments) => _ContainerEnvironments(
        server: widget.server,
        environments: environments,
        onRefresh: _load,
        onAction: _runAction,
        onInstallRuntime: _installRuntime,
        focusComposeProject: widget.focusComposeProject,
      ),
    );
  }
}

/// Linked compose project and the live containers that belong to it.
class _ServerProjectGroup {
  _ServerProjectGroup({
    this.link,
    required this.name,
    this.directory,
    required this.runtime,
    required this.scope,
  });

  final ComposeProjectLink? link;
  final String name;
  final String? directory;
  final ContainerRuntime runtime;
  final ContainerScope scope;
  final containers = <ServerContainer>[];

  int get runningCount =>
      containers.where((container) => isContainerRunning(container)).length;
}

/// Composite key for a container inside a runtime/scope environment.
String _containerEnvKey(
  ContainerRuntime runtime,
  ContainerScope scope,
  String containerId,
) => '${runtime.name}|${scope.name}|$containerId';

List<_ServerProjectGroup> _projectGroupsForServer({
  required Server server,
  required List<ComposeProjectLink> links,
  required List<ContainerEnvironment> environments,
  String? focusComposeProject,
}) {
  final groups = <_ServerProjectGroup>[];
  for (final link in links.where((item) => item.serverId == server.id)) {
    final runtime = ContainerRuntime.values.byName(link.runtime);
    final scope = ContainerScope.values.byName(link.scope);
    final group = _ServerProjectGroup(
      link: link,
      name: link.name,
      directory: link.directory,
      runtime: runtime,
      scope: scope,
    );
    for (final environment in environments.where(
      (env) => env.isAvailable && env.runtime == runtime && env.scope == scope,
    )) {
      for (final container in environment.containers) {
        if (container.composeProject == link.name) {
          group.containers.add(container);
        }
      }
    }
    groups.add(group);
  }
  if (focusComposeProject != null &&
      !groups.any((group) => group.name == focusComposeProject)) {
    for (final environment in environments.where((env) => env.isAvailable)) {
      final matching = environment.containers
          .where((container) => container.composeProject == focusComposeProject)
          .toList();
      if (matching.isEmpty) continue;
      final group = _ServerProjectGroup(
        name: focusComposeProject,
        runtime: environment.runtime,
        scope: environment.scope,
      );
      group.containers.addAll(matching);
      groups.add(group);
    }
  }
  if (focusComposeProject != null) {
    groups.removeWhere((group) => group.name != focusComposeProject);
  }
  groups.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return groups;
}

/// Containers that belong to any linked project on this server.
Set<String> _projectContainerKeys(List<_ServerProjectGroup> projects) {
  final keys = <String>{};
  for (final project in projects) {
    for (final container in project.containers) {
      keys.add(_containerEnvKey(project.runtime, project.scope, container.id));
    }
  }
  return keys;
}

/// Environments with project-owned containers removed for the standalone list.
List<ContainerEnvironment> _environmentsWithoutProjects(
  List<ContainerEnvironment> environments,
  Set<String> projectContainerKeys,
) {
  return [
    for (final environment in environments)
      ContainerEnvironment(
        runtime: environment.runtime,
        scope: environment.scope,
        error: environment.error,
        containers: [
          for (final container in environment.containers)
            if (!projectContainerKeys.contains(
              _containerEnvKey(
                environment.runtime,
                environment.scope,
                container.id,
              ),
            ))
              container,
        ],
      ),
  ];
}

class _ContainerEnvironments extends ConsumerWidget {
  const _ContainerEnvironments({
    required this.server,
    required this.environments,
    required this.onRefresh,
    required this.onAction,
    required this.onInstallRuntime,
    this.focusComposeProject,
  });

  final Server server;
  final List<ContainerEnvironment> environments;
  final Future<void> Function() onRefresh;
  final Future<void> Function(
    ContainerEnvironment,
    ServerContainer,
    ContainerAction,
  )
  onAction;
  final Future<void> Function() onInstallRuntime;
  final String? focusComposeProject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (environments.isEmpty) {
      return _ContainerEmptyPanel(
        icon: Symbols.deployed_code,
        message: 'containersNotInstalled'.tr(),
        actionLabel: 'containersInstallRuntimeShort'.tr(),
        onAction: onInstallRuntime,
        filledAction: true,
        actionIcon: Symbols.download,
      );
    }

    final links =
        ref.watch(composeProjectLinksProvider).asData?.value ??
        const <ComposeProjectLink>[];
    final projects = _projectGroupsForServer(
      server: server,
      links: links,
      environments: environments,
      focusComposeProject: focusComposeProject,
    );
    final projectKeys = _projectContainerKeys(projects);
    final standaloneEnvironments = _environmentsWithoutProjects(
      environments,
      projectKeys,
    );

    final totalContainers = environments
        .where((env) => env.isAvailable)
        .fold<int>(0, (sum, env) => sum + env.containers.length);
    final standaloneCount = standaloneEnvironments
        .where((env) => env.isAvailable)
        .fold<int>(0, (sum, env) => sum + env.containers.length);

    final summaryParts = <String>[
      totalContainers == 1
          ? 'containersSummaryContainer'.tr()
          : 'containersSummaryContainers'.tr(args: ['$totalContainers']),
      if (projects.isNotEmpty)
        projects.length == 1
            ? 'containersSummaryProject'.tr()
            : 'containersSummaryProjects'.tr(args: ['${projects.length}']),
      if (projects.isNotEmpty && standaloneCount > 0)
        standaloneCount == 1
            ? 'containersSummaryStandalone'.tr()
            : 'containersSummaryStandalones'.tr(args: ['$standaloneCount']),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  summaryParts.join(' · '),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'containersRefreshTooltip'.tr(),
                visualDensity: VisualDensity.compact,
                onPressed: onRefresh,
                icon: const Icon(Symbols.refresh),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              if (projects.isNotEmpty) ...[
                Text(
                  'containersProjects'.tr(),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < projects.length; i++) ...[
                  _ProjectCollapsibleTile(
                    server: server,
                    project: projects[i],
                    onAction: onAction,
                  ),
                  if (i != projects.length - 1) const SizedBox(height: 8),
                ],
              ],
              ..._standaloneSections(
                projects: projects,
                environments: environments,
                standaloneEnvironments: standaloneEnvironments,
                theme: theme,
                scheme: scheme,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Environment sections with project-owned containers removed. Empty
  /// environments are hidden only when projects already cover that runtime.
  List<Widget> _standaloneSections({
    required List<_ServerProjectGroup> projects,
    required List<ContainerEnvironment> environments,
    required List<ContainerEnvironment> standaloneEnvironments,
    required ThemeData theme,
    required ColorScheme scheme,
  }) {
    final visible = <ContainerEnvironment>[
      for (final environment in standaloneEnvironments)
        if (projects.isEmpty ||
            !environment.isAvailable ||
            environment.containers.isNotEmpty ||
            environments
                .where(
                  (env) =>
                      env.runtime == environment.runtime &&
                      env.scope == environment.scope,
                )
                .every((env) => !env.isAvailable || env.containers.isEmpty))
          environment,
    ];
    if (visible.isEmpty) return const [];

    return [
      if (projects.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text(
          'containersStandalone'.tr(),
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
      ],
      for (var i = 0; i < visible.length; i++) ...[
        _ContainerEnvironmentSection(
          server: server,
          environment: visible[i],
          onAction: onAction,
        ),
        if (i != visible.length - 1) const SizedBox(height: 16),
      ],
    ];
  }
}

class _ProjectCollapsibleTile extends StatelessWidget {
  const _ProjectCollapsibleTile({
    required this.server,
    required this.project,
    required this.onAction,
  });

  final Server server;
  final _ServerProjectGroup project;
  final Future<void> Function(
    ContainerEnvironment,
    ServerContainer,
    ContainerAction,
  )
  onAction;

  ContainerEnvironment get _environment => ContainerEnvironment(
    runtime: project.runtime,
    scope: project.scope,
    containers: project.containers,
  );

  String get _runtimeLabel {
    final name = project.runtime.name;
    return '${name[0].toUpperCase()}${name.substring(1)}';
  }

  String get _scopeLabel => project.scope == ContainerScope.root
      ? 'commonRoot'.tr()
      : 'commonUser'.tr();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = project.containers.length;
    final running = project.runningCount;
    final statusLabel = count == 0
        ? 'containerNoContainers'.tr()
        : running == count
        ? 'containerRunningCount'.tr(args: ['$running'])
        : 'containerRunningFraction'.tr(args: ['$running', '$count']);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: count > 0 && count <= 6,
          tilePadding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
          childrenPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          collapsedShape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          title: Text(
            project.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall,
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project.directory ?? 'Detected from running containers',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _MetaChip(label: _runtimeLabel),
                    _MetaChip(label: _scopeLabel),
                    _MetaChip(label: statusLabel),
                  ],
                ),
              ],
            ),
          ),
          trailing: project.link == null
              ? null
              : IconButton(
                  tooltip: 'containersOpenProject'.tr(),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => context.router.push(
                    ProjectDetailRoute(linkId: project.link!.id),
                  ),
                  icon: const Icon(Symbols.open_in_new, size: 20),
                ),
          children: [
            Divider(height: 1, color: scheme.outlineVariant),
            if (project.containers.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Text(
                  'containerNoContainersInProject'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (var i = 0; i < project.containers.length; i++) ...[
                _ContainerActionTile(
                  server: server,
                  environment: _environment,
                  container: project.containers[i],
                  onAction: (action) =>
                      onAction(_environment, project.containers[i], action),
                ),
                if (i != project.containers.length - 1)
                  Divider(
                    height: 1,
                    indent: 12,
                    endIndent: 12,
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
              ],
          ],
        ),
      ),
    );
  }
}

class _ContainerEnvironmentSection extends StatelessWidget {
  const _ContainerEnvironmentSection({
    required this.server,
    required this.environment,
    required this.onAction,
  });

  final Server server;
  final ContainerEnvironment environment;
  final Future<void> Function(
    ContainerEnvironment,
    ServerContainer,
    ContainerAction,
  )
  onAction;

  String get _runtimeLabel {
    final name = environment.runtime.name;
    return '${name[0].toUpperCase()}${name.substring(1)}';
  }

  String get _scopeLabel => environment.scope == ContainerScope.root
      ? 'commonRoot'.tr()
      : 'commonUser'.tr();

  IconData get _runtimeIcon => switch (environment.runtime) {
    ContainerRuntime.docker => Symbols.deployed_code,
    ContainerRuntime.podman => Symbols.package_2,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Icon(_runtimeIcon, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_runtimeLabel, style: theme.textTheme.titleSmall),
                ),
                _MetaChip(label: _scopeLabel),
                if (environment.isAvailable) ...[
                  const SizedBox(width: 8),
                  _MetaChip(
                    label: environment.containers.isEmpty
                        ? 'containersEmpty'.tr()
                        : 'containerEnvCount'.tr(
                            args: ['${environment.containers.length}'],
                          ),
                  ),
                ],
              ],
            ),
          ),
          if (!environment.isAvailable)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Symbols.info, size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      environment.error ?? 'commonUnavailable'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (environment.containers.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(
                'No containers in this environment.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else ...[
            Divider(height: 1, color: scheme.outlineVariant),
            for (var i = 0; i < environment.containers.length; i++) ...[
              _ContainerActionTile(
                server: server,
                environment: environment,
                container: environment.containers[i],
                onAction: (action) =>
                    onAction(environment, environment.containers[i], action),
              ),
              if (i != environment.containers.length - 1)
                Divider(
                  height: 1,
                  indent: 12,
                  endIndent: 12,
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Shared container row with context menu and action overflow.
class _ContainerActionTile extends StatelessWidget {
  const _ContainerActionTile({
    required this.server,
    required this.environment,
    required this.container,
    required this.onAction,
  });

  final Server server;
  final ContainerEnvironment environment;
  final ServerContainer container;
  final Future<void> Function(ContainerAction action) onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final running = isContainerRunning(container);
    final paused = isContainerPaused(container);
    final canPause = running && !paused;
    final canUnpause = paused;

    List<Widget> menuRows(ContainerAction action, IconData icon) {
      final destructive =
          action == ContainerAction.kill || action == ContainerAction.remove;
      return [
        Icon(icon, size: 20, color: destructive ? scheme.error : null),
        const SizedBox(width: 12),
        Text(
          action.label,
          style: destructive ? TextStyle(color: scheme.error) : null,
        ),
      ];
    }

    Menu menu() => Menu(
      children: [
        MenuAction(
          title: ContainerAction.start.label,
          image: MenuImage.icon(Symbols.play_arrow),
          attributes: MenuActionAttributes(disabled: running),
          callback: () => onAction(ContainerAction.start),
        ),
        MenuAction(
          title: ContainerAction.stop.label,
          image: MenuImage.icon(Symbols.stop),
          attributes: MenuActionAttributes(disabled: !running),
          callback: () => onAction(ContainerAction.stop),
        ),
        MenuAction(
          title: ContainerAction.restart.label,
          image: MenuImage.icon(Symbols.restart_alt),
          callback: () => onAction(ContainerAction.restart),
        ),
        MenuAction(
          title: ContainerAction.pause.label,
          image: MenuImage.icon(Symbols.pause),
          attributes: MenuActionAttributes(disabled: !canPause),
          callback: () => onAction(ContainerAction.pause),
        ),
        MenuAction(
          title: ContainerAction.unpause.label,
          image: MenuImage.icon(Symbols.play_circle),
          attributes: MenuActionAttributes(disabled: !canUnpause),
          callback: () => onAction(ContainerAction.unpause),
        ),
        MenuSeparator(),
        MenuAction(
          title: ContainerAction.kill.label,
          image: MenuImage.icon(Symbols.dangerous),
          attributes: MenuActionAttributes(
            destructive: true,
            disabled: !running,
          ),
          callback: () => onAction(ContainerAction.kill),
        ),
        MenuAction(
          title: ContainerAction.remove.label,
          image: MenuImage.icon(Symbols.delete),
          attributes: const MenuActionAttributes(destructive: true),
          callback: () => onAction(ContainerAction.remove),
        ),
      ],
    );
    return AppContextMenuRegion(
      menuBuilder: menu,
      child: ContainerListTile(
        container: container,
        contentPadding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        onOpen: () => context.router.push(
          ContainerDetailRoute(
            server: server,
            runtime: environment.runtime,
            scope: environment.scope,
            containerId: container.id,
            containerName: container.name,
          ),
        ),
        trailing: PopupMenuButton<ContainerAction>(
          tooltip: 'Container actions',
          onSelected: onAction,
          itemBuilder: (context) => [
            PopupMenuItem(
              value: ContainerAction.start,
              enabled: !running,
              child: Row(
                children: menuRows(ContainerAction.start, Symbols.play_arrow),
              ),
            ),
            PopupMenuItem(
              value: ContainerAction.stop,
              enabled: running,
              child: Row(
                children: menuRows(ContainerAction.stop, Symbols.stop),
              ),
            ),
            PopupMenuItem(
              value: ContainerAction.restart,
              child: Row(
                children: menuRows(
                  ContainerAction.restart,
                  Symbols.restart_alt,
                ),
              ),
            ),
            PopupMenuItem(
              value: ContainerAction.pause,
              enabled: canPause,
              child: Row(
                children: menuRows(ContainerAction.pause, Symbols.pause),
              ),
            ),
            PopupMenuItem(
              value: ContainerAction.unpause,
              enabled: canUnpause,
              child: Row(
                children: menuRows(
                  ContainerAction.unpause,
                  Symbols.play_circle,
                ),
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: ContainerAction.kill,
              enabled: running,
              child: Row(
                children: menuRows(ContainerAction.kill, Symbols.dangerous),
              ),
            ),
            PopupMenuItem(
              value: ContainerAction.remove,
              child: Row(
                children: menuRows(ContainerAction.remove, Symbols.delete),
              ),
            ),
          ],
          icon: const Icon(Symbols.more_vert),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ContainerEmptyPanel extends StatelessWidget {
  const _ContainerEmptyPanel({
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
        ),
      ),
    );
  }
}
