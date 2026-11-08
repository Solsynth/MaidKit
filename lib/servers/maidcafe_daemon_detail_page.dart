import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'package:maid_kit/theme.dart';
import 'package:maid_kit/shared/presentation/app_scaffold.dart';
import 'package:maid_kit/shared/presentation/icon_label_tab.dart';
import 'maidcafe_service.dart';
import 'server_providers.dart';

/// Detail page for one MaidCafe cloud daemon: the managed container status
/// the daemon uploads on its metrics tick (Containers), the retained uploaded
/// log lines (Logs), the reported actions (Actions), and notification requests.
///
/// All views are read from workspace-member cloud endpoints; daemon management
/// stays on the fleet card.
class MaidCafeDaemonDetailPage extends ConsumerWidget {
  const MaidCafeDaemonDetailPage({super.key, required this.daemon});

  final MaidCafeDaemon daemon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: MaidKitAppScaffold(
        appBar: AppBar(
          title: Text(
            daemon.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          bottom: TabBar(
            // Left-aligned and scrollable: a four-tab strip spread across a
            // wide window reads as table headers, not as navigation.
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              IconLabelTab(
                icon: const Icon(Symbols.inventory_2, size: 18),
                label: 'daemonDetailContainers'.tr(),
              ),
              IconLabelTab(
                icon: const Icon(Symbols.bolt, size: 18),
                label: 'daemonDetailOperations'.tr(),
              ),
              IconLabelTab(
                icon: const Icon(Symbols.description, size: 18),
                label: 'daemonDetailLogs'.tr(),
              ),
              IconLabelTab(
                icon: const Icon(Symbols.list_alt, size: 18),
                label: 'daemonDetailActions'.tr(),
              ),
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

/// The actions the daemon reported to the cloud. They can be invoked here;
/// native operations prompt for their parameters before relay.
class _ActionsTab extends ConsumerStatefulWidget {
  const _ActionsTab({required this.daemonId, this.nativeOnly = false});

  final String daemonId;
  final bool nativeOnly;

  @override
  ConsumerState<_ActionsTab> createState() => _ActionsTabState();
}

class _ActionsTabState extends ConsumerState<_ActionsTab> {
  late Future<List<MaidCafeCloudAction>> _future;
  var _busy = false;

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

  Future<void> _invokeCloudAction(MaidCafeCloudAction action) async {
    if (_busy || !action.enabled) return;
    final fields = _nativeOpParamFields(action.name);
    Map<String, dynamic> body = const {};
    if (fields.isNotEmpty) {
      final values = await showDialog<Map<String, String>>(
        context: context,
        builder: (context) => _NativeOpParamsDialog(
          title: action.displayName.isNotEmpty
              ? action.displayName
              : action.name,
          fields: fields,
        ),
      );
      if (values == null || !mounted) return;
      body = values;
    }
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(maidCafeServiceProvider)
          .invokeActionViaCloud(
            daemonId: widget.daemonId,
            actionName: action.name,
            body: body,
          );
      if (mounted) {
        final stdout = utf8.decode(result.body, allowMalformed: true).trim();
        final stderr = result.error?.trim() ?? '';
        showSnackBar(
          stdout.isNotEmpty
              ? stdout
              : stderr.isNotEmpty
              ? stderr
              : 'maidCafeActionInvoked'.tr(),
        );
      }
    } on MaidCafeException catch (error) {
      if (mounted) showSnackBar(error.message);
    } catch (error) {
      if (mounted) showSnackBar(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestPushNotification() async {
    if (_busy) return;
    final requested = await showModalBottomSheet<({String title, String body})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const _RequestNotificationSheet(),
    );
    if (requested == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(maidCafeServiceProvider)
          .requestPushNotification(
            widget.daemonId,
            kind: 'user.request',
            title: requested.title,
            body: requested.body,
          );
      if (mounted) showSnackBar('maidCafeActionInvoked'.tr());
    } on MaidCafeException catch (error) {
      if (mounted) showSnackBar(error.message);
    } catch (error) {
      if (mounted) showSnackBar(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The parameters a native operation slug requires, in prompt order.
  static List<({String key, String label})> _nativeOpParamFields(String slug) {
    if (slug.startsWith('container.')) {
      return [(key: 'id', label: 'maidCafeNativeOpFieldId')];
    }
    if (slug == 'process.kill') {
      return [(key: 'pid', label: 'maidCafeNativeOpFieldPid')];
    }
    if (slug.startsWith('systemd.')) {
      return [(key: 'unit', label: 'maidCafeNativeOpFieldUnit')];
    }
    if (slug.startsWith('compose.')) {
      return [
        (key: 'project', label: 'maidCafeNativeOpFieldProject'),
        (key: 'directory', label: 'maidCafeNativeOpFieldDirectory'),
      ];
    }
    return const [];
  }

  /// Rows for the daemon's own reported actions: a plain list, one verb each.
  List<Widget> _actionRows(
    BuildContext context,
    List<MaidCafeCloudAction> actions,
  ) {
    final colors = Theme.of(context).colorScheme;
    return [
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
          trailing: FilledButton.tonal(
            onPressed: _busy || !action.enabled
                ? null
                : () => _invokeCloudAction(action),
            child: Text('maidCafeNativeOpRun'.tr()),
          ),
        ),
    ];
  }

  /// Native operations grouped by the thing they operate on, with each verb
  /// named in plain language instead of the RPC slug. Destructive verbs are
  /// marked and tinted; operations that need parameters say so before they
  /// are run, never after.
  List<Widget> _nativeGroups(
    BuildContext context,
    List<MaidCafeCloudAction> actions,
  ) {
    final composeOps = <MaidCafeCloudAction>[];
    final containerOps = <MaidCafeCloudAction>[];
    final systemOps = <MaidCafeCloudAction>[];
    final otherOps = <MaidCafeCloudAction>[];
    for (final action in actions) {
      if (action.name.startsWith('compose.')) {
        composeOps.add(action);
      } else if (action.name.startsWith('container.')) {
        containerOps.add(action);
      } else if (action.name.startsWith('systemd.') ||
          action.name == 'process.kill') {
        systemOps.add(action);
      } else {
        otherOps.add(action);
      }
    }
    return [
      if (composeOps.isNotEmpty)
        ..._group(
          context,
          'daemonOpGroupCompose',
          composeOps,
          Symbols.folder_copy,
        ),
      if (containerOps.isNotEmpty)
        ..._group(
          context,
          'daemonOpGroupContainers',
          containerOps,
          Symbols.inventory_2,
        ),
      if (systemOps.isNotEmpty)
        ..._group(
          context,
          'daemonOpGroupServices',
          systemOps,
          Symbols.settings_applications,
        ),
      if (otherOps.isNotEmpty)
        ..._group(context, 'daemonOpGroupOther', otherOps, Symbols.bolt),
    ];
  }

  List<Widget> _group(
    BuildContext context,
    String titleKey,
    List<MaidCafeCloudAction> actions,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Row(
          children: [
            Icon(icon, size: 16, color: colors.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              titleKey.tr(),
              style: theme.textTheme.labelLarge?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      for (final action in actions)
        _NativeOpRow(
          action: action,
          busy: _busy,
          needsParams: _nativeOpParamFields(action.name).isNotEmpty,
          onRun: () => _invokeCloudAction(action),
        ),
    ];
  }

  Widget _requestButton() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: _busy ? null : _requestPushNotification,
        icon: const Icon(Symbols.notifications, size: 18),
        label: Text('maidCafeRequestNotification'.tr()),
      ),
    ),
  );

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
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (!widget.nativeOnly) _requestButton(),
              if (actions.isEmpty)
                // Inline rather than the shared empty view: that one scrolls
                // its own list, and a scroll view cannot nest inside this one.
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Column(
                    children: [
                      Icon(
                        widget.nativeOnly ? Symbols.inventory_2 : Symbols.bolt,
                        size: 40,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        (widget.nativeOnly
                                ? 'daemonDetailNoOperations'
                                : 'daemonDetailNoActions')
                            .tr(),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              else if (widget.nativeOnly)
                ..._nativeGroups(context, actions)
              else
                ..._actionRows(context, actions),
            ],
          );
        },
      ),
    );
  }
}

/// One native operation: what it does, whether it is destructive, and
/// whether it needs parameters before it can run.
class _NativeOpRow extends StatelessWidget {
  const _NativeOpRow({
    required this.action,
    required this.busy,
    required this.needsParams,
    required this.onRun,
  });

  final MaidCafeCloudAction action;
  final bool busy;
  final bool needsParams;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final label = nativeOpLabel(action);
    final destructive = nativeOpIsDestructive(action.name);
    final enabled = action.enabled && !busy;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Icon(
        nativeOpIcon(action.name),
        size: 18,
        color: !action.enabled
            ? colors.outline
            : destructive
            ? colors.error
            : colors.onSurfaceVariant,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: action.enabled ? null : colors.outline,
              ),
            ),
          ),
          if (destructive) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: 'daemonOpDestructiveHint'.tr(),
              child: Icon(Symbols.warning, size: 14, color: colors.error),
            ),
          ],
        ],
      ),
      subtitle: Text(
        [
          action.name,
          if (action.timeout.isNotEmpty) action.timeout,
          if (action.user.isNotEmpty) action.user,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: colors.onSurfaceVariant,
          fontFamily: MaidKitFonts.mono,
        ),
      ),
      trailing: needsParams
          ? OutlinedButton.icon(
              onPressed: enabled ? onRun : null,
              icon: const Icon(Symbols.tune, size: 16),
              label: Text('daemonOpConfigureAndRun'.tr()),
            )
          : destructive
          ? OutlinedButton(
              onPressed: enabled ? onRun : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.error,
                side: BorderSide(color: colors.error.withValues(alpha: 0.5)),
              ),
              child: Text('maidCafeNativeOpRun'.tr()),
            )
          : FilledButton.tonal(
              onPressed: enabled ? onRun : null,
              child: Text('maidCafeNativeOpRun'.tr()),
            ),
    );
  }
}

/// A native operation's name in the reader's words, not the RPC slug.
String nativeOpLabel(MaidCafeCloudAction action) {
  final named = action.name;
  final key = switch (named) {
    'container.start' => 'daemonOpContainerStart',
    'container.stop' => 'daemonOpContainerStop',
    'container.restart' => 'daemonOpContainerRestart',
    'container.pause' => 'daemonOpContainerPause',
    'container.unpause' => 'daemonOpContainerResume',
    'container.kill' => 'daemonOpContainerKill',
    'container.remove' => 'daemonOpContainerRemove',
    'container.pull' => 'daemonOpContainerPull',
    'compose.up' => 'daemonOpComposeUp',
    'compose.stop' => 'daemonOpComposeStop',
    'compose.restart' => 'daemonOpComposeRestart',
    'compose.pull' => 'daemonOpComposePull',
    'compose.recreate' => 'daemonOpComposeRecreate',
    'process.kill' => 'daemonOpProcessKill',
    _ => null,
  };
  if (key != null) return key.tr();
  if (named.startsWith('systemd.')) {
    final verb = named.substring('systemd.'.length);
    return 'daemonOpSystemdVerb'.tr(args: [verb]);
  }
  return action.label;
}

/// Verbs that interrupt or destroy a running workload.
bool nativeOpIsDestructive(String name) => switch (name) {
  'container.kill' ||
  'container.remove' ||
  'container.stop' ||
  'compose.stop' ||
  'process.kill' => true,
  _ => name.startsWith('systemd.') && name.endsWith('stop'),
};

IconData nativeOpIcon(String name) => switch (name) {
  'container.pull' || 'compose.pull' => Symbols.download,
  'container.restart' ||
  'compose.restart' ||
  'compose.recreate' => Symbols.restart_alt,
  'container.remove' => Symbols.delete_outline,
  'container.start' || 'compose.up' => Symbols.play_arrow,
  'container.stop' || 'compose.stop' || 'process.kill' => Symbols.stop,
  'container.pause' => Symbols.pause,
  _ => Symbols.bolt,
};

bool _isNativeOperation(MaidCafeCloudAction action) {
  final name = action.name;
  return name.startsWith('container.') ||
      name.startsWith('compose.') ||
      name.startsWith('systemd.') ||
      name == 'process.kill';
}

class _RequestNotificationSheet extends StatefulWidget {
  const _RequestNotificationSheet();

  @override
  State<_RequestNotificationSheet> createState() =>
      _RequestNotificationSheetState();
}

class _RequestNotificationSheetState extends State<_RequestNotificationSheet> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 560,
    child: SheetScaffold(
      titleText: 'maidCafeRequestNotification'.tr(),
      heightFactor: 0.5,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: 'maidCafeNotificationTitle'.tr(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyController,
            decoration: InputDecoration(
              labelText: 'maidCafeNotificationBody'.tr(),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('maidCafeCancel'.tr()),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.pop(context, (
                  title: _titleController.text,
                  body: _bodyController.text,
                )),
                child: Text('maidCafeRequest'.tr()),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _NativeOpParamsDialog extends StatefulWidget {
  const _NativeOpParamsDialog({required this.title, required this.fields});

  final String title;
  final List<({String key, String label})> fields;

  @override
  State<_NativeOpParamsDialog> createState() => _NativeOpParamsDialogState();
}

class _NativeOpParamsDialogState extends State<_NativeOpParamsDialog> {
  late final List<TextEditingController> _controllers = List.generate(
    widget.fields.length,
    (_) => TextEditingController(),
  );

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < widget.fields.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _controllers[i],
                  autofocus: i == 0,
                  decoration: InputDecoration(
                    labelText: widget.fields[i].label.tr(),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('maidCafeNativeOpCancel'.tr()),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () {
            final values = <String, String>{
              for (var i = 0; i < widget.fields.length; i++)
                widget.fields[i].key: _controllers[i].text.trim(),
            };
            Navigator.pop(context, values);
          },
          child: Text('maidCafeNativeOpRun'.tr()),
        ),
      ],
    );
  }
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
