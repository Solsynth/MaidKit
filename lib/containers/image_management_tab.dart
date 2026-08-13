import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:super_context_menu/super_context_menu.dart';

import 'package:easy_localization/easy_localization.dart';
import 'container_image_list_tile.dart';
import 'container_models.dart';
import 'container_runtime_install.dart';
import 'image_actions.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/shared/presentation/app_context_menu.dart';
import 'package:maid_kit/shared/presentation/maidkit_alert.dart';
import 'package:maid_kit/theme.dart';

/// Image management surface for a single server, scoped by runtime and
/// user/root environment (same layout pattern as [ContainerManagementTab]).
class ImageManagementTab extends ConsumerStatefulWidget {
  const ImageManagementTab({
    super.key,
    required this.server,
    required this.connected,
    required this.connectionError,
    required this.onConnect,
    required this.refreshInterval,
  });

  final Server server;
  final bool connected;
  final String? connectionError;
  final Future<void> Function() onConnect;
  final Duration refreshInterval;

  @override
  ConsumerState<ImageManagementTab> createState() => _ImageManagementTabState();
}

class _ImageManagementTabState extends ConsumerState<ImageManagementTab> {
  AsyncValue<List<ImageEnvironment>> _environments = const AsyncValue.data([]);
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
  void didUpdateWidget(ImageManagementTab oldWidget) {
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
          .listImages(
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

  Future<String?> _storedSudoPassword() async {
    final credential = await ref
        .read(serverRepositoryProvider)
        .credentialFor(widget.server);
    return credential.type == CredentialType.password
        ? credential.password
        : null;
  }

  Future<void> _runAction(
    ImageEnvironment environment,
    ServerContainerImage image,
    ImageAction action,
  ) async {
    if (action == ImageAction.remove) {
      final approved = await showMaidKitConfirmAlert(
        'imagesRemoveConfirm'.tr(),
        'imagesRemoveTitle'.tr(args: [image.reference]),
        isDanger: true,
      );
      if (!approved || !mounted) return;
    }
    try {
      await runImageRemoveWithTerminal(
        ref: ref,
        serverId: widget.server.id,
        serverName: widget.server.name,
        runtime: environment.runtime,
        scope: environment.scope,
        imageId: image.id,
        imageLabel: image.reference,
        sudoPassword: await _storedSudoPassword(),
      );
      if (!mounted) return;
      showStyledSnackBar(
        title: 'imagesRemoveSuccess'.tr(),
        message: image.reference,
        icon: Symbols.check_circle,
        accentColor: Theme.of(context).colorScheme.primary,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      showStyledSnackBar(
        title: 'imagesRemoveError'.tr(),
        message: error.toString(),
        icon: Symbols.error,
        accentColor: Theme.of(context).colorScheme.error,
      );
    }
  }

  Future<void> _prune(ImageEnvironment environment) async {
    final unusedTagged = environment.images
        .where((image) => image.unused && !image.isDangling)
        .length;
    final dangling = environment.images
        .where((image) => image.isDangling)
        .length;
    final result = await showModalBottomSheet<_PruneSheetResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (_) => _PruneImagesSheet(
        runtime: environment.runtime,
        scope: environment.scope,
        serverName: widget.server.name,
        danglingCount: dangling,
        unusedTaggedCount: unusedTagged,
      ),
    );
    if (result == null || !mounted) return;
    try {
      await runImagePruneWithTerminal(
        ref: ref,
        serverId: widget.server.id,
        serverName: widget.server.name,
        runtime: environment.runtime,
        scope: environment.scope,
        force: result.force,
        allUnused: result.allUnused,
        sudoPassword: await _storedSudoPassword(),
      );
      if (!mounted) return;
      showStyledSnackBar(
        title: 'imagesPruneFinished'.tr(),
        message: result.allUnused
            ? 'imagesPruneUnused'.tr(args: [environment.runtime.name])
            : 'imagesPruneDangling'.tr(args: [environment.runtime.name]),
        icon: Symbols.check_circle,
        accentColor: Theme.of(context).colorScheme.primary,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      showStyledSnackBar(
        title: 'imagesPruneError'.tr(),
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
        title: 'imagesRuntimeInstalled'.tr(args: [runtime.name]),
        message: 'imagesRuntimeRefreshing'.tr(),
        icon: Symbols.check_circle,
        accentColor: Theme.of(context).colorScheme.primary,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      showStyledSnackBar(
        title: 'imagesRuntimeInstallError'.tr(args: [runtime.name]),
        message: error.toString(),
        icon: Symbols.error,
        accentColor: Theme.of(context).colorScheme.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.connected) {
      return _ImageEmptyPanel(
        icon: Symbols.link_off,
        message: widget.connectionError ?? 'imagesConnectToManage'.tr(),
        actionLabel: 'commonConnect'.tr(),
        onAction: widget.onConnect,
        filledAction: true,
        actionIcon: Symbols.link,
      );
    }
    return _environments.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ImageEmptyPanel(
        icon: Symbols.error_outline,
        message: 'imagesLoadError'.tr(args: [error.toString()]),
        actionLabel: 'imagesTryAgain'.tr(),
        onAction: _load,
      ),
      data: (environments) => _ImageEnvironments(
        environments: environments,
        onRefresh: _load,
        onAction: _runAction,
        onPrune: _prune,
        onInstallRuntime: _installRuntime,
      ),
    );
  }
}

class _PruneSheetResult {
  const _PruneSheetResult({required this.force, required this.allUnused});
  final bool force;
  final bool allUnused;
}

/// Bottom sheet to configure and run image prune (same sheet pattern as
/// standalone container run / compose project sheets).
class _PruneImagesSheet extends StatefulWidget {
  const _PruneImagesSheet({
    required this.runtime,
    required this.scope,
    required this.serverName,
    required this.danglingCount,
    required this.unusedTaggedCount,
  });

  final ContainerRuntime runtime;
  final ContainerScope scope;
  final String serverName;
  final int danglingCount;
  final int unusedTaggedCount;

  @override
  State<_PruneImagesSheet> createState() => _PruneImagesSheetState();
}

class _PruneImagesSheetState extends State<_PruneImagesSheet> {
  // Non-interactive SSH sessions hang without -f when the CLI prompts.
  var _force = true;
  // Default to -a when tagged unused images exist — plain prune only clears
  // dangling layers and leaves "Unused" labels in the list.
  late var _allUnused = widget.unusedTaggedCount > 0;

  String get _runtimeName => widget.runtime.name;

  String get _scopeLabel => widget.scope == ContainerScope.root
      ? 'commonRoot'.tr()
      : 'commonUser'.tr();

  String get _commandPreview {
    final flags = [if (_allUnused) '-a', if (_force) '-f'].join(' ');
    return '$_runtimeName image prune${flags.isEmpty ? '' : ' $flags'}';
  }

  void _submit() {
    Navigator.pop(
      context,
      _PruneSheetResult(force: _force, allUnused: _allUnused),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SheetScaffold(
      titleText: 'imagesPruneTitle'.tr(args: [_runtimeName]),
      heightFactor: 0.62,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            'imagesPruneInfo'.tr(args: [widget.serverName, _scopeLabel]),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _CountChip(
                label: 'imagesPruneDanglingLabel'.tr(),
                count: widget.danglingCount,
              ),
              const SizedBox(width: 8),
              _CountChip(
                label: 'imagesPruneUnusedLabel'.tr(),
                count: widget.unusedTaggedCount,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _allUnused
                ? 'imagesPruneAllInfo'.tr()
                : 'imagesPruneDanglingInfo'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('imagesPruneAllUnused'.tr()),
            subtitle: Text('imagesPruneAllUnusedHint'.tr()),
            value: _allUnused,
            onChanged: (value) => setState(() => _allUnused = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('imagesPruneForce'.tr()),
            subtitle: Text('imagesPruneForceHint'.tr()),
            value: _force,
            onChanged: (value) => setState(() => _force = value),
          ),
          const SizedBox(height: 16),
          Text(
            'imagesPruneCommandPreview'.tr(),
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
              color: scheme.surfaceContainerLowest,
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                _commandPreview,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: MaidKitFonts.mono,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('commonCancel').tr(),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Symbols.play_arrow, size: 18),
                label: const Text('imagesPruneRun').tr(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        '$count $label',
        style: theme.textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ImageEnvironments extends StatelessWidget {
  const _ImageEnvironments({
    required this.environments,
    required this.onRefresh,
    required this.onAction,
    required this.onPrune,
    required this.onInstallRuntime,
  });

  final List<ImageEnvironment> environments;
  final Future<void> Function() onRefresh;
  final Future<void> Function(
    ImageEnvironment,
    ServerContainerImage,
    ImageAction,
  )
  onAction;
  final Future<void> Function(ImageEnvironment environment) onPrune;
  final Future<void> Function() onInstallRuntime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (environments.isEmpty) {
      return _ImageEmptyPanel(
        icon: Symbols.image,
        message: 'containersNotInstalled'.tr(),
        actionLabel: 'containersInstallRuntimeShort'.tr(),
        onAction: onInstallRuntime,
        filledAction: true,
        actionIcon: Symbols.download,
      );
    }

    final totalImages = environments
        .where((env) => env.isAvailable)
        .fold<int>(0, (sum, env) => sum + env.images.length);
    final totalUnused = environments
        .where((env) => env.isAvailable)
        .fold<int>(0, (sum, env) => sum + env.unusedCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  [
                    totalImages == 1
                        ? 'imagesCountOne'.tr()
                        : 'imagesCountOther'.tr(args: [totalImages.toString()]),
                    if (totalUnused > 0)
                      totalUnused == 1
                          ? 'imagesUnusedOne'.tr()
                          : 'imagesUnusedOther'.tr(
                              args: [totalUnused.toString()],
                            ),
                  ].join(' · '),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'imagesRefreshTooltip'.tr(),
                visualDensity: VisualDensity.compact,
                onPressed: onRefresh,
                icon: const Icon(Symbols.refresh),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            itemCount: environments.length,
            itemBuilder: (context, index) => Padding(
              padding: EdgeInsets.only(
                bottom: index == environments.length - 1 ? 0 : 16,
              ),
              child: _ImageEnvironmentSection(
                environment: environments[index],
                onAction: onAction,
                onPrune: () => onPrune(environments[index]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ImageEnvironmentSection extends StatelessWidget {
  const _ImageEnvironmentSection({
    required this.environment,
    required this.onAction,
    required this.onPrune,
  });

  final ImageEnvironment environment;
  final Future<void> Function(
    ImageEnvironment,
    ServerContainerImage,
    ImageAction,
  )
  onAction;
  final Future<void> Function() onPrune;

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

  Widget _imageTile({required ServerContainerImage image}) {
    Menu menu() => Menu(
      children: [
        MenuAction(
          title: 'commonRemove'.tr(),
          image: MenuImage.icon(Symbols.delete),
          attributes: const MenuActionAttributes(destructive: true),
          callback: () => onAction(environment, image, ImageAction.remove),
        ),
      ],
    );
    return AppContextMenuRegion(
      menuBuilder: menu,
      child: ContainerImageListTile(
        image: image,
        contentPadding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        trailing: PopupMenuButton<ImageAction>(
          tooltip: 'imagesActionsTooltip'.tr(),
          onSelected: (action) => onAction(environment, image, action),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: ImageAction.remove,
              child: Row(
                children: [
                  const Icon(Symbols.delete, size: 20),
                  const SizedBox(width: 12),
                  Text('commonRemove'.tr()),
                ],
              ),
            ),
          ],
          icon: const Icon(Symbols.more_vert),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unused = environment.unusedCount;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
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
                    label: environment.images.isEmpty
                        ? 'imagesEmptyMeta'.tr()
                        : 'imagesCountOther'.tr(
                            args: [environment.images.length.toString()],
                          ),
                  ),
                  if (unused > 0) ...[
                    const SizedBox(width: 8),
                    _MetaChip(
                      label: 'imagesUnusedCount'.tr(args: [unused.toString()]),
                    ),
                  ],
                ],
                if (environment.isAvailable)
                  IconButton(
                    tooltip: 'imagesPruneDanglingLabel'.tr(),
                    visualDensity: VisualDensity.compact,
                    onPressed: onPrune,
                    icon: const Icon(Symbols.cleaning_services, size: 20),
                  ),
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
                      environment.error ?? 'imagesUnavailable'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (environment.images.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(
                'containersNoContainersEnv'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else ...[
            Divider(height: 1, color: scheme.outlineVariant),
            for (var i = 0; i < environment.images.length; i++) ...[
              _imageTile(image: environment.images[i]),
              if (i != environment.images.length - 1)
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

class _ImageEmptyPanel extends StatelessWidget {
  const _ImageEmptyPanel({
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
