import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:super_context_menu/super_context_menu.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/shared/presentation/deploy_terminal.dart';
import 'package_models.dart';
import 'server_connection_actions.dart';
import 'server_models.dart';
import 'server_providers.dart';

/// Host package maintenance for supported package managers.
class PackageManagementTab extends ConsumerStatefulWidget {
  const PackageManagementTab({
    super.key,
    required this.server,
    required this.connected,
    required this.connectionError,
    required this.onConnect,
  });

  final Server server;
  final bool connected;
  final String? connectionError;
  final Future<void> Function() onConnect;

  @override
  ConsumerState<PackageManagementTab> createState() =>
      _PackageManagementTabState();
}

class _PackageManagementTabState extends ConsumerState<PackageManagementTab> {
  AsyncValue<PackageManagerStatus> _status = const AsyncValue.loading();
  AsyncValue<List<PackageSearchResult>> _results = const AsyncValue.data([]);
  final _searchController = TextEditingController();
  PackageManager? _manager;
  var _busy = false;

  bool get _isRoot => widget.server.username == 'root';

  @override
  void initState() {
    super.initState();
    if (widget.connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void didUpdateWidget(PackageManagementTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connected &&
        (!oldWidget.connected || oldWidget.server.id != widget.server.id)) {
      _load();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<String?> _sudoPassword() async {
    final credential = await ref
        .read(serverRepositoryProvider)
        .credentialFor(widget.server);
    return credential.type == CredentialType.password
        ? credential.password
        : null;
  }

  Future<void> _load() async {
    if (!mounted || !widget.connected) return;
    setState(() => _status = const AsyncValue.loading());
    try {
      final status = await ref
          .read(connectionManagerProvider)
          .getPackageManagerStatus(
            widget.server.id,
            preferredManager: _manager,
          );
      if (mounted) {
        setState(() {
          _status = AsyncValue.data(status);
          _manager = status.available.contains(_manager)
              ? _manager
              : status.preferred;
        });
      }
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() => _status = AsyncValue.error(error, stackTrace));
      }
    }
  }

  Future<void> _search() async {
    final manager = _manager;
    final query = _searchController.text.trim();
    if (manager == null || query.isEmpty) return;
    setState(() => _results = const AsyncValue.loading());
    try {
      final results = await ref
          .read(connectionManagerProvider)
          .searchPackages(widget.server.id, manager: manager, query: query);
      if (mounted) setState(() => _results = AsyncValue.data(results));
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() => _results = AsyncValue.error(error, stackTrace));
      }
    }
  }

  Future<void> _run(
    PackageAction action, {
    String? packageName,
    bool skipConfirmation = false,
    bool canRetryConnection = true,
  }) async {
    final manager = _manager;
    if (manager == null || (_busy && !skipConfirmation)) return;
    if (!skipConfirmation &&
        (!await _confirm(action, packageName: packageName) || !mounted)) {
      return;
    }
    setState(() => _busy = true);
    try {
      await runWithDeployTerminal(
        ref: ref,
        title: action.label,
        subtitle: '${manager.label} · ${widget.server.name}',
        command: _actionDescription(action, packageName),
        run: (onOutput) async {
          await ref
              .read(connectionManagerProvider)
              .runPackageAction(
                widget.server.id,
                manager: manager,
                action: action,
                packageName: packageName,
                sshUserIsRoot: _isRoot,
                sudoPassword: await _sudoPassword(),
                onOutput: onOutput,
              );
        },
      );
      if (!mounted) return;
      showStyledSnackBar(
        message: 'packageActionCompleted'.tr(args: [action.label]),
        title: 'packagePackages'.tr(),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      final shouldRetry =
          canRetryConnection &&
          await shouldReconnectAndRetry(context, error, widget.server);
      if (!mounted) return;
      if (shouldRetry) {
        await widget.onConnect();
        if (mounted) {
          await _run(
            action,
            packageName: packageName,
            skipConfirmation: true,
            canRetryConnection: false,
          );
        }
        return;
      }
      if (mounted) {
        showStyledSnackBar(
          message: error.toString(),
          title: 'packageActionFailed'.tr(),
          icon: Symbols.error,
          accentColor: Theme.of(context).colorScheme.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(PackageAction action, {String? packageName}) async {
    final needsConfirmation = action != PackageAction.refresh;
    if (!needsConfirmation) return true;
    final object = packageName ?? 'all available packages';
    return (await showModalBottomSheet<bool>(
          context: context,
          useRootNavigator: true,
          useSafeArea: true,
          builder: (sheetContext) => SheetScaffold(
            titleText: 'packageActionConfirm'.tr(args: [action.label]),
            heightFactor: 0.34,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    action.isDestructive
                        ? 'packageRemoveConfirm'.tr(args: [object])
                        : 'packageActionGenericConfirm'.tr(
                            args: [action.label, object],
                          ),
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext, false),
                        child: Text('commonCancel'.tr()),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => Navigator.pop(sheetContext, true),
                        child: Text(action.label),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        )) ==
        true;
  }

  String _actionDescription(PackageAction action, String? packageName) =>
      '${_manager!.label} ${action.label.toLowerCase()}${packageName == null ? '' : ' $packageName'}';

  @override
  Widget build(BuildContext context) {
    if (!widget.connected) {
      return _PackageEmpty(
        icon: Symbols.link_off,
        message: widget.connectionError ?? 'packageConnectToManage'.tr(),
        actionLabel: 'commonConnect'.tr(),
        onAction: widget.onConnect,
      );
    }
    return _status.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _PackageEmpty(
        icon: Symbols.error_outline,
        message: 'packageInspectError'.tr(args: ['$error']),
        actionLabel: 'systemdTryAgain'.tr(),
        onAction: _load,
      ),
      data: (status) => status.available.isEmpty
          ? _PackageEmpty(
              icon: Symbols.inventory_2,
              message: 'packageNoManagerFound'.tr(),
              actionLabel: 'commonRefresh'.tr(),
              onAction: _load,
            )
          : _content(context, status),
    );
  }

  Widget _content(BuildContext context, PackageManagerStatus status) {
    final scheme = Theme.of(context).colorScheme;
    final manager = _manager!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(
            children: [
              const Icon(Symbols.inventory_2, size: 20),
              const SizedBox(width: 8),
              DropdownButton<PackageManager>(
                value: manager,
                underline: const SizedBox.shrink(),
                items: [
                  for (final item in status.available)
                    DropdownMenuItem(value: item, child: Text(item.label)),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        setState(() {
                          _manager = value;
                          _results = const AsyncValue.data([]);
                        });
                        _load();
                      },
              ),
              const Spacer(),
              IconButton(
                tooltip: 'packageRefreshTooltip'.tr(),
                padding: const EdgeInsets.all(4),
                visualDensity: VisualDensity.compact,
                onPressed: _busy ? null : _load,
                icon: const Icon(Symbols.refresh),
              ),
              if (status.outdatedPackages.isNotEmpty)
                IconButton(
                  tooltip: 'packageUpgradeTooltip'.tr(),
                  padding: const EdgeInsets.all(4),
                  visualDensity: VisualDensity.compact,
                  onPressed: _busy ? null : () => _run(PackageAction.upgrade),
                  icon: const Icon(Symbols.system_update),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              _PackageMetric(
                value: status.installedPackageCount?.toString() ?? '—',
                label: 'packageInstalled'.tr(),
              ),
              const SizedBox(width: 24),
              _PackageMetric(
                value: status.outdatedPackages.length.toString(),
                label: 'packageUpgradesAvailable'.tr(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    labelText: 'packageFindPackage'.tr(),
                    hintText: 'packageFindPackageHint'.tr(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'packageSearchTooltip'.tr(),
                padding: const EdgeInsets.all(4),
                visualDensity: VisualDensity.compact,
                onPressed: _busy ? null : _search,
                icon: const Icon(Symbols.search),
              ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: _body(status)),
      ],
    );
  }

  Widget _body(PackageManagerStatus status) {
    if (_results.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_results.hasError) {
      return _PackageEmpty(
        icon: Symbols.error_outline,
        message: 'packageSearchError'.tr(args: ['${_results.error}']),
        actionLabel: 'systemdTryAgain'.tr(),
        onAction: _search,
      );
    }
    final results = _results.value ?? const <PackageSearchResult>[];
    if (results.isNotEmpty) return _packageList(results);
    if (_searchController.text.trim().isNotEmpty) {
      return _PackageEmpty(
        icon: Symbols.search_off,
        message: 'packageNoMatch'.tr(),
      );
    }
    if (status.outdatedPackages.isNotEmpty) {
      return _updatesList(status.outdatedPackages);
    }
    return _PackageEmpty(
      icon: Symbols.check_circle,
      message: 'packageNoUpdates'.tr(),
    );
  }

  Widget _updatesList(List<String> packages) => ListView.separated(
    itemCount: packages.length,
    separatorBuilder: (_, _) => const Divider(height: 1),
    itemBuilder: (_, index) => ListTile(
      dense: true,
      leading: const Icon(Symbols.system_update),
      title: Text(packages[index]),
      subtitle: Text('packageUpdateAvailable'.tr()),
    ),
  );

  Widget _packageList(List<PackageSearchResult> packages) => ListView.separated(
    itemCount: packages.length,
    separatorBuilder: (_, _) => const Divider(height: 1),
    itemBuilder: (_, index) {
      final item = packages[index];
      final action = item.installed
          ? PackageAction.remove
          : PackageAction.install;
      return ContextMenuWidget(
        menuProvider: (_) => Menu(
          children: [
            MenuAction(
              title: action.label,
              image: MenuImage.icon(
                item.installed ? Symbols.delete_outline : Symbols.download,
              ),
              attributes: MenuActionAttributes(disabled: _busy),
              callback: () => _run(action, packageName: item.name),
            ),
          ],
        ),
        child: ListTile(
          dense: true,
          title: Text(item.name),
          subtitle: item.description == null
              ? null
              : Text(
                  item.description!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          trailing: IconButton(
            tooltip: action.label,
            onPressed: _busy
                ? null
                : () => _run(action, packageName: item.name),
            icon: Icon(
              item.installed ? Symbols.delete_outline : Symbols.download,
            ),
          ),
        ),
      );
    },
  );
}

class _PackageMetric extends StatelessWidget {
  const _PackageMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: theme.textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _PackageEmpty extends StatelessWidget {
  const _PackageEmpty({
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
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 28,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (actionLabel != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}
