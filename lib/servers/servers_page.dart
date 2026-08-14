import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:styled_widget/styled_widget.dart';
import 'package:super_context_menu/super_context_menu.dart';
import 'package:tailscale/tailscale.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/github/github_workflow_strip.dart';
import 'package:maid_kit/shared/presentation/app_scaffold.dart';
import 'package:maid_kit/shared/presentation/collapsible_section.dart';
import 'package:maid_kit/snippets/snippet_repository.dart';
import 'server_connection_actions.dart';
import 'server_models.dart';
import 'server_providers.dart';
import 'serial_port_client.dart';
import 'privacy_preferences.dart';
import 'sessions_page.dart';
import 'tailscale_service.dart';
import 'tailscale_settings_section.dart';
import 'tailscale_ssh_socket.dart';
import 'terminal_tabs_provider.dart';

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
    if (server.connectionType == ServerConnectionType.serial.name) {
      await openSerialTerminalSession(context, ref, server);
    } else if (server.connectionType == ServerConnectionType.local.name) {
      await openLocalTerminalSession(context, ref, server);
    } else {
      await connectForStatistics(context, ref, server);
    }
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
            connectionType:
                ServerConnectionType.values
                    .asNameMap()[server.connectionType] ??
                ServerConnectionType.ssh,
            serialConfig: decodeSerialConfig(server.serialConfig),
          ),
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
          server.connectionType == ServerConnectionType.local.name
          ? ref.read(localConnectionManagerProvider).refreshNow()
          : ref.read(connectionManagerProvider).refreshServerInfo(server),
    );
  }

  Future<void> _openFiles(
    BuildContext context,
    WidgetRef ref,
    Server server,
  ) async {
    if (server.connectionType == ServerConnectionType.serial.name) return;
    if (server.connectionType == ServerConnectionType.local.name) {
      ref.read(terminalTabsProvider.notifier).openFileManagement(server);
      return;
    }
    final manager = ref.read(connectionManagerProvider);
    if (manager.clientFor(server.id) == null &&
        !await connectForStatistics(context, ref, server)) {
      return;
    }
    ref.read(terminalTabsProvider.notifier).openFileManagement(server);
  }
}

@RoutePage()
class ServersPage extends StatelessWidget {
  const ServersPage({super.key});

  @override
  Widget build(BuildContext context) => const SessionsWorkspace();
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
      body: servers.when(
        data: (items) => items.isEmpty
            ? _EmptyServers(onAdd: onAdd)
            : _ServerGrid(
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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text('serversLoadError'.tr(args: [error.toString()])),
        ),
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

class _ServerGridState extends ConsumerState<_ServerGrid> {
  var _isReconnecting = false;
  var _isArranging = false;
  var _isSavingOrder = false;
  final _selectedTags = <String>{};
  List<int>? _pendingOrder;

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

  @override
  Widget build(BuildContext context) {
    final isCompactView = ref.watch(dashboardCompactViewProvider);
    final sessionsByServerId = {
      for (final session in widget.sessions) session.serverId: session,
    };
    final allTags =
        widget.servers
            .expand((server) => decodeStringList(server.tags))
            .toSet()
            .toList()
          ..sort();
    final visibleServers = _orderedServers.where((server) {
      final tags = decodeStringList(server.tags).toSet();
      return _selectedTags.every(tags.contains);
    }).toList();
    final disconnectedServers = visibleServers.where((server) {
      // The local machine is always reachable and never participates in
      // reconnect-all.
      if (server.connectionType == ServerConnectionType.local.name) {
        return false;
      }
      final status = sessionsByServerId[server.id]?.status;
      return status != SessionStatus.connected &&
          status != SessionStatus.connecting;
    }).toList();

    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => SizeTransition(
            sizeFactor: animation,
            alignment: Alignment.topCenter,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: disconnectedServers.length > 1
              ? Padding(
                  key: const ValueKey('servers-reconnect-all'),
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                  child: _ReconnectAllCard(
                    count: disconnectedServers.length,
                    isReconnecting: _isReconnecting,
                    onPressed: () => _reconnectAll(disconnectedServers),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('servers-reconnect-none')),
        ),
        if (allTags.isNotEmpty)
          Padding(
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
        if (visibleServers.isEmpty)
          Expanded(
            child: CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: GithubWorkflowStatusStrip()),
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: _NoServersMatch()),
                ),
                SliverToBoxAdapter(child: _arrangeServersFooter(context)),
              ],
            ),
          )
        else
          Expanded(
            child: CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: GithubWorkflowStatusStrip()),
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
                        onConnect: () => widget.onConnect(server),
                        onOpenDetail: () => widget.onOpenDetail(server),
                        onOpenTerminal: () => widget.onOpenTerminal(server),
                        onOpenFiles: () => widget.onOpenFiles(server),
                        onRefresh: () => widget.onRefresh(server),
                      );
                      // The local machine is a virtual server: it is not in
                      // the database, so it cannot be reordered, edited, or
                      // deleted, and gets no context menu.
                      final isLocal =
                          server.connectionType ==
                          ServerConnectionType.local.name;
                      if (isLocal) return card;
                      if (_isArranging) {
                        return _ReorderableServerTile(
                          server: server,
                          isSavingOrder: _isSavingOrder,
                          onMoveBefore: _moveBefore,
                          child: card,
                        );
                      }
                      return ContextMenuWidget(
                        menuProvider: (_) => Menu(
                          children: [
                            MenuAction(
                              title: 'serversEditServer'.tr(),
                              callback: () => widget.onEdit(server),
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
                SliverToBoxAdapter(child: _arrangeServersFooter(context)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _arrangeServersFooter(BuildContext context) {
    final isCompactView = ref.watch(dashboardCompactViewProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              OutlinedButton.icon(
                onPressed: () => ref
                    .read(dashboardCompactViewProvider.notifier)
                    .setCompact(!isCompactView),
                icon: Icon(
                  isCompactView ? Symbols.view_agenda : Symbols.view_compact,
                ),
                label: Text(
                  isCompactView
                      ? 'serversDetailedView'.tr()
                      : 'serversCompactView'.tr(),
                ),
              ),
              const SizedBox(width: 8),
              _ArrangeServersControl(
                isArranging: _isArranging,
                canArrange: widget.servers.length > 1,
                onPressed: _isArranging
                    ? () => setState(() => _isArranging = false)
                    : _startArranging,
              ),
            ],
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

class _ArrangeServersControl extends StatelessWidget {
  const _ArrangeServersControl({
    required this.isArranging,
    required this.canArrange,
    required this.onPressed,
  });

  final bool isArranging;
  final bool canArrange;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (isArranging) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Symbols.check),
        label: Text('serversDoneArranging'.tr()),
      );
    }

    return OutlinedButton.icon(
      onPressed: canArrange ? onPressed : null,
      icon: const Icon(Symbols.drag_indicator),
      label: Text('serversArrange'.tr()),
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
    final isSerial = server.connectionType == ServerConnectionType.serial.name;
    final isLocal = server.connectionType == ServerConnectionType.local.name;
    // The local machine is always reachable; its session may lag one refresh
    // behind, so never surface it as disconnected.
    final connected = isLocal || session?.status == SessionStatus.connected;
    final connecting = session?.status == SessionStatus.connecting;
    final failed = session?.status == SessionStatus.failed;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // The local machine has no SSH details page; its actions live on the
        // card itself (terminal, files, refresh).
        onTap: isLocal ? null : onOpenDetail,
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
                      isLocal ? Symbols.computer : Symbols.dns,
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
                              if (!isSerial &&
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
                              if (isLocal) ...[
                                const SizedBox(width: 6),
                                _BadgeChip(label: 'localMachineBadge'.tr()),
                              ],
                            ],
                          ),
                          _ServerBadges(server: server),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'serversRefreshStatistics'.tr(),
                      visualDensity: VisualDensity.compact,
                      onPressed: isSerial
                          ? null
                          : (connected ? onRefresh : null),
                      icon: const Icon(Symbols.refresh),
                    ),
                  ],
                ),
              ),
              SizedBox(height: compact ? 8 : 12),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
                  child: isSerial
                      ? _StatsMessage(
                          icon: Symbols.usb,
                          message: 'serversSerialConsole'.tr(),
                        )
                      : connected
                      ? _ServerStats(
                          stats: session?.stats,
                          systemInfo: session?.systemInfo,
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
                      latency: session?.latency,
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
                  onOpenFiles: connecting || isSerial ? null : onOpenFiles,
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
    this.latency,
  });

  final bool connected;
  final bool connecting;
  final bool failed;
  final Duration? latency;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final latency = this.latency;

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
          Text(
            latency == null ? '—' : '${latency.inMilliseconds} ms',
            style: textTheme.labelLarge?.copyWith(color: latencyColor),
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

    return Column(
      mainAxisAlignment: compact
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
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
                  progress: gpuMemoryUsedKb == null || gpuMemoryTotalKb == null
                      ? null
                      : (gpuMemoryUsedKb / gpuMemoryTotalKb).clamp(0.0, 1.0),
                  progressColor: _memoryColor(
                    gpuMemoryUsedKb == null || gpuMemoryTotalKb == null
                        ? null
                        : (gpuMemoryUsedKb / gpuMemoryTotalKb).clamp(0.0, 1.0),
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
  });

  final ServerDraft? initial;
  final int? serverId;
  final List<SavedCredential> credentials;
  final List<Server> servers;

  /// Saved snippets offered as initial-snippet choices for this server.
  final List<ScriptSnippet> snippets;
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
  int? _credentialId;
  bool _useNewCredential = true;
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

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial == null) return;
    _name.text = initial.name;
    _host.text = initial.host;
    _port.text = initial.port.toString();
    _user.text = initial.username;
    _credentialId = initial.credentialId;
    _useNewCredential = initial.credentialId == null;
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
      _serialDevice,
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
  String? _validPort(String? value) {
    final port = int.tryParse(value ?? '');
    return port != null && port > 0 && port < 65536
        ? null
        : 'serverPortInvalid'.tr();
  }

  bool _hasJumpHostCycle() {
    if (_jumpHostServerId == null) return false;
    if (_connectionType != ServerConnectionType.ssh) return true;
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
    final credential = !_useNewCredential
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
        jumpHostServerId: _jumpHostServerId,
        username: _user.text,
        credential: credential,
        credentialId: _useNewCredential ? null : _credentialId,
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
        titleText: _connectionType == ServerConnectionType.serial
            ? 'serversAddSerialSheetTitle'.tr()
            : 'serversAddSheetTitle'.tr(),
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
                  if (serialPortsSupported && widget.initial != null)
                    ButtonSegment(
                      value: ServerConnectionType.serial,
                      label: Text('serverConnectionSerial'.tr()),
                    ),
                ],
                selected: {_connectionType},
                onSelectionChanged: (value) {
                  setState(() => _connectionType = value.first);
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
                if (widget.credentials.isNotEmpty) ...[
                  DropdownButtonFormField<int?>(
                    initialValue: _useNewCredential ? null : _credentialId,
                    decoration: InputDecoration(
                      labelText: 'serverCredentialLabel'.tr(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text('serverCredentialNew'.tr()),
                      ),
                      ...widget.credentials.map(
                        (credential) => DropdownMenuItem(
                          value: credential.id,
                          child: Text(credential.name),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() {
                      _credentialId = value;
                      _useNewCredential = value == null;
                    }),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_useNewCredential) ...[
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
                      validator: _required,
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
                    subtitle: Text(
                      _jumpHostServerId == null
                          ? 'serverJumpHostNone'.tr()
                          : widget.servers
                                    .where(
                                      (server) =>
                                          server.id == _jumpHostServerId,
                                    )
                                    .firstOrNull
                                    ?.name ??
                                'serverJumpHostMissing'.tr(),
                    ),
                    children: [
                      DropdownButtonFormField<int?>(
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
                    ],
                  ),
                ],
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
