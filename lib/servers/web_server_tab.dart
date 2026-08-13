import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/highlight_core.dart' show Mode;
import 'package:highlight/languages/bash.dart' as bash;
import 'package:highlight/languages/nginx.dart' as nginx;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:super_context_menu/super_context_menu.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/containers/project_repository.dart';
import 'package:maid_kit/containers/deployment_project_models.dart';
import 'package:maid_kit/shared/presentation/deploy_terminal.dart';
import 'package:maid_kit/shared/presentation/maidkit_alert.dart';
import 'package:maid_kit/theme.dart';
import 'server_models.dart';
import 'server_providers.dart';
import 'web_server_models.dart';

/// Host web server management (nginx / caddy via adapters).
class WebServerTab extends ConsumerStatefulWidget {
  const WebServerTab({
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
  ConsumerState<WebServerTab> createState() => _WebServerTabState();
}

class _WebServerTabState extends ConsumerState<WebServerTab> {
  AsyncValue<List<WebServerDetection>> _detections = const AsyncValue.loading();
  AsyncValue<WebServerStatus>? _status;
  String? _adapterId;
  var _busy = false;
  WebServerTaskResult? _lastResult;

  bool get _isRoot => widget.server.username == 'root';

  @override
  void initState() {
    super.initState();
    if (widget.connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadDetections());
    }
  }

  @override
  void didUpdateWidget(WebServerTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connected &&
        (!oldWidget.connected || oldWidget.server.id != widget.server.id)) {
      _lastResult = null;
      _loadDetections();
    }
  }

  Future<String?> _sudoPassword() async {
    final credential = await ref
        .read(serverRepositoryProvider)
        .credentialFor(widget.server);
    return credential.type == CredentialType.password
        ? credential.password
        : null;
  }

  Future<void> _loadDetections() async {
    if (!mounted || !widget.connected) return;
    setState(() {
      _detections = const AsyncValue.loading();
      _status = null;
    });
    try {
      final detections = await ref
          .read(connectionManagerProvider)
          .detectWebServers(
            widget.server.id,
            sshUserIsRoot: _isRoot,
            sudoPassword: await _sudoPassword(),
          );
      if (!mounted) return;
      final installed = detections.where((d) => d.installed).toList();
      final preferred = installed.any((d) => d.adapterId == _adapterId)
          ? _adapterId
          : installed.isNotEmpty
          ? installed.first.adapterId
          : null;
      setState(() {
        _detections = AsyncValue.data(detections);
        _adapterId = preferred;
      });
      if (preferred != null) await _loadStatus(preferred);
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() => _detections = AsyncValue.error(error, stackTrace));
      }
    }
  }

  Future<void> _loadStatus(String adapterId) async {
    if (!mounted || !widget.connected) return;
    setState(() => _status = const AsyncValue.loading());
    try {
      final status = await ref
          .read(connectionManagerProvider)
          .getWebServerStatus(
            widget.server.id,
            adapterId: adapterId,
            sshUserIsRoot: _isRoot,
            sudoPassword: await _sudoPassword(),
          );
      if (mounted) setState(() => _status = AsyncValue.data(status));
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() => _status = AsyncValue.error(error, stackTrace));
      }
    }
  }

  Future<void> _selectAdapter(String adapterId) async {
    if (adapterId == _adapterId) return;
    setState(() {
      _adapterId = adapterId;
      _lastResult = null;
    });
    await _loadStatus(adapterId);
  }

  Future<void> _runTask({
    required String title,
    required String command,
    required Future<WebServerTaskResult> Function(
      void Function(String chunk) onOutput,
    )
    run,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    WebServerTaskResult? result;
    try {
      await runWithDeployTerminal(
        ref: ref,
        title: title,
        subtitle: widget.server.name,
        command: command,
        run: (onOutput) async {
          result = await run(onOutput);
          if (result != null && !result!.success) {
            throw StateError(result!.summary);
          }
        },
      );
    } catch (_) {
      // Failure is already in the deploy terminal + result banner.
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          if (result != null) _lastResult = result;
        });
        final id = _adapterId;
        if (id != null) await _loadStatus(id);
      }
    }
  }

  Future<bool> _confirm(WebServerAction action, String label) async {
    if (!action.isDestructive &&
        action != WebServerAction.restart &&
        action != WebServerAction.reload &&
        action != WebServerAction.enable &&
        action != WebServerAction.disable) {
      return true;
    }
    return showMaidKitConfirmAlert(
      'webServerActionConfirmBody'.tr(args: [action.trLabel.tr(), label]),
      'webServerActionConfirm'.tr(args: [action.trLabel.tr()]),
      isDanger: action.isDestructive,
    );
  }

  Future<void> _onAction(WebServerAction action) async {
    final status = _status?.asData?.value;
    final adapterId = _adapterId;
    if (status == null || adapterId == null || _busy) return;
    if (!await _confirm(action, status.label) || !mounted) return;
    final sudo = await _sudoPassword();
    await _runTask(
      title: '${action.englishLabel} ${status.label}',
      command:
          'systemctl ${action.systemctlVerb} ${status.serviceUnit ?? adapterId}',
      run: (onOutput) => ref
          .read(connectionManagerProvider)
          .runWebServerAction(
            widget.server.id,
            adapterId: adapterId,
            action: action,
            sshUserIsRoot: _isRoot,
            sudoPassword: sudo,
            onOutput: onOutput,
          ),
    );
  }

  Future<void> _validate() async {
    final adapterId = _adapterId;
    final status = _status?.asData?.value;
    if (adapterId == null || status == null || _busy) return;
    final sudo = await _sudoPassword();
    await _runTask(
      title: 'webServerValidateTitle'.tr(args: [status.label]),
      command: status.label == 'Nginx' ? 'nginx -t' : 'caddy validate',
      run: (onOutput) => ref
          .read(connectionManagerProvider)
          .validateWebServerConfig(
            widget.server.id,
            adapterId: adapterId,
            sshUserIsRoot: _isRoot,
            sudoPassword: sudo,
            onOutput: onOutput,
          ),
    );
  }

  Future<void> _editConfig({String? siteId, String? title}) async {
    final adapterId = _adapterId;
    final status = _status?.asData?.value;
    if (adapterId == null || status == null || _busy) return;

    final path = siteId ?? status.configPath;
    final name =
        title ??
        (path == null
            ? status.label
            : path
                  .split('/')
                  .lastWhere((s) => s.isNotEmpty, orElse: () => path));
    final location = path ?? status.label;

    await showAttentionModal(
      id: 'web-server-editor-${widget.server.id}-$adapterId-${path ?? 'main'}',
      replaceIfExists: true,
      barrierDismissible: false,
      builder: (context, dismiss) => _WebServerConfigEditor(
        name: name,
        location: location,
        load: () async {
          return ref
              .read(connectionManagerProvider)
              .readWebServerConfig(
                widget.server.id,
                adapterId: adapterId,
                siteId: siteId,
                sshUserIsRoot: _isRoot,
                sudoPassword: await _sudoPassword(),
              );
        },
        apply: (text, mode) async {
          WebServerTaskResult? result;
          final sudo = await _sudoPassword();
          await runWithDeployTerminal(
            ref: ref,
            title: switch (mode) {
              WebServerApplyMode.saveOnly => 'webServerTaskSave'.tr(
                args: [status.label],
              ),
              WebServerApplyMode.saveAndValidate => 'webServerTaskSaveCheck'.tr(
                args: [status.label],
              ),
              WebServerApplyMode.saveValidateReload =>
                'webServerTaskSaveCheckReload'.tr(args: [status.label]),
            },
            subtitle: location,
            command: switch (mode) {
              WebServerApplyMode.saveOnly => 'write $location',
              WebServerApplyMode.saveAndValidate =>
                'write + validate $location',
              WebServerApplyMode.saveValidateReload =>
                'write + validate + reload $location',
            },
            run: (onOutput) async {
              result = await ref
                  .read(connectionManagerProvider)
                  .applyWebServerConfig(
                    widget.server.id,
                    adapterId: adapterId,
                    content: text,
                    mode: mode,
                    siteId: siteId,
                    sshUserIsRoot: _isRoot,
                    sudoPassword: sudo,
                    onOutput: onOutput,
                  );
              if (result != null && !result!.success) {
                throw StateError(result!.summary);
              }
            },
          );
          if (mounted && result != null) {
            setState(() => _lastResult = result);
            await _loadStatus(adapterId);
          }
          return result ??
              WebServerTaskResult(
                success: false,
                title: 'webServerTaskSave'.tr(args: [status.label]),
                summary: 'webServerActionFailed'.tr(),
              );
        },
        dismiss: dismiss,
      ),
    );
  }

  Future<void> _showLogs() async {
    final adapterId = _adapterId;
    final status = _status?.asData?.value;
    if (adapterId == null || status == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (sheetContext) => _TextSheet(
        title: 'webServerLogsTitle'.tr(args: [status.label]),
        load: () async {
          return ref
              .read(connectionManagerProvider)
              .getWebServerLogs(
                widget.server.id,
                adapterId: adapterId,
                sshUserIsRoot: _isRoot,
                sudoPassword: await _sudoPassword(),
              );
        },
      ),
    );
  }

  Future<void> _addToDeploymentProject(WebServerStatus status) async {
    final projects =
        ref.read(deploymentProjectsProvider).asData?.value ??
        const <DeploymentProject>[];
    if (projects.isEmpty) {
      if (mounted) {
        showSnackBar('Create a deployment project before adding resources.');
      }
      return;
    }
    final project = await showDialog<DeploymentProject>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add web server to deployment project'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final item in projects)
                ListTile(
                  leading: const Icon(Symbols.deployed_code),
                  title: Text(item.name),
                  subtitle: item.description == null
                      ? null
                      : Text(item.description!),
                  onTap: () => Navigator.pop(context, item),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('commonCancel'.tr()),
          ),
        ],
      ),
    );
    if (project == null) return;
    await ref
        .read(projectRepositoryProvider)
        .addResource(
          projectId: project.id,
          kind: DeploymentResourceKind.webServer.name,
          name: status.label,
          serverId: widget.server.id,
          configuration: {
            'adapter_id': status.adapterId,
            'service_unit': status.serviceUnit,
            'config_path': status.configPath,
            'sites': [
              for (final site in status.sites)
                {
                  'name': site.name,
                  'path': site.path,
                  'server_names': site.serverNames,
                },
            ],
          },
        );
    if (mounted) {
      showSnackBar('${status.label} added to ${project.name}.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.connected) {
      return _WebEmpty(
        icon: Symbols.link_off,
        message: widget.connectionError ?? 'webServerConnectToManage'.tr(),
        actionLabel: 'commonConnect'.tr(),
        onAction: widget.onConnect,
        filled: true,
      );
    }

    return _detections.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _WebEmpty(
        icon: Symbols.error_outline,
        message: 'webServerLoadError'.tr(args: ['$error']),
        actionLabel: 'commonRetry'.tr(),
        onAction: _loadDetections,
      ),
      data: (detections) {
        final installed = detections.where((d) => d.installed).toList();
        if (installed.isEmpty) {
          return _WebEmpty(
            icon: Symbols.language,
            message: 'webServerNoneFound'.tr(),
            actionLabel: 'commonRefresh'.tr(),
            onAction: _loadDetections,
          );
        }
        return _content(context, installed);
      },
    );
  }

  Widget _content(BuildContext context, List<WebServerDetection> installed) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final adapterId = _adapterId ?? installed.first.adapterId;
    final statusAsync = _status;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Symbols.language, size: 20, color: scheme.primary),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    isDense: true,
                    value: adapterId,
                    underline: const SizedBox.shrink(),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onSurface,
                    ),
                    items: [
                      for (final item in installed)
                        DropdownMenuItem(
                          value: item.adapterId,
                          child: Text(
                            item.version == null
                                ? item.label
                                : '${item.label} · ${item.version}',
                          ),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value != null) _selectAdapter(value);
                          },
                  ),
                  IconButton(
                    tooltip: 'Add to deployment project',
                    visualDensity: VisualDensity.compact,
                    onPressed: _busy || statusAsync?.asData?.value == null
                        ? null
                        : () => _addToDeploymentProject(
                            statusAsync!.asData!.value,
                          ),
                    icon: const Icon(Symbols.add_link),
                  ),
                  const Spacer(),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  IconButton(
                    tooltip: 'commonRefresh'.tr(),
                    visualDensity: VisualDensity.compact,
                    onPressed: _busy ? null : _loadDetections,
                    icon: const Icon(Symbols.refresh),
                  ),
                ],
              ),
              if (_lastResult != null) ...[
                const SizedBox(height: 8),
                _LastTaskBanner(
                  result: _lastResult!,
                  onDismiss: () => setState(() => _lastResult = null),
                ),
              ],
              if (statusAsync != null)
                statusAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                  error: (error, _) => Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'webServerLoadError'.tr(args: ['$error']),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                  ),
                  data: (status) => _StatusHeader(
                    status: status,
                    busy: _busy,
                    onAction: _onAction,
                    onValidate: _validate,
                    onEditConfig: () => _editConfig(),
                    onLogs: _showLogs,
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(child: _sitesBody(context, statusAsync)),
      ],
    );
  }

  Widget _sitesBody(
    BuildContext context,
    AsyncValue<WebServerStatus>? statusAsync,
  ) {
    if (statusAsync == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return statusAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _WebEmpty(
        icon: Symbols.error_outline,
        message: 'webServerLoadError'.tr(args: ['$error']),
        actionLabel: 'commonRetry'.tr(),
        onAction: () {
          final id = _adapterId;
          if (id != null) return _loadStatus(id);
          return _loadDetections();
        },
      ),
      data: (status) {
        if (status.sites.isEmpty) {
          return _WebEmpty(
            icon: Symbols.language,
            message: 'webServerNoSites'.tr(args: [status.label]),
            actionLabel: 'webServerEditConfig'.tr(),
            onAction: () => _editConfig(),
          );
        }
        return ListView.separated(
          itemCount: status.sites.length,
          separatorBuilder: (_, _) => Divider(
            height: 1,
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          itemBuilder: (context, index) {
            final site = status.sites[index];
            return _SiteTile(
              site: site,
              busy: _busy,
              onEdit: () => _editConfig(siteId: site.path, title: site.name),
            );
          },
        );
      },
    );
  }
}

class _LastTaskBanner extends StatelessWidget {
  const _LastTaskBanner({required this.result, required this.onDismiss});

  final WebServerTaskResult result;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ok = result.success;
    final bg = ok
        ? scheme.secondaryContainer.withValues(alpha: 0.65)
        : scheme.errorContainer.withValues(alpha: 0.65);
    final fg = ok ? scheme.onSecondaryContainer : scheme.onErrorContainer;
    final icon = ok ? Symbols.check_circle : Symbols.error;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: ok
              ? scheme.outlineVariant.withValues(alpha: 0.5)
              : scheme.error.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ok
                        ? 'webServerResultSuccess'.tr()
                        : 'webServerResultFailed'.tr(),
                    style: theme.textTheme.labelLarge?.copyWith(color: fg),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    result.summary,
                    style: theme.textTheme.bodySmall?.copyWith(color: fg),
                  ),
                  if (result.steps.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final step in result.steps)
                          _StepChip(step: step, okTheme: ok),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'commonClose'.tr(),
              visualDensity: VisualDensity.compact,
              onPressed: onDismiss,
              icon: Icon(Symbols.close, size: 18, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({required this.step, required this.okTheme});

  final WebServerTaskStep step;
  final bool okTheme;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = step.success
        ? (okTheme ? scheme.onSecondaryContainer : scheme.primary)
        : scheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            step.success ? Symbols.check : Symbols.close,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            step.label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({
    required this.status,
    required this.busy,
    required this.onAction,
    required this.onValidate,
    required this.onEditConfig,
    required this.onLogs,
  });

  final WebServerStatus status;
  final bool busy;
  final void Function(WebServerAction action) onAction;
  final VoidCallback onValidate;
  final VoidCallback onEditConfig;
  final VoidCallback onLogs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            _StateChip(running: status.running),
            const SizedBox(width: 8),
            Text(
              status.enabled
                  ? 'webServerEnabledOnBoot'.tr()
                  : 'webServerDisabledOnBoot'.tr(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (status.configValid != null) ...[
              const SizedBox(width: 8),
              Icon(
                status.configValid! ? Symbols.check_circle : Symbols.error,
                size: 16,
                color: status.configValid! ? scheme.primary : scheme.error,
              ),
              const SizedBox(width: 4),
              Text(
                status.configValid!
                    ? 'webServerConfigOk'.tr()
                    : 'webServerConfigInvalid'.tr(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: status.configValid! ? scheme.primary : scheme.error,
                ),
              ),
            ],
          ],
        ),
        if (status.configPath != null) ...[
          const SizedBox(height: 4),
          Text(
            status.configPath!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontFamily: MaidKitFonts.mono,
              fontSize: 11,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (!status.running)
              _ActionChip(
                icon: Symbols.play_arrow,
                label: 'webServerStart'.tr(),
                onPressed: busy ? null : () => onAction(WebServerAction.start),
              ),
            if (status.running) ...[
              _ActionChip(
                icon: Symbols.stop,
                label: 'webServerStop'.tr(),
                onPressed: busy ? null : () => onAction(WebServerAction.stop),
              ),
              _ActionChip(
                icon: Symbols.restart_alt,
                label: 'webServerRestart'.tr(),
                onPressed: busy
                    ? null
                    : () => onAction(WebServerAction.restart),
              ),
              _ActionChip(
                icon: Symbols.sync,
                label: 'webServerReload'.tr(),
                onPressed: busy ? null : () => onAction(WebServerAction.reload),
              ),
            ],
            if (!status.enabled)
              _ActionChip(
                icon: Symbols.toggle_on,
                label: 'webServerEnable'.tr(),
                onPressed: busy ? null : () => onAction(WebServerAction.enable),
              )
            else
              _ActionChip(
                icon: Symbols.toggle_off,
                label: 'webServerDisable'.tr(),
                onPressed: busy
                    ? null
                    : () => onAction(WebServerAction.disable),
              ),
            _ActionChip(
              icon: Symbols.rule,
              label: 'webServerValidate'.tr(),
              onPressed: busy ? null : onValidate,
            ),
            _ActionChip(
              icon: Symbols.edit,
              label: 'webServerEditConfig'.tr(),
              onPressed: busy ? null : onEditConfig,
            ),
            _ActionChip(
              icon: Symbols.terminal,
              label: 'webServerLogs'.tr(),
              onPressed: busy ? null : onLogs,
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.running});

  final bool running;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: running
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        running ? 'webServerRunning'.tr() : 'webServerStoppedLabel'.tr(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: running
              ? scheme.onSecondaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SiteTile extends StatelessWidget {
  const _SiteTile({
    required this.site,
    required this.busy,
    required this.onEdit,
  });

  final WebServerSite site;
  final bool busy;
  final VoidCallback onEdit;

  Menu _menu() => Menu(
    children: [
      MenuAction(
        title: 'webServerEditConfig'.tr(),
        image: MenuImage.icon(Symbols.edit),
        callback: onEdit,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subtitle = <String>[
      if (site.listen.isNotEmpty) site.listen.join(', '),
      site.path,
    ].join(' · ');

    return ContextMenuWidget(
      menuProvider: (_) => _menu(),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(
          site.kind == WebServerSiteKind.main
              ? Symbols.settings
              : Symbols.public,
          color: site.enabled ? scheme.primary : scheme.onSurfaceVariant,
        ),
        title: Text(
          site.displayNames,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontFamily: MaidKitFonts.mono,
            fontSize: 11,
          ),
        ),
        trailing: IconButton(
          tooltip: 'webServerEditConfig'.tr(),
          onPressed: busy ? null : onEdit,
          icon: const Icon(Symbols.edit, size: 20),
        ),
        onTap: busy ? null : onEdit,
      ),
    );
  }
}

/// Config editor modeled on the file manager editor, with save / check / reload.
class _WebServerConfigEditor extends StatefulWidget {
  const _WebServerConfigEditor({
    required this.name,
    required this.location,
    required this.load,
    required this.apply,
    required this.dismiss,
  });

  final String name;
  final String location;
  final Future<String> Function() load;
  final Future<WebServerTaskResult> Function(
    String text,
    WebServerApplyMode mode,
  )
  apply;
  final VoidCallback dismiss;

  @override
  State<_WebServerConfigEditor> createState() => _WebServerConfigEditorState();
}

class _WebServerConfigEditorState extends State<_WebServerConfigEditor> {
  late final CodeController _controller;
  var _loading = true;
  var _saving = false;
  String _savedText = '';
  WebServerTaskResult? _lastApply;

  bool get _isDirty => !_loading && _controller.text != _savedText;

  @override
  void initState() {
    super.initState();
    _controller = CodeController(language: _languageForConfigName(widget.name));
    unawaited(_load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final text = await widget.load();
      if (!mounted) return;
      setState(() {
        _controller.text = text;
        _savedText = text;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      showMaidKitErrorAlert(
        error,
        title: 'webServerOpenFailed'.tr(args: [widget.name]),
      );
      widget.dismiss();
    }
  }

  Future<void> _apply(WebServerApplyMode mode) async {
    if (_loading || _saving) return;
    if (mode != WebServerApplyMode.saveOnly && !_isDirty) {
      // Allow validate+reload on unchanged file when user chooses full apply
      // only if dirty for save-only; for check/reload allow even if clean.
    }
    if (mode == WebServerApplyMode.saveOnly && !_isDirty) return;

    setState(() => _saving = true);
    try {
      final result = await widget.apply(_controller.text, mode);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _lastApply = result;
        if (result.success &&
            (mode == WebServerApplyMode.saveOnly ||
                mode == WebServerApplyMode.saveAndValidate ||
                mode == WebServerApplyMode.saveValidateReload)) {
          // Content is on disk after a successful save step.
          if (result.steps.any((s) => s.id == 'save' && s.success)) {
            _savedText = _controller.text;
          }
        }
      });
      if (result.success) {
        showStyledSnackBar(
          message: result.summary,
          title: 'webServerResultSuccess'.tr(),
          icon: Symbols.check_circle,
          accentColor: Theme.of(context).colorScheme.primary,
        );
      } else {
        showStyledSnackBar(
          message: result.summary,
          title: 'webServerResultFailed'.tr(),
          icon: Symbols.error,
          accentColor: Theme.of(context).colorScheme.error,
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMaidKitErrorAlert(
        error,
        title: 'webServerSaveFailed'.tr(args: [widget.name]),
      );
    }
  }

  Future<void> _requestDismiss() async {
    if (_saving) return;
    if (_isDirty) {
      final discard = await showMaidKitConfirmAlert(
        'webServerDiscardBody'.tr(args: [widget.name]),
        'webServerDiscardTitle'.tr(),
        isDanger: true,
      );
      if (!discard || !mounted) return;
    }
    widget.dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return AttentionModalScaffold(
      titleText: 'webServerEditTitle'.tr(args: [widget.name]),
      onDismiss: () => unawaited(_requestDismiss()),
      maxWidth: 1080,
      maxHeightFactor: 0.9,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.location,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontFamily: MaidKitFonts.mono,
              ),
            ),
            if (_lastApply != null) ...[
              const SizedBox(height: 8),
              _LastTaskBanner(
                result: _lastApply!,
                onDismiss: () => setState(() => _lastApply = null),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(child: _buildEditor(context)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _saving
                        ? 'webServerSaving'.tr()
                        : _isDirty
                        ? 'webServerUnsaved'.tr()
                        : 'fileManagerSaved'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () => unawaited(_requestDismiss()),
                  child: Text('commonClose'.tr()),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _loading || _saving || !_isDirty
                      ? null
                      : () => unawaited(_apply(WebServerApplyMode.saveOnly)),
                  child: Text('commonSave'.tr()),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _loading || _saving
                      ? null
                      : () => unawaited(
                          _apply(WebServerApplyMode.saveAndValidate),
                        ),
                  child: Text('webServerSaveAndCheck'.tr()),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _loading || _saving
                      ? null
                      : () => unawaited(
                          _apply(WebServerApplyMode.saveValidateReload),
                        ),
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Symbols.published_with_changes, size: 18),
                  label: Text('webServerSaveCheckReload'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CodeTheme(
          data: CodeThemeData(
            styles: {
              'root': TextStyle(
                color: scheme.onSurface,
                backgroundColor: scheme.surfaceContainerLowest,
                fontFamily: MaidKitFonts.mono,
              ),
              'comment': TextStyle(color: scheme.onSurfaceVariant),
              'keyword': TextStyle(color: scheme.primary),
              'string': TextStyle(color: scheme.tertiary),
              'number': TextStyle(color: scheme.secondary),
            },
          ),
          child: CodeField(
            controller: _controller,
            expands: true,
            wrap: false,
            padding: const EdgeInsets.all(12),
            textStyle: const TextStyle(fontFamily: MaidKitFonts.mono),
            gutterStyle: GutterStyle(
              textStyle: TextStyle(color: scheme.onSurfaceVariant),
              showErrors: false,
              showFoldingHandles: false,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ),
    );
  }
}

Mode? _languageForConfigName(String name) {
  final lower = name.toLowerCase();
  if (lower == 'caddyfile' || lower.endsWith('caddyfile')) return bash.bash;
  if (lower.endsWith('.conf') || lower.contains('nginx')) return nginx.nginx;
  final dot = name.lastIndexOf('.');
  final extension = dot == -1 ? '' : name.substring(dot + 1).toLowerCase();
  return switch (extension) {
    'conf' => nginx.nginx,
    'sh' || 'bash' => bash.bash,
    _ => null,
  };
}

class _TextSheet extends StatefulWidget {
  const _TextSheet({required this.title, this.load});

  final String title;
  final Future<String> Function()? load;

  @override
  State<_TextSheet> createState() => _TextSheetState();
}

class _TextSheetState extends State<_TextSheet> {
  AsyncValue<String> _text = const AsyncValue.loading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final load = widget.load;
    if (load == null) {
      setState(() => _text = const AsyncValue.data(''));
      return;
    }
    setState(() => _text = const AsyncValue.loading());
    try {
      final value = await load();
      if (mounted) setState(() => _text = AsyncValue.data(value));
    } catch (error, stackTrace) {
      if (mounted) setState(() => _text = AsyncValue.error(error, stackTrace));
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showStyledSnackBar(
      message: 'commonCopiedToClipboard'.tr(),
      title: widget.title,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SheetScaffold(
      titleText: widget.title,
      heightFactor: 0.78,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _text.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '$error',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ),
              data: (text) => SelectionArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Text(
                    text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: MaidKitFonts.mono,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('commonClose'.tr()),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _text.asData == null
                      ? null
                      : () => _copy(_text.asData!.value),
                  icon: const Icon(Symbols.content_copy, size: 18),
                  label: Text('commonCopy'.tr()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WebEmpty extends StatelessWidget {
  const _WebEmpty({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.filled = false,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;
  final bool filled;

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
              if (filled)
                FilledButton(onPressed: onAction, child: Text(actionLabel!))
              else
                OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
