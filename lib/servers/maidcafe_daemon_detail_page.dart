import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:maid_kit/theme.dart';

import 'maidcafe_service.dart';
import 'server_providers.dart';

/// Detail page for one MaidCafe cloud daemon: the managed container status
/// the daemon uploads on its metrics tick (Containers), the retained uploaded
/// log lines (Logs), and the actions the daemon reports (Actions).
///
/// All three tabs are read-only views over workspace-member cloud endpoints;
/// invocation and management stay on the fleet card.
class MaidCafeDaemonDetailPage extends ConsumerWidget {
  const MaidCafeDaemonDetailPage({super.key, required this.daemon});

  final MaidCafeDaemon daemon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            daemon.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          bottom: TabBar(
            tabs: [
              Tab(text: 'daemonDetailContainers'.tr()),
              Tab(text: 'daemonDetailOperations'.tr()),
              Tab(text: 'daemonDetailLogs'.tr()),
              Tab(text: 'daemonDetailActions'.tr()),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ContainersTab(daemonId: daemon.id),
            _ActionsTab(daemonId: daemon.id, nativeOnly: true),
            _LogsTab(daemonId: daemon.id),
            _ActionsTab(daemonId: daemon.id),
          ],
        ),
      ),
    );
  }
}

/// The managed container status uploaded by the daemon, grouped by compose
/// project. Empty compose projects group under the standalone label.
class _ContainersTab extends ConsumerStatefulWidget {
  const _ContainersTab({required this.daemonId});

  final String daemonId;

  @override
  ConsumerState<_ContainersTab> createState() => _ContainersTabState();
}

class _ContainersTabState extends ConsumerState<_ContainersTab> {
  late Future<List<MaidCafeCloudContainer>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<MaidCafeCloudContainer>> _load() => ref
      .read(maidCafeServiceProvider)
      .listContainers(widget.daemonId, limit: 200);

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<MaidCafeCloudContainer>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData && !snapshot.hasError) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(error: snapshot.error!, onRetry: _refresh);
          }
          final containers = snapshot.data ?? const <MaidCafeCloudContainer>[];
          if (containers.isEmpty) {
            return _EmptyView(
              icon: Symbols.inventory_2,
              message: 'daemonDetailNoContainers'.tr(),
            );
          }
          final groups = <String, List<MaidCafeCloudContainer>>{};
          for (final container in containers) {
            groups
                .putIfAbsent(
                  container.composeProject.isEmpty
                      ? 'daemonDetailStandalone'.tr()
                      : container.composeProject,
                  () => [],
                )
                .add(container);
          }
          final projects = groups.keys.toList()..sort();
          return ListView.builder(
            itemCount: projects.length,
            itemBuilder: (context, index) {
              final project = projects[index];
              final group = groups[project]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _GroupHeader(label: project, count: group.length),
                  for (final container in group) _ContainerTile(container),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContainerTile extends StatelessWidget {
  const _ContainerTile(this.container);

  final MaidCafeCloudContainer container;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final mono = theme.textTheme.bodySmall?.copyWith(
      fontFamily: MaidKitFonts.mono,
      fontSize: 12,
    );
    final subtitle = [
      if (container.image.isNotEmpty) container.image,
      if (container.status.isNotEmpty) container.status,
    ].join(' · ');
    return ListTile(
      leading: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: container.running ? colors.primary : colors.error,
          shape: BoxShape.circle,
        ),
      ),
      title: Text(
        container.name.isEmpty ? container.containerId : container.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono,
            ),
      trailing: Text(
        _formatSeen(container.lastSeenAt),
        style: theme.textTheme.labelSmall?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The retained uploaded log lines, oldest listing newest-first like the
/// cloud returns them.
class _LogsTab extends ConsumerStatefulWidget {
  const _LogsTab({required this.daemonId});

  final String daemonId;

  @override
  ConsumerState<_LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends ConsumerState<_LogsTab> {
  late Future<List<MaidCafeCloudLog>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<MaidCafeCloudLog>> _load() =>
      ref.read(maidCafeServiceProvider).listLogs(widget.daemonId, limit: 200);

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<MaidCafeCloudLog>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData && !snapshot.hasError) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(error: snapshot.error!, onRetry: _refresh);
          }
          final logs = snapshot.data ?? const <MaidCafeCloudLog>[];
          if (logs.isEmpty) {
            return _EmptyView(
              icon: Symbols.description,
              message: 'daemonDetailNoLogs'.tr(),
            );
          }
          final theme = Theme.of(context);
          return ListView.separated(
            itemCount: logs.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final log = logs[index];
              return ListTile(
                dense: true,
                title: Text(
                  log.line,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: MaidKitFonts.mono,
                  ),
                ),
                subtitle: Text(
                  '${log.containerId} · '
                  '${DateFormat('MM/dd HH:mm:ss').format(log.timestamp.toLocal())}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// The actions the daemon reported to the cloud, read-only; invocation stays
/// on the fleet card.
class _ActionsTab extends ConsumerStatefulWidget {
  const _ActionsTab({required this.daemonId, this.nativeOnly = false});

  final String daemonId;
  final bool nativeOnly;
  @override
  ConsumerState<_ActionsTab> createState() => _ActionsTabState();
}

class _ActionsTabState extends ConsumerState<_ActionsTab> {
  late Future<List<MaidCafeCloudAction>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<MaidCafeCloudAction>> _load() =>
      ref.read(maidCafeServiceProvider).listActions(widget.daemonId);

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<MaidCafeCloudAction>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData && !snapshot.hasError) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(error: snapshot.error!, onRetry: _refresh);
          }
          final actions = (snapshot.data ?? const <MaidCafeCloudAction>[])
              .where(
                (action) => _isNativeOperation(action) == widget.nativeOnly,
              )
              .toList(growable: false);
          if (actions.isEmpty) {
            return _EmptyView(
              icon: widget.nativeOnly ? Symbols.inventory_2 : Symbols.bolt,
              message:
                  (widget.nativeOnly
                          ? 'daemonDetailNoOperations'
                          : 'daemonDetailNoActions')
                      .tr(),
            );
          }
          final colors = Theme.of(context).colorScheme;
          return ListView(
            children: [
              for (final action in actions)
                ListTile(
                  leading: Icon(
                    Symbols.bolt,
                    color: action.enabled ? colors.primary : colors.outline,
                  ),
                  title: Text(action.label),
                  subtitle: Text(
                    [
                      action.name,
                      if (action.timeout.isNotEmpty) action.timeout,
                      if (action.user.isNotEmpty) action.user,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

bool _isNativeOperation(MaidCafeCloudAction action) {
  final name = action.name;
  return name.startsWith('container.') ||
      name.startsWith('compose.') ||
      name.startsWith('systemd.') ||
      name == 'process.kill';
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        const SizedBox(height: 80),
        Icon(Symbols.error, size: 40, color: theme.colorScheme.error),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            '$error',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: OutlinedButton(
            onPressed: onRetry,
            child: Text('daemonDetailRetry'.tr()),
          ),
        ),
      ],
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        const SizedBox(height: 80),
        Icon(icon, size: 40, color: theme.colorScheme.outline),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

String _formatSeen(DateTime value) {
  final local = value.toLocal();
  final difference = DateTime.now().difference(local);
  if (difference.inMinutes < 1) return 'now';
  if (difference.inHours < 24) return '${difference.inHours}h';
  return DateFormat('MM/dd HH:mm').format(local);
}
