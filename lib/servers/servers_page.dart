import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:styled_widget/styled_widget.dart';
import 'package:flutter/services.dart';
import 'package:maid_kit/platform/tailscale.dart';
import 'package:super_context_menu/super_context_menu.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/github/github_workflow_strip.dart';
import 'package:maid_kit/shared/presentation/app_context_menu.dart';
import 'package:maid_kit/shared/presentation/app_scaffold.dart';
import 'package:maid_kit/shared/presentation/collapsible_section.dart';
import 'package:maid_kit/shared/presentation/deploy_terminal.dart';
import 'package:maid_kit/snippets/snippet_repository.dart';
import 'maidcafe_service.dart';
import 'port_forward_sheet.dart';
import 'port_forwarding_models.dart';
import 'server_connection_actions.dart';
import 'dashboard_actions_bar.dart';
import 'dashboard_runtimes_section.dart';
import 'server_health_chip.dart';
import 'server_models.dart';
import 'server_providers.dart';
import 'serial_port_client.dart';
import 'privacy_preferences.dart';
import 'tailscale_service.dart';
import 'tailscale_settings_section.dart';
import 'tailscale_ssh_socket.dart';
import 'terminal_tabs_provider.dart';
import 'workspace_snapshot.dart';

/// Pane width below which the dashboard counts as narrow: the port-forward
/// chip leaves the fixed strip above the catalog for the bottom action bar,
/// where it costs the cards no height. The workspace's own narrow breakpoint.
const _portForwardFooterBreakpoint = 768.0;

class ServerDashboardTab extends ConsumerWidget {
  const ServerDashboardTab({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(serverRepositoryProvider);
    final credentials = await repository.credentials();
    final snippets = await ref.read(snippetRepositoryProvider).all();
    final servers = await repository.all();
    if (!context.mounted) return;
    final draft = await showModalBottomSheet<ServerDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ServerEditorDialog(
        credentials: credentials,
        snippets: snippets,
        servers: servers,
      ),
    );
    if (draft == null || !context.mounted) return;
    try {
      final server = await ref.read(serverRepositoryProvider).create(draft);
      if (!context.mounted) return;
      await _connect(context, ref, server);
    } catch (_) {
      if (context.mounted) {
        showStyledSnackBar(
          message: 'serversSaveError'.tr(),
          title: 'serversSaveError'.tr(),
          icon: Symbols.error,
          accentColor: Theme.of(context).colorScheme.error,
        );
      }
    }
  }

  Future<void> _connect(
    BuildContext context,
    WidgetRef ref,
    Server server,
  ) async {
    // SSH servers connect without opening a terminal so the card can collect
    // statistics; every other transport exists to serve a terminal.
    if (server.connectionType == ServerConnectionType.ssh.name) {
      await connectForStatistics(context, ref, server);
      return;
    }
    await openTerminalFor(context, ref, server);
  }

  Future<void> _reconnectAll(
    BuildContext context,
    WidgetRef ref,
    List<Server> servers,
  ) async {
    for (final server in servers) {
      if (!context.mounted) return;
      await _connect(context, ref, server);
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Server server) async {
    try {
      final repository = ref.read(serverRepositoryProvider);
      final credential = server.credentialId == null
          ? null
          : await repository.credentialFor(server);
      final proxy = await repository.proxyFor(server);
      final credentials = await repository.credentials();
      final snippets = await ref.read(snippetRepositoryProvider).all();
      final servers = await repository.all();
      if (!context.mounted) return;
      final draft = await showModalBottomSheet<ServerDraft>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => ServerEditorDialog(
          credentials: credentials,
          snippets: snippets,
          servers: servers,
          serverId: server.id,
          initial: ServerDraft(
            name: server.name,
            host: server.host,
            port: server.port,
            username: server.username,
            credential: credential,
            credentialId: server.credentialId,
            collectStats: server.collectStats,
            collectSystemInfo: server.collectSystemInfo,
            proxy: proxy,
            jumpHostServerId: server.jumpHostServerId,
            environment: decodeEnvironmentMap(server.environment),
            initialSnippets: decodeSnippetIdList(server.initialSnippets),
            tags: decodeStringList(server.tags),
            fileManagementInitialPath: server.fileManagementInitialPath,
            fileManagementFavorites: decodeStringList(
              server.fileManagementFavorites,
            ),
            connectionType:
                ServerConnectionType.values
                    .asNameMap()[server.connectionType] ??
                ServerConnectionType.ssh,
            serialConfig: decodeSerialConfig(server.serialConfig),
            maidCafeTerminalUrl: server.maidCafeTerminalUrl,
            maidCafeDaemonId: server.maidCafeDaemonId,
            maidCafeTerminalViaCloud: server.maidCafeTerminalViaCloud,
            maidCafeTerminalUser: server.maidCafeTerminalUser,
          ),
          maidCafeTerminalSecretStored:
              server.encryptedMaidCafeTerminalSecret != null,
        ),
      );
      if (draft != null) {
        await repository.update(server, draft);
      }
    } catch (error) {
      if (context.mounted) {
        showStyledSnackBar(
          message: error.toString(),
          title: 'serversEditError'.tr(),
          icon: Symbols.error_outline,
          accentColor: Theme.of(context).colorScheme.error,
        );
      }
    }
  }

  Future<void> _delete(WidgetRef ref, Server server) async {
    await ref.read(terminalTabsProvider.notifier).closeForServer(server.id);
    await ref.read(connectionManagerProvider).disconnect(server.id);
    await ref.read(serverRepositoryProvider).delete(server);
  }

  /// Persists the full dashboard order selected in arrange mode.
  Future<void> _reorderServers(WidgetRef ref, List<int> orderedIds) async {
    final repository = ref.read(serverRepositoryProvider);
    await repository.reorderServers(orderedIds);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    final sessions = ref.watch(sessionsProvider).asData?.value ?? const [];
    return _ServersCatalog(
      servers: servers,
      sessions: sessions,
      onAdd: () => _add(context, ref),
      onConnect: (server) => _connect(context, ref, server),
      onReconnectAll: (disconnectedServers) =>
          _reconnectAll(context, ref, disconnectedServers),
      onEdit: (server) => _edit(context, ref, server),
      onDelete: (server) => _delete(ref, server),
      onReorder: (orderedIds) => _reorderServers(ref, orderedIds),
      onOpenDetail: (server) =>
          ref.read(terminalTabsProvider.notifier).openServerDetails(server),
      onOpenTerminal: (server) => openTerminalFor(context, ref, server),
      onOpenFiles: (server) => _openFiles(context, ref, server),
      onRefresh: (server) =>
          ref.read(connectionManagerProvider).refreshServerInfo(server),
    );
  }

  Future<void> _openFiles(
    BuildContext context,
    WidgetRef ref,
    Server server,
  ) async {
    // File management talks to the host over SSH; serial and daemon servers
    // have no SSH client to reach it with.
    if (server.connectionType != ServerConnectionType.ssh.name) return;
    final manager = ref.read(connectionManagerProvider);
    if (manager.clientFor(server.id) == null &&
        !await connectForStatistics(context, ref, server)) {
      return;
    }
    ref.read(terminalTabsProvider.notifier).openFileManagement(server);
  }
}

class _ServersCatalog extends StatelessWidget {
  const _ServersCatalog({
    required this.servers,
    required this.sessions,
    required this.onAdd,
    required this.onConnect,
    required this.onReconnectAll,
    required this.onEdit,
    required this.onDelete,
    required this.onReorder,
    required this.onOpenDetail,
    required this.onOpenTerminal,
    required this.onOpenFiles,
    required this.onRefresh,
  });

  final AsyncValue<List<Server>> servers;
  final List<SshSessionInfo> sessions;
  final VoidCallback onAdd;
  final ValueChanged<Server> onConnect;
  final Future<void> Function(List<Server>) onReconnectAll;
  final ValueChanged<Server> onEdit;
  final ValueChanged<Server> onDelete;
  final Future<void> Function(List<int> orderedIds) onReorder;
  final ValueChanged<Server> onOpenDetail;
  final ValueChanged<Server> onOpenTerminal;
  final ValueChanged<Server> onOpenFiles;
  final ValueChanged<Server> onRefresh;

  @override
  Widget build(BuildContext context) {
    return MaidKitAppScaffold(
      // The pane owns the narrow decision: the strip above the catalog and the
      // catalog's own footer must agree on where the port-forward chip lives.
      body: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < _portForwardFooterBreakpoint;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _WorkspaceSurfacesRow(narrow: narrow),
              Expanded(
                child: servers.when(
                  data: (items) => items.isEmpty
                      ? _EmptyServers(onAdd: onAdd)
                      : _ServerGrid(
                          narrow: narrow,
                          servers: items,
                          sessions: sessions,
                          onConnect: onConnect,
                          onReconnectAll: onReconnectAll,
                          onEdit: onEdit,
                          onDelete: onDelete,
                          onReorder: onReorder,
                          onOpenDetail: onOpenDetail,
                          onOpenTerminal: onOpenTerminal,
                          onOpenFiles: onOpenFiles,
                          onRefresh: onRefresh,
                        ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(
                    child: Text(
                      'serversLoadError'.tr(args: [error.toString()]),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'servers-create-fab',
        onPressed: onAdd,
        icon: const Icon(Symbols.add),
        label: Text('serversAddServer'.tr()),
      ),
    );
  }
}

class _ServerGrid extends ConsumerStatefulWidget {
  const _ServerGrid({
    required this.narrow,
    required this.servers,
    required this.sessions,
    required this.onConnect,
    required this.onReconnectAll,
    required this.onEdit,
    required this.onDelete,
    required this.onReorder,
    required this.onOpenDetail,
    required this.onOpenTerminal,
    required this.onOpenFiles,
    required this.onRefresh,
  });

  /// Whether the pane is narrow enough for the port-forward chip to live in
  /// this widget's footer instead of the strip above the catalog.
  final bool narrow;
  final List<Server> servers;
  final List<SshSessionInfo> sessions;
  final ValueChanged<Server> onConnect;
  final Future<void> Function(List<Server>) onReconnectAll;
  final ValueChanged<Server> onEdit;
  final ValueChanged<Server> onDelete;
  final Future<void> Function(List<int> orderedIds) onReorder;
  final ValueChanged<Server> onOpenDetail;
  final ValueChanged<Server> onOpenTerminal;
  final ValueChanged<Server> onOpenFiles;
  final ValueChanged<Server> onRefresh;

  @override
  ConsumerState<_ServerGrid> createState() => _ServerGridState();
}

class _SearchIntent extends Intent {
  const _SearchIntent();
}

class _ServerGridState extends ConsumerState<_ServerGrid> {
  var _isReconnecting = false;
  var _isArranging = false;
  var _isSavingOrder = false;
  var _isRestoringWorkspace = false;
  final _selectedTags = <String>{};
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _scrollController = ScrollController();
  var _query = '';

  var _showSearch = false;
  List<int>? _pendingOrder;

  /// Reveals the header search field and brings it back into view.
  ///
  /// The field lives in the scrolling header now, so it can be scrolled off:
  /// clearing focus first makes the re-focus below re-run the field's own
  /// "keep the caret visible" scroll even when it is already focused.
  void _showSearchBar() {
    if (!_showSearch) setState(() => _showSearch = true);
    _searchFocusNode.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _toggleSearch() {
    if (_showSearch) {
      setState(() => _showSearch = false);
      _searchController.clear();
      _query = '';
    } else {
      _showSearchBar();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<Server> get _orderedServers {
    final pendingOrder = _pendingOrder;
    if (!_isArranging || pendingOrder == null) return widget.servers;

    final byId = {for (final server in widget.servers) server.id: server};
    return [for (final id in pendingOrder) ?byId.remove(id), ...byId.values];
  }

  void _startArranging() {
    setState(() {
      _isArranging = true;
      _selectedTags.clear();
      _pendingOrder = [for (final server in widget.servers) server.id];
    });
  }

  Future<void> _moveBefore(int draggedId, int targetId) async {
    if (_isSavingOrder || draggedId == targetId) return;
    final reordered = [for (final server in _orderedServers) server.id];
    final oldIndex = reordered.indexOf(draggedId);
    final targetIndex = reordered.indexOf(targetId);
    if (oldIndex < 0 || targetIndex < 0) return;

    reordered.removeAt(oldIndex);
    final insertionIndex = reordered.indexOf(targetId);
    reordered.insert(insertionIndex, draggedId);
    setState(() {
      _pendingOrder = reordered;
      _isSavingOrder = true;
    });
    try {
      await widget.onReorder(reordered);
    } catch (_) {
      if (mounted) {
        setState(() => _pendingOrder = null);
      }
    } finally {
      if (mounted) setState(() => _isSavingOrder = false);
    }
  }

  Future<void> _reconnectAll(List<Server> servers) async {
    setState(() => _isReconnecting = true);
    try {
      await widget.onReconnectAll(servers);
    } finally {
      if (mounted) setState(() => _isReconnecting = false);
    }
  }

  Future<void> _restoreWorkspace() async {
    setState(() => _isRestoringWorkspace = true);
    try {
      await ref.read(terminalTabsProvider.notifier).restoreLastWorkspace();
    } catch (_) {
      // Restore failures leave the dashboard as-is; the snapshot survives for
      // another attempt.
    } finally {
      if (mounted) setState(() => _isRestoringWorkspace = false);
    }
  }

  /// Hides the restore offer for the saved workspace it is currently showing.
  void _dismissRestoreWorkspace() {
    final stored = ref.read(workspaceSnapshotProvider).value;
    if (stored == null) return;
    unawaited(
      ref
          .read(workspaceRestoreDismissalProvider.notifier)
          .dismiss(stored.updatedAt),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompactView = ref.watch(dashboardCompactViewProvider);
    final savedSnapshot = ref.watch(workspaceSnapshotProvider).value;
    final dismissedSnapshotAt = ref.watch(workspaceRestoreDismissalProvider);
    final showRestoreCard = ref.watch(
      terminalTabsProvider.select(
        (tabs) => shouldOfferWorkspaceRestore(
          tabs: tabs,
          stored: savedSnapshot,
          dismissedSnapshotAt: dismissedSnapshotAt,
        ),
      ),
    );
    final sessionsByServerId = {
      for (final session in widget.sessions) session.serverId: session,
    };
    final allTags =
        widget.servers
            .expand((server) => decodeStringList(server.tags))
            .toSet()
            .toList()
          ..sort();
    final query = _query.trim().toLowerCase();
    final visibleServers = _orderedServers.where((server) {
      final tags = decodeStringList(server.tags).toSet();
      if (!_selectedTags.every(tags.contains)) return false;
      if (query.isEmpty) return true;
      final name = server.name.toLowerCase();
      final host = server.host.toLowerCase();
      final tagsText = tags.join(' ').toLowerCase();
      return name.contains(query) ||
          host.contains(query) ||
          tagsText.contains(query);
    }).toList();
    final disconnectedServers = visibleServers.where((server) {
      final status = sessionsByServerId[server.id]?.status;
      return status != SessionStatus.connected &&
          status != SessionStatus.connecting;
    }).toList();

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyF, meta: true): _SearchIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _SearchIntent(),
      },
      child: Actions(
        actions: {
          _SearchIntent: CallbackAction<_SearchIntent>(
            onInvoke: (_) {
              _showSearchBar();
              return null;
            },
          ),
        },
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            // The dashboard header scrolls with the catalog: contextual cards,
            // the search field, and tag filters are content, not fixed chrome.
            _AnimatedHeaderSliver(
              key: const ValueKey('servers-restore-workspace'),
              visible: showRestoreCard,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: _RestoreWorkspaceCard(
                  isRestoring: _isRestoringWorkspace,
                  onPressed: () => unawaited(_restoreWorkspace()),
                  onDismiss: _dismissRestoreWorkspace,
                ),
              ),
            ),
            _AnimatedHeaderSliver(
              key: const ValueKey('servers-reconnect-all'),
              visible: disconnectedServers.length > 1,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: _ReconnectAllCard(
                  count: disconnectedServers.length,
                  isReconnecting: _isReconnecting,
                  onPressed: () => _reconnectAll(disconnectedServers),
                ),
              ),
            ),
            _AnimatedHeaderSliver(
              key: const ValueKey('servers-search'),
              visible: _showSearch,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'serversSearchHint'.tr(),
                    prefixIcon: const Icon(Symbols.search, size: 20),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'commonClearSearch'.tr(),
                            icon: const Icon(Symbols.close, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
            ),
            if (allTags.isNotEmpty)
              SliverToBoxAdapter(
                key: const ValueKey('servers-tag-filters'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tag in allTags)
                          FilterChip(
                            label: Text(tag),
                            visualDensity: VisualDensity.compact,
                            selected: _selectedTags.contains(tag),
                            onSelected: (selected) => setState(() {
                              if (selected) {
                                _selectedTags.add(tag);
                              } else {
                                _selectedTags.remove(tag);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            if (visibleServers.isEmpty) ...[
              const SliverToBoxAdapter(
                key: ValueKey('dashboard-workflow-strip'),
                child: GithubWorkflowStatusStrip(),
              ),
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: _NoServersMatch()),
              ),
            ] else ...[
              const SliverToBoxAdapter(
                key: ValueKey('dashboard-runtimes'),
                child: DashboardRuntimesSection(),
              ),
              const SliverToBoxAdapter(
                key: ValueKey('dashboard-workflow-strip'),
                child: GithubWorkflowStatusStrip(),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(24),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 380,
                    mainAxisExtent: isCompactView ? 200 : 320,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final server = visibleServers[index];
                    final session = sessionsByServerId[server.id];
                    final card = _ServerCard(
                      server: server,
                      session: session,
                      compact: isCompactView,
                      onConnect: () =>
                          serverConnectionTypeFromName(server.connectionType) ==
                              ServerConnectionType.ssh
                          ? widget.onConnect(server)
                          : widget.onOpenTerminal(server),
                      onOpenDetail: () => widget.onOpenDetail(server),
                      onOpenTerminal: () => widget.onOpenTerminal(server),
                      onOpenFiles: () => widget.onOpenFiles(server),
                      onRefresh: () => widget.onRefresh(server),
                    );
                    if (_isArranging) {
                      return _ReorderableServerTile(
                        server: server,
                        isSavingOrder: _isSavingOrder,
                        onMoveBefore: _moveBefore,
                        child: card,
                      );
                    }
                    final hasDaemonId =
                        server.maidCafeDaemonId?.trim().isNotEmpty ?? false;
                    return ContextMenuWidget(
                      desktopMenuWidgetBuilder: maidKitDesktopMenuWidgetBuilder,
                      menuProvider: (_) => Menu(
                        children: [
                          MenuAction(
                            title: 'serversEditServer'.tr(),
                            callback: () => widget.onEdit(server),
                          ),
                          MenuSeparator(),
                          // The daemon and the relay are transports of
                          // their own: a native client keeps its SSH
                          // session for everything else and can still
                          // attach a terminal through either of them.
                          MenuAction(
                            title: 'serversOpenViaMaidCafeDaemon'.tr(),
                            image: MenuImage.icon(Symbols.terminal),
                            attributes: MenuActionAttributes(
                              disabled: !server.hasMaidCafeTerminalRoute,
                            ),
                            callback: () => unawaited(
                              openMaidCafeTerminalSession(
                                context,
                                ref,
                                server,
                                route: MaidCafeTerminalRoute.daemon,
                              ),
                            ),
                          ),
                          MenuAction(
                            title: 'serversOpenViaMaidCafeRelay'.tr(),
                            image: MenuImage.icon(Symbols.cloud),
                            attributes: MenuActionAttributes(
                              disabled: !hasDaemonId,
                            ),
                            callback: () => unawaited(
                              openMaidCafeTerminalSession(
                                context,
                                ref,
                                server,
                                route: MaidCafeTerminalRoute.relay,
                              ),
                            ),
                          ),
                          MenuAction(
                            title: 'serversCheckMaidCafe'.tr(),
                            image: MenuImage.icon(Symbols.network_check),
                            callback: () => unawaited(
                              checkMaidCafeConnectivity(context, ref, server),
                            ),
                          ),
                          MenuSeparator(),
                          MenuAction(
                            title: 'serversDeleteServer'.tr(),
                            attributes: const MenuActionAttributes(
                              destructive: true,
                            ),
                            callback: () => widget.onDelete(server),
                          ),
                        ],
                      ),
                      child: card,
                    );
                  }, childCount: visibleServers.length),
                ),
              ),
            ],
            SliverToBoxAdapter(child: _dashboardActions(context)),
          ],
        ),
      ),
    );
  }

  Widget _dashboardActions(BuildContext context) {
    // A narrow pane keeps the port-forward chip down here with the other
    // dashboard controls; above the catalog it would cost the cards height.
    final activeForwards = ref.watch(dashboardPortForwardsProvider);
    final forwards = widget.narrow
        ? activeForwards
        : const <ActivePortForward>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (forwards.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => showPortForwardSheet(context, forwards),
                icon: const Icon(Symbols.swap_horiz, size: 18),
                label: Text('activePortForwards'.plural(forwards.length)),
              ),
            ),
            const SizedBox(height: 8),
          ],
          DashboardActionsBar(
            isArranging: _isArranging,
            canArrange: widget.servers.length > 1,
            onToggleArrange: _isArranging
                ? () => setState(() => _isArranging = false)
                : _startArranging,
            isSearching: _showSearch,
            onToggleSearch: _toggleSearch,
          ),
          if (_isArranging) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'serversArrangeHint'.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The workspace-wide surfaces the navigation rail used to host: live port
/// forwards and deploy sessions nobody is looking at. Both hide themselves
/// when there is nothing to show.
///
/// On a narrow pane ([narrow]) the port-forward chip is not here: it belongs to
/// the dashboard's bottom action bar, which cannot afford it above the cards.
class _WorkspaceSurfacesRow extends ConsumerWidget {
  const _WorkspaceSurfacesRow({required this.narrow});

  /// Whether the pane is narrow enough to have given the port-forward chip to
  /// the catalog's footer.
  final bool narrow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeForwards = ref.watch(dashboardPortForwardsProvider);
    final forwards = narrow ? const <ActivePortForward>[] : activeForwards;
    final hiddenDeploys = ref
        .watch(deploySessionsProvider)
        .where((session) => !session.modalVisible)
        .toList();
    if (forwards.isEmpty && hiddenDeploys.isEmpty) {
      return const SizedBox.shrink();
    }
    final running = hiddenDeploys.any((session) => session.isRunning);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (forwards.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => showPortForwardSheet(context, forwards),
              icon: const Icon(Symbols.swap_horiz, size: 18),
              label: Text('activePortForwards'.plural(forwards.length)),
            ),
          if (hiddenDeploys.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => showDeployTerminal(ref, hiddenDeploys.last.id),
              icon: Icon(
                running ? Symbols.progress_activity : Symbols.terminal,
                size: 18,
              ),
              label: Text('deployLogLabel'.tr()),
            ),
        ],
      ),
    );
  }
}

/// Animates one dashboard header section in and out of the catalog.
///
/// The header used to sit in a fixed column above the scroll view; it is now
/// part of the same [CustomScrollView] as the server grid, so each section
/// owns a [SliverToBoxAdapter] and keeps its enter/exit transition.
class _AnimatedHeaderSliver extends StatelessWidget {
  const _AnimatedHeaderSliver({
    super.key,
    required this.visible,
    required this.child,
  });

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => SizeTransition(
          sizeFactor: animation,
          alignment: Alignment.topCenter,
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: visible ? child : const SizedBox.shrink(),
      ),
    );
  }
}

class _ReorderableServerTile extends StatelessWidget {
  const _ReorderableServerTile({
    required this.server,
    required this.isSavingOrder,
    required this.onMoveBefore,
    required this.child,
  });

  final Server server;
  final bool isSavingOrder;
  final Future<void> Function(int draggedId, int targetId) onMoveBefore;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) =>
          !isSavingOrder && details.data != server.id,
      onAcceptWithDetails: (details) => onMoveBefore(details.data, server.id),
      builder: (context, candidateData, rejectedData) {
        final isDropTarget = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            border: Border.all(
              color: isDropTarget
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              IgnorePointer(child: child),
              Positioned(
                // Keep the handle in the trailing corner while sharing the
                // vertical center of the leading server icon row.
                right: 8,
                top: 5,
                child: MouseRegion(
                  cursor: isSavingOrder
                      ? SystemMouseCursors.basic
                      : SystemMouseCursors.grab,
                  child: Draggable<int>(
                    data: server.id,
                    maxSimultaneousDrags: isSavingOrder ? 0 : 1,
                    feedback: _ServerDragFeedback(name: server.name),
                    childWhenDragging: const Opacity(
                      opacity: 0.35,
                      child: _ServerDragHandle(),
                    ),
                    child: const _ServerDragHandle(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ServerDragHandle extends StatelessWidget {
  const _ServerDragHandle();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.all(8),
        child: Icon(Symbols.drag_indicator, size: 20),
      ),
    );
  }
}

class _ServerDragFeedback extends StatelessWidget {
  const _ServerDragFeedback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: Card(
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Symbols.drag_indicator, color: colorScheme.primary),
              const SizedBox(width: 12),
              Text(name, style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoServersMatch extends StatelessWidget {
  const _NoServersMatch();

  @override
  Widget build(BuildContext context) => Text(
    'serversNoMatches'.tr(),
    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class _ReconnectAllCard extends StatelessWidget {
  const _ReconnectAllCard({
    required this.count,
    required this.isReconnecting,
    required this.onPressed,
  });

  final int count;
  final bool isReconnecting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Row(
          children: [
            Icon(
              Symbols.cloud_off,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'serversDisconnectedCount'.plural(count),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall,
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              onPressed: isReconnecting ? null : onPressed,
              icon: isReconnecting
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    )
                  : const Icon(Symbols.sync, size: 18),
              label: Text('serversReconnectAll'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

class _RestoreWorkspaceCard extends StatelessWidget {
  const _RestoreWorkspaceCard({
    required this.isRestoring,
    required this.onPressed,
    required this.onDismiss,
  });

  final bool isRestoring;
  final VoidCallback onPressed;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        child: Row(
          children: [
            Icon(
              Symbols.restore,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'dashboardRestoreWorkspaceHint'.tr(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall,
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              onPressed: isRestoring ? null : onPressed,
              icon: isRestoring
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    )
                  : const Icon(Symbols.history, size: 18),
              label: Text('dashboardRestoreWorkspace'.tr()),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'commonDismiss'.tr(),
              visualDensity: VisualDensity.compact,
              onPressed: onDismiss,
              icon: const Icon(Symbols.close, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerCard extends ConsumerWidget {
  const _ServerCard({
    required this.server,
    required this.session,
    required this.compact,
    required this.onConnect,
    required this.onOpenDetail,
    required this.onOpenTerminal,
    required this.onOpenFiles,
    required this.onRefresh,
  });

  final Server server;
  final SshSessionInfo? session;
  final bool compact;
  final VoidCallback onConnect;
  final VoidCallback onOpenDetail;
  final VoidCallback onOpenTerminal;
  final VoidCallback onOpenFiles;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final hideAddresses = ref.watch(hideServerAddressesProvider);
    final connectionType = serverConnectionTypeFromName(server.connectionType);
    // SSH is the only transport that opens its own connection to collect
    // statistics; serial and daemon hosts have no SSH route at all, so their
    // card names the transport instead of offering an SSH-shaped action.
    final isTerminalOnly = connectionType != ServerConnectionType.ssh;
    // Statistics come from the MaidCafe daemon when the host runs one on a
    // directly reachable address — no SSH session is opened for them. The SSH
    // route stays the default for every other host, and for a daemon host it
    // remains the fallback while the direct route answers nothing.
    final daemonStats = ref.watch(maidCafeStatsProvider)[server.id];
    final stats = daemonStats?.stats ?? session?.stats;
    final systemInfo = session?.systemInfo;
    final statsFromDaemon = daemonStats != null;
    // A card with daemon statistics is live without an SSH session: that is the
    // point of the direct route, and the only statistics route in a browser.
    final connected =
        session?.status == SessionStatus.connected || statsFromDaemon;
    final connecting =
        session?.status == SessionStatus.connecting && !statsFromDaemon;
    final failed = session?.status == SessionStatus.failed && !statsFromDaemon;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenDetail,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: compact ? 8 : 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.only(
                  left: compact ? 12 : 16,
                  right: compact ? 4 : 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Symbols.dns,
                      fill: connected ? 1 : 0,
                      size: compact ? 20 : 22,
                      color: connected
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    SizedBox(width: compact ? 8 : 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            server.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (connectionType == ServerConnectionType.ssh &&
                                  tailscaleSupported &&
                                  isTailnetAddress(server.host)) ...[
                                Tooltip(
                                  message: 'tailscaleViaTailnet'.tr(),
                                  child: Icon(
                                    Symbols.lan,
                                    size: 14,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 4),
                              ],
                              Flexible(
                                child: Text(
                                  serverAddressLabel(
                                    server,
                                    hideAddresses: hideAddresses,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          _ServerBadges(server: server),
                        ],
                      ),
                    ),
                    // The daemon's own score for the host it runs on, read
                    // with the rest of the snapshot. A route that cannot score
                    // health (SSH) shows no chip at all.
                    if (stats?.health != null) ...[
                      ServerHealthChip(health: stats!.health, compact: compact),
                      const SizedBox(width: 4),
                    ],
                    IconButton(
                      tooltip: 'serversRefreshStatistics'.tr(),
                      visualDensity: VisualDensity.compact,
                      // A daemon-backed card refreshes the daemon; an SSH card
                      // refreshes the session it already holds.
                      onPressed: !connected
                          ? null
                          : statsFromDaemon
                          ? () => unawaited(
                              ref
                                  .read(maidCafeStatsSchedulerProvider)
                                  .refreshServer(server),
                            )
                          : onRefresh,
                      icon: const Icon(Symbols.refresh),
                    ),
                  ],
                ),
              ),
              SizedBox(height: compact ? 8 : 12),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
                  // A serial or daemon server has no SSH route, so its card
                  // shows the transport instead of a stats grid — unless a
                  // MaidCafe daemon already answered with real numbers, which
                  // is exactly what makes those cards useful on the web.
                  child: isTerminalOnly && stats == null
                      ? _StatsMessage(
                          icon: connectionType == ServerConnectionType.serial
                              ? Symbols.usb
                              : Symbols.cloud,
                          message: connectionType == ServerConnectionType.serial
                              ? 'serversSerialConsole'.tr()
                              : 'serversMaidCafeConsole'.tr(),
                        )
                      : connected
                      ? _ServerStats(
                          stats: stats,
                          systemInfo: systemInfo,
                          compact: compact,
                          collectStats: server.collectStats,
                          collectSystemInfo: server.collectSystemInfo,
                        )
                      : _DisconnectedStats(
                          connecting: connecting,
                          error: session?.error,
                        ),
                ),
              ),
              SizedBox(height: compact ? 8 : 12),
              const Divider(height: 1),
              SizedBox(height: compact ? 6 : 10),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
                child: Row(
                  children: [
                    _ConnectionStatus(
                      connected: connected,
                      connecting: connecting,
                      failed: failed,
                      networkLatency: session?.networkLatency,
                      // Only an SSH session measures a round trip; a card fed
                      // by the daemon has no ping to report.
                      measuresLatency: !statsFromDaemon,
                    ),
                    const Spacer(),
                    if (!connected && !connecting)
                      TextButton(
                        onPressed: onConnect,
                        child: Text('serversConnect'.tr()),
                      ),
                    if (connecting)
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.primary,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: compact ? 4 : 8),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
                child: _ServerQuickActions(
                  compact: compact,
                  onOpenTerminal: connecting ? null : onOpenTerminal,
                  onOpenFiles: connecting || isTerminalOnly
                      ? null
                      : onOpenFiles,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small label chip shared by the local-machine badge and tag chips.
class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// Tag chips shown under a server card's title.
class _ServerBadges extends StatelessWidget {
  const _ServerBadges({required this.server});

  final Server server;

  @override
  Widget build(BuildContext context) {
    final tags = decodeStringList(server.tags);
    if (tags.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final tag in tags.take(3)) _BadgeChip(label: tag),
          if (tags.length > 3) _BadgeChip(label: '+${tags.length - 3}'),
        ],
      ),
    );
  }
}

class _ServerQuickActions extends StatelessWidget {
  const _ServerQuickActions({
    this.compact = false,
    this.onOpenTerminal,
    this.onOpenFiles,
  });

  final bool compact;
  final VoidCallback? onOpenTerminal;
  final VoidCallback? onOpenFiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 340) {
          return Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onOpenTerminal,
                  style: ButtonStyle(
                    visualDensity: compact ? VisualDensity.compact : null,
                  ),
                  icon: const Icon(Symbols.terminal, size: 18),
                  label: Text('sessionsNewTerminal'.tr()),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'sessionsOpenFileManagement'.tr(),
                child: IconButton.outlined(
                  onPressed: onOpenFiles,
                  visualDensity: compact ? VisualDensity.compact : null,
                  icon: const Icon(Symbols.folder, size: 18),
                ),
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onOpenTerminal,
                style: ButtonStyle(
                  visualDensity: compact ? VisualDensity.compact : null,
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
                icon: const Icon(Symbols.terminal, size: 18),
                label: Text('sessionsNewTerminal'.tr()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onOpenFiles,
                style: ButtonStyle(
                  visualDensity: compact ? VisualDensity.compact : null,
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
                icon: const Icon(Symbols.folder, size: 18),
                label: Text('sessionsOpenFileManagement'.tr()),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ConnectionStatus extends StatelessWidget {
  const _ConnectionStatus({
    required this.connected,
    required this.connecting,
    required this.failed,
    required this.measuresLatency,
    this.networkLatency,
  });

  final bool connected;
  final bool connecting;
  final bool failed;
  final Duration? networkLatency;

  /// Whether the card's numbers arrived with a measured round trip. A daemon
  /// snapshot does not, so the ping slot names the connection state instead of
  /// showing a dash that reads as "no latency data".
  final bool measuresLatency;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final latency = networkLatency;

    if (connected) {
      final latencyColor = latency == null
          ? colorScheme.onSurfaceVariant
          : latency.inMilliseconds >= 250
          ? colorScheme.error
          : latency.inMilliseconds >= 100
          ? colorScheme.tertiary
          : colorScheme.onSurfaceVariant;
      return Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          if (measuresLatency)
            Tooltip(
              message: 'serversNetworkPingTooltip'.tr(),
              child: Text(
                latency == null ? '—' : '${latency.inMilliseconds} ms',
                style: textTheme.labelLarge?.copyWith(color: latencyColor),
              ),
            )
          else
            Text(
              'serversConnected'.tr(),
              style: textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
        ],
      );
    }

    final (label, color) = switch ((connecting, failed)) {
      (true, _) => ('serversConnecting'.tr(), colorScheme.tertiary),
      (_, true) => ('serversFailed'.tr(), colorScheme.error),
      _ => ('serversNotConnected'.tr(), colorScheme.onSurfaceVariant),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: textTheme.labelLarge?.copyWith(color: colorScheme.onSurface),
        ),
      ],
    );
  }
}

class _DisconnectedStats extends StatelessWidget {
  const _DisconnectedStats({required this.connecting, this.error});

  final bool connecting;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final message = connecting
        ? 'serversEstablishingSession'.tr()
        : (error ?? 'serversConnectToViewStats'.tr());

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Row(
          children: [
            Icon(
              connecting ? Symbols.hourglass_top : Symbols.insights,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerStats extends StatelessWidget {
  const _ServerStats({
    required this.stats,
    required this.systemInfo,
    required this.compact,
    required this.collectStats,
    required this.collectSystemInfo,
  });

  final ServerStats? stats;
  final ServerSystemInfo? systemInfo;
  final bool compact;
  final bool collectStats;
  final bool collectSystemInfo;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (!collectStats && !collectSystemInfo) {
      return _StatsMessage(
        icon: Symbols.visibility_off,
        message: 'serversCollectionDisabled'.tr(),
      );
    }
    if (stats == null && systemInfo == null) {
      return _StatsMessage(
        icon: Symbols.sync,
        message: 'serversFetchingInfo'.tr(),
      );
    }

    final usedMemoryKb =
        stats?.memoryTotalKb == null || stats?.memoryAvailableKb == null
        ? null
        : stats!.memoryTotalKb! - stats!.memoryAvailableKb!;
    final memoryRatio =
        usedMemoryKb == null ||
            stats?.memoryTotalKb == null ||
            stats!.memoryTotalKb == 0
        ? null
        : (usedMemoryKb / stats!.memoryTotalKb!).clamp(0.0, 1.0);
    final memoryPercent = memoryRatio == null
        ? null
        : (memoryRatio * 100).round();
    final gpus = stats?.gpus ?? const <ServerGpuStats>[];
    final gpuUtilization = _averageGpuUtilization(gpus);
    final gpuMemoryUsedKb = _sumGpuMemory(gpus, used: true);
    final gpuMemoryTotalKb = _sumGpuMemory(gpus, used: false);
    final systemLabel = [
      systemInfo?.distribution,
      systemInfo?.kernel,
    ].whereType<String>().join(' · ');

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (stats != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _StatTile(
                    compact: compact,
                    label: 'detailLoadAverage'.tr(),
                    value: stats!.loadAverage?.toStringAsFixed(2) ?? '—',
                    detail: compact ? null : _loadDetail(stats!.loadAverage),
                    valueColor: _loadColor(stats!.loadAverage, colorScheme),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatTile(
                    compact: compact,
                    label: 'detailMemory'.tr(),
                    value: memoryPercent == null ? '—' : '$memoryPercent%',
                    detail:
                        compact ||
                            usedMemoryKb == null ||
                            stats!.memoryTotalKb == null
                        ? null
                        : '${_formatBytes(usedMemoryKb * 1024)} / ${_formatBytes(stats!.memoryTotalKb! * 1024)}',
                    progress: memoryRatio,
                    progressColor: _memoryColor(memoryRatio, colorScheme),
                    valueColor: _memoryColor(memoryRatio, colorScheme),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatTile(
                    compact: compact,
                    label: 'detailUptime'.tr(),
                    value: _formatUptime(stats!.uptime),
                    detail: compact ? null : _uptimeDetail(stats!.uptime),
                  ),
                ),
              ],
            )
          else if (collectStats)
            _StatsMessage(
              icon: Symbols.query_stats,
              message: 'serversStatsUnavailable'.tr(),
            ),
          if (gpus.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _StatTile(
                    compact: compact,
                    label: 'detailGpu'.tr(),
                    value: gpuUtilization == null
                        ? '—'
                        : '${gpuUtilization.toStringAsFixed(0)}%',
                    detail: compact
                        ? null
                        : 'detailGpuCount'.tr(args: ['${gpus.length}']),
                    progress:
                        gpuMemoryUsedKb == null || gpuMemoryTotalKb == null
                        ? null
                        : (gpuMemoryUsedKb / gpuMemoryTotalKb).clamp(0.0, 1.0),
                    progressColor: _memoryColor(
                      gpuMemoryUsedKb == null || gpuMemoryTotalKb == null
                          ? null
                          : (gpuMemoryUsedKb / gpuMemoryTotalKb).clamp(
                              0.0,
                              1.0,
                            ),
                      colorScheme,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (!compact && systemLabel.isNotEmpty) ...[
            const SizedBox(height: 8),

            Text(
              systemLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ).padding(horizontal: 4),
          ],
          if (!compact && stats?.updatedAt != null) ...[
            Text(
              'detailRefreshDetailsAt'.tr(
                args: [_formatRelative(stats!.updatedAt)],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(color: colorScheme.outline),
            ).padding(horizontal: 4),
          ],
        ],
      ),
    );
  }

  static double? _averageGpuUtilization(List<ServerGpuStats> gpus) {
    final values = gpus
        .map((gpu) => gpu.utilizationPercent)
        .whereType<double>()
        .toList();
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  static int? _sumGpuMemory(List<ServerGpuStats> gpus, {required bool used}) {
    final values = gpus
        .map((gpu) => used ? gpu.memoryUsedKb : gpu.memoryTotalKb)
        .whereType<int>()
        .toList();
    if (values.isEmpty) return null;
    return values.fold<int>(0, (sum, value) => sum + value);
  }

  static String? _loadDetail(double? load) {
    if (load == null) return null;
    if (load < 1) return 'serversLoadIdle'.tr();
    if (load < 2) return 'serversLoadNormal'.tr();
    if (load < 4) return 'serversLoadBusy'.tr();
    return 'serversLoadHigh'.tr();
  }

  static String? _uptimeDetail(Duration? uptime) {
    if (uptime == null || uptime.inSeconds == 0) return null;
    if (uptime.inDays >= 30) return 'serversUptimeStable'.tr();
    if (uptime.inHours < 1) return 'serversUptimeRecent'.tr();
    return null;
  }

  static Color? _loadColor(double? load, ColorScheme scheme) {
    if (load == null) return null;
    if (load >= 4) return scheme.error;
    if (load >= 2) return scheme.tertiary;
    return null;
  }

  static Color? _memoryColor(double? ratio, ColorScheme scheme) {
    if (ratio == null) return null;
    if (ratio >= 0.9) return scheme.error;
    if (ratio >= 0.75) return scheme.tertiary;
    return null;
  }
}

class _StatsMessage extends StatelessWidget {
  const _StatsMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    this.compact = false,
    this.detail,
    this.progress,
    this.progressColor,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool compact;
  final String? detail;
  final double? progress;
  final Color? progressColor;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final resolvedValueColor = valueColor ?? colorScheme.onSurface;
    final resolvedProgressColor = progressColor ?? colorScheme.primary;

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
              label,
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
                    color: resolvedValueColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
            SizedBox(height: compact ? 4 : 8),
            if (progress != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: colorScheme.onSurface.withValues(
                    alpha: 0.08,
                  ),
                  color: resolvedProgressColor,
                ),
              )
            else
              SizedBox(height: compact ? 0 : 4),
            if (!compact) ...[
              const SizedBox(height: 6),
              Text(
                detail ?? ' ',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  const megabyte = 1024 * 1024;
  const gigabyte = 1024 * megabyte;
  return bytes >= gigabyte
      ? '${(bytes / gigabyte).toStringAsFixed(1)} GB'
      : '${(bytes / megabyte).toStringAsFixed(0)} MB';
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

String _formatRelative(DateTime time) {
  final delta = DateTime.now().difference(time);
  if (delta.inSeconds < 15) return 'just now';
  if (delta.inMinutes < 1) return '${delta.inSeconds}s ago';
  if (delta.inHours < 1) return '${delta.inMinutes}m ago';
  if (delta.inDays < 1) return '${delta.inHours}h ago';
  return '${delta.inDays}d ago';
}

class _EmptyServers extends StatelessWidget {
  const _EmptyServers({required this.onAdd});
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Symbols.dns,
            size: 36,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'serversEmpty'.tr(),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text('serversEmptyHint'.tr()),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Symbols.add),
            label: Text('serversAddServer'.tr()),
          ),
        ],
      ),
    ),
  );
}

class ServerEditorDialog extends ConsumerStatefulWidget {
  const ServerEditorDialog({
    super.key,
    required this.credentials,
    this.servers = const [],
    this.serverId,
    this.initial,
    this.snippets = const [],
    this.maidCafeTerminalSecretStored = false,
  });

  final ServerDraft? initial;
  final int? serverId;
  final List<SavedCredential> credentials;
  final List<Server> servers;

  /// Saved snippets offered as initial-snippet choices for this server.
  final List<ScriptSnippet> snippets;

  /// Whether the edited server already has a stored daemon terminal
  /// credential. Secrets are never read back into the form, so this only
  /// controls the "forget the stored credential" affordance.
  final bool maidCafeTerminalSecretStored;

  @override
  ConsumerState<ServerEditorDialog> createState() => _AddServerDialogState();
}

class _AddServerDialogState extends ConsumerState<ServerEditorDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _host = TextEditingController();
  late final _port = TextEditingController(text: 'serverDefaultPort'.tr());
  final _user = TextEditingController();
  final _secret = TextEditingController();
  final _passphrase = TextEditingController();
  CredentialType _type = CredentialType.password;

  ({int? id, bool isNew}) _credentialChoice = (id: null, isNew: true);
  bool _collectStats = true;
  bool _collectSystemInfo = true;

  // Connection transport and serial-port settings.
  ServerConnectionType _connectionType = ServerConnectionType.ssh;
  final _serialDevice = TextEditingController();
  List<String> _serialDevices = const [];
  var _scanningSerialDevices = false;
  int _serialBaud = 115200;
  int _serialDataBits = 8;
  SerialParity _serialParity = SerialParity.none;
  int _serialStopBits = 1;
  SerialFlowControl _serialFlowControl = SerialFlowControl.none;

  // MaidCafe daemon terminal settings.
  final _maidCafeTerminalUrl = TextEditingController();
  final _maidCafeTerminalSecret = TextEditingController();
  final _maidCafeDaemonId = TextEditingController();
  final _maidCafeTerminalUser = TextEditingController();
  bool _maidCafeTerminalViaCloud = false;
  bool _clearMaidCafeTerminalSecret = false;

  // Per-server proxy configuration.
  ServerProxyType _proxyType = ServerProxyType.none;
  final _proxyHost = TextEditingController();
  late final _proxyPort = TextEditingController(
    text: 'serverDefaultProxyPort'.tr(),
  );
  final _proxyUsername = TextEditingController();
  final _proxyPassword = TextEditingController();
  int? _jumpHostServerId;

  // Per-server environment variables, initial snippets, and tags.
  final _envRows =
      <({TextEditingController name, TextEditingController value})>[];
  final _snippetIds = <int>{};
  final _tags = <String>[];
  final _tagInput = TextEditingController();
  final _fileManagementInitialPath = TextEditingController();

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial == null) return;
    _name.text = initial.name;
    _host.text = initial.host;
    _port.text = initial.port.toString();
    _user.text = initial.username;
    _credentialChoice = initial.credentialId != null
        ? (id: initial.credentialId, isNew: false)
        : initial.credential != null
        ? (id: null, isNew: true)
        : (id: null, isNew: false);
    final credential = initial.credential;
    if (credential != null) {
      _type = credential.type;
      _secret.text = credential.password ?? credential.privateKey ?? '';
      _passphrase.text = credential.keyPassphrase ?? '';
    }
    _jumpHostServerId = initial.jumpHostServerId;
    _collectStats = initial.collectStats;
    _collectSystemInfo = initial.collectSystemInfo;
    _connectionType = initial.connectionType;
    // The endpoint is metadata and reopens in the form; the terminal
    // credential is never decrypted into it.
    _maidCafeTerminalUrl.text = initial.maidCafeTerminalUrl ?? '';
    _maidCafeDaemonId.text = initial.maidCafeDaemonId ?? '';
    _maidCafeTerminalUser.text = initial.maidCafeTerminalUser ?? '';
    _maidCafeTerminalViaCloud = initial.maidCafeTerminalViaCloud;
    final serialConfig = initial.serialConfig;
    if (serialConfig != null) {
      _serialDevice.text = serialConfig.device;
      _serialBaud = serialConfig.baudRate;
      _serialDataBits = serialConfig.dataBits;
      _serialParity = serialConfig.parity;
      _serialStopBits = serialConfig.stopBits;
      _serialFlowControl = serialConfig.flowControl;
    }
    if (_connectionType == ServerConnectionType.serial &&
        serialPortsSupported) {
      // Populate the device picker with the machine's serial ports. Runs
      // off the build phase; errors surface as a snackbar.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scanSerialDevices();
      });
    }
    final proxy = initial.proxy;
    if (proxy != null) {
      _proxyType = proxy.type;
      _proxyHost.text = proxy.host;
      _proxyPort.text = proxy.port.toString();
      _proxyUsername.text = proxy.username ?? '';
      // The stored password is not decrypted into the form; leaving the field
      // blank keeps the existing password when saving.
    }
    _tags.addAll(initial.tags);
    _fileManagementInitialPath.text = initial.fileManagementInitialPath ?? '';
    _snippetIds.addAll(initial.initialSnippets);
    for (final entry in initial.environment.entries) {
      _envRows.add((
        name: TextEditingController(text: entry.key),
        value: TextEditingController(text: entry.value),
      ));
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _host,
      _port,
      _user,
      _secret,
      _passphrase,
      _proxyHost,
      _proxyPort,
      _proxyUsername,
      _proxyPassword,
      _tagInput,
      _fileManagementInitialPath,
      _serialDevice,
      _maidCafeTerminalUrl,
      _maidCafeTerminalSecret,
      _maidCafeDaemonId,
      _maidCafeTerminalUser,
    ]) {
      controller.dispose();
    }
    for (final row in _envRows) {
      row.name.dispose();
      row.value.dispose();
    }
    super.dispose();
  }

  Future<void> _pickKey() async {
    final result = await FilePicker.pickFiles(withData: true);
    final bytes = result?.files.single.bytes;
    if (bytes != null) {
      setState(() => _secret.text = String.fromCharCodes(bytes));
    }
  }

  /// Discovers serial devices through the platform bridge helper and fills
  /// the device dropdown. A picked device replaces the current field value.
  Future<void> _scanSerialDevices() async {
    if (!serialPortsSupported) {
      if (mounted) {
        showStyledSnackBar(
          message: 'serverSerialNotSupported'.tr(),
          title: 'serverSerialScanError'.tr(),
          icon: Symbols.usb,
          accentColor: Theme.of(context).colorScheme.error,
        );
      }
      return;
    }
    if (_scanningSerialDevices) return;
    setState(() => _scanningSerialDevices = true);
    try {
      final devices = await ref.read(serialPortClientProvider).listDevices();
      if (!mounted) return;
      setState(() {
        _serialDevices = devices;
        // Auto-select when the field is still empty and a device exists.
        if (_serialDevice.text.trim().isEmpty && devices.isNotEmpty) {
          _serialDevice.text = devices.first;
        }
      });
    } on SerialPortException catch (error) {
      if (mounted) {
        showStyledSnackBar(
          message: error.message,
          title: 'serverSerialScanError'.tr(),
          icon: Symbols.usb,
          accentColor: Theme.of(context).colorScheme.error,
        );
      }
    } catch (_) {
      if (mounted) {
        showStyledSnackBar(
          message: 'serverSerialScanError'.tr(),
          title: 'serverSerialScanError'.tr(),
          icon: Symbols.usb,
          accentColor: Theme.of(context).colorScheme.error,
        );
      }
    } finally {
      if (mounted) setState(() => _scanningSerialDevices = false);
    }
  }

  /// Fills the host with a tailnet machine's IP. Requires the embedded
  /// Tailscale node to be up (sign in under Settings → Tailscale first).
  Future<void> _pickTailscaleMachine(BuildContext context) async {
    List<TailscaleNode> nodes;
    try {
      await ensureTailscaleInitialized();
      nodes = await Tailscale.instance.nodes();
    } catch (_) {
      if (context.mounted) {
        showSnackBar('tailscaleNotRunning'.tr());
      }
      return;
    }
    if (!context.mounted) return;
    final online = nodes.where((node) => node.online).toList();
    if (online.isEmpty) {
      showSnackBar('tailscaleNoMachines'.tr());
      return;
    }
    final address = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('tailscalePickMachine'.tr()),
        children: [
          for (final node in online)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, node.ipv4),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(node.hostName),
                subtitle: Text(
                  node.tailscaleIPs.where((ip) => !ip.contains(':')).join(', '),
                ),
              ),
            ),
        ],
      ),
    );
    if (address != null) setState(() => _host.text = address);
  }

  void _addEnvRow() {
    setState(() {
      _envRows.add((
        name: TextEditingController(),
        value: TextEditingController(),
      ));
    });
  }

  void _removeEnvRow(
    ({TextEditingController name, TextEditingController value}) row,
  ) {
    setState(() => _envRows.remove(row));
    row.name.dispose();
    row.value.dispose();
  }

  void _addTag() {
    final candidates = _tagInput.text
        .split(RegExp(r'[,;]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (candidates.isEmpty) return;
    setState(() {
      for (final tag in candidates) {
        if (!_tags.contains(tag)) _tags.add(tag);
      }
      _tagInput.clear();
    });
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'serverPortRequired'.tr() : null;
  String? _requiredSecret(String? value) =>
      value == null || value.isEmpty ? 'serverPortRequired'.tr() : null;
  String? _validPort(String? value) {
    final port = int.tryParse(value ?? '');
    return port != null && port > 0 && port < 65536
        ? null
        : 'serverPortInvalid'.tr();
  }

  String _jumpHostSummary() {
    if (_jumpHostServerId == null) return 'serverJumpHostNone'.tr();
    final names = <String>[];
    final visited = <int>{};
    var current = _jumpHostServerId;
    while (current != null && visited.add(current)) {
      final host = widget.servers
          .where((server) => server.id == current)
          .firstOrNull;
      if (host == null) {
        names.add('serverJumpHostMissing'.tr());
        break;
      }
      names.add(host.name);
      current = host.jumpHostServerId;
    }
    return names.reversed.join(' → ');
  }

  bool _hasJumpHostCycle() {
    // A jump host is an SSH hop. The other transports save no jump host, so a
    // value left over from an earlier transport must not block the form.
    if (_connectionType != ServerConnectionType.ssh) return false;
    if (_jumpHostServerId == null) return false;
    var current = _jumpHostServerId;
    final visited = <int>{};
    while (current != null) {
      if (!visited.add(current) || current == widget.serverId) return true;
      current = widget.servers
          .where((server) => server.id == current)
          .firstOrNull
          ?.jumpHostServerId;
    }
    return false;
  }

  /// Validates the MaidCafe daemon endpoint: an absolute HTTP(S) URL the app
  /// itself can reach. Non-loopback plain HTTP is rejected because the daemon
  /// has no TLS of its own — such an endpoint has to be behind the operator's
  /// TLS front, which also gives the WebSocket a `wss://` URL.
  String? _validateMaidCafeTerminalUrl(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return 'serverMaidCafeTerminalUrlRequired'.tr();
    try {
      normalizeMaidCafeLocalDaemonUrl(raw);
    } on MaidCafeException catch (error) {
      return error.message;
    }
    return null;
  }

  /// The same check for an optional route: an SSH server may leave the daemon
  /// endpoint empty and stay a plain SSH server.
  String? _validateOptionalMaidCafeTerminalUrl(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return null;
    return _validateMaidCafeTerminalUrl(raw);
  }

  /// True when the server already carries a daemon route, so the SSH editor
  /// section opens expanded instead of hiding a configured endpoint.
  bool get _maidCafeRouteConfigured =>
      _maidCafeTerminalUrl.text.trim().isNotEmpty ||
      _maidCafeDaemonId.text.trim().isNotEmpty;

  /// The MaidCafe daemon terminal fields: the only terminal transport of a
  /// MaidCafe server, and an optional extra route for an SSH server, which
  /// uses it where a raw socket is impossible (a browser build).
  List<Widget> _maidCafeTerminalFields(
    BuildContext context, {
    required bool urlRequired,
  }) => [
    TextFormField(
      controller: _maidCafeTerminalUrl,
      keyboardType: TextInputType.url,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: 'serverMaidCafeTerminalUrlLabel'.tr(),
        helperText: 'serverMaidCafeTerminalUrlHint'.tr(),
      ),
      validator: urlRequired
          ? _validateMaidCafeTerminalUrl
          : _validateOptionalMaidCafeTerminalUrl,
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _maidCafeTerminalSecret,
      obscureText: true,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: 'serverMaidCafeTerminalSecretLabel'.tr(),
        helperText: 'serverMaidCafeTerminalSecretHint'.tr(),
      ),
    ),
    if (widget.maidCafeTerminalSecretStored &&
        !_clearMaidCafeTerminalSecret) ...[
      const SizedBox(height: 4),
      TextButton.icon(
        onPressed: () => setState(() => _clearMaidCafeTerminalSecret = true),
        icon: const Icon(Symbols.delete, size: 18),
        label: Text('serverMaidCafeTerminalSecretForget'.tr()),
      ),
    ],
    if (_clearMaidCafeTerminalSecret) ...[
      const SizedBox(height: 4),
      Text(
        'serverMaidCafeTerminalSecretWillClear'.tr(),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.error,
        ),
      ),
    ],
    const SizedBox(height: 12),
    TextFormField(
      controller: _maidCafeTerminalUser,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: 'serverMaidCafeTerminalUserLabel'.tr(),
        helperText: 'serverMaidCafeTerminalUserHint'.tr(),
      ),
    ),
    const SizedBox(height: 12),
    TextFormField(
      controller: _maidCafeDaemonId,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: 'serverMaidCafeDaemonIdLabel'.tr(),
        helperText: 'serverMaidCafeDaemonIdHint'.tr(),
      ),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: _maidCafeTerminalViaCloud,
      title: Text('serverMaidCafeViaCloudLabel'.tr()),
      subtitle: Text('serverMaidCafeViaCloudHint'.tr()),
      onChanged: (value) => setState(() => _maidCafeTerminalViaCloud = value),
    ),
    const SizedBox(height: 12),
    Text(
      'serverMaidCafeTerminalNote'.tr(),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  ];

  void _save() {
    if (!_form.currentState!.validate()) return;
    if (_hasJumpHostCycle()) {
      showStyledSnackBar(
        message: 'serverJumpHostCycle'.tr(),
        title: 'serverJumpHostLabel'.tr(),
        icon: Symbols.account_tree,
        accentColor: Theme.of(context).colorScheme.error,
      );
      return;
    }
    // The device picker is a DropdownMenu, which is not a FormField, so the
    // empty-device check must run outside the form validator.
    if (_connectionType == ServerConnectionType.serial &&
        _serialDevice.text.trim().isEmpty) {
      showStyledSnackBar(
        message: 'serverSerialDeviceRequired'.tr(),
        title: 'serverSerialDeviceRequired'.tr(),
        icon: Symbols.usb,
        accentColor: Theme.of(context).colorScheme.error,
      );
      return;
    }
    // Routing through the cloud needs a daemon identity to address; the id can
    // also be entered by hand when the app did not create the daemon.
    if (_maidCafeTerminalViaCloud && _maidCafeDaemonId.text.trim().isEmpty) {
      showStyledSnackBar(
        message: 'serverMaidCafeDaemonIdRequired'.tr(),
        title: 'serverMaidCafeDaemonIdRequired'.tr(),
        icon: Symbols.cloud,
        accentColor: Theme.of(context).colorScheme.error,
      );
      return;
    }
    final credential = !_credentialChoice.isNew
        ? null
        : _type == CredentialType.password
        ? ServerCredential.password(_secret.text)
        : ServerCredential.privateKey(
            privateKey: _secret.text,
            keyPassphrase: _passphrase.text.isEmpty ? null : _passphrase.text,
          );
    Navigator.pop(
      context,
      ServerDraft(
        name: _name.text,
        host: _host.text,
        port: int.parse(_port.text),
        // A jump host only applies to the SSH transport.
        jumpHostServerId: _connectionType == ServerConnectionType.ssh
            ? _jumpHostServerId
            : null,
        username: _user.text,
        credential: credential,
        credentialId: _credentialChoice.isNew ? null : _credentialChoice.id,
        credentialName: _name.text,
        collectStats: _collectStats,
        collectSystemInfo: _collectSystemInfo,
        proxy: _proxyType == ServerProxyType.none
            ? null
            : ServerProxy(
                type: _proxyType,
                host: _proxyHost.text.trim(),
                port: int.parse(_proxyPort.text),
                username: _proxyUsername.text.trim().isEmpty
                    ? null
                    : _proxyUsername.text.trim(),
                password: _proxyPassword.text.isEmpty
                    ? null
                    : _proxyPassword.text,
              ),
        environment: {
          for (final row in _envRows)
            if (row.name.text.trim().isNotEmpty)
              row.name.text.trim(): row.value.text,
        },
        initialSnippets: _snippetIds.toList(),
        tags: List.of(_tags),
        fileManagementInitialPath:
            _fileManagementInitialPath.text.trim().isEmpty
            ? null
            : _fileManagementInitialPath.text.trim(),
        connectionType: _connectionType,
        serialConfig: _connectionType == ServerConnectionType.serial
            ? SerialConfig(
                device: _serialDevice.text.trim(),
                baudRate: _serialBaud,
                dataBits: _serialDataBits,
                parity: _serialParity,
                stopBits: _serialStopBits,
                flowControl: _serialFlowControl,
              )
            : null,
        // The serial settings belong to the serial transport alone, so
        // switching away drops them instead of leaving a dead device behind.
        // The daemon route is a transport of its own: it survives an SSH
        // server, which uses it where a raw socket is impossible (a browser
        // build), and only disappears when the server becomes a serial one.
        maidCafeTerminalUrl: _connectionType == ServerConnectionType.serial
            ? null
            : _maidCafeTerminalUrl.text.trim(),
        maidCafeTerminalSecret: _connectionType == ServerConnectionType.serial
            ? null
            : _maidCafeTerminalSecret.text,
        maidCafeDaemonId: _connectionType == ServerConnectionType.serial
            ? null
            : _maidCafeDaemonId.text.trim(),
        maidCafeTerminalUser: _connectionType == ServerConnectionType.serial
            ? null
            : _maidCafeTerminalUser.text.trim(),
        maidCafeTerminalViaCloud:
            _connectionType != ServerConnectionType.serial &&
            _maidCafeTerminalViaCloud,
        clearMaidCafeTerminalSecret:
            _clearMaidCafeTerminalSecret ||
            _connectionType == ServerConnectionType.serial,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The Tailscale picker needs a running embedded node; hide it when the
    // node is disconnected, starting, or in a login state.
    final tailscaleRunning =
        tailscaleSupported &&
        ref.watch(tailscaleSnapshotProvider).value?.status?.state ==
            NodeState.running;
    return SizedBox(
      width: 560,
      child: SheetScaffold(
        titleText: switch (_connectionType) {
          ServerConnectionType.serial => 'serversAddSerialSheetTitle'.tr(),
          ServerConnectionType.maidcafe => 'serversAddMaidCafeSheetTitle'.tr(),
          ServerConnectionType.ssh => 'serversAddSheetTitle'.tr(),
        },
        heightFactor: 0.78,
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Text(
                'serverConnectionType'.tr(),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SegmentedButton<ServerConnectionType>(
                segments: [
                  ButtonSegment(
                    value: ServerConnectionType.ssh,
                    label: Text('serverConnectionSsh'.tr()),
                  ),
                  if (widget.initial != null)
                    ButtonSegment(
                      value: ServerConnectionType.serial,
                      label: Text('serverConnectionSerial'.tr()),
                      // A browser has no device nodes: the stored type stays
                      // visible for an existing server but cannot be picked.
                      enabled: serialPortsSupported,
                      tooltip: serialPortsSupported
                          ? null
                          : 'serverSerialNotSupported'.tr(),
                    ),
                  ButtonSegment(
                    value: ServerConnectionType.maidcafe,
                    label: Text('serverConnectionMaidCafe'.tr()),
                  ),
                ],
                selected: {_connectionType},
                onSelectionChanged: (value) {
                  setState(() {
                    _connectionType = value.first;
                    // A jump host is an SSH hop; keeping one on a terminal-only
                    // transport would leave the form rejecting itself.
                    if (value.first != ServerConnectionType.ssh) {
                      _jumpHostServerId = null;
                    }
                  });
                  if (value.first == ServerConnectionType.serial) {
                    _scanSerialDevices();
                  }
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: InputDecoration(labelText: 'serverNameLabel'.tr()),
                validator: _required,
              ),
              const SizedBox(height: 12),
              if (_connectionType == ServerConnectionType.ssh) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _host,
                        decoration: InputDecoration(
                          labelText: 'serverHostLabel'.tr(),
                          suffixIcon: tailscaleRunning
                              ? IconButton(
                                  tooltip: 'tailscalePickMachine'.tr(),
                                  icon: const Icon(Symbols.lan),
                                  onPressed: () =>
                                      _pickTailscaleMachine(context),
                                )
                              : null,
                        ),
                        validator: _required,
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 100,
                      child: TextFormField(
                        controller: _port,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'serverPortLabel'.tr(),
                        ),
                        validator: _validPort,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _user,
                  decoration: InputDecoration(
                    labelText: 'serverUsernameLabel'.tr(),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<({int? id, bool isNew})>(
                  initialValue: _credentialChoice,
                  decoration: InputDecoration(
                    labelText: 'serverCredentialLabel'.tr(),
                    helperText: 'serverCredentialOptionalHint'.tr(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: (id: null, isNew: false),
                      child: Text('serverCredentialNone'.tr()),
                    ),
                    DropdownMenuItem(
                      value: (id: null, isNew: true),
                      child: Text('serverCredentialNew'.tr()),
                    ),
                    ...widget.credentials.map(
                      (credential) => DropdownMenuItem(
                        value: (id: credential.id, isNew: false),
                        child: Text(credential.name),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _credentialChoice = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                if (_credentialChoice.isNew) ...[
                  SegmentedButton<CredentialType>(
                    segments: [
                      ButtonSegment(
                        value: CredentialType.password,
                        label: Text('serverAuthPassword'.tr()),
                      ),
                      ButtonSegment(
                        value: CredentialType.privateKey,
                        label: Text('serverAuthPrivateKey'.tr()),
                      ),
                    ],
                    selected: {_type},
                    onSelectionChanged: (value) =>
                        setState(() => _type = value.first),
                  ),
                  const SizedBox(height: 12),
                  if (_type == CredentialType.password)
                    TextFormField(
                      controller: _secret,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'serverPasswordLabel'.tr(),
                      ),
                      validator: _requiredSecret,
                    )
                  else ...[
                    TextFormField(
                      controller: _secret,
                      minLines: 4,
                      maxLines: 8,
                      validator: _required,
                      decoration: InputDecoration(
                        labelText: 'serverPrivateKeyLabel'.tr(),
                        suffixIcon: IconButton(
                          onPressed: _pickKey,
                          icon: const Icon(Symbols.upload_file),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passphrase,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'serverKeyPassphraseLabel'.tr(),
                      ),
                    ),
                  ],
                ],
                if (_connectionType == ServerConnectionType.ssh) ...[
                  MaidKitCollapsibleSection(
                    initiallyExpanded: _jumpHostServerId != null,
                    tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                    childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    title: Text('serverJumpHostLabel'.tr()),
                    subtitle: Text(_jumpHostSummary()),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: DropdownButtonFormField<int?>(
                          initialValue: _jumpHostServerId,
                          decoration: InputDecoration(
                            labelText: 'serverJumpHostLabel'.tr(),
                            helperText: 'serverJumpHostHint'.tr(),
                          ),
                          items: [
                            DropdownMenuItem<int?>(
                              value: null,
                              child: Text('serverJumpHostNone'.tr()),
                            ),
                            if (_jumpHostServerId != null &&
                                !widget.servers.any(
                                  (server) => server.id == _jumpHostServerId,
                                ))
                              DropdownMenuItem<int?>(
                                value: _jumpHostServerId,
                                child: Text('serverJumpHostMissing'.tr()),
                              ),
                            for (final candidate in widget.servers)
                              if (candidate.id != widget.serverId &&
                                  candidate.connectionType ==
                                      ServerConnectionType.ssh.name)
                                DropdownMenuItem<int?>(
                                  value: candidate.id,
                                  child: Text(candidate.name),
                                ),
                          ],
                          onChanged: (value) =>
                              setState(() => _jumpHostServerId = value),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                MaidKitCollapsibleSection(
                  initiallyExpanded: false,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  title: Text('serverProxyLabel'.tr()),
                  subtitle: Text(switch (_proxyType) {
                    ServerProxyType.none => 'serverProxyNone'.tr(),
                    ServerProxyType.http => 'serverProxyHttp'.tr(),
                    ServerProxyType.socks5 => 'serverProxySocks5'.tr(),
                  }),
                  children: [
                    SegmentedButton<ServerProxyType>(
                      segments: [
                        ButtonSegment(
                          value: ServerProxyType.none,
                          label: Text('serverProxyNone'.tr()),
                        ),
                        ButtonSegment(
                          value: ServerProxyType.http,
                          label: Text('serverProxyHttp'.tr()),
                        ),
                        ButtonSegment(
                          value: ServerProxyType.socks5,
                          label: Text('serverProxySocks5'.tr()),
                        ),
                      ],
                      selected: {_proxyType},
                      onSelectionChanged: (value) =>
                          setState(() => _proxyType = value.first),
                    ),
                    if (_proxyType != ServerProxyType.none) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _proxyHost,
                              decoration: InputDecoration(
                                labelText: 'serverProxyHostLabel'.tr(),
                              ),
                              validator: _required,
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 100,
                            child: TextFormField(
                              controller: _proxyPort,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'serverProxyPortLabel'.tr(),
                              ),
                              validator: _validPort,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _proxyUsername,
                        decoration: InputDecoration(
                          labelText: 'serverProxyUsernameLabel'.tr(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _proxyPassword,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'serverProxyPasswordLabel'.tr(),
                          helperText: widget.initial?.proxy != null
                              ? 'serverProxyPasswordKeepHint'.tr()
                              : null,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                MaidKitCollapsibleSection(
                  initiallyExpanded: false,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  title: Text('serverEnvironmentLabel'.tr()),
                  subtitle: Text('serverEnvironmentHint'.tr()),
                  children: [
                    for (final row in _envRows) ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: row.name,
                              decoration: InputDecoration(
                                labelText: 'serverEnvNameLabel'.tr(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: row.value,
                              decoration: InputDecoration(
                                labelText: 'serverEnvValueLabel'.tr(),
                                isDense: true,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'serverRemoveVariable'.tr(),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _removeEnvRow(row),
                            icon: const Icon(Symbols.close, size: 18),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _addEnvRow,
                        icon: const Icon(Symbols.add, size: 18),
                        label: Text('serverAddEnvVar'.tr()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                MaidKitCollapsibleSection(
                  initiallyExpanded: false,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  title: Text('serverInitialSnippetsLabel'.tr()),
                  subtitle: Text('serverInitialSnippetsHint'.tr()),
                  children: [
                    if (widget.snippets.isEmpty)
                      Text(
                        'serverNoSnippetsHint'.tr(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final snippet in widget.snippets)
                              FilterChip(
                                label: Text(snippet.name),
                                selected: _snippetIds.contains(snippet.id),
                                onSelected: (selected) => setState(() {
                                  if (selected) {
                                    _snippetIds.add(snippet.id);
                                  } else {
                                    _snippetIds.remove(snippet.id);
                                  }
                                }),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ] else if (_connectionType == ServerConnectionType.maidcafe) ...[
                ..._maidCafeTerminalFields(context, urlRequired: true),
              ] else if (_connectionType == ServerConnectionType.ssh) ...[
                // A browser cannot open a raw SSH socket, so an SSH server can
                // also store a MaidCafe daemon route and serve its terminal
                // over the daemon there. Native builds keep using SSH and
                // ignore this section.
                ExpansionTile(
                  initiallyExpanded: _maidCafeRouteConfigured,
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 12),
                  title: Text('serverMaidCafeDaemonFallbackTitle'.tr()),
                  subtitle: Text('serverMaidCafeDaemonFallbackHint'.tr()),
                  children: _maidCafeTerminalFields(
                    context,
                    urlRequired: false,
                  ),
                ),
              ] else ...[
                DropdownMenu<String>(
                  controller: _serialDevice,
                  enableFilter: true,
                  requestFocusOnTap: true,
                  expandedInsets: EdgeInsets.zero,
                  label: Text('serverSerialDeviceLabel'.tr()),
                  helperText: 'serverSerialDeviceHint'.tr(),
                  trailingIcon: _scanningSerialDevices
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  dropdownMenuEntries: [
                    for (final device in _serialDevices)
                      DropdownMenuEntry(
                        value: device,
                        label: device,
                        leadingIcon: const Icon(Symbols.usb, size: 18),
                      ),
                  ],
                  onSelected: (value) {
                    if (value != null) {
                      _serialDevice.text = value;
                    }
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _scanningSerialDevices
                          ? null
                          : _scanSerialDevices,
                      icon: Icon(
                        _scanningSerialDevices ? Symbols.sync : Symbols.refresh,
                        size: 18,
                      ),
                      label: Text('serverSerialScan'.tr()),
                    ),
                    if (_serialDevices.isEmpty &&
                        _serialDevice.text.trim().isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          'serverSerialNoDevices'.tr(),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _serialBaud,
                  decoration: InputDecoration(
                    labelText: 'serverSerialBaudLabel'.tr(),
                  ),
                  items: [
                    for (final value in [
                      9600,
                      19200,
                      38400,
                      57600,
                      115200,
                      230400,
                      460800,
                      921600,
                    ])
                      DropdownMenuItem(value: value, child: Text('$value')),
                  ],
                  onChanged: (value) =>
                      setState(() => _serialBaud = value ?? _serialBaud),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _serialDataBits,
                  decoration: InputDecoration(
                    labelText: 'serverSerialDataBitsLabel'.tr(),
                  ),
                  items: [
                    for (final value in [5, 6, 7, 8])
                      DropdownMenuItem(value: value, child: Text('$value')),
                  ],
                  onChanged: (value) => setState(
                    () => _serialDataBits = value ?? _serialDataBits,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<SerialParity>(
                  initialValue: _serialParity,
                  decoration: InputDecoration(
                    labelText: 'serverSerialParityLabel'.tr(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: SerialParity.none,
                      child: Text('serverSerialParityNone'.tr()),
                    ),
                    DropdownMenuItem(
                      value: SerialParity.even,
                      child: Text('serverSerialParityEven'.tr()),
                    ),
                    DropdownMenuItem(
                      value: SerialParity.odd,
                      child: Text('serverSerialParityOdd'.tr()),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _serialParity = value ?? _serialParity),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _serialStopBits,
                  decoration: InputDecoration(
                    labelText: 'serverSerialStopBitsLabel'.tr(),
                  ),
                  items: [
                    for (final value in [1, 2])
                      DropdownMenuItem(value: value, child: Text('$value')),
                  ],
                  onChanged: (value) => setState(
                    () => _serialStopBits = value ?? _serialStopBits,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<SerialFlowControl>(
                  initialValue: _serialFlowControl,
                  decoration: InputDecoration(
                    labelText: 'serverSerialFlowControlLabel'.tr(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: SerialFlowControl.none,
                      child: Text('serverSerialFlowNone'.tr()),
                    ),
                    DropdownMenuItem(
                      value: SerialFlowControl.hardware,
                      child: Text('serverSerialFlowHardware'.tr()),
                    ),
                    DropdownMenuItem(
                      value: SerialFlowControl.software,
                      child: Text('serverSerialFlowSoftware'.tr()),
                    ),
                  ],
                  onChanged: (value) => setState(
                    () => _serialFlowControl = value ?? _serialFlowControl,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              MaidKitCollapsibleSection(
                initiallyExpanded: _fileManagementInitialPath.text.isNotEmpty,
                tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                title: Text('serverFileManagementLabel'.tr()),
                subtitle: Text('serverFileManagementHint'.tr()),
                children: [
                  TextFormField(
                    controller: _fileManagementInitialPath,
                    decoration: InputDecoration(
                      labelText: 'serverFileManagementInitialPath'.tr(),
                      helperText: 'serverFileManagementInitialPathHint'.tr(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              MaidKitCollapsibleSection(
                initiallyExpanded: false,
                tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                title: Text('serverTagsLabel'.tr()),
                subtitle: Text('serverTagsAddHint'.tr()),
                children: [
                  if (_tags.isNotEmpty) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final tag in _tags)
                            InputChip(
                              label: Text(tag),
                              onDeleted: () =>
                                  setState(() => _tags.remove(tag)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _tagInput,
                          decoration: InputDecoration(
                            labelText: 'serverTagAdd'.tr(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _addTag(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        onPressed: _addTag,
                        icon: const Icon(Symbols.add, size: 18),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_connectionType == ServerConnectionType.ssh) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('serverCollectStats'.tr()),
                  subtitle: Text('serverCollectStatsHint'.tr()),
                  value: _collectStats,
                  onChanged: (value) => setState(() => _collectStats = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('serverDiscoverSystemInfo'.tr()),
                  subtitle: Text('serverDiscoverSystemInfoHint'.tr()),
                  value: _collectSystemInfo,
                  onChanged: (value) =>
                      setState(() => _collectSystemInfo = value),
                ),
              ],
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('commonCancel'.tr()),
                  ),
                  FilledButton(
                    onPressed: _save,
                    child: Text('serverSaveAndConnect'.tr()),
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
