import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/github/github_models.dart';
import 'package:maid_kit/github/github_providers.dart';
import 'package:maid_kit/github/github_ui.dart';
import 'package:maid_kit/routing/app_router.dart';
import 'package:maid_kit/routing/app_router.gr.dart';
import 'package:maid_kit/servers/server_connection_actions.dart';
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/systemd_models.dart';
import 'package:maid_kit/servers/terminal_tabs_provider.dart';
import 'package:maid_kit/shared/presentation/app_scaffold.dart';
import 'package:maid_kit/shared/presentation/cloud_file_picker.dart';
import 'package:maid_kit/theme.dart';
import 'package:url_launcher/url_launcher.dart';
import 'container_models.dart';
import 'container_list_tile.dart';
import 'compose_project_actions.dart';
import 'deployment_project_models.dart';
import 'image_actions.dart';
import 'project_repository.dart';

/// Detail view for a stored deployment project — a collection of resources.
/// [linkId] remains for links opened from the server container view.
@RoutePage()
class ProjectDetailPage extends ConsumerWidget {
  const ProjectDetailPage({super.key, this.projectId, this.linkId});

  final int? projectId;
  final int? linkId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(deploymentProjectsProvider);
    final resources = ref.watch(deploymentResourcesProvider);
    return projects.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        body: Center(
          child: Text('deploymentDetailLoadError'.tr(args: ['$error'])),
        ),
      ),
      data: (allProjects) {
        final allResources =
            resources.asData?.value ?? const <DeploymentResource>[];
        final resolvedId =
            projectId ?? _projectForComposeLink(allResources, linkId);
        final project = allProjects
            .where((item) => item.id == resolvedId)
            .firstOrNull;
        if (project == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text('deploymentDetailUnavailable'.tr())),
          );
        }
        return _ProjectDetail(
          project: project,
          resources: allResources
              .where((item) => item.projectId == project.id)
              .toList(),
        );
      },
    );
  }
}

int? _projectForComposeLink(List<DeploymentResource> resources, int? linkId) {
  if (linkId == null) return null;
  for (final resource in resources) {
    final config = _configuration(resource.configuration);
    if (config['compose_link_id'] == linkId) return resource.projectId;
  }
  return null;
}

class _ProjectDetail extends ConsumerStatefulWidget {
  const _ProjectDetail({required this.project, required this.resources});
  final DeploymentProject project;
  final List<DeploymentResource> resources;

  @override
  ConsumerState<_ProjectDetail> createState() => _ProjectDetailState();
}

class _ProjectDetailState extends ConsumerState<_ProjectDetail> {
  DeploymentResourceKind? _kindFilter;
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _addResource(List<Server> servers) async {
    final draft = await showModalBottomSheet<_ResourceDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (_) => _LinkResourceSheet(servers: servers),
    );
    if (draft == null) return;
    await ref
        .read(projectRepositoryProvider)
        .addResource(
          projectId: widget.project.id,
          kind: draft.kind.name,
          name: draft.name,
          serverId: draft.serverId,
          configuration: draft.configuration,
        );
    if (mounted) {
      showStyledSnackBar(
        message: 'deploymentResourceAdded'.tr(args: [draft.name]),
        title: 'deploymentResourceAddedTitle'.tr(),
        icon: Symbols.check_circle,
      );
    }
  }

  Future<void> _editProject() async {
    final draft = await showDialog<_ProjectEditDraft>(
      context: context,
      builder: (context) => _ProjectEditDialog(
        initialName: widget.project.name,
        initialDescription: widget.project.description,
      ),
    );
    if (draft == null) return;
    await ref
        .read(projectRepositoryProvider)
        .updateProject(
          projectId: widget.project.id,
          name: draft.name,
          description: draft.description,
        );
  }

  Future<void> _deleteProject() async {
    final count = widget.resources.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('deploymentDeleteTitle'.tr()),
        content: Text(
          count == 0
              ? 'deploymentDeleteConfirmEmpty'.tr(args: [widget.project.name])
              : 'deploymentDeleteConfirm'.tr(
                  namedArgs: {
                    'name': widget.project.name,
                    'count': '$count',
                    'plural': count == 1 ? '' : 's',
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('commonCancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: Text('commonDelete'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(projectRepositoryProvider).deleteProject(widget.project.id);
    if (mounted) context.router.maybePop();
  }

  Future<void> _deleteResource(DeploymentResource resource) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('deploymentRemoveTitle'.tr()),
        content: Text('deploymentRemoveConfirm'.tr(args: [resource.name])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('commonCancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('commonRemove'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(projectRepositoryProvider).deleteResource(resource.id);
  }

  List<DeploymentResource> get _filteredResources {
    final query = _query.trim().toLowerCase();
    return widget.resources.where((resource) {
      final kind = deploymentResourceKindFromId(resource.kind);
      if (_kindFilter != null && kind != _kindFilter) return false;
      if (query.isEmpty) return true;
      if (resource.name.toLowerCase().contains(query)) return true;
      if (resource.kind.toLowerCase().contains(query)) return true;
      final config = resource.configuration.toLowerCase();
      return config.contains(query);
    }).toList();
  }

  Map<DeploymentResourceKind, List<DeploymentResource>> get _grouped {
    final map = <DeploymentResourceKind, List<DeploymentResource>>{};
    for (final resource in _filteredResources) {
      final kind = deploymentResourceKindFromId(resource.kind);
      map.putIfAbsent(kind, () => []).add(resource);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final servers =
        ref.watch(serversProvider).asData?.value ?? const <Server>[];
    final serverNames = {for (final server in servers) server.id: server.name};
    final serverById = {for (final server in servers) server.id: server};
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final kindCounts = <DeploymentResourceKind, int>{};
    for (final resource in widget.resources) {
      final kind = deploymentResourceKindFromId(resource.kind);
      kindCounts[kind] = (kindCounts[kind] ?? 0) + 1;
    }
    final serverIds = {
      for (final r in widget.resources)
        if (r.serverId != null) r.serverId!,
    };
    // Flatten by kind so cards can share one horizontal waterfall instead of
    // stacking separate full-width sections under each kind header.
    final grouped = _grouped;
    final orderedResources = [
      for (final kind in DeploymentResourceKind.values) ...?grouped[kind],
    ];

    return MaidKitAppScaffold(
      appBar: AppBar(
        title: Text(widget.project.name),
        actions: [
          IconButton(
            tooltip: 'deploymentEditProject'.tr(),
            icon: const Icon(Symbols.edit),
            onPressed: _editProject,
          ),
          IconButton(
            tooltip: 'deploymentDeleteProject'.tr(),
            icon: const Icon(Symbols.delete),
            onPressed: _deleteProject,
          ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: () => _addResource(servers),
              icon: const Icon(Symbols.add, size: 18),
              label: Text('deploymentAddResource'.tr()),
            ),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.project.description?.isNotEmpty ?? false) ...[
                    Text(
                      widget.project.description!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _SummaryPill(
                        icon: Symbols.inventory_2,
                        label:
                            '${widget.resources.length} resource'
                            '${widget.resources.length == 1 ? '' : 's'}',
                      ),
                      if (serverIds.isNotEmpty)
                        _SummaryPill(
                          icon: Symbols.dns,
                          label: serverIds.length == 1
                              ? (serverNames[serverIds.first] ?? '1 server')
                              : '${serverIds.length} servers',
                        ),
                      for (final entry in kindCounts.entries)
                        _SummaryPill(
                          icon: deploymentResourceKindIcon(entry.key),
                          label:
                              '${deploymentResourceKindLabel(entry.key)}'
                              '${entry.value > 1 ? ' ×${entry.value}' : ''}',
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (widget.resources.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final wideToolbar = constraints.maxWidth >= 720;
                        final searchField = TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'deploymentFilterResources'.tr(),
                            prefixIcon: const Icon(Symbols.search, size: 20),
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'deploymentClearTooltip'.tr(),
                                    icon: const Icon(Symbols.close, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _query = '');
                                    },
                                  ),
                          ),
                          onChanged: (value) => setState(() => _query = value),
                        );
                        final kindChips = kindCounts.length > 1
                            ? SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    FilterChip(
                                      label: Text('deploymentFilterAll'.tr()),
                                      selected: _kindFilter == null,
                                      onSelected: (_) =>
                                          setState(() => _kindFilter = null),
                                    ),
                                    const SizedBox(width: 8),
                                    for (final kind in kindCounts.keys) ...[
                                      FilterChip(
                                        avatar: Icon(
                                          deploymentResourceKindIcon(kind),
                                          size: 16,
                                        ),
                                        label: Text(
                                          '${deploymentResourceKindLabel(kind)}'
                                          ' (${kindCounts[kind]})',
                                        ),
                                        selected: _kindFilter == kind,
                                        onSelected: (selected) => setState(
                                          () => _kindFilter = selected
                                              ? kind
                                              : null,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                  ],
                                ),
                              )
                            : null;

                        if (!wideToolbar || kindChips == null) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              searchField,
                              if (kindChips != null) ...[
                                const SizedBox(height: 10),
                                kindChips,
                              ],
                            ],
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(width: 280, child: searchField),
                            const SizedBox(width: 16),
                            Expanded(child: kindChips),
                          ],
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text(
                        'deploymentResourcesTitle'.tr(),
                        style: theme.textTheme.titleMedium,
                      ),
                      const Spacer(),
                      if (widget.resources.isNotEmpty)
                        Text(
                          _filteredResources.length == widget.resources.length
                              ? 'deploymentResourcesTotal'.tr(
                                  args: ['${widget.resources.length}'],
                                )
                              : 'deploymentResourcesFiltered'.tr(
                                  args: [
                                    '${_filteredResources.length}',
                                    '${widget.resources.length}',
                                  ],
                                ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          if (widget.resources.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              sliver: SliverToBoxAdapter(
                child: _EmptyResources(
                  projectName: widget.project.name,
                  onAdd: () => _addResource(servers),
                ),
              ),
            )
          else if (_filteredResources.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              sliver: SliverToBoxAdapter(
                child: Center(child: Text('deploymentNoFilterMatch'.tr())),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              sliver: SliverToBoxAdapter(
                child: _ResourceWaterfall(
                  resources: orderedResources,
                  serverNames: serverNames,
                  serverById: serverById,
                  onDelete: _deleteResource,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Multi-column masonry layout. Wider columns, packs left-to-right so the
/// resource preview uses horizontal space instead of a single tall stack.
class _ResourceWaterfall extends StatelessWidget {
  const _ResourceWaterfall({
    required this.resources,
    required this.serverNames,
    required this.serverById,
    required this.onDelete,
  });

  final List<DeploymentResource> resources;
  final Map<int, String> serverNames;
  final Map<int, Server> serverById;
  final ValueChanged<DeploymentResource> onDelete;

  /// Prefer fewer, wider cards on desktop.
  static const double _minColumnWidth = 480;
  static const double _columnGap = 16;
  static const int _maxColumns = 3;

  static int columnCountFor(double width) {
    if (width <= 0) return 1;
    final raw = ((width + _columnGap) / (_minColumnWidth + _columnGap)).floor();
    return raw.clamp(1, _maxColumns);
  }

  /// Row-major buckets: item 0 → col 0, item 1 → col 1, … so the first
  /// screenful fills across before growing downward.
  static List<List<T>> distribute<T>(List<T> items, int columns) {
    if (columns <= 1) return [List<T>.from(items)];
    final buckets = List.generate(columns, (_) => <T>[]);
    for (var i = 0; i < items.length; i++) {
      buckets[i % columns].add(items[i]);
    }
    return buckets;
  }

  Widget _tile(DeploymentResource resource) {
    return _ResourceTile(
      resource: resource,
      serverName: resource.serverId == null
          ? null
          : serverNames[resource.serverId!],
      server: resource.serverId == null ? null : serverById[resource.serverId!],
      onDelete: () => onDelete(resource),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnCountFor(constraints.maxWidth);
        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final resource in resources) _tile(resource)],
          );
        }

        final buckets = distribute(resources, columns);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < columns; c++) ...[
              if (c > 0) const SizedBox(width: _columnGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final resource in buckets[c]) _tile(resource),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
        color: scheme.surfaceContainerLowest,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _ProjectEditDraft {
  const _ProjectEditDraft({required this.name, this.description});
  final String name;
  final String? description;
}

class _ProjectEditDialog extends StatefulWidget {
  const _ProjectEditDialog({
    required this.initialName,
    this.initialDescription,
  });
  final String initialName;
  final String? initialDescription;

  @override
  State<_ProjectEditDialog> createState() => _ProjectEditDialogState();
}

class _ProjectEditDialogState extends State<_ProjectEditDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _descriptionController = TextEditingController(
      text: widget.initialDescription ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final description = _descriptionController.text.trim();
    Navigator.pop(
      context,
      _ProjectEditDraft(
        name: name,
        description: description.isEmpty ? null : description,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('deploymentEditTitle'.tr()),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'deploymentEditNameLabel'.tr(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'deploymentEditDescriptionLabel'.tr(),
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text('commonCancel'.tr()),
      ),
      FilledButton(onPressed: _submit, child: Text('commonSave'.tr())),
    ],
  );
}

class _ResourceTile extends ConsumerStatefulWidget {
  const _ResourceTile({
    required this.resource,
    this.serverName,
    this.server,
    required this.onDelete,
  });
  final DeploymentResource resource;
  final String? serverName;
  final Server? server;
  final VoidCallback onDelete;

  @override
  ConsumerState<_ResourceTile> createState() => _ResourceTileState();
}

class _ResourceTileState extends ConsumerState<_ResourceTile> {
  var _expanded = false;
  var _busy = false;

  DeploymentResource get resource => widget.resource;
  Server? get server => widget.server;

  Map<String, Object?> get config => _configuration(resource.configuration);
  DeploymentResourceKind get kind =>
      deploymentResourceKindFromId(resource.kind);

  String get _githubOwner => '${effectiveConfig['owner'] ?? ''}'.trim();
  String get _githubName => '${effectiveConfig['name'] ?? ''}'.trim();
  String get _githubWorkflow => '${effectiveConfig['workflow'] ?? ''}'.trim();

  /// The latest run of the linked workflow, watched while the tile builds.
  WorkflowRun? get _githubRun {
    if (_githubOwner.isEmpty ||
        _githubName.isEmpty ||
        _githubWorkflow.isEmpty) {
      return null;
    }
    return ref
        .watch(
          githubLinkedRunProvider((
            owner: _githubOwner,
            name: _githubName,
            workflowName: _githubWorkflow,
          )),
        )
        .asData
        ?.value;
  }

  /// Portable JSON plus fields resolved from a linked [ComposeProjectLink]
  /// (migrated resources often only store `compose_link_id`).
  Map<String, Object?> get effectiveConfig {
    final base = Map<String, Object?>.of(config);
    final link = _composeLink;
    if (link == null) return base;
    base.putIfAbsent('directory', () => link.directory);
    base.putIfAbsent('runtime', () => link.runtime);
    base.putIfAbsent('scope', () => link.scope);
    base.putIfAbsent('compose_project', () => link.name);
    if ('${base['directory'] ?? ''}'.trim().isEmpty) {
      base['directory'] = link.directory;
    }
    if ('${base['runtime'] ?? ''}'.trim().isEmpty) {
      base['runtime'] = link.runtime;
    }
    if ('${base['scope'] ?? ''}'.trim().isEmpty) {
      base['scope'] = link.scope;
    }
    if ('${base['compose_project'] ?? ''}'.trim().isEmpty) {
      base['compose_project'] = link.name;
    }
    return base;
  }

  ComposeProjectLink? get _composeLink {
    final raw = config['compose_link_id'];
    if (raw == null) return null;
    final linkId = raw is int ? raw : int.tryParse('$raw');
    if (linkId == null) return null;
    final links =
        ref.watch(composeProjectLinksProvider).asData?.value ??
        const <ComposeProjectLink>[];
    return links.where((item) => item.id == linkId).firstOrNull;
  }

  ContainerRuntime get _runtime => _runtimeFrom(effectiveConfig);
  ContainerScope get _scope => _scopeFrom(effectiveConfig);

  String get _composeName =>
      '${effectiveConfig['compose_project'] ?? resource.name}'.trim();
  String get _composeDirectory =>
      '${effectiveConfig['directory'] ?? ''}'.trim();
  bool get _composeReady =>
      server != null && _composeDirectory.isNotEmpty && _composeName.isNotEmpty;
  String get _containerRef =>
      '${effectiveConfig['container'] ?? resource.name}'.trim();
  String get _systemdUnit {
    final unit =
        '${effectiveConfig['unit'] ?? effectiveConfig['service_unit'] ?? ''}'
            .trim();
    if (unit.isNotEmpty) return unit;
    if (kind == DeploymentResourceKind.systemdService) return resource.name;
    return '';
  }

  List<_QuickActionSpec> get _quickActions {
    if (server == null) return const [];
    return switch (kind) {
      DeploymentResourceKind.compose => [
        _QuickActionSpec(
          id: 'compose_up',
          label: 'deploymentQuickActionStart'.tr(),
          icon: Symbols.play_arrow,
          enabled: _composeReady,
        ),
        _QuickActionSpec(
          id: 'compose_pull',
          label: 'deploymentQuickActionPull'.tr(),
          icon: Symbols.download,
          enabled: _composeReady,
        ),
        _QuickActionSpec(
          id: 'compose_restart',
          label: 'deploymentQuickActionRestart'.tr(),
          icon: Symbols.restart_alt,
          enabled: _composeReady,
        ),
        _QuickActionSpec(
          id: 'compose_logs',
          label: 'deploymentQuickActionLogs'.tr(),
          icon: Symbols.terminal,
          enabled: _composeReady,
        ),
        _QuickActionSpec(
          id: 'prune_images',
          label: 'deploymentCleanUpImages'.tr(),
          icon: Symbols.cleaning_services,
        ),
        _QuickActionSpec(
          id: 'compose_stop',
          label: 'deploymentQuickActionStop'.tr(),
          icon: Symbols.stop,
          enabled: _composeReady,
        ),
      ],
      DeploymentResourceKind.container => [
        _QuickActionSpec(
          id: 'container_restart',
          label: 'deploymentQuickActionRestart'.tr(),
          icon: Symbols.restart_alt,
          enabled: _containerRef.isNotEmpty,
        ),
        _QuickActionSpec(
          id: 'container_logs',
          label: 'deploymentQuickActionLogs'.tr(),
          icon: Symbols.terminal,
          enabled: _containerRef.isNotEmpty,
        ),
        _QuickActionSpec(
          id: 'prune_images',
          label: 'deploymentCleanUpImages'.tr(),
          icon: Symbols.cleaning_services,
        ),
        _QuickActionSpec(
          id: 'container_start',
          label: 'deploymentQuickActionStart'.tr(),
          icon: Symbols.play_arrow,
          enabled: _containerRef.isNotEmpty,
        ),
        _QuickActionSpec(
          id: 'container_stop',
          label: 'deploymentQuickActionStop'.tr(),
          icon: Symbols.stop,
          enabled: _containerRef.isNotEmpty,
        ),
      ],
      DeploymentResourceKind.systemdService ||
      DeploymentResourceKind.webServer => [
        _QuickActionSpec(
          id: 'systemd_status',
          label: 'deploymentQuickActionStatus'.tr(),
          icon: Symbols.info,
          enabled: _systemdUnit.isNotEmpty,
        ),
        _QuickActionSpec(
          id: 'systemd_logs',
          label: 'deploymentQuickActionLogs'.tr(),
          icon: Symbols.terminal,
          enabled: _systemdUnit.isNotEmpty,
        ),
        _QuickActionSpec(
          id: 'systemd_restart',
          label: 'deploymentQuickActionRestart'.tr(),
          icon: Symbols.restart_alt,
          enabled: _systemdUnit.isNotEmpty,
        ),
        _QuickActionSpec(
          id: 'systemd_start',
          label: 'deploymentQuickActionStart'.tr(),
          icon: Symbols.play_arrow,
          enabled: _systemdUnit.isNotEmpty,
        ),
        _QuickActionSpec(
          id: 'systemd_stop',
          label: 'deploymentQuickActionStop'.tr(),
          icon: Symbols.stop,
          enabled: _systemdUnit.isNotEmpty,
        ),
      ],
      DeploymentResourceKind.githubWorkflow => [
        _QuickActionSpec(
          id: 'github_open_run',
          label: 'deploymentGithubOpenRun'.tr(),
          icon: Symbols.open_in_new,
          enabled: _githubRun != null,
        ),
        _QuickActionSpec(
          id: 'github_open_web',
          label: 'githubRunOpen'.tr(),
          icon: Symbols.language,
          enabled: _githubRun?.htmlUrl.isNotEmpty ?? false,
        ),
      ],
      _ => const [],
    };
  }

  Future<String?> _sudoPassword() async {
    final host = server;
    if (host == null) return null;
    final credential = await ref
        .read(serverRepositoryProvider)
        .credentialFor(host);
    return credential.type == CredentialType.password
        ? credential.password
        : null;
  }

  Future<void> _runQuickAction(String id) async {
    final host = server;
    if (host == null || _busy) return;
    setState(() => _busy = true);
    try {
      switch (id) {
        case 'compose_up':
          await _runCompose(ComposeProjectAction.up);
        case 'compose_pull':
          await _runCompose(ComposeProjectAction.pull);
        case 'compose_restart':
          await _runCompose(ComposeProjectAction.restart);
        case 'compose_stop':
          await _runCompose(ComposeProjectAction.stop);
        case 'compose_logs':
          await _showComposeLogs();
        case 'prune_images':
          await _pruneImages();
        case 'container_start':
          await _runContainer(ContainerAction.start);
        case 'container_stop':
          await _runContainer(ContainerAction.stop);
        case 'container_restart':
          await _runContainer(ContainerAction.restart);
        case 'container_logs':
          await _showContainerLogs();
        case 'systemd_status':
          await _showSystemdStatus();
        case 'systemd_logs':
          await _showSystemdLogs();
        case 'systemd_start':
          await _runSystemd(SystemdUnitAction.start);
        case 'systemd_stop':
          await _runSystemd(SystemdUnitAction.stop);
        case 'systemd_restart':
          await _runSystemd(SystemdUnitAction.restart);
        case 'github_open_run':
          await _openGithubRun();
        case 'github_open_web':
          final run = _githubRun;
          if (run != null && run.htmlUrl.isNotEmpty) {
            await launchUrl(Uri.parse(run.htmlUrl));
          }
      }
    } catch (error) {
      if (mounted) {
        showStyledSnackBar(
          message: '$error',
          title: 'deploymentActionFailed'.tr(),
          icon: Symbols.error,
          accentColor: Theme.of(context).colorScheme.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openGithubRun() async {
    final run = _githubRun;
    if (run == null) return;
    await context.router.push(
      GitHubRunDetailRoute(
        owner: _githubOwner,
        name: _githubName,
        runId: run.id,
        run: run,
      ),
    );
  }

  Future<void> _runCompose(ComposeProjectAction action) async {
    final host = server!;
    if (!_composeReady) {
      throw StateError('deploymentComposeMissing'.tr());
    }
    await runComposeProjectActionWithTerminal(
      ref: ref,
      serverId: host.id,
      serverName: host.name,
      runtime: _runtime,
      scope: _scope,
      projectName: _composeName,
      directory: _composeDirectory,
      action: action,
      sudoPassword: await _sudoPassword(),
    );
  }

  Future<void> _runContainer(ContainerAction action) async {
    final host = server!;
    if (_containerRef.isEmpty) {
      throw StateError('deploymentContainerMissing'.tr());
    }
    await ref
        .read(connectionManagerProvider)
        .runContainerAction(
          host.id,
          runtime: _runtime,
          scope: _scope,
          containerId: _containerRef,
          action: action,
          sudoPassword: await _sudoPassword(),
        );
    if (mounted) {
      showStyledSnackBar(
        message: resource.name,
        title: 'deploymentContainerSuccess'.tr(args: [action.pastLabel]),
        icon: Symbols.check_circle,
      );
    }
  }

  Future<void> _pruneImages() async {
    final host = server!;
    await runImagePruneWithTerminal(
      ref: ref,
      serverId: host.id,
      serverName: host.name,
      runtime: _runtime,
      scope: _scope,
      sudoPassword: await _sudoPassword(),
    );
    if (mounted) {
      showStyledSnackBar(
        message: 'deploymentCleanUpImagesHint'.tr(),
        title: 'deploymentCleanUpImagesDone'.tr(),
        icon: Symbols.check_circle,
      );
    }
  }

  Future<void> _runSystemd(SystemdUnitAction action) async {
    final host = server!;
    final unit = _systemdUnit;
    if (unit.isEmpty) {
      throw StateError('deploymentSystemdMissing'.tr());
    }
    await ref
        .read(connectionManagerProvider)
        .runSystemdUnitAction(
          host.id,
          unit: unit,
          action: action,
          sshUserIsRoot: host.username == 'root',
          sudoPassword: await _sudoPassword(),
        );
    if (mounted) {
      final past = switch (action) {
        SystemdUnitAction.start => 'deploymentServiceStarted',
        SystemdUnitAction.stop => 'deploymentServiceStopped',
        SystemdUnitAction.restart => 'deploymentServiceRestarted',
        SystemdUnitAction.reload => 'deploymentServiceReloaded',
        SystemdUnitAction.enable => 'deploymentServiceEnabled',
        SystemdUnitAction.disable => 'deploymentServiceDisabled',
      };
      showStyledSnackBar(
        message: unit,
        title: 'deploymentServiceSuccess'.tr(args: [past.tr()]),
        icon: Symbols.check_circle,
      );
    }
  }

  Future<void> _showComposeLogs() async {
    final host = server!;
    if (!_composeReady) {
      throw StateError('deploymentComposeMissing'.tr());
    }
    await _showRemoteText(
      title: 'deploymentLogsTitle'.tr(args: [_composeName]),
      load: () async {
        final sudo = await _sudoPassword();
        return ref
            .read(connectionManagerProvider)
            .readComposeProjectLogs(
              host.id,
              runtime: _runtime,
              scope: _scope,
              projectName: _composeName,
              directory: _composeDirectory,
              sudoPassword: sudo,
            );
      },
    );
  }

  Future<void> _showContainerLogs() async {
    final host = server!;
    await context.router.push(
      ContainerDetailRoute(
        server: host,
        runtime: _runtime,
        scope: _scope,
        containerId: _containerRef,
        containerName: _containerRef,
      ),
    );
  }

  Future<void> _showSystemdStatus() async {
    final host = server!;
    final unit = _systemdUnit;
    await _showRemoteText(
      title: 'deploymentStatusTitle'.tr(args: [unit]),
      load: () async {
        final sudo = await _sudoPassword();
        return ref
            .read(connectionManagerProvider)
            .getSystemdUnitStatus(
              host.id,
              unit: unit,
              sshUserIsRoot: host.username == 'root',
              sudoPassword: sudo,
            );
      },
    );
  }

  Future<void> _showSystemdLogs() async {
    final host = server!;
    final unit = _systemdUnit;
    await _showRemoteText(
      title: 'deploymentLogsTitle'.tr(args: [unit]),
      load: () async {
        final sudo = await _sudoPassword();
        return ref
            .read(connectionManagerProvider)
            .getSystemdUnitLogs(
              host.id,
              unit: unit,
              sshUserIsRoot: host.username == 'root',
              sudoPassword: sudo,
            );
      },
    );
  }

  Future<void> _showRemoteText({
    required String title,
    required Future<String> Function() load,
  }) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (_) => _RemoteTextSheet(title: title, load: load),
    );
  }

  Future<void> _editConfiguration() async {
    final servers = ref.read(serversProvider).asData?.value ?? const <Server>[];
    final draft = await showModalBottomSheet<_ResourceDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (_) => _LinkResourceSheet(
        servers: servers,
        initialDraft: _ResourceDraft(
          kind: kind,
          name: resource.name,
          serverId: resource.serverId,
          configuration: effectiveConfig,
        ),
      ),
    );
    if (draft == null) return;

    await ref
        .read(projectRepositoryProvider)
        .updateResource(
          resourceId: resource.id,
          kind: draft.kind.name,
          name: draft.name,
          serverId: draft.serverId,
          configuration: draft.configuration,
        );
    if (mounted) {
      showStyledSnackBar(
        message: resource.name,
        title: 'deploymentConfigSaved'.tr(),
        icon: Symbols.check_circle,
      );
    }
  }

  Future<void> _openOnServer() async {
    final host = server;
    if (host == null) return;
    if (kind == DeploymentResourceKind.serverFolder) {
      final manager = ref.read(connectionManagerProvider);
      if (manager.clientFor(host.id) == null &&
          !await connectForStatistics(context, ref, host)) {
        return;
      }
      if (!mounted) return;
      final path = '${effectiveConfig['path'] ?? ''}'.trim();
      // Land on the Servers workspace tab with a file-management tab opened
      // at the linked folder instead of a transient picker.
      ref
          .read(terminalTabsProvider.notifier)
          .openFileManagement(host, initialPath: path.isEmpty ? null : path);
      context.router.root.navigate(
        ServerWorkspaceRoute(children: [ServersTab()]),
      );
      return;
    }
    if (kind == DeploymentResourceKind.compose) {
      if (!_composeReady) {
        // Missing identity — fall back to the server's container tab.
        context.router.push(ServerDetailRoute(server: host, initialTab: 4));
        return;
      }
      context.router.push(
        ComposeDetailRoute(
          server: host,
          runtime: _runtime,
          scope: _scope,
          projectName: _composeName,
          directory: _composeDirectory,
        ),
      );
      return;
    }
    context.router.push(
      ServerDetailRoute(server: host, initialTab: _serverTabFor(kind)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final configSummary = deploymentResourceConfigSummary(effectiveConfig);
    final subtitleParts = <String>[
      deploymentResourceKindLabel(kind),
      ?widget.serverName,
      if (configSummary.isNotEmpty) configSummary,
    ];
    final actions = _quickActions;
    // Show the most useful actions as chips; remainder stay in overflow menu.
    final primary = actions.take(4).toList();
    final overflow = actions.skip(4).toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              child: Row(
                children: [
                  Icon(deploymentResourceKindIcon(kind), color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(resource.name, style: theme.textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          subtitleParts.join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  Icon(
                    _expanded ? Symbols.expand_less : Symbols.expand_more,
                    color: scheme.onSurfaceVariant,
                  ),
                  IconButton(
                    tooltip: 'deploymentRemoveFromProject'.tr(),
                    icon: const Icon(Symbols.close),
                    onPressed: widget.onDelete,
                  ),
                ],
              ),
            ),
          ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final action in primary)
                    OutlinedButton.icon(
                      onPressed: _busy || !action.enabled
                          ? null
                          : () => _runQuickAction(action.id),
                      icon: Icon(action.icon, size: 16),
                      label: Text(action.label),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                    ),
                  if (overflow.isNotEmpty)
                    PopupMenuButton<String>(
                      tooltip: 'deploymentMoreActions'.tr(),
                      enabled: !_busy,
                      onSelected: _runQuickAction,
                      itemBuilder: (_) => [
                        for (final action in overflow)
                          PopupMenuItem(
                            value: action.id,
                            enabled: action.enabled,
                            child: Text(action.label),
                          ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Symbols.more_horiz,
                              size: 18,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'deploymentMoreActions'.tr(),
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(height: 1, color: scheme.outlineVariant),
                  const SizedBox(height: 12),
                  if (kind == DeploymentResourceKind.githubWorkflow)
                    _GithubWorkflowLivePanel(
                      owner: _githubOwner,
                      name: _githubName,
                      workflow: _githubWorkflow,
                    ),
                  if (kind == DeploymentResourceKind.compose && server != null)
                    _ComposeLivePanel(
                      server: server!,
                      resource: resource,
                      configuration: effectiveConfig,
                    ),
                  if (!_composeReady && kind == DeploymentResourceKind.compose)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        'deploymentComposeNotReady'.tr(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.error,
                        ),
                      ),
                    ),
                  if (effectiveConfig.isNotEmpty) ...[
                    Row(
                      children: [
                        Text(
                          'deploymentConfigTitle'.tr(),
                          style: theme.textTheme.labelMedium,
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'deploymentEditConfiguration'.tr(),
                          icon: const Icon(Symbols.edit, size: 18),
                          onPressed: _editConfiguration,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ...effectiveConfig.entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 120,
                              child: Text(
                                entry.key,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                _formatConfigValue(entry.value),
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ] else
                    Row(
                      children: [
                        Expanded(child: Text('deploymentConfigEmpty'.tr())),
                        IconButton(
                          tooltip: 'deploymentEditConfiguration'.tr(),
                          icon: const Icon(Symbols.edit, size: 18),
                          onPressed: _editConfiguration,
                        ),
                      ],
                    ),
                  if (server != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _openOnServer,
                        icon: const Icon(Symbols.open_in_new, size: 18),
                        label: Text(
                          kind == DeploymentResourceKind.serverFolder
                              ? 'deploymentBrowseServer'.tr(
                                  args: [server!.name],
                                )
                              : 'deploymentOpenOnServer'.tr(
                                  args: [server!.name],
                                ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickActionSpec {
  const _QuickActionSpec({
    required this.id,
    required this.label,
    required this.icon,
    this.enabled = true,
  });

  final String id;
  final String label;
  final IconData icon;
  final bool enabled;
}

class _RemoteTextSheet extends StatefulWidget {
  const _RemoteTextSheet({required this.title, required this.load});

  final String title;
  final Future<String> Function() load;

  @override
  State<_RemoteTextSheet> createState() => _RemoteTextSheetState();
}

class _RemoteTextSheetState extends State<_RemoteTextSheet> {
  late Future<String> _future;
  String? _text;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _text = null;
    _future = widget.load().then((value) {
      if (mounted) setState(() => _text = value);
      return value;
    });
  }

  Future<void> _copy() async {
    final text = _text;
    if (text == null || text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showStyledSnackBar(
      message: 'deploymentRemoteCopySuccess'.tr(),
      title: widget.title,
      icon: Symbols.content_copy,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canCopy = _text != null && _text!.isNotEmpty;
    return SheetScaffold(
      titleText: widget.title,
      heightFactor: 0.78,
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: () => setState(_reload),
          icon: const Icon(Symbols.refresh),
          style: IconButton.styleFrom(minimumSize: const Size(36, 36)),
        ),
        IconButton(
          tooltip: 'Copy',
          onPressed: canCopy ? _copy : null,
          icon: const Icon(Symbols.content_copy),
          style: IconButton.styleFrom(minimumSize: const Size(36, 36)),
        ),
      ],
      child: FutureBuilder<String>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'deploymentRemoteLoading'.tr(args: ['${snapshot.error}']),
                    style: TextStyle(color: scheme.error),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonal(
                      onPressed: () => setState(_reload),
                      child: Text('deploymentRemoteRetry'.tr()),
                    ),
                  ),
                ],
              ),
            );
          }
          final text = snapshot.data ?? '';
          if (text.trim().isEmpty) {
            return Center(child: Text('deploymentRemoteEmpty'.tr()));
          }
          return SelectionArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: MaidKitFonts.mono,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

ContainerRuntime _runtimeFrom(Map<String, Object?> config) {
  final raw = '${config['runtime'] ?? 'docker'}';
  return ContainerRuntime.values.firstWhere(
    (value) => value.name == raw,
    orElse: () => ContainerRuntime.docker,
  );
}

ContainerScope _scopeFrom(Map<String, Object?> config) {
  final raw = '${config['scope'] ?? 'user'}';
  return ContainerScope.values.firstWhere(
    (value) => value.name == raw,
    orElse: () => ContainerScope.user,
  );
}

String _formatConfigValue(Object? value) {
  if (value is List) {
    if (value.isEmpty) return '—';
    if (value.first is Map) {
      return value
          .map((item) {
            if (item is Map) {
              final name = item['name'] ?? item['path'];
              return name?.toString() ?? item.toString();
            }
            return item.toString();
          })
          .join(', ');
    }
    return value.join(', ');
  }
  if (value is Map) {
    return value.entries.map((e) => '${e.key}: ${e.value}').join(', ');
  }
  final text = '$value'.trim();
  return text.isEmpty ? '—' : text;
}

class _ComposeLivePanel extends ConsumerStatefulWidget {
  const _ComposeLivePanel({
    required this.server,
    required this.resource,
    required this.configuration,
  });
  final Server server;
  final DeploymentResource resource;
  final Map<String, Object?> configuration;
  @override
  ConsumerState<_ComposeLivePanel> createState() => _ComposeLivePanelState();
}

class _ComposeLivePanelState extends ConsumerState<_ComposeLivePanel> {
  Future<List<ServerContainer>>? _containers;
  String get _name =>
      '${widget.configuration['compose_project'] ?? widget.resource.name}';
  @override
  void initState() {
    super.initState();
    _containers = _load();
  }

  Future<List<ServerContainer>> _load() async {
    final credential = await ref
        .read(serverRepositoryProvider)
        .credentialFor(widget.server);
    final environments = await ref
        .read(connectionManagerProvider)
        .listContainers(
          widget.server.id,
          sshUserIsRoot: widget.server.username == 'root',
          sudoPassword: credential.type == CredentialType.password
              ? credential.password
              : null,
        );
    return [
      for (final environment in environments)
        ...environment.containers.where((item) => item.composeProject == _name),
    ];
  }

  ContainerRuntime get _runtime => _runtimeFrom(widget.configuration);
  ContainerScope get _scope => _scopeFrom(widget.configuration);

  Future<String?> _sudoPassword() async {
    final credential = await ref
        .read(serverRepositoryProvider)
        .credentialFor(widget.server);
    return credential.type == CredentialType.password
        ? credential.password
        : null;
  }

  Future<void> _containerAction(
    ServerContainer container,
    ContainerAction action,
  ) async {
    try {
      await ref
          .read(connectionManagerProvider)
          .runContainerAction(
            widget.server.id,
            runtime: _runtime,
            scope: _scope,
            containerId: container.id,
            action: action,
            sudoPassword: await _sudoPassword(),
          );
      if (mounted) {
        showStyledSnackBar(
          message: container.name,
          title: 'deploymentContainerSuccess'.tr(args: [action.pastLabel]),
          icon: Symbols.check_circle,
        );
        setState(() => _containers = _load());
      }
    } catch (error) {
      if (mounted) {
        showStyledSnackBar(
          message: '$error',
          title: 'Action failed',
          icon: Symbols.error,
          accentColor: Theme.of(context).colorScheme.error,
        );
      }
    }
  }

  Future<void> _containerLogs(ServerContainer container) async {
    await context.router.push(
      ContainerDetailRoute(
        server: widget.server,
        runtime: _runtime,
        scope: _scope,
        containerId: container.id,
        containerName: container.name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ServerContainer>>(
    future: _containers,
    builder: (context, snapshot) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'deploymentLiveStack'.tr(),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              if (snapshot.connectionState == ConnectionState.done)
                IconButton(
                  tooltip: 'deploymentRefreshContainers'.tr(),
                  icon: const Icon(Symbols.refresh, size: 18),
                  onPressed: () => setState(() => _containers = _load()),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (snapshot.connectionState != ConnectionState.done)
            const LinearProgressIndicator()
          else if (snapshot.hasError)
            Text('deploymentStackLoadError'.tr(args: ['${snapshot.error}']))
          else if (snapshot.data!.isEmpty)
            Text('deploymentNoComposeContainers'.tr())
          else
            ...snapshot.data!.map((item) {
              final running = isContainerRunning(item);
              return ContainerListTile(
                container: item,
                contentPadding: EdgeInsets.zero,
                onOpen: () => context.router.push(
                  ContainerDetailRoute(
                    server: widget.server,
                    runtime: _runtime,
                    scope: _scope,
                    containerId: item.id,
                    containerName: item.name,
                  ),
                ),
                trailing: PopupMenuButton<String>(
                  tooltip: 'deploymentContainerActions'.tr(),
                  onSelected: (value) {
                    switch (value) {
                      case 'restart':
                        _containerAction(item, ContainerAction.restart);
                      case 'start':
                        _containerAction(item, ContainerAction.start);
                      case 'stop':
                        _containerAction(item, ContainerAction.stop);
                      case 'logs':
                        _containerLogs(item);
                    }
                  },
                  itemBuilder: (_) => [
                    if (running)
                      PopupMenuItem(
                        value: 'restart',
                        child: Text('deploymentQuickActionRestart'.tr()),
                      ),
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
                      value: 'logs',
                      child: Text('deploymentQuickActionLogs'.tr()),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    ),
  );
}

/// Latest run status of a linked GitHub workflow deployment resource.
class _GithubWorkflowLivePanel extends ConsumerWidget {
  const _GithubWorkflowLivePanel({
    required this.owner,
    required this.name,
    required this.workflow,
  });

  final String owner;
  final String name;
  final String workflow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final key = (owner: owner, name: name, workflowName: workflow);
    final run = ref.watch(githubLinkedRunProvider(key)).asData?.value;
    final loading = ref.watch(githubLinkedRunProvider(key)).isLoading;

    if (loading && run == null) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: LinearProgressIndicator(),
      );
    }
    if (run == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          'githubNoRuns'.tr(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final (:icon, :color) = githubRunStatusVisual(
      context,
      run.status,
      run.conclusion,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  run.displayTitle.isEmpty ? run.name : run.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (run.runNumber > 0) '#${run.runNumber}',
                    if (run.headBranch.isNotEmpty) run.headBranch,
                    githubRunDateTime(context, run.updatedAt ?? run.createdAt),
                    githubTimeAgo(context, run.updatedAt ?? run.createdAt),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'githubRunOpen'.tr(),
            onPressed: run.htmlUrl.isEmpty
                ? null
                : () => launchUrl(Uri.parse(run.htmlUrl)),
            icon: const Icon(Symbols.open_in_new, size: 18),
          ),
        ],
      ),
    );
  }
}

class _EmptyResources extends StatelessWidget {
  const _EmptyResources({required this.projectName, required this.onAdd});
  final String projectName;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surfaceContainerLowest,
      ),
      child: Column(
        children: [
          Icon(
            Symbols.add_link,
            size: 32,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'deploymentEmptyResourcesTitle'.tr(args: [projectName]),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Text(
            'deploymentEmptyResourcesHint'.tr(),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Symbols.add, size: 18),
            label: Text('deploymentAddResource'.tr()),
          ),
        ],
      ),
    );
  }
}

Map<String, Object?> _configuration(String source) {
  try {
    final value = jsonDecode(source);
    if (value is Map) return value.map((key, value) => MapEntry('$key', value));
  } catch (_) {}
  return const {};
}

int _serverTabFor(DeploymentResourceKind kind) => switch (kind) {
  DeploymentResourceKind.systemdService => 2,
  DeploymentResourceKind.webServer => 3,
  DeploymentResourceKind.container || DeploymentResourceKind.compose => 4,
  DeploymentResourceKind.firewallRule => 8,
  _ => 0,
};

class _ResourceDraft {
  const _ResourceDraft({
    required this.kind,
    required this.name,
    required this.serverId,
    required this.configuration,
  });

  final DeploymentResourceKind kind;
  final String name;
  final int? serverId;
  final Map<String, Object?> configuration;
}

class _LinkResourceSheet extends ConsumerStatefulWidget {
  const _LinkResourceSheet({required this.servers, this.initialDraft});
  final List<Server> servers;
  final _ResourceDraft? initialDraft;

  @override
  ConsumerState<_LinkResourceSheet> createState() => _LinkResourceSheetState();
}

class _LinkResourceSheetState extends ConsumerState<_LinkResourceSheet> {
  var _kind = DeploymentResourceKind.compose;
  int? _serverId;
  var _name = '';
  var _location = '';
  var _directory = '';
  var _runtime = ContainerRuntime.docker;
  var _scope = ContainerScope.user;
  var _suggestions = const <String>[];
  var _loadingSuggestions = false;
  String? _suggestionError;
  String? _ghRepoSlug;
  String? _ghWorkflow;

  bool get _isEditing => widget.initialDraft != null;

  static const _linkableKinds = [
    DeploymentResourceKind.compose,
    DeploymentResourceKind.container,
    DeploymentResourceKind.serverFolder,
    DeploymentResourceKind.firewallRule,
    DeploymentResourceKind.systemdService,
    DeploymentResourceKind.githubWorkflow,
  ];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDraft;
    if (initial == null) return;

    _kind = initial.kind;
    _serverId = initial.serverId;
    _name = initial.name;
    final configuration = initial.configuration;
    _location = switch (_kind) {
      DeploymentResourceKind.serverFolder => '${configuration['path'] ?? ''}',
      DeploymentResourceKind.container => '${configuration['container'] ?? ''}',
      DeploymentResourceKind.compose =>
        '${configuration['compose_project'] ?? ''}',
      DeploymentResourceKind.firewallRule => '${configuration['rule'] ?? ''}',
      DeploymentResourceKind.systemdService =>
        '${configuration['unit'] ?? configuration['service_unit'] ?? ''}',
      _ => '',
    };
    _directory = '${configuration['directory'] ?? ''}';
    _runtime = _runtimeFrom(configuration);
    _scope = _scopeFrom(configuration);
    if (_kind == DeploymentResourceKind.githubWorkflow) {
      _ghRepoSlug =
          '${configuration['owner'] ?? ''}/${configuration['name'] ?? ''}';
      _ghWorkflow = '${configuration['workflow'] ?? ''}';
    }
  }

  String get _locationLabel => switch (_kind) {
    DeploymentResourceKind.serverFolder => 'deploymentLocationFolder'.tr(),
    DeploymentResourceKind.container => 'deploymentLocationContainer'.tr(),
    DeploymentResourceKind.compose => 'deploymentLocationCompose'.tr(),
    DeploymentResourceKind.firewallRule => 'deploymentLocationFirewall'.tr(),
    DeploymentResourceKind.systemdService => 'deploymentLocationSystemd'.tr(),
    _ => '',
  };

  Map<String, Object?> get _configuration => switch (_kind) {
    DeploymentResourceKind.serverFolder => {'path': _location.trim()},
    DeploymentResourceKind.container => {'container': _location.trim()},
    DeploymentResourceKind.compose => {
      'compose_project': _location.trim(),
      'directory': _directory.trim(),
      'runtime': _runtime.name,
      'scope': _scope.name,
    },
    DeploymentResourceKind.firewallRule => {'rule': _location.trim()},
    DeploymentResourceKind.systemdService => {'unit': _location.trim()},
    DeploymentResourceKind.githubWorkflow => {
      'owner': _ghRepoSlug?.split('/').first ?? '',
      'name': _ghRepoSlug?.split('/').skip(1).join('/') ?? '',
      'workflow': _ghWorkflow ?? '',
    },
    _ => widget.initialDraft?.configuration ?? const {},
  };

  Future<void> _loadSuggestions() async {
    final serverId = _serverId;
    if (serverId == null || _locationLabel.isEmpty) return;
    final server = widget.servers
        .where((item) => item.id == serverId)
        .firstOrNull;
    if (server == null) return;
    setState(() {
      _loadingSuggestions = true;
      _suggestionError = null;
      _suggestions = const [];
    });
    try {
      final credential = await ref
          .read(serverRepositoryProvider)
          .credentialFor(server);
      final sudoPassword = credential.type == CredentialType.password
          ? credential.password
          : null;
      final manager = ref.read(connectionManagerProvider);
      final values = switch (_kind) {
        DeploymentResourceKind.container ||
        DeploymentResourceKind.compose => () async {
          final environments = await manager.listContainers(
            serverId,
            sshUserIsRoot: server.username == 'root',
            sudoPassword: sudoPassword,
          );
          return _kind == DeploymentResourceKind.compose
              ? {
                  for (final environment in environments)
                    for (final container in environment.containers)
                      if (container.composeProject != null)
                        container.composeProject!,
                }.toList()
              : [
                  for (final environment in environments)
                    for (final container in environment.containers)
                      container.name,
                ];
        }(),
        DeploymentResourceKind.systemdService => () async {
          final snapshot = await manager.listSystemdUnits(
            serverId,
            sshUserIsRoot: server.username == 'root',
            sudoPassword: sudoPassword,
          );
          return [for (final unit in snapshot.units) unit.name];
        }(),
        DeploymentResourceKind.firewallRule => () async {
          final status = await manager.getFirewallStatus(
            serverId,
            sshUserIsRoot: server.username == 'root',
            sudoPassword: sudoPassword,
          );
          return [for (final rule in status.rules) rule.display];
        }(),
        _ => Future.value(const <String>[]),
      };
      final suggestions = await values;
      if (mounted) {
        final unique = suggestions.toSet().toList()..sort();
        setState(() => _suggestions = unique);
      }
    } catch (error) {
      if (mounted) setState(() => _suggestionError = '$error');
    } finally {
      if (mounted) setState(() => _loadingSuggestions = false);
    }
  }

  void _selectSuggestion(String value) {
    setState(() {
      _location = value;
      if (_name.trim().isEmpty) _name = value;
    });
  }

  /// Repo picker for the GitHub workflow kind. Keyed by repo slug with a
  /// membership-guarded value so an async items refresh can never leave the
  /// dropdown holding a value that no longer matches an item.
  Widget _githubRepoDropdown() {
    final repos =
        ref.watch(githubAvailableReposProvider).asData?.value ??
        const <GitHubRepo>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'githubSelectRepo'.tr(),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        DropdownButton<String>(
          value: repos.any((repo) => repo.slug == _ghRepoSlug)
              ? _ghRepoSlug
              : null,
          isExpanded: true,
          hint: Text('githubSelectRepo'.tr()),
          items: [
            for (final repo in repos)
              DropdownMenuItem(
                value: repo.slug,
                child: Text(
                  repo.slug,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (slug) => setState(() {
            _ghRepoSlug = slug;
            _ghWorkflow = null;
          }),
        ),
      ],
    );
  }

  /// Workflow picker for the GitHub workflow kind, gated on the selected repo.
  Widget _githubWorkflowDropdown() {
    final workflows = _ghRepoSlug == null
        ? const <GitHubWorkflow>[]
        : ref
                  .watch(
                    githubWorkflowsProvider(
                      GitHubRepoRef(
                        owner: _ghRepoSlug!.split('/').first,
                        name: _ghRepoSlug!.split('/').skip(1).join('/'),
                      ),
                    ),
                  )
                  .asData
                  ?.value ??
              const <GitHubWorkflow>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'githubSelectWorkflow'.tr(),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        DropdownButton<String>(
          value: workflows.any((workflow) => workflow.name == _ghWorkflow)
              ? _ghWorkflow
              : null,
          isExpanded: true,
          hint: Text('githubSelectWorkflow'.tr()),
          items: [
            for (final workflow in workflows)
              DropdownMenuItem(
                value: workflow.name,
                child: Text(
                  workflow.name.isEmpty
                      ? workflow.path
                      : '${workflow.name} (${workflow.path})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (name) => setState(() {
            _ghWorkflow = name;
            if (name != null) _name = name;
          }),
        ),
        if (_ghRepoSlug != null && workflows.isEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'githubNoWorkflows'.tr(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _pickFolder() async {
    final server = widget.servers
        .where((item) => item.id == _serverId)
        .firstOrNull;
    if (server == null) return;
    final result = await pickRemotePaths(
      context,
      ref,
      server,
      title: 'deploymentChooseLinkedFolder'.tr(),
      initialPath: _location.isEmpty ? '.' : _location,
      selection: CloudFilePickerSelection.folder,
    );
    if (result != null && result.isNotEmpty && mounted) {
      _selectSuggestion(result.first.path);
    }
  }

  void _submit() {
    if (_kind == DeploymentResourceKind.githubWorkflow) {
      if (_ghRepoSlug == null || _ghWorkflow == null || _ghWorkflow!.isEmpty) {
        return;
      }
      _name = _ghWorkflow!;
    } else {
      if (_serverId == null || _name.trim().isEmpty) return;
      if (_locationLabel.isNotEmpty && _location.trim().isEmpty) return;
      if (_kind == DeploymentResourceKind.compose &&
          _directory.trim().isEmpty) {
        return;
      }
    }
    Navigator.pop(
      context,
      _ResourceDraft(
        kind: _kind,
        name: _name.trim(),
        serverId: _serverId,
        configuration: _configuration,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isGithub = _kind == DeploymentResourceKind.githubWorkflow;
    final canSubmit = isGithub
        ? (_ghRepoSlug != null &&
              _ghWorkflow != null &&
              _ghWorkflow!.isNotEmpty)
        : _serverId != null &&
              _name.trim().isNotEmpty &&
              (_locationLabel.isEmpty || _location.trim().isNotEmpty) &&
              (_kind != DeploymentResourceKind.compose ||
                  _directory.trim().isNotEmpty);

    return SheetScaffold(
      titleText:
          (_isEditing ? 'deploymentEditResource' : 'deploymentSheetTitle').tr(),
      heightFactor: 0.72,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            (_isEditing ? 'deploymentEditResourceInfo' : 'deploymentSheetInfo')
                .tr(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<DeploymentResourceKind>(
            initialValue: _kind,
            decoration: InputDecoration(
              labelText: 'deploymentResourceType'.tr(),
            ),
            items: [
              for (final kind in [
                ..._linkableKinds,
                if (_isEditing && !_linkableKinds.contains(_kind)) _kind,
              ])
                DropdownMenuItem(
                  value: kind,
                  child: Row(
                    children: [
                      Icon(deploymentResourceKindIcon(kind), size: 18),
                      const SizedBox(width: 8),
                      Text(deploymentResourceKindLabel(kind)),
                    ],
                  ),
                ),
            ],
            onChanged: (value) {
              setState(() {
                _kind = value!;
                _location = '';
              });
              _loadSuggestions();
            },
          ),
          const SizedBox(height: 12),
          if (isGithub) ...[
            _githubRepoDropdown(),
            const SizedBox(height: 16),
            _githubWorkflowDropdown(),
          ] else ...[
            if (widget.servers.isEmpty)
              Text(
                'deploymentNoServersHint'.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              )
            else
              DropdownButtonFormField<int>(
                initialValue: _serverId,
                decoration: InputDecoration(
                  labelText: 'deploymentServerLabel'.tr(),
                ),
                items: [
                  for (final server in widget.servers)
                    DropdownMenuItem(
                      value: server.id,
                      child: Text(server.name),
                    ),
                ],
                onChanged: (value) {
                  setState(() => _serverId = value);
                  _loadSuggestions();
                },
              ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: _name,
              decoration: InputDecoration(
                labelText: 'deploymentDisplayName'.tr(),
                helperText: 'deploymentDisplayNameHelper'.tr(),
              ),
              onChanged: (value) => setState(() => _name = value),
              onFieldSubmitted: (_) {
                if (canSubmit) _submit();
              },
            ),
            if (_locationLabel.isNotEmpty) ...[
              const SizedBox(height: 12),
              Autocomplete<String>(
                optionsBuilder: (value) {
                  final query = value.text.toLowerCase();
                  return _suggestions.where(
                    (item) =>
                        query.isEmpty || item.toLowerCase().contains(query),
                  );
                },
                onSelected: _selectSuggestion,
                fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                  if (controller.text != _location) {
                    controller.value = TextEditingValue(
                      text: _location,
                      selection: TextSelection.collapsed(
                        offset: _location.length,
                      ),
                    );
                  }
                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      labelText: _locationLabel,
                      suffixIcon: _loadingSuggestions
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : IconButton(
                              tooltip: 'deploymentRefreshSuggestions'.tr(),
                              icon: const Icon(Symbols.refresh),
                              onPressed: _loadSuggestions,
                            ),
                    ),
                    onChanged: (value) => setState(() => _location = value),
                    onFieldSubmitted: (_) {
                      if (canSubmit) _submit();
                    },
                  );
                },
              ),
              if (_suggestionError != null) ...[
                const SizedBox(height: 6),
                Text(
                  'deploymentLoadSuggestionsError'.tr(
                    args: [_suggestionError!],
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ] else if (_suggestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'deploymentDetectedOnServer'.tr(),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final item in _suggestions.take(12))
                      ActionChip(
                        label: Text(item),
                        onPressed: () => _selectSuggestion(item),
                      ),
                  ],
                ),
              ],
              if (_kind == DeploymentResourceKind.compose) ...[
                const SizedBox(height: 12),
                TextFormField(
                  decoration: InputDecoration(
                    labelText: 'deploymentRemoteDirectory'.tr(),
                  ),
                  onChanged: (value) => setState(() => _directory = value),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<ContainerRuntime>(
                  initialValue: _runtime,
                  decoration: InputDecoration(
                    labelText: 'deploymentRuntime'.tr(),
                  ),
                  items: [
                    for (final runtime in ContainerRuntime.values)
                      DropdownMenuItem(
                        value: runtime,
                        child: Text(runtime.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _runtime = value!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<ContainerScope>(
                  initialValue: _scope,
                  decoration: InputDecoration(
                    labelText: 'deploymentScope'.tr(),
                  ),
                  items: [
                    for (final scope in ContainerScope.values)
                      DropdownMenuItem(value: scope, child: Text(scope.name)),
                  ],
                  onChanged: (value) => setState(() => _scope = value!),
                ),
              ],
              if (_kind == DeploymentResourceKind.serverFolder) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _serverId == null ? null : _pickFolder,
                    icon: const Icon(Symbols.folder_open, size: 18),
                    label: Text('deploymentBrowseFolders'.tr()),
                  ),
                ),
              ],
            ],
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: canSubmit ? _submit : null,
            icon: Icon(_isEditing ? Symbols.save : Symbols.add),
            label: Text(
              (_isEditing ? 'commonSave' : 'deploymentAddToProject').tr(),
            ),
          ),
        ],
      ),
    );
  }
}
