import 'dart:async';
import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:styled_widget/styled_widget.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/server_connection_actions.dart';
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/ssh_connection_manager.dart';
import 'package:maid_kit/shared/presentation/ansi_log_view.dart';
import 'package:maid_kit/shared/presentation/deploy_terminal.dart';
import 'package:maid_kit/shared/presentation/icon_label_tab.dart';
import 'package:maid_kit/shared/presentation/maidkit_alert.dart';
import 'package:maid_kit/theme.dart';
import 'container_models.dart';
import 'container_command_preferences.dart';

@RoutePage()
class ContainerDetailPage extends ConsumerStatefulWidget {
  const ContainerDetailPage({
    super.key,
    required this.server,
    required this.runtime,
    required this.scope,
    required this.containerId,
    required this.containerName,
  });

  final Server server;
  final ContainerRuntime runtime;
  final ContainerScope scope;
  final String containerId;
  final String containerName;

  @override
  ConsumerState<ContainerDetailPage> createState() =>
      _ContainerDetailPageState();
}

class _ContainerDetailPageState extends ConsumerState<ContainerDetailPage> {
  ContainerInspectDetail? _inspect;
  Object? _inspectError;
  var _loadingInspect = false;

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

  ContainerStats? _stats;
  Object? _statsError;

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
      unawaited(_loadStats());
      // Keep inspect state reasonably fresh without spamming logs.
      unawaited(_loadInspect(silent: true));
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
    await Future.wait([_loadInspect(), _startLogFollow(), _loadStats()]);
  }

  Future<void> _loadInspect({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loadingInspect = true;
        _inspectError = null;
      });
    }
    try {
      final detail = await ref
          .read(connectionManagerProvider)
          .inspectContainer(
            widget.server.id,
            runtime: widget.runtime,
            scope: widget.scope,
            containerId: widget.containerId,
            sudoPassword: await _sudoPassword(),
          );
      if (!mounted) return;
      setState(() {
        _inspect = detail;
        _inspectError = null;
        _loadingInspect = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (!silent || _inspect == null) _inspectError = error;
        _loadingInspect = false;
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
          .followContainerLogs(
            widget.server.id,
            runtime: widget.runtime,
            scope: widget.scope,
            containerId: widget.containerId,
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

  Future<void> _loadStats() async {
    final running = _inspect?.isRunning ?? true;
    if (!running) {
      if (mounted) setState(() => _stats = null);
      return;
    }
    try {
      final samples = await ref
          .read(connectionManagerProvider)
          .listContainerStats(
            widget.server.id,
            runtime: widget.runtime,
            scope: widget.scope,
            containerIds: [widget.containerId],
            sudoPassword: await _sudoPassword(),
          );
      if (!mounted) return;
      setState(() {
        _stats = samples.isEmpty ? null : samples.first;
        _statsError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _statsError = error);
    }
  }

  Future<void> _connect() async {
    final connected = await connectForStatistics(context, ref, widget.server);
    if (connected && mounted) await _bootstrap();
  }

  Future<bool> _confirmAction(
    ContainerAction action, {
    required String name,
    required bool forceRemove,
  }) async {
    final title = switch (action) {
      ContainerAction.stop => 'containerStopConfirm'.tr(args: [name]),
      ContainerAction.restart => 'containerRestartConfirm'.tr(args: [name]),
      ContainerAction.kill => 'containerKillConfirm'.tr(args: [name]),
      ContainerAction.remove =>
        forceRemove
            ? 'containerForceDeleteConfirm'.tr(args: [name])
            : 'containerDeleteConfirm'.tr(args: [name]),
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

  Future<void> _runAction(ContainerAction action) async {
    if (_actionBusy) return;
    final name = _inspect?.name.isNotEmpty == true
        ? _inspect!.name
        : widget.containerName;
    final running = _inspect?.isRunning ?? false;
    final forceRemove = action == ContainerAction.remove && running;
    if (action.requiresConfirmation) {
      final approved = await _confirmAction(
        action,
        name: name,
        forceRemove: forceRemove,
      );
      if (!approved || !mounted) return;
    }
    setState(() => _actionBusy = true);
    try {
      await ref
          .read(connectionManagerProvider)
          .runContainerAction(
            widget.server.id,
            runtime: widget.runtime,
            scope: widget.scope,
            containerId: widget.containerId,
            action: action,
            force: forceRemove,
            sudoPassword: await _sudoPassword(),
          );
      if (!mounted) return;
      showStyledSnackBar(
        title: 'containerActionSuccess'.tr(args: [action.pastLabel]),
        message: name,
        icon: Symbols.check_circle,
        accentColor: Theme.of(context).colorScheme.primary,
      );
      if (action == ContainerAction.remove) {
        if (mounted) context.router.maybePop();
        return;
      }
      await _bootstrap();
    } catch (error) {
      if (!mounted) return;
      showStyledSnackBar(
        title: 'containerActionError'.tr(args: [action.label.toLowerCase()]),
        message: error.toString(),
        icon: Symbols.error,
        accentColor: Theme.of(context).colorScheme.error,
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
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

  Future<void> _runContainerCommand({required bool attach}) async {
    final preferences = await ContainerCommandPreferences.load();
    final lastCommand = await preferences.commandFor(
      serverId: widget.server.id,
      containerId: widget.containerId,
    );
    if (!mounted) return;
    final request = await showDialog<_ContainerCommandRequest>(
      context: context,
      builder: (context) =>
          _ContainerCommandDialog(attach: attach, initialCommand: lastCommand),
    );
    if (request == null || !mounted) return;
    if (!attach) {
      await preferences.saveCommand(
        serverId: widget.server.id,
        containerId: widget.containerId,
        command: request.command,
      );
    }
    if (!mounted) return;

    if (request.interactive) {
      final command = attach
          ? buildContainerAttachCommand(
              runtime: widget.runtime,
              containerId: widget.containerId,
            )
          : buildContainerExecCommand(
              runtime: widget.runtime,
              containerId: widget.containerId,
              command: request.command,
            );
      if (!mounted) return;
      await openTerminalSession(
        context,
        ref,
        widget.server,
        initialScripts: [
          buildContainerTerminalScript(scope: widget.scope, command: command),
        ],
      );
      return;
    }

    setState(() => _actionBusy = true);
    final manager = ref.read(connectionManagerProvider);
    try {
      await runWithDeployTerminal(
        ref: ref,
        title: 'containerExecTitle'.tr(),
        subtitle: widget.server.name,
        command:
            '${widget.runtime.name} exec ${widget.containerId} '
            '${request.command}',
        run: (onOutput) async => manager.runContainerCommand(
          widget.server.id,
          runtime: widget.runtime,
          scope: widget.scope,
          containerId: widget.containerId,
          command: request.command,
          sudoPassword: await _sudoPassword(),
          onOutput: onOutput,
        ),
      );
      if (!mounted) return;
      showStyledSnackBar(
        title: 'containerExecSuccess'.tr(),
        message: request.command,
        icon: Symbols.check_circle,
        accentColor: Theme.of(context).colorScheme.primary,
      );
    } catch (error) {
      if (!mounted) return;
      showStyledSnackBar(
        title: 'containerExecError'.tr(),
        message: error.toString(),
        icon: Symbols.error,
        accentColor: Theme.of(context).colorScheme.error,
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _recreateFromInspect() async {
    final inspect = _inspect;
    if (inspect == null || _actionBusy) return;
    final command = inspect.rerunCommand(widget.runtime);
    final approved = await showMaidKitConfirmAlert(
      'containerRecreateMessage'.tr(args: [inspect.name, command]),
      'containerRecreateTitle'.tr(),
      isDanger: true,
    );
    if (!approved || !mounted) return;

    setState(() => _actionBusy = true);
    final sudo = await _sudoPassword();
    final manager = ref.read(connectionManagerProvider);
    final cleanName = inspect.name.startsWith('/')
        ? inspect.name.substring(1)
        : inspect.name;
    try {
      await runWithDeployTerminal(
        ref: ref,
        title: 'containerRecreateTask'.tr(args: [inspect.name]),
        subtitle: widget.server.name,
        command: command,
        run: (onOutput) async {
          if (inspect.isRunning) {
            onOutput('Stopping ${inspect.name}…\n');
            await manager.runContainerAction(
              widget.server.id,
              runtime: widget.runtime,
              scope: widget.scope,
              containerId: widget.containerId,
              action: ContainerAction.stop,
              sudoPassword: sudo,
            );
          }
          await manager.removeContainer(
            widget.server.id,
            runtime: widget.runtime,
            scope: widget.scope,
            containerId: widget.containerId,
            force: true,
            sudoPassword: sudo,
            onOutput: onOutput,
          );
          final args = _argumentsFromInspect(inspect);
          await manager.startRawContainer(
            widget.server.id,
            runtime: widget.runtime,
            scope: widget.scope,
            name: cleanName,
            image: inspect.image,
            arguments: args,
            sudoPassword: sudo,
            onOutput: onOutput,
          );
        },
      );
      if (!mounted) return;
      showStyledSnackBar(
        title: 'containerRecreateSuccess'.tr(),
        message: cleanName,
        icon: Symbols.check_circle,
        accentColor: Theme.of(context).colorScheme.primary,
      );
      // The old id is gone; pop so the caller can refresh its list.
      if (mounted) context.router.maybePop();
    } catch (error) {
      if (!mounted) return;
      showStyledSnackBar(
        title: 'containerRecreateError'.tr(),
        message: error.toString(),
        icon: Symbols.error,
        accentColor: Theme.of(context).colorScheme.error,
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  String _argumentsFromInspect(ContainerInspectDetail inspect) {
    final parts = <String>[];
    if (inspect.restartPolicy.isNotEmpty && inspect.restartPolicy != 'no') {
      parts.add('--restart ${inspect.restartPolicy}');
    }
    if (inspect.networkMode.isNotEmpty &&
        inspect.networkMode != 'default' &&
        inspect.networkMode != 'bridge') {
      parts.add('--network ${_quote(inspect.networkMode)}');
    }
    if (inspect.user != null && inspect.user!.isNotEmpty) {
      parts.add('--user ${_quote(inspect.user!)}');
    }
    if (inspect.workingDir != null && inspect.workingDir!.isNotEmpty) {
      parts.add('-w ${_quote(inspect.workingDir!)}');
    }
    for (final port in inspect.ports) {
      parts.add('-p ${_quote(port)}');
    }
    for (final bind in inspect.binds) {
      parts.add('-v ${_quote(bind)}');
    }
    for (final variable in inspect.env) {
      if (variable.startsWith('PATH=')) continue;
      parts.add('-e ${_quote(variable)}');
    }
    for (final entry in inspect.labels.entries) {
      if (entry.key.startsWith('com.docker.compose.') ||
          entry.key.startsWith('io.podman.compose.')) {
        continue;
      }
      parts.add('--label ${_quote('${entry.key}=${entry.value}')}');
    }
    if (inspect.command.isNotEmpty) {
      // Command must follow the image in `run`; startRawContainer places image
      // last, so append via a trailing arg after image is not supported.
      // Keep command only in the displayed re-run string.
    }
    return parts.join(' ');
  }

  String _quote(String value) {
    if (RegExp(r'^[a-zA-Z0-9_./:@%+=,-]+$').hasMatch(value)) return value;
    return "'${value.replaceAll("'", "'\\''")}'";
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(sessionsProvider).asData?.value ?? const [];
    final session = sessions
        .where((item) => item.serverId == widget.server.id)
        .firstOrNull;
    final connected = session?.status == SessionStatus.connected;
    final inspect = _inspect;
    final running = inspect?.isRunning ?? false;
    final title = inspect?.name.isNotEmpty == true
        ? inspect!.name
        : widget.containerName;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'containerRefresh'.tr(),
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
                  unawaited(_runAction(ContainerAction.start));
                case 'stop':
                  unawaited(_runAction(ContainerAction.stop));
                case 'restart':
                  unawaited(_runAction(ContainerAction.restart));
                case 'pause':
                  unawaited(_runAction(ContainerAction.pause));
                case 'unpause':
                  unawaited(_runAction(ContainerAction.unpause));
                case 'kill':
                  unawaited(_runAction(ContainerAction.kill));
                case 'remove':
                  unawaited(_runAction(ContainerAction.remove));
                case 'exec':
                  unawaited(_runContainerCommand(attach: false));
                case 'attach':
                  unawaited(_runContainerCommand(attach: true));
                case 'recreate':
                  unawaited(_recreateFromInspect());
              }
            },
            itemBuilder: (context) {
              final scheme = Theme.of(context).colorScheme;
              final paused = inspect?.isPaused ?? false;
              return [
                PopupMenuItem(
                  value: 'exec',
                  enabled: running,
                  child: Text('containerExec'.tr()),
                ),
                PopupMenuItem(
                  value: 'attach',
                  enabled: running,
                  child: Text('containerAttach'.tr()),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'start',
                  enabled: !running,
                  child: const Text('containerStart').tr(),
                ),
                PopupMenuItem(
                  value: 'stop',
                  enabled: running,
                  child: const Text('containerStop').tr(),
                ),
                PopupMenuItem(
                  value: 'restart',
                  child: Text('containerRestart'.tr()),
                ),
                PopupMenuItem(
                  value: 'pause',
                  enabled: running && !paused,
                  child: const Text('containerPause').tr(),
                ),
                PopupMenuItem(
                  value: 'unpause',
                  enabled: paused,
                  child: const Text('containerUnpause').tr(),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'kill',
                  enabled: running,
                  child: Text(
                    'containerKill'.tr(),
                    style: TextStyle(color: scheme.error),
                  ),
                ),
                PopupMenuItem(
                  value: 'remove',
                  child: Text(
                    'containerDelete'.tr(),
                    style: TextStyle(color: scheme.error),
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'recreate',
                  child: Text('containerReCreateInspect'.tr()),
                ),
              ];
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: !connected && inspect == null
          ? _EmptyBody(
              icon: Symbols.link_off,
              message: session?.error ?? 'containerConnectToInspect'.tr(),
              actionLabel: 'commonConnect'.tr(),
              onAction: _connect,
            )
          : _DetailWorkspace(
              overview: _OverviewPanel(
                server: widget.server,
                runtime: widget.runtime,
                scope: widget.scope,
                containerId: widget.containerId,
                connected: connected,
                session: session,
                inspect: inspect,
                loading: _loadingInspect && inspect == null,
                error: _inspectError,
                stats: _stats,
                statsError: _statsError,
                onConnect: _connect,
                onRefresh: () => unawaited(_bootstrap()),
              ),
              inspector: _InspectorTabs(
                inspect: inspect,
                inspectError: _inspectError,
                loadingInspect: _loadingInspect,
                logs: _logs,
                logsError: _logsError,
                loadingLogs: _loadingLogs,
                followingLogs: _followingLogs,
                logTail: _logTail,
                logTimestamps: _logTimestamps,
                runtime: widget.runtime,
                onRefreshInspect: () => unawaited(_loadInspect()),
                onRefreshLogs: () => unawaited(_startLogFollow()),
                onLogTailChanged: (value) {
                  setState(() => _logTail = value);
                  unawaited(_startLogFollow());
                },
                onLogTimestampsChanged: (value) {
                  setState(() => _logTimestamps = value);
                  unawaited(_startLogFollow());
                },
                onCopy: _copy,
                onRecreate: inspect == null
                    ? null
                    : () => unawaited(_recreateFromInspect()),
              ),
            ),
    );
  }
}

class _DetailWorkspace extends StatelessWidget {
  const _DetailWorkspace({required this.overview, required this.inspector});

  final Widget overview;
  final Widget inspector;

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
              SizedBox(height: 560, child: _PanelSurface(child: inspector)),
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
                child: _PanelSurface(child: inspector),
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
    // Clip children (e.g. the log terminal) so they respect the rounded panel.
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

class _OverviewPanel extends StatelessWidget {
  const _OverviewPanel({
    required this.server,
    required this.runtime,
    required this.scope,
    required this.containerId,
    required this.connected,
    required this.session,
    required this.inspect,
    required this.loading,
    required this.error,
    required this.stats,
    required this.statsError,
    required this.onConnect,
    required this.onRefresh,
  });

  final Server server;
  final ContainerRuntime runtime;
  final ContainerScope scope;
  final String containerId;
  final bool connected;
  final SshSessionInfo? session;
  final ContainerInspectDetail? inspect;
  final bool loading;
  final Object? error;
  final ContainerStats? stats;
  final Object? statsError;
  final Future<void> Function() onConnect;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel('containerDetails'.tr()),
        const SizedBox(height: 12),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (inspect == null && error != null)
          Text(
            'containerCouldNotInspect'.tr(args: [error.toString()]),
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
          )
        else if (inspect == null)
          Text(
            connected
                ? 'containerNoInspectData'.tr()
                : (session?.error ?? 'commonNotConnected'.tr()),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          )
        else ...[
          _IdentityBlock(
            name: inspect!.name,
            image: inspect!.image,
            state: inspect!.state,
            status: inspect!.status,
            running: inspect!.isRunning,
          ),
          const SizedBox(height: 16),
          _KeyValue(
            label: 'containerFieldId'.tr(),
            value: inspect!.id.isEmpty ? containerId : inspect!.id,
            mono: true,
          ),
          _KeyValue(label: 'containerFieldServer'.tr(), value: server.name),
          _KeyValue(label: 'containerFieldRuntime'.tr(), value: runtime.name),
          _KeyValue(
            label: 'containerFieldScope'.tr(),
            value: scope == ContainerScope.root
                ? 'commonSystem'.tr()
                : 'commonUser'.tr(),
          ),
          if (inspect!.restartPolicy.isNotEmpty)
            _KeyValue(
              label: 'containerFieldRestart'.tr(),
              value: inspect!.restartPolicy,
            ),
          if (inspect!.networkMode.isNotEmpty)
            _KeyValue(
              label: 'containerFieldNetwork'.tr(),
              value: inspect!.networkMode,
            ),
          if (inspect!.created != null)
            _KeyValue(
              label: 'containerFieldCreated'.tr(),
              value: _formatTimestamp(inspect!.created!),
            ),
          if (inspect!.startedAt != null)
            _KeyValue(
              label: 'containerFieldStarted'.tr(),
              value: _formatTimestamp(inspect!.startedAt!),
            ),
          if (inspect!.exitCode != null && !inspect!.isRunning)
            _KeyValue(
              label: 'containerFieldExitCode'.tr(),
              value: '${inspect!.exitCode}',
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
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Symbols.refresh, size: 18),
            label: Text('commonRefresh'.tr()),
          ),
        ],
        const SizedBox(height: 24),
        _SectionLabel('containerResources'.tr()),
        const SizedBox(height: 12),
        if (statsError != null)
          Text(
            'containerStatsUnavailable'.tr(args: [statsError.toString()]),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          )
        else if (stats == null)
          Text(
            inspect?.isRunning == true
                ? 'containerStatsWaiting'.tr()
                : 'containerStatsOnlyRunning'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          )
        else
          _StatsGrid(stats: stats!),
      ],
    );
  }
}

class _IdentityBlock extends StatelessWidget {
  const _IdentityBlock({
    required this.name,
    required this.image,
    required this.state,
    required this.status,
    required this.running,
  });

  final String name;
  final String image;
  final String state;
  final String status;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          running ? Symbols.play_circle : Symbols.stop_circle,
          color: running ? scheme.primary : scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                image,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: MaidKitFonts.mono,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: running
                      ? scheme.secondaryContainer
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  status.isEmpty ? state : status,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: running
                        ? scheme.onSecondaryContainer
                        : scheme.onSurfaceVariant,
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

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});

  final ContainerStats stats;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _StatChip(
          label: 'detailCpu'.tr(),
          value: stats.cpuPercent == null
              ? '—'
              : '${stats.cpuPercent!.toStringAsFixed(1)}%',
        ),
        _StatChip(
          label: 'detailMemory'.tr(),
          value: stats.memUsage.isEmpty ? '—' : stats.memUsage,
        ),
        _StatChip(
          label: 'activityNetwork'.tr(),
          value: stats.netIO.isEmpty ? '—' : stats.netIO,
        ),
        _StatChip(
          label: 'detailRootDisk'.tr(),
          value: stats.blockIO.isEmpty ? '—' : stats.blockIO,
        ),
        if (stats.pids != null)
          _StatChip(label: 'detailPid'.tr(), value: '${stats.pids}'),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: MaidKitFonts.mono,
            ),
          ),
        ],
      ),
    );
  }
}

class _InspectorTabs extends StatelessWidget {
  const _InspectorTabs({
    required this.inspect,
    required this.inspectError,
    required this.loadingInspect,
    required this.logs,
    required this.logsError,
    required this.loadingLogs,
    required this.followingLogs,
    required this.logTail,
    required this.logTimestamps,
    required this.runtime,
    required this.onRefreshInspect,
    required this.onRefreshLogs,
    required this.onLogTailChanged,
    required this.onLogTimestampsChanged,
    required this.onCopy,
    required this.onRecreate,
  });

  final ContainerInspectDetail? inspect;
  final Object? inspectError;
  final bool loadingInspect;
  final String? logs;
  final Object? logsError;
  final bool loadingLogs;
  final bool followingLogs;
  final int logTail;
  final bool logTimestamps;
  final ContainerRuntime runtime;
  final VoidCallback onRefreshInspect;
  final VoidCallback onRefreshLogs;
  final ValueChanged<int> onLogTailChanged;
  final ValueChanged<bool> onLogTimestampsChanged;
  final Future<void> Function(String value, {required String title}) onCopy;
  final VoidCallback? onRecreate;

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
              IconLabelTab(
                icon: const Icon(Symbols.terminal, size: 18),
                label: 'containerLogs'.tr(),
              ),
              IconLabelTab(
                icon: const Icon(Symbols.replay, size: 18),
                label: 'containerReRunCommand'.tr(),
              ),
              IconLabelTab(
                icon: const Icon(Symbols.info, size: 18),
                label: 'containerDetails'.tr(),
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _LogsPane(
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
                _RerunPane(
                  inspect: inspect,
                  runtime: runtime,
                  onCopy: onCopy,
                  onRecreate: onRecreate,
                ),
                _DetailsPane(
                  inspect: inspect,
                  error: inspectError,
                  loading: loadingInspect,
                  onRefresh: onRefreshInspect,
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

class _LogsPane extends StatelessWidget {
  const _LogsPane({
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

class _RerunPane extends StatelessWidget {
  const _RerunPane({
    required this.inspect,
    required this.runtime,
    required this.onCopy,
    required this.onRecreate,
  });

  final ContainerInspectDetail? inspect;
  final ContainerRuntime runtime;
  final Future<void> Function(String value, {required String title}) onCopy;
  final VoidCallback? onRecreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (inspect == null) {
      return _EmptyBody(
        icon: Symbols.replay,
        message: 'containerInspectToGenerate'.tr(),
      );
    }
    final command = inspect!.rerunCommand(runtime);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'containerRecreateInfo'.tr(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              command,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: MaidKitFonts.mono,
                height: 1.45,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton.icon(
              onPressed: () =>
                  onCopy(command, title: 'containerCommandCopied'.tr()),
              icon: const Icon(Symbols.content_copy, size: 18),
              label: const Text('containerCopyCommand').tr(),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onRecreate,
              icon: const Icon(Symbols.replay, size: 18),
              label: const Text('containerReCreateInspect').tr(),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _SectionLabel('containerIncludedConfig'.tr()),
        const SizedBox(height: 8),
        _SummaryLine(label: 'containerFieldImage'.tr(), value: inspect!.image),
        _SummaryLine(
          label: 'containerPorts'.tr(),
          value: inspect!.ports.isEmpty ? '—' : inspect!.ports.join(', '),
        ),
        _SummaryLine(
          label: 'containerVolumes'.tr(),
          value: inspect!.binds.isEmpty ? '—' : inspect!.binds.join(', '),
        ),
        _SummaryLine(
          label: 'containerEnvVarsCount'.tr(),
          value: '${inspect!.env.where((e) => !e.startsWith('PATH=')).length}',
        ),
        _SummaryLine(
          label: 'containerFieldRestart'.tr(),
          value: inspect!.restartPolicy,
        ),
        _SummaryLine(
          label: 'containerFieldNetwork'.tr(),
          value: inspect!.networkMode,
        ),
        if (inspect!.command.isNotEmpty)
          _SummaryLine(
            label: 'detailCommand'.tr(),
            value: inspect!.command.join(' '),
          ),
      ],
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: MaidKitFonts.mono,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsPane extends StatelessWidget {
  const _DetailsPane({
    required this.inspect,
    required this.error,
    required this.loading,
    required this.onRefresh,
    required this.onCopy,
  });

  final ContainerInspectDetail? inspect;
  final Object? error;
  final bool loading;
  final VoidCallback onRefresh;
  final Future<void> Function(String value, {required String title}) onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (loading && inspect == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (inspect == null) {
      return _EmptyBody(
        icon: Symbols.error_outline,
        message: error == null
            ? 'containerNoDetailsAvailable'.tr()
            : 'containerCouldNotInspect'.tr(args: [error.toString()]),
        actionLabel: 'commonRetry'.tr(),
        onAction: () async => onRefresh(),
      );
    }

    String prettyJson;
    try {
      prettyJson = const JsonEncoder.withIndent(
        '  ',
      ).convert(jsonDecode(inspect!.rawJson));
    } catch (_) {
      prettyJson = inspect!.rawJson;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text(
              'containerEnvironment'.tr(),
              style: theme.textTheme.titleSmall,
            ),
            const Spacer(),
            IconButton(
              tooltip: 'containerCopyJson'.tr(),
              onPressed: () =>
                  onCopy(prettyJson, title: 'containerInspectJsonCopied'.tr()),
              icon: const Icon(Symbols.content_copy, size: 18),
            ),
            IconButton(
              tooltip: 'commonRefresh'.tr(),
              onPressed: onRefresh,
              icon: const Icon(Symbols.refresh, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (inspect!.env.isEmpty)
          Text(
            'containerNoEnvVars'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          )
        else
          for (final item in inspect!.env)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SelectableText(
                item,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: MaidKitFonts.mono,
                ),
              ),
            ),
        const SizedBox(height: 20),
        Text('containerPorts'.tr(), style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (inspect!.ports.isEmpty)
          Text(
            'containerNoPorts'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          )
        else
          for (final port in inspect!.ports)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                port,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: MaidKitFonts.mono,
                ),
              ),
            ),
        const SizedBox(height: 20),
        Text('containerMounts'.tr(), style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (inspect!.mounts.isEmpty && inspect!.binds.isEmpty)
          Text(
            'containerNoMounts'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          )
        else
          for (final mount
              in (inspect!.mounts.isNotEmpty
                  ? inspect!.mounts
                  : inspect!.binds))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                mount,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: MaidKitFonts.mono,
                ),
              ),
            ),
        if (inspect!.networks.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('containerNetworks'.tr(), style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(
            inspect!.networks.join(', '),
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: MaidKitFonts.mono,
            ),
          ),
        ],
        if (inspect!.labels.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('containerLabels'.tr(), style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final entry in inspect!.labels.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SelectableText(
                '${entry.key}=${entry.value}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: MaidKitFonts.mono,
                ),
              ),
            ),
        ],
        const SizedBox(height: 20),
        Text('containerRawJson'.tr(), style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              prettyJson,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: MaidKitFonts.mono,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ContainerCommandRequest {
  const _ContainerCommandRequest({
    required this.command,
    required this.interactive,
  });

  final String command;
  final bool interactive;
}

class _ContainerCommandDialog extends StatefulWidget {
  const _ContainerCommandDialog({
    required this.attach,
    required this.initialCommand,
  });

  final bool attach;
  final String? initialCommand;

  @override
  State<_ContainerCommandDialog> createState() =>
      _ContainerCommandDialogState();
}

class _ContainerCommandDialogState extends State<_ContainerCommandDialog> {
  late final TextEditingController _commandController = TextEditingController(
    text: widget.initialCommand?.trim().isNotEmpty == true
        ? widget.initialCommand
        : 'bash',
  );
  late var _interactive = true;

  @override
  void dispose() {
    _commandController.dispose();
    super.dispose();
  }

  void _submit() {
    final command = _commandController.text.trim();
    if (!widget.attach && command.isEmpty) return;
    Navigator.of(context).pop(
      _ContainerCommandRequest(command: command, interactive: _interactive),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(
        widget.attach ? 'containerAttachTitle'.tr() : 'containerExecTitle'.tr(),
      ),
      content: SizedBox(
        width: 480,
        child: widget.attach
            ? Text(
                'containerAttachTitle'.tr(),
                style: theme.textTheme.bodyMedium,
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _commandController,
                      autofocus: true,
                      maxLines: 4,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'containerCommand'.tr(),
                        hintText: 'containerCommandHint'.tr(),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'containerQuickCommands'.tr(),
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final command in ['bash', 'sh', 'rcon-cli'])
                          ActionChip(
                            label: Text(command),
                            onPressed: () => setState(
                              () => _commandController.text = command,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _interactive,
                      onChanged: (value) =>
                          setState(() => _interactive = value ?? true),
                      title: Text('containerInteractive'.tr()),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('commonCancel'.tr()),
        ),
        FilledButton(
          onPressed: widget.attach || _commandController.text.trim().isNotEmpty
              ? _submit
              : null,
          child: Text('containerRun'.tr()),
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

String _formatTimestamp(String raw) {
  final parsed = DateTime.tryParse(raw);
  if (parsed == null || parsed.year <= 1) return raw;
  return parsed.toLocal().toString();
}
