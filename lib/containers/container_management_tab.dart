import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:super_context_menu/super_context_menu.dart';

import 'package:easy_localization/easy_localization.dart';
import 'container_detail_page.dart';
import 'container_list_tile.dart';
import 'compose_scan_dialog.dart';
import 'compose_stack_update.dart';
import 'container_models.dart';
import 'container_runtime_install.dart';
import 'container_sudo_guide.dart';
import 'container_ui.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/maidcafe_service.dart';
import 'package:maid_kit/servers/maidcafe_stream.dart';
import 'package:maid_kit/servers/maidcafe_session_registry.dart';
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/shared/presentation/app_context_menu.dart';
import 'package:maid_kit/shared/presentation/maidkit_alert.dart';
import 'package:maid_kit/shared/presentation/tab_navigator.dart';

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
  late final MaidCafeSessionRegistry _sessionRegistry;
  MaidCafeStreamSession? _maidCafeStream;
  StreamSubscription<MaidCafeStreamEvent>? _containersSubscription;
  var _containersSseActive = false;

  /// The daemon reported no container runtime; stop asking until a manual
  /// refresh, an explicit action, or a fresh session.
  var _containersUnavailable = false;

  /// The stream already failed once; do not re-subscribe on later ticks.
  /// Cleared by a manual refresh, an explicit action, or a fresh session.
  var _containersSseAttempted = false;

  /// Whether the visible list came from the MaidCafe daemon. The toolbar's
  /// stamp names the transport this says.
  var _containersFromMaidCafe = false;

  /// Last `containers` event timestamp and the daemon's announced cadence,
  /// used to detect a stream that stays connected but stops delivering data.
  DateTime _lastContainersEvent = DateTime.fromMillisecondsSinceEpoch(0);
  int _containersSseIntervalSeconds = 5;

  /// The daemon's update answers, for the list's badges. Empty without a
  /// daemon route, and on a daemon older than the update feature.
  ContainerUpdates _updates = const ContainerUpdates();

  /// The compose projects the daemon manages, as its scan registry reports
  /// them. They are what turns a container's project into a project row even
  /// when this app has no link for it, and they carry the directory the daemon
  /// runs compose in. Empty without a daemon route, or before the first read.
  ComposeStacksSnapshot _stacks = const ComposeStacksSnapshot();

  /// Whether the daemon is the only transport this client can offer — a
  /// browser, which has no SSH at all. A native client keeps its SSH default
  /// and the connect prompt with it, the same rule the file surfaces apply.
  bool get _daemonAllowed => kIsWeb;

  @override
  void initState() {
    super.initState();
    _sessionRegistry = ref.read(maidCafeSessionRegistryProvider);
    _sessionRegistry.retain(widget.server);
    if (widget.connected || _daemonAllowed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    _startRefreshTimer();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _closeContainersSse();
    _sessionRegistry.release(widget.server);
    super.dispose();
  }

  @override
  void didUpdateWidget(ContainerManagementTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final serverChanged = oldWidget.server.id != widget.server.id;
    if (serverChanged) {
      _closeContainersSse();
      _sessionRegistry.release(oldWidget.server);
      _sessionRegistry.retain(widget.server);
      _maidCafeStream = null;
      _containersSseAttempted = false;
      _containersUnavailable = false;
      _containersFromMaidCafe = false;
      _hasLoadedEnvironments = false;
    } else if (!widget.connected && oldWidget.connected) {
      _closeContainersSse();
      _sessionRegistry.invalidate(widget.server);
      _maidCafeStream = null;
      _containersFromMaidCafe = false;
      _hasLoadedEnvironments = false;
    }
    if (widget.connected && (!oldWidget.connected || serverChanged)) {
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

  Future<void> _load({bool force = false}) async {
    if (!mounted || _loading) return;
    // A browser reaches containers only through the daemon; everywhere else
    // the SSH session is the gate, exactly as before.
    if (!widget.connected && !_daemonAllowed) return;
    _loading = true;
    try {
      if (force) {
        // An explicit action may have changed what the daemon can see.
        _containersSseAttempted = false;
        _containersUnavailable = false;
      }
      if (!force) {
        // SSE containers own freshness while active. When it is not, one
        // stream attempt per tick is made only until it fails once; MaidCafe
        // is not retried automatically once unavailable — only a manual
        // refresh, an explicit action, or a fresh session re-attempts it.
        if (_containersSseActive) {
          final silence = DateTime.now().difference(_lastContainersEvent);
          final timeoutSeconds = _containersSseIntervalSeconds * 3 >= 15
              ? _containersSseIntervalSeconds * 3
              : 15;
          if (silence > Duration(seconds: timeoutSeconds)) {
            // The stream stays connected (heartbeats) but stopped delivering
            // data — the daemon collector may be disabled or failing. Fall
            // back to on-demand fetches instead of freezing the list.
            _containersSseAttempted = true;
            _closeContainersSse();
          } else {
            return;
          }
        }
        if (_containersSubscription == null &&
            !_containersSseAttempted &&
            !_containersUnavailable) {
          await _startContainersSse();
        }
        if (_containersSseActive) return;
        if (!_hasLoadedEnvironments) {
          setState(() => _environments = const AsyncValue.loading());
        }
      }
      if (!_containersUnavailable) {
        final session = await _ensureMaidCafeStream();
        if (session != null) {
          try {
            final snapshot = parseMaidCafeContainers(
              await session.containers(),
            );
            if (snapshot.hasRuntimes && mounted) {
              setState(() {
                _containersFromMaidCafe = true;
                _hasLoadedEnvironments = true;
                _environments = AsyncValue.data(_environmentsFrom(snapshot));
              });
              unawaited(_loadUpdateStatuses(session));
              unawaited(_loadManagedStacks(session));
              return;
            }
            if (!snapshot.hasRuntimes) {
              // The daemon has no container runtime; stop asking for it.
              _containersUnavailable = true;
            }
          } catch (_) {
            // Old daemon without /api/v1/containers: fall back to SSH.
          }
        }
      }
      if (!widget.connected) {
        // A browser has no SSH to fall back on, and the daemon route did not
        // answer: leave the list empty rather than showing a connect prompt
        // that cannot be acted on. [build] explains the missing route.
        if (mounted) {
          setState(() {
            _hasLoadedEnvironments = true;
            _environments = const AsyncValue.data([]);
          });
        }
        return;
      }
      final environments = await ref
          .read(connectionManagerProvider)
          .listContainers(
            widget.server.id,
            sshUserIsRoot: widget.server.username == 'root',
            sudoPassword: await _storedSudoPassword(),
          );
      if (mounted) {
        setState(() {
          _containersFromMaidCafe = false;
          // The registry is the daemon's: a list served over SSH has no daemon
          // behind it, so its projects come from the containers themselves.
          _stacks = const ComposeStacksSnapshot();
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

  /// Manual refresh: always fetch (the stream may be silent), and re-arm the
  /// MaidCafe path when it was previously unavailable.
  Future<void> _refreshManually() async {
    if (!_containersSseActive) {
      _containersSseAttempted = false;
      _containersUnavailable = false;
      _maidCafeStream = null;
      _sessionRegistry.invalidate(widget.server);
    }
    await _load(force: true);
  }

  /// Opens a MaidCafe session and subscribes to `containers` events.
  ///
  /// Failures leave [._containersSseActive] false so the SSH poller keeps
  /// running; the failed attempt is latched so later ticks do not re-subscribe.
  Future<void> _startContainersSse() async {
    if (_containersSubscription != null ||
        _containersSseAttempted ||
        _containersUnavailable) {
      return;
    }
    final session = await _ensureMaidCafeStream();
    if (session == null || !mounted) return;
    try {
      final events = session.openStream(
        events: const {MaidCafeStreamEventType.containers},
      );
      final subscription = events.listen(
        _onContainersEvent,
        onError: (Object error, StackTrace stackTrace) {
          _containersSseAttempted = true;
          _closeContainersSse();
        },
        onDone: () {
          _containersSseAttempted = true;
          _closeContainersSse();
        },
      );
      _containersSubscription = subscription;
    } catch (_) {
      _containersSseAttempted = true;
      _closeContainersSse();
    }
  }

  Future<MaidCafeStreamSession?> _ensureMaidCafeStream() async {
    final cached = _maidCafeStream;
    if (cached != null && !cached.isClosed) return cached;
    _maidCafeStream = null;
    final session = await _sessionRegistry.sessionFor(widget.server);
    if (session != null) {
      _maidCafeStream = session;
      if (!identical(session, cached)) {
        // A fresh session (reconnect or daemon restart) warrants a new stream
        // attempt and a re-probe of the runtime.
        _containersSseAttempted = false;
        _containersUnavailable = false;
      }
    }
    return session;
  }

  void _onContainersEvent(MaidCafeStreamEvent event) {
    if (!mounted) return;
    if (event.type == MaidCafeStreamEventType.hello) {
      _lastContainersEvent = DateTime.now();
      final intervals = event.data['intervals'];
      if (intervals is Map) {
        final seconds = intervals['containers'];
        if (seconds is num && seconds > 0) {
          _containersSseIntervalSeconds = seconds.toInt();
        }
      }
      return;
    }
    if (event.type != MaidCafeStreamEventType.containers) return;
    _lastContainersEvent = DateTime.now();
    final snapshot = parseMaidCafeContainers(event.data);
    if (!snapshot.hasRuntimes) {
      // No runtime on the host: fall back to SSH without retrying the stream.
      _containersUnavailable = true;
      _containersSseAttempted = true;
      _closeContainersSse();
      unawaited(_load());
      return;
    }
    setState(() {
      _containersSseActive = true;
      _containersFromMaidCafe = true;
      _containersUnavailable = false;
      _hasLoadedEnvironments = true;
      _environments = AsyncValue.data(_environmentsFrom(snapshot));
    });
  }

  List<ContainerEnvironment> _environmentsFrom(
    MaidCafeContainersSnapshot snapshot,
  ) => [
    for (final runtime in snapshot.runtimes)
      ContainerEnvironment(
        runtime: runtime.runtime == 'podman'
            ? ContainerRuntime.podman
            : ContainerRuntime.docker,
        scope: containerScopeForStore(runtime.store),
        containers: runtime.containers,
        error: runtime.error,
      ),
  ];

  void _closeContainersSse() {
    final subscription = _containersSubscription;
    _containersSubscription = null;
    _containersSseActive = false;
    if (subscription != null) {
      unawaited(subscription.cancel());
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
      final session = await _ensureMaidCafeStream();
      if (session != null) {
        // Daemon present: run the native op so the action also works without
        // a workstation SSH session. The daemon validates the target and
        // elevates through sudo -n when needed; failures surface as errors
        // instead of silently retrying over SSH.
        final result = await session.runContainerAction(
          container.id,
          action.name,
          force: forceRemove,
          invokedBy: ref.read(cloudUserProvider).asData?.value?.handle,
        );
        result.ensureSuccess();
      } else {
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
      }
      if (!mounted) return;
      showStyledSnackBar(
        title: 'containerActionSuccess'.tr(args: [action.pastLabel]),
        message: container.name,
        icon: Symbols.check_circle,
        accentColor: Theme.of(context).colorScheme.primary,
      );
      await _load(force: true);
    } catch (error) {
      if (!mounted) return;
      await reportContainerSudoFailure(
        context: context,
        ref: ref,
        server: widget.server,
        error: error,
        snackBarTitle: 'containerActionError'.tr(
          args: [action.label.toLowerCase()],
        ),
        onRetry: () => _runAction(environment, container, action),
      );
    }
  }

  /// Updates one whole stack: the daemon pulls every service's image and
  /// recreates the project's containers on them, in the directory it manages
  /// for that project. The app sends no directory, so a project the registry
  /// does not hold is refused rather than updated somewhere this app picked.
  Future<void> _updateStack(ComposeStack stack) async {
    final session = await _ensureMaidCafeStream();
    if (!mounted || session == null) return;
    if (!await confirmComposeStackUpdate(context, stack)) return;
    if (!mounted) return;
    await updateComposeStack(
      context,
      ref: ref,
      session: session,
      server: widget.server,
      stack: stack,
      invokedBy: ref.read(cloudUserProvider).asData?.value?.handle,
    );
    if (!mounted) return;
    await _load(force: true);
  }

  /// Updates every stack this daemon manages, one at a time.
  ///
  /// Sequential on purpose: each stack is a pull and a recreate on a real host,
  /// and the daemon already serializes native operations — issuing them
  /// together would only queue them behind each other while making progress
  /// unreadable. One stack failing does not stop the rest.
  Future<void> _updateAllStacks() async {
    final session = await _ensureMaidCafeStream();
    if (!mounted || session == null) return;
    final stacks = _stacks.stacks;
    if (stacks.isEmpty) return;
    if (!await confirmComposeStackUpdateAll(context, stacks.length)) return;
    if (!mounted) return;
    final invokedBy = ref.read(cloudUserProvider).asData?.value?.handle;
    await showComposeStackUpdateAllDialog(
      context: context,
      stacks: stacks,
      run: (stack, onStage) async {
        try {
          final task = await session.startComposeAction(
            stack.project,
            'update',
            '',
            invokedBy: invokedBy,
          );
          final finished = await session.followTask(task, onStage: onStage);
          finished.result.ensureSuccess();
          return ComposeStackUpdateOutcome(stack: stack);
        } catch (error) {
          return ComposeStackUpdateOutcome(
            stack: stack,
            error: error.toString(),
          );
        }
      },
      onOpenGuide: (stack, error) {
        unawaited(
          reportContainerSudoFailure(
            context: context,
            ref: ref,
            server: widget.server,
            error: error,
            snackBarTitle: 'composeStacksUpdateAll'.tr(),
          ),
        );
      },
    );
    if (!mounted) return;
    await _load(force: true);
  }

  /// Refreshes the daemon's managed compose stacks, which is what makes a
  /// container's project a project row on this tab — with the directory the
  /// daemon runs compose in, which the containers themselves do not carry. A
  /// daemon older than the registry leaves the list grouped exactly as before.
  Future<void> _loadManagedStacks(MaidCafeStreamSession session) async {
    try {
      final stacks = parseComposeStacks(await session.composeStacks());
      if (!mounted) return;
      setState(() => _stacks = stacks);
    } catch (_) {
      // No registry on this daemon: the projects come from the containers.
    }
  }

  /// Asks where to look for compose projects and scans there. The assignment
  /// is the daemon's to keep, so the answer comes back as a fresh registry
  /// rather than as state this tab invents.
  Future<void> _scanComposeStacks() async {
    final session = await _ensureMaidCafeStream();
    if (!mounted) return;
    if (session == null) return;
    final outcome = await showComposeStackScanDialog(
      context: context,
      policy: _stacks.scan,
      onScan: (path, depth) =>
          runComposeStackScan(session, path: path, depth: depth),
    );
    if (outcome == null || !mounted) return;
    setState(() {
      _stacks = ComposeStacksSnapshot(
        stacks: outcome.stacks.stacks,
        scan: _stacks.scan,
      );
    });
    showStyledSnackBar(
      title: 'composeStacksScan'.tr(),
      message: outcome.changed
          ? 'composeStacksScanResult'.tr(
              args: [
                '${outcome.found}',
                '${outcome.added.length}',
                '${outcome.updated.length}',
                '${outcome.removed.length}',
              ],
            )
          : 'composeStacksScanNoChange'.tr(args: ['${outcome.found}']),
      icon: Symbols.check_circle,
      accentColor: Theme.of(context).colorScheme.primary,
    );
  }

  /// Refreshes the daemon's cached update answers, which the list badges paint
  /// from. This reads the daemon's own cache and never asks a registry, so it
  /// costs nothing on the refresh cadence. A daemon older than the update
  /// feature leaves every badge off.
  Future<void> _loadUpdateStatuses(MaidCafeStreamSession session) async {
    try {
      final updates = parseContainerUpdates(await session.containerUpdates());
      if (!mounted) return;
      setState(() => _updates = updates);
    } catch (_) {
      // No update route on this daemon.
    }
  }

  /// Runs the daemon's image pull, or its pull-and-recreate update.
  ///
  /// The daemon reads the container's own configuration to find the runtime
  /// and image reference, so there is no SSH path to fall back to: a local
  /// session would have to reconstruct the reference from what the container
  /// records, which is the guess these operations exist to avoid. A container
  /// that is not compose-managed comes back refused with its reason.
  Future<void> _runContainerUpdate(
    ServerContainer container,
    String verb,
  ) async {
    final pullOnly = verb == 'pull';
    final session = await _ensureMaidCafeStream();
    if (!mounted) return;
    if (session == null) {
      showStyledSnackBar(
        title: 'containerUpdateNeedsDaemon'.tr(),
        message: container.name,
        icon: Symbols.error,
        accentColor: Theme.of(context).colorScheme.error,
      );
      return;
    }
    if (!pullOnly) {
      final approved = await showMaidKitConfirmAlert(
        'containerUpdateConfirm'.tr(args: [container.name]),
        'containerUpdate'.tr(),
      );
      if (!approved || !mounted) return;
    }
    try {
      final result = await session.runContainerAction(
        container.id,
        verb,
        invokedBy: ref.read(cloudUserProvider).asData?.value?.handle,
      );
      result.ensureSuccess();
      if (!mounted) return;
      showStyledSnackBar(
        title: (pullOnly ? 'containerPullDone' : 'containerUpdateDone').tr(),
        message: container.name,
        icon: Symbols.check_circle,
        accentColor: Theme.of(context).colorScheme.primary,
      );
      await _load(force: true);
    } catch (error) {
      if (!mounted) return;
      await reportContainerSudoFailure(
        context: context,
        ref: ref,
        server: widget.server,
        error: error,
        snackBarTitle: (pullOnly ? 'containerPull' : 'containerUpdate').tr(),
        onRetry: () => _runContainerUpdate(container, verb),
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
      await _load(force: true);
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
    if (!widget.connected && !_daemonAllowed) {
      return ContainerEmptyPanel(
        icon: Symbols.link_off,
        message: widget.connectionError ?? 'containersConnectToManage'.tr(),
        actionLabel: 'commonConnect'.tr(),
        onAction: widget.onConnect,
        filledAction: true,
        actionIcon: Symbols.link,
      );
    }
    if (!widget.connected &&
        _hasLoadedEnvironments &&
        _maidCafeStream == null) {
      // A browser with no route to the server's daemon: there is no second
      // transport to offer, so the tab names the missing route instead.
      return ContainerEmptyPanel(
        icon: Symbols.link_off,
        message: 'containersNoDaemonRoute'.tr(),
        actionLabel: 'commonRetry'.tr(),
        onAction: _refreshManually,
      );
    }
    return _environments.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ContainerEmptyPanel(
        icon: Symbols.error_outline,
        message: 'containersLoadError'.tr(args: [error.toString()]),
        actionLabel: 'commonRetry'.tr(),
        onAction: _load,
      ),
      data: (environments) => _ContainerEnvironments(
        server: widget.server,
        environments: environments,
        updates: _updates,
        stacks: _stacks,
        source: _containersFromMaidCafe
            ? ContainerListSource.daemon
            : ContainerListSource.ssh,
        pollInterval: widget.refreshInterval,
        onRefresh: _refreshManually,
        onScan: _maidCafeStream == null ? null : _scanComposeStacks,
        onUpdateAll: _maidCafeStream == null ? null : _updateAllStacks,
        onUpdateStack: _maidCafeStream == null ? null : _updateStack,
        onAction: _runAction,
        onUpdateAction: _maidCafeStream == null ? null : _runContainerUpdate,
        onInstallRuntime: _installRuntime,
        focusComposeProject: widget.focusComposeProject,
      ),
    );
  }
}

/// Linked compose project and the live containers that belong to it.
class _ServerProjectGroup {
  _ServerProjectGroup({
    this.stack,
    required this.name,
    this.directory,
    required this.runtime,
    required this.scope,
  });

  /// The daemon's managed stack, when the row is one a scan assigned. A stack
  /// is what tells the daemon where to run compose for these containers, so
  /// its directory is the one the row shows and the one an update uses.
  final ComposeStack? stack;

  final String name;
  final String? directory;

  /// The environment the group's containers came from. Null only for a managed
  /// stack whose containers no runtime lists: the row still names it and its
  /// directory, without an environment to claim.
  final ContainerRuntime? runtime;
  final ContainerScope? scope;
  final containers = <ServerContainer>[];

  int get runningCount =>
      containers.where((container) => isContainerRunning(container)).length;

  /// The environment these containers came from, or null for a managed stack
  /// whose containers the daemon does not currently see: such a stack is still
  /// assigned, and saying so is the point of showing it.
  ContainerEnvironment? get environment {
    final envRuntime = runtime;
    final envScope = scope;
    if (envRuntime == null || envScope == null) return null;
    return ContainerEnvironment(
      runtime: envRuntime,
      scope: envScope,
      containers: containers,
    );
  }
}

/// Composite key for a container inside a runtime/scope environment.
String _containerEnvKey(
  ContainerRuntime runtime,
  ContainerScope scope,
  String containerId,
) => '${runtime.name}|${scope.name}|$containerId';

/// The project rows for one server.
///
/// Each project is the daemon's, not this app's: a stack is a row because a
/// scan assigned it, and its containers are the ones carrying its project
/// label. A stack with containers in more than one runtime/scope environment
/// gets a row per environment, which is where its containers actually run.
///
/// A stack whose containers the daemon cannot see still gets a row: it is
/// assigned, and nothing running is a fact about it.
List<_ServerProjectGroup> _projectGroupsForServer({
  required Server server,
  List<ComposeStack> stacks = const [],
  required List<ContainerEnvironment> environments,
  String? focusComposeProject,
}) {
  final groups = <_ServerProjectGroup>[];
  for (final stack in stacks) {
    if (stack.project.isEmpty) continue;
    var grouped = false;
    for (final environment in environments.where((env) => env.isAvailable)) {
      final matching = environment.containers
          .where(
            (container) =>
                container.composeProject?.toLowerCase() ==
                stack.project.toLowerCase(),
          )
          .toList();
      if (matching.isEmpty) continue;
      final group = _ServerProjectGroup(
        stack: stack,
        name: stack.project,
        directory: stack.directory,
        runtime: environment.runtime,
        scope: environment.scope,
      );
      group.containers.addAll(matching);
      groups.add(group);
      grouped = true;
    }
    if (!grouped) {
      groups.add(
        _ServerProjectGroup(
          stack: stack,
          name: stack.project,
          directory: stack.directory,
          runtime: null,
          scope: null,
        ),
      );
    }
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

/// Containers that belong to any linked or managed project on this server.
Set<String> _projectContainerKeys(List<_ServerProjectGroup> projects) {
  final keys = <String>{};
  for (final project in projects) {
    final runtime = project.runtime;
    final scope = project.scope;
    if (runtime == null || scope == null) continue;
    for (final container in project.containers) {
      keys.add(_containerEnvKey(runtime, scope, container.id));
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
    required this.updates,
    required this.stacks,
    required this.source,
    this.pollInterval,
    required this.onRefresh,
    this.onScan,
    this.onUpdateAll,
    this.onUpdateStack,
    required this.onAction,
    this.onUpdateAction,
    required this.onInstallRuntime,
    this.focusComposeProject,
  });

  final Server server;
  final List<ContainerEnvironment> environments;

  /// The daemon's update answers, for the per-container badges.
  final ContainerUpdates updates;

  /// Which transport answered this list, for the toolbar's stamp.
  final ContainerListSource source;

  /// The cadence the SSH poller refreshes on.
  final Duration? pollInterval;

  /// The daemon's managed compose stacks: what a scan assigned to it. They
  /// are grouped as projects alongside this app's own project links, and they
  /// are what the daemon needs to update a container whose own labels do not
  /// record where its project lives.
  final ComposeStacksSnapshot stacks;

  final Future<void> Function() onRefresh;

  /// Opens the scan that assigns compose projects to the daemon. Null when no
  /// daemon route is open, which is also when the registry cannot be read.
  final Future<void> Function()? onScan;

  /// Updates every managed stack, one at a time. Null without a daemon route,
  /// and the control is hidden when no stack is assigned.
  final Future<void> Function()? onUpdateAll;

  /// Updates one whole stack. Null without a daemon route, which is also when
  /// the daemon could not resolve the project's directory.
  final Future<void> Function(ComposeStack stack)? onUpdateStack;
  final Future<void> Function(
    ContainerEnvironment,
    ServerContainer,
    ContainerAction,
  )
  onAction;

  /// Runs the daemon's image pull (verb `pull`) or pull-and-recreate update
  /// (verb `update`) for one container. Null while no daemon route is open,
  /// which is also what hides those entries: neither verb exists over SSH,
  /// since the daemon reads the image reference from the container itself.
  final Future<void> Function(ServerContainer, String)? onUpdateAction;
  final Future<void> Function() onInstallRuntime;
  final String? focusComposeProject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (environments.isEmpty) {
      return ContainerEmptyPanel(
        icon: Symbols.deployed_code,
        message: 'containersNotInstalled'.tr(),
        actionLabel: 'containersInstallRuntimeShort'.tr(),
        onAction: onInstallRuntime,
        filledAction: true,
        actionIcon: Symbols.download,
      );
    }

    final projects = _projectGroupsForServer(
      server: server,
      stacks: stacks.stacks,
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

    // The two sections partition the list — what a project owns, and what
    // nothing claims — so the counts a reader adds up are the ones they see.
    final projectContainerCount = totalContainers - standaloneCount;
    final summaryParts = <String>[
      totalContainers == 1
          ? 'containersSummaryContainer'.tr()
          : 'containersSummaryContainers'.tr(args: ['$totalContainers']),
      if (projects.isNotEmpty)
        projects.length == 1
            ? 'containersSummaryProject'.tr()
            : 'containersSummaryProjects'.tr(args: ['${projects.length}']),
    ];

    final standaloneGroups = _standaloneGroups(
      projects: projects,
      environments: environments,
      standaloneEnvironments: standaloneEnvironments,
    );

    final sections = <Widget>[];
    if (projects.isNotEmpty) {
      sections
        ..add(
          ContainerSectionLabel(
            label: 'containersProjects'.tr(),
            count: projectContainerCount,
          ),
        )
        ..addAll(
          spacedContainerGroups([
            for (final p in projects) _projectGroup(context, p),
          ]),
        );
    }
    if (standaloneGroups.isNotEmpty) {
      if (sections.isNotEmpty) sections.add(const SizedBox(height: 16));
      sections
        ..add(
          ContainerSectionLabel(
            label: 'containersStandalone'.tr(),
            count: standaloneCount,
          ),
        )
        ..addAll(
          spacedContainerGroups([
            for (final e in standaloneGroups) _environmentGroup(e),
          ]),
        );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ContainerListToolbar(
          summary: summaryParts,
          source: source,
          pollInterval: pollInterval,
          actions: [
            IconButton(
              tooltip: 'containersRefreshTooltip'.tr(),
              visualDensity: VisualDensity.compact,
              onPressed: onRefresh,
              icon: const Icon(Symbols.refresh),
            ),
            if (onScan != null)
              IconButton(
                tooltip: 'composeStacksScan'.tr(),
                visualDensity: VisualDensity.compact,
                onPressed: onScan,
                icon: const Icon(Symbols.scan),
              ),
            if (onUpdateAll != null && stacks.stacks.isNotEmpty)
              IconButton(
                tooltip: 'composeStacksUpdateAll'.tr(),
                visualDensity: VisualDensity.compact,
                onPressed: onUpdateAll,
                icon: const Icon(Symbols.update),
              ),
          ],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: sections,
          ),
        ),
      ],
    );
  }

  /// One compose project: its directory, the store its containers live in, and
  /// how much of it is up.
  Widget _projectGroup(BuildContext context, _ServerProjectGroup project) {
    final stack = project.stack;
    final environment = project.environment;
    final count = project.containers.length;
    return ContainerGroup(
      title: project.name,
      titleTrailing: project.directory,
      spec: [
        if (environment != null) project.runtime!.name,
        if (environment != null) containerStoreLabel(environment.scope),
        count == 0
            ? 'containersSummaryContainers'.tr(args: ['0'])
            : 'containerRunningFraction'.tr(
                args: ['${project.runningCount}', '$count'],
              ),
        if (stack != null) 'composeStacksManaged'.tr(),
      ],
      actions: [
        if (stack != null && project.directory != null)
          IconButton(
            tooltip: 'composeStacksCopyDirectory'.tr(),
            visualDensity: VisualDensity.compact,
            onPressed: () => _copyDirectory(context, project.directory!),
            icon: const Icon(Symbols.content_copy, size: 16),
          ),
        if (onUpdateStack != null && stack != null)
          IconButton(
            tooltip: 'composeStacksUpdate'.tr(),
            visualDensity: VisualDensity.compact,
            onPressed: () => onUpdateStack!(stack),
            icon: const Icon(Symbols.upgrade, size: 20),
          ),
      ],
      // An assigned stack with nothing running opens on its own: the row's
      // content is the fact that it is assigned and idle, and a collapsed row
      // would hide exactly that. A project with many containers stays closed.
      initiallyExpanded: count == 0 ? stack != null : count <= 6,
      children: project.containers.isEmpty
          ? [
              ContainerGroupNote(
                project.stack == null
                    ? 'containerNoContainersInProject'.tr()
                    : 'composeStacksNoContainers'.tr(),
              ),
            ]
          : [
              for (final container in project.containers)
                _ContainerActionTile(
                  server: server,
                  // A group holds containers only when it knows the environment
                  // they came from, so this is set wherever this branch runs.
                  environment: environment!,
                  container: container,
                  updateStatus: _updateFor(container),
                  onUpdateAction: onUpdateAction == null
                      ? null
                      : (verb) => onUpdateAction!(container, verb),
                  onAction: (action) =>
                      onAction(environment, container, action),
                ),
            ],
    );
  }

  /// One runtime and store: the containers it holds, or why it could not be
  /// read.
  Widget _environmentGroup(ContainerEnvironment environment) {
    final available = environment.isAvailable;
    final count = environment.containers.length;
    final running = environment.containers.where(isContainerRunning).length;
    return ContainerGroup(
      title: environment.runtime == ContainerRuntime.podman
          ? 'runtimePodman'.tr()
          : 'runtimeDocker'.tr(),
      spec: [
        containerStoreLabel(environment.scope),
        if (available)
          count == 1
              ? 'containersSummaryContainer'.tr()
              : 'containersSummaryContainers'.tr(args: ['$count']),
        if (available && count > 0)
          'containerRunningCount'.tr(args: ['$running']),
      ],
      children: !available
          ? [ContainerGroupNote(environment.error ?? 'commonUnavailable'.tr())]
          : count == 0
          ? [ContainerGroupNote('containersNoContainersEnv'.tr())]
          : [
              for (final container in environment.containers)
                _ContainerActionTile(
                  server: server,
                  environment: environment,
                  container: container,
                  updateStatus: _updateFor(container),
                  onUpdateAction: onUpdateAction == null
                      ? null
                      : (verb) => onUpdateAction!(container, verb),
                  onAction: (action) =>
                      onAction(environment, container, action),
                ),
            ],
    );
  }

  /// Environment sections with project-owned containers removed. Empty
  /// environments are hidden only when projects already cover that runtime.
  List<ContainerEnvironment> _standaloneGroups({
    required List<_ServerProjectGroup> projects,
    required List<ContainerEnvironment> environments,
    required List<ContainerEnvironment> standaloneEnvironments,
  }) => [
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

  ContainerUpdateStatus? _updateFor(ServerContainer container) =>
      updates.forContainer(container.id, name: container.name);

  Future<void> _copyDirectory(BuildContext context, String directory) async {
    await Clipboard.setData(ClipboardData(text: directory));
    if (!context.mounted) return;
    showStyledSnackBar(
      title: 'composeStacksCopyDirectory'.tr(),
      message: 'commonCopiedToClipboard'.tr(),
      icon: Symbols.content_copy,
      accentColor: Theme.of(context).colorScheme.primary,
    );
  }
}

/// A group with no rows: what is true instead — nothing running, or nothing
/// readable.

/// Shared container row with context menu and action overflow.
class _ContainerActionTile extends StatelessWidget {
  const _ContainerActionTile({
    required this.server,
    required this.environment,
    required this.container,
    required this.onAction,
    this.updateStatus,
    this.onUpdateAction,
  });

  final Server server;
  final ContainerEnvironment environment;
  final ServerContainer container;
  final Future<void> Function(ContainerAction action) onAction;

  /// The daemon's update answer for this container, when it has one.
  final ContainerUpdateStatus? updateStatus;

  /// Runs the daemon's `pull` or `update` verb. Null when no daemon route is
  /// open, which is also what hides those entries: neither verb exists over
  /// SSH, since the daemon reads the image reference from the container itself.
  final Future<void> Function(String verb)? onUpdateAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final running = isContainerRunning(container);
    final paused = isContainerPaused(container);
    final canPause = running && !paused;
    final canUnpause = paused;
    final update = updateStatus;
    final canUpdate = onUpdateAction != null;

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
        if (canUpdate) ...[
          MenuAction(
            title: 'containerPull'.tr(),
            image: MenuImage.icon(Symbols.download),
            callback: () => onUpdateAction!('pull'),
          ),
          MenuAction(
            title: 'containerUpdate'.tr(),
            image: MenuImage.icon(Symbols.upgrade),
            callback: () => onUpdateAction!('update'),
          ),
          MenuSeparator(),
        ],
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
        updateStatus: update,
        onUpdateAction: onUpdateAction,
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        onOpen: () => TabNavigator.of(context).push(
          ContainerDetailPage(
            server: server,
            runtime: environment.runtime,
            scope: environment.scope,
            containerId: container.id,
            containerName: container.name,
          ),
        ),
        trailing: PopupMenuButton<Object>(
          tooltip: 'containersActionTooltip'.tr(),
          onSelected: (value) {
            if (value is ContainerAction) {
              onAction(value);
            } else if (value is String) {
              onUpdateAction?.call(value);
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem<Object>(
              value: ContainerAction.start,
              enabled: !running,
              child: Row(
                children: menuRows(ContainerAction.start, Symbols.play_arrow),
              ),
            ),
            PopupMenuItem<Object>(
              value: ContainerAction.stop,
              enabled: running,
              child: Row(
                children: menuRows(ContainerAction.stop, Symbols.stop),
              ),
            ),
            PopupMenuItem<Object>(
              value: ContainerAction.restart,
              child: Row(
                children: menuRows(
                  ContainerAction.restart,
                  Symbols.restart_alt,
                ),
              ),
            ),
            PopupMenuItem<Object>(
              value: ContainerAction.pause,
              enabled: canPause,
              child: Row(
                children: menuRows(ContainerAction.pause, Symbols.pause),
              ),
            ),
            PopupMenuItem<Object>(
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
            if (canUpdate) ...[
              PopupMenuItem<Object>(
                value: 'pull',
                child: Row(
                  children: [
                    const Icon(Symbols.download, size: 20),
                    const SizedBox(width: 12),
                    Text('containerPull'.tr()),
                  ],
                ),
              ),
              PopupMenuItem<Object>(
                value: 'update',
                child: Row(
                  children: [
                    const Icon(Symbols.upgrade, size: 20),
                    const SizedBox(width: 12),
                    Text('containerUpdate'.tr()),
                  ],
                ),
              ),
              const PopupMenuDivider(),
            ],
            PopupMenuItem<Object>(
              value: ContainerAction.kill,
              enabled: running,
              child: Row(
                children: menuRows(ContainerAction.kill, Symbols.dangerous),
              ),
            ),
            PopupMenuItem<Object>(
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
