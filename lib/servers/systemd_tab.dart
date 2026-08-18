import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:super_context_menu/super_context_menu.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/shared/presentation/app_context_menu.dart';
import 'package:maid_kit/theme.dart';
import 'maidcafe_service.dart';
import 'maidcafe_stream.dart';
import 'maidcafe_session_registry.dart';
import 'server_connection_actions.dart';
import 'server_models.dart';
import 'server_providers.dart';
import 'systemd_models.dart';

enum _ServiceFilter { all, active, failed, inactive }

/// Host systemd service management (systemctl list / start / stop / enable / logs).
class SystemdTab extends ConsumerStatefulWidget {
  const SystemdTab({
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
  ConsumerState<SystemdTab> createState() => _SystemdTabState();
}

class _SystemdTabState extends ConsumerState<SystemdTab> {
  AsyncValue<SystemdUnitsSnapshot> _snapshot = const AsyncValue.loading();
  final _searchController = TextEditingController();
  var _filter = _ServiceFilter.all;
  var _busy = false;
  String? _busyUnit;
  late final MaidCafeSessionRegistry _sessionRegistry;
  MaidCafeStreamSession? _maidCafeStream;
  StreamSubscription<MaidCafeStreamEvent>? _systemdSubscription;
  var _systemdSseActive = false;

  /// The daemon reported no systemctl; stop asking until a manual refresh, an
  /// explicit action, or a fresh session.
  var _systemdUnavailable = false;

  /// The stream already failed once; do not re-subscribe on later ticks.
  var _systemdSseAttempted = false;

  /// Last `systemd` event timestamp and the daemon's announced cadence, used
  /// to detect a stream that stays connected but stops delivering data.
  DateTime _lastSystemdEvent = DateTime.fromMillisecondsSinceEpoch(0);
  int _systemdSseIntervalSeconds = 30;

  bool get _isRoot => widget.server.username == 'root';

  @override
  void initState() {
    super.initState();
    _sessionRegistry = ref.read(maidCafeSessionRegistryProvider);
    _sessionRegistry.retain(widget.server);
    _searchController.addListener(() => setState(() {}));
    if (widget.connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _closeSystemdSse();
    _sessionRegistry.release(widget.server);
    super.dispose();
  }

  @override
  void didUpdateWidget(SystemdTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final serverChanged = oldWidget.server.id != widget.server.id;
    if (serverChanged) {
      _closeSystemdSse();
      _sessionRegistry.release(oldWidget.server);
      _sessionRegistry.retain(widget.server);
      _maidCafeStream = null;
      _systemdSseAttempted = false;
      _systemdUnavailable = false;
    } else if (!widget.connected && oldWidget.connected) {
      _closeSystemdSse();
      _sessionRegistry.invalidate(widget.server);
      _maidCafeStream = null;
      _systemdSseAttempted = false;
      _systemdUnavailable = false;
    }
    if (widget.connected && (!oldWidget.connected || serverChanged)) {
      _load();
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

  Future<void> _load({bool force = false}) async {
    if (!mounted || !widget.connected) return;
    if (force) {
      // An explicit action may have changed what the daemon can see.
      _systemdSseAttempted = false;
      _systemdUnavailable = false;
    }
    if (!force) {
      // SSE owns freshness while active. When it is not, one stream attempt
      // is made only until it fails once — MaidCafe is not retried
      // automatically, only on manual refresh, an explicit action, or a
      // fresh session.
      if (_systemdSseActive) {
        final silence = DateTime.now().difference(_lastSystemdEvent);
        final timeoutSeconds = _systemdSseIntervalSeconds * 3 >= 15
            ? _systemdSseIntervalSeconds * 3
            : 15;
        if (silence > Duration(seconds: timeoutSeconds)) {
          // The stream stays connected (heartbeats) but stopped delivering
          // data — the daemon collector may be disabled or failing. Fall
          // back to on-demand fetches instead of freezing the snapshot.
          _systemdSseAttempted = true;
          _closeSystemdSse();
        } else {
          return;
        }
      }
      if (_systemdSubscription == null && !_systemdSseAttempted) {
        await _startSystemdSse();
      }
      if (_systemdSseActive) return;
    }
    setState(() => _snapshot = const AsyncValue.loading());
    if (!_systemdUnavailable) {
      final session = await _ensureMaidCafeStream();
      if (session != null) {
        try {
          final snapshot = parseMaidCafeSystemd(await session.systemd());
          if (snapshot.available && mounted) {
            setState(() {
              _snapshot = AsyncValue.data(
                SystemdUnitsSnapshot(available: true, units: snapshot.units),
              );
            });
            return;
          }
          if (!snapshot.available) {
            // The daemon (root) found no systemctl; stop asking for it.
            _systemdUnavailable = true;
            if (mounted) {
              setState(() {
                _snapshot = AsyncValue.data(
                  SystemdUnitsSnapshot(available: false, error: snapshot.error),
                );
              });
            }
            return;
          }
        } catch (_) {
          // Old daemon without /api/v1/systemd: fall back to SSH.
        }
      }
    }
    try {
      final snapshot = await ref
          .read(connectionManagerProvider)
          .listSystemdUnits(
            widget.server.id,
            sshUserIsRoot: _isRoot,
            sudoPassword: await _sudoPassword(),
          );
      if (mounted) setState(() => _snapshot = AsyncValue.data(snapshot));
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() => _snapshot = AsyncValue.error(error, stackTrace));
      }
    }
  }

  /// Manual refresh: always fetch (the stream may be silent), and re-arm the
  /// MaidCafe path when it was previously unavailable.
  void _refreshManually() {
    if (!_systemdSseActive) {
      _systemdSseAttempted = false;
      _systemdUnavailable = false;
      _maidCafeStream = null;
      _sessionRegistry.invalidate(widget.server);
    }
    unawaited(_load(force: true));
  }

  /// Opens a MaidCafe session and subscribes to `systemd` events.
  ///
  /// Failures leave [._systemdSseActive] false so the SSH probe keeps
  /// working; the failed attempt is latched so later ticks do not re-subscribe.
  Future<void> _startSystemdSse() async {
    if (_systemdSubscription != null ||
        _systemdSseAttempted ||
        _systemdUnavailable) {
      return;
    }
    final session = await _ensureMaidCafeStream();
    if (session == null || !mounted) return;
    try {
      final events = session.openStream(
        events: const {MaidCafeStreamEventType.systemd},
      );
      final subscription = events.listen(
        _onSystemdEvent,
        onError: (Object error, StackTrace stackTrace) {
          _systemdSseAttempted = true;
          _closeSystemdSse();
        },
        onDone: () {
          _systemdSseAttempted = true;
          _closeSystemdSse();
        },
      );
      _systemdSubscription = subscription;
    } catch (_) {
      _systemdSseAttempted = true;
      _closeSystemdSse();
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
        // A fresh session (reconnect or daemon restart) warrants a new
        // stream attempt and a re-probe of systemd availability.
        _systemdSseAttempted = false;
        _systemdUnavailable = false;
      }
    }
    return session;
  }

  void _onSystemdEvent(MaidCafeStreamEvent event) {
    if (!mounted) return;
    if (event.type == MaidCafeStreamEventType.hello) {
      _lastSystemdEvent = DateTime.now();
      final intervals = event.data['intervals'];
      if (intervals is Map) {
        final seconds = intervals['systemd'];
        if (seconds is num && seconds > 0) {
          _systemdSseIntervalSeconds = seconds.toInt();
        }
      }
      return;
    }
    if (event.type != MaidCafeStreamEventType.systemd) return;
    _lastSystemdEvent = DateTime.now();
    final snapshot = parseMaidCafeSystemd(event.data);
    if (!snapshot.available) {
      // The daemon has no systemctl; stop retrying the stream.
      _systemdUnavailable = true;
      _systemdSseAttempted = true;
      _closeSystemdSse();
    }
    setState(() {
      _systemdSseActive = snapshot.available;
      _snapshot = AsyncValue.data(
        SystemdUnitsSnapshot(
          available: snapshot.available,
          units: snapshot.units,
          error: snapshot.error,
        ),
      );
    });
  }

  void _closeSystemdSse() {
    final subscription = _systemdSubscription;
    _systemdSubscription = null;
    _systemdSseActive = false;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
  }

  Future<void> _run(
    Future<void> Function() action, {
    required String success,
    String? unit,
    bool canRetryConnection = true,
  }) async {
    setState(() {
      _busy = true;
      _busyUnit = unit;
    });
    try {
      await action();
      if (!mounted) return;
      showStyledSnackBar(message: success, title: 'systemdServices'.tr());
      await _load(force: true);
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
            success: success,
            unit: unit,
            canRetryConnection: false,
          );
        }
        return;
      }
      if (!mounted) return;
      showStyledSnackBar(
        message: error.toString(),
        title: 'systemdServiceActionFailed'.tr(),
        icon: Symbols.error,
        accentColor: Theme.of(context).colorScheme.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyUnit = null;
        });
      }
    }
  }

  Future<bool> _confirmAction(
    SystemdUnit unit,
    SystemdUnitAction action,
  ) async {
    final critical = isCriticalSystemdUnit(unit.name) && action.isDestructive;
    final approved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (sheetContext) => SheetScaffold(
        titleText: 'systemdActionConfirm'.tr(
          args: ['${action.trLabel} ${unit.name}'],
        ),
        heightFactor: critical ? 0.42 : 0.36,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              _confirmMessage(unit, action, critical: critical),
              style: Theme.of(sheetContext).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(sheetContext, false),
                  child: const Text('commonCancel').tr(),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  child: Text(action.trLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return approved == true;
  }

  String _confirmMessage(
    SystemdUnit unit,
    SystemdUnitAction action, {
    required bool critical,
  }) {
    final base = switch (action) {
      SystemdUnitAction.stop => 'systemdStopConfirm'.tr(args: [unit.name]),
      SystemdUnitAction.restart => 'systemdRestartConfirm'.tr(
        args: [unit.name],
      ),
      SystemdUnitAction.reload => 'systemdReloadConfirm'.tr(args: [unit.name]),
      SystemdUnitAction.disable => 'systemdDisableConfirm'.tr(
        args: [unit.name],
      ),
      SystemdUnitAction.enable => 'systemdEnableConfirm'.tr(args: [unit.name]),
      SystemdUnitAction.start => 'systemdStartConfirm'.tr(args: [unit.name]),
    };
    if (!critical) return base;
    return '$base\n\n${'systemdCriticalWarning'.tr()}';
  }

  Future<void> _onAction(SystemdUnit unit, SystemdUnitAction action) async {
    if (action.isDestructive ||
        action == SystemdUnitAction.restart ||
        action == SystemdUnitAction.enable ||
        isCriticalSystemdUnit(unit.name)) {
      final ok = await _confirmAction(unit, action);
      if (!ok || !mounted) return;
    }
    await _run(
      () async {
        final session = await _ensureMaidCafeStream();
        if (session != null) {
          // Daemon present: run the native systemd op. The daemon validates
          // the unit name and elevates through sudo -n when needed.
          final result = await session.runSystemdAction(
            unit.name,
            action.name,
            invokedBy: ref.read(cloudUserProvider).asData?.value?.handle,
          );
          result.ensureSuccess();
        } else {
          await ref
              .read(connectionManagerProvider)
              .runSystemdUnitAction(
                widget.server.id,
                unit: unit.name,
                action: action,
                sshUserIsRoot: _isRoot,
                sudoPassword: await _sudoPassword(),
              );
        }
      },
      success: 'systemdSuccess'.tr(
        args: ['${action.trPastLabel} ${unit.name}'],
      ),
      unit: unit.name,
    );
  }

  Future<void> _showStatus(SystemdUnit unit) async {
    await _showTextSheet(
      title: unit.name,
      load: () async {
        return ref
            .read(connectionManagerProvider)
            .getSystemdUnitStatus(
              widget.server.id,
              unit: unit.name,
              sshUserIsRoot: _isRoot,
              sudoPassword: await _sudoPassword(),
            );
      },
    );
  }

  Future<void> _showLogs(SystemdUnit unit) async {
    await _showTextSheet(
      title: 'systemdLogsTitle'.tr(args: [unit.name]),
      load: () async {
        return ref
            .read(connectionManagerProvider)
            .getSystemdUnitLogs(
              widget.server.id,
              unit: unit.name,
              sshUserIsRoot: _isRoot,
              sudoPassword: await _sudoPassword(),
            );
      },
    );
  }

  Future<void> _showTextSheet({
    required String title,
    required Future<String> Function() load,
  }) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (sheetContext) => _UnitTextSheet(title: title, load: load),
    );
  }

  List<SystemdUnit> _filtered(List<SystemdUnit> units) {
    final query = _searchController.text.trim().toLowerCase();
    return units.where((unit) {
      final matchesFilter = switch (_filter) {
        _ServiceFilter.all => true,
        _ServiceFilter.active => unit.isActive,
        _ServiceFilter.failed => unit.isFailed,
        _ServiceFilter.inactive => !unit.isActive && !unit.isFailed,
      };
      if (!matchesFilter) return false;
      if (query.isEmpty) return true;
      return unit.name.toLowerCase().contains(query) ||
          unit.description.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.connected) {
      return _ServicesEmpty(
        icon: Symbols.link_off,
        message: widget.connectionError ?? 'systemdConnectToManage'.tr(),
        actionLabel: 'commonConnect'.tr(),
        onAction: widget.onConnect,
        filled: true,
      );
    }

    return _snapshot.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ServicesEmpty(
        icon: Symbols.error_outline,
        message: 'systemdLoadError'.tr(args: ['$error']),
        actionLabel: 'systemdTryAgain'.tr(),
        onAction: _load,
      ),
      data: (snapshot) {
        if (!snapshot.available) {
          return _ServicesEmpty(
            icon: Symbols.settings_applications,
            message: snapshot.error ?? 'systemdNotAvailable'.tr(),
            actionLabel: 'commonRefresh'.tr(),
            onAction: _load,
          );
        }

        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final filtered = _filtered(snapshot.units);

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
                      Icon(
                        Symbols.settings_applications,
                        size: 20,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'systemdServices'.tr(),
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${snapshot.activeCount} active · '
                        '${snapshot.failedCount} failed · '
                        '${snapshot.units.length} total',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
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
                        onPressed: _busy ? null : _refreshManually,
                        icon: const Icon(Symbols.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchController,
                    enabled: !_busy,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'systemdFilterHint'.tr(),
                      prefixIcon: const Icon(Symbols.search, size: 20),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'systemdClearFilter'.tr(),
                              onPressed: () => _searchController.clear(),
                              icon: const Icon(Symbols.close, size: 18),
                            ),
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final filter in _ServiceFilter.values)
                        FilterChip(
                          label: Text(_filterLabel(filter, snapshot)),
                          selected: _filter == filter,
                          onSelected: _busy
                              ? null
                              : (_) => setState(() => _filter = filter),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Expanded(
              child: filtered.isEmpty
                  ? _ServicesEmpty(
                      icon: Symbols.settings_applications,
                      message: snapshot.units.isEmpty
                          ? 'systemdNoServices'.tr()
                          : 'systemdNoFilterMatch'.tr(),
                      actionLabel: 'commonRefresh'.tr(),
                      onAction: _load,
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: scheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                      itemBuilder: (context, index) {
                        final unit = filtered[index];
                        final unitBusy = _busyUnit == unit.name;
                        return _ServiceTile(
                          unit: unit,
                          busy: unitBusy || _busy,
                          onAction: (action) => _onAction(unit, action),
                          onStatus: () => _showStatus(unit),
                          onLogs: () => _showLogs(unit),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  String _filterLabel(_ServiceFilter filter, SystemdUnitsSnapshot snapshot) {
    return switch (filter) {
      _ServiceFilter.all => 'systemdFilterAll'.tr(
        args: ['${snapshot.units.length}'],
      ),
      _ServiceFilter.active => 'systemdFilterActive'.tr(
        args: ['${snapshot.activeCount}'],
      ),
      _ServiceFilter.failed => 'systemdFilterFailed'.tr(
        args: ['${snapshot.failedCount}'],
      ),
      _ServiceFilter.inactive => 'systemdFilterInactive'.tr(
        args: [
          '${snapshot.units.where((u) => !u.isActive && !u.isFailed).length}',
        ],
      ),
    };
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.unit,
    required this.busy,
    required this.onAction,
    required this.onStatus,
    required this.onLogs,
  });

  final SystemdUnit unit;
  final bool busy;
  final void Function(SystemdUnitAction action) onAction;
  final VoidCallback onStatus;
  final VoidCallback onLogs;

  Menu _menu() => Menu(
    children: [
      if (!unit.isActive)
        MenuAction(
          title: 'systemdStart'.tr(),
          image: MenuImage.icon(Symbols.play_arrow),
          callback: () => onAction(SystemdUnitAction.start),
        ),
      if (unit.isActive) ...[
        MenuAction(
          title: 'systemdStop'.tr(),
          image: MenuImage.icon(Symbols.stop),
          callback: () => onAction(SystemdUnitAction.stop),
        ),
        MenuAction(
          title: 'systemdRestart'.tr(),
          image: MenuImage.icon(Symbols.restart_alt),
          callback: () => onAction(SystemdUnitAction.restart),
        ),
        MenuAction(
          title: 'systemdReload'.tr(),
          image: MenuImage.icon(Symbols.sync),
          callback: () => onAction(SystemdUnitAction.reload),
        ),
      ],
      if (unit.canEnable)
        MenuAction(
          title: 'systemdEnableBoot'.tr(),
          image: MenuImage.icon(Symbols.toggle_on),
          callback: () => onAction(SystemdUnitAction.enable),
        ),
      if (unit.canDisable)
        MenuAction(
          title: 'systemdDisableBoot'.tr(),
          image: MenuImage.icon(Symbols.toggle_off),
          callback: () => onAction(SystemdUnitAction.disable),
        ),
      MenuSeparator(),
      MenuAction(
        title: 'systemdStatus'.tr(),
        image: MenuImage.icon(Symbols.info),
        callback: onStatus,
      ),
      MenuAction(
        title: 'systemdLogs'.tr(),
        image: MenuImage.icon(Symbols.terminal),
        callback: onLogs,
      ),
    ],
  );

  void _onPopupSelected(_ServiceMenuAction value) {
    switch (value) {
      case _ServiceMenuAction.start:
        onAction(SystemdUnitAction.start);
      case _ServiceMenuAction.stop:
        onAction(SystemdUnitAction.stop);
      case _ServiceMenuAction.restart:
        onAction(SystemdUnitAction.restart);
      case _ServiceMenuAction.reload:
        onAction(SystemdUnitAction.reload);
      case _ServiceMenuAction.enable:
        onAction(SystemdUnitAction.enable);
      case _ServiceMenuAction.disable:
        onAction(SystemdUnitAction.disable);
      case _ServiceMenuAction.status:
        onStatus();
      case _ServiceMenuAction.logs:
        onLogs();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColor = unit.isFailed
        ? scheme.error
        : unit.isActive
        ? scheme.primary
        : scheme.onSurfaceVariant;

    return AppContextMenuRegion(
      enabled: !busy,
      menuBuilder: _menu,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(
          unit.isFailed
              ? Symbols.error
              : unit.isActive
              ? Symbols.play_circle
              : Symbols.stop_circle,
          color: statusColor,
        ),
        title: Text(
          unit.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontFamily: MaidKitFonts.mono,
            fontSize: 13,
          ),
        ),
        subtitle: Text(
          [
            unit.statusLabel,
            unit.enablementLabel,
            if (unit.description.isNotEmpty) unit.description,
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        trailing: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : PopupMenuButton<_ServiceMenuAction>(
                tooltip: 'systemdActions'.tr(),
                onSelected: _onPopupSelected,
                itemBuilder: (context) => [
                  if (!unit.isActive)
                    PopupMenuItem(
                      value: _ServiceMenuAction.start,
                      child: Text('systemdStart'.tr()),
                    ),
                  if (unit.isActive) ...[
                    PopupMenuItem(
                      value: _ServiceMenuAction.stop,
                      child: Text('systemdStop'.tr()),
                    ),
                    PopupMenuItem(
                      value: _ServiceMenuAction.restart,
                      child: Text('systemdRestart'.tr()),
                    ),
                    PopupMenuItem(
                      value: _ServiceMenuAction.reload,
                      child: Text('systemdReload'.tr()),
                    ),
                  ],
                  if (unit.canEnable)
                    PopupMenuItem(
                      value: _ServiceMenuAction.enable,
                      child: Text('systemdEnableBoot'.tr()),
                    ),
                  if (unit.canDisable)
                    PopupMenuItem(
                      value: _ServiceMenuAction.disable,
                      child: Text('systemdDisableBoot'.tr()),
                    ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: _ServiceMenuAction.status,
                    child: Text('systemdStatus'.tr()),
                  ),
                  PopupMenuItem(
                    value: _ServiceMenuAction.logs,
                    child: Text('systemdLogs'.tr()),
                  ),
                ],
              ),
        onTap: busy ? null : onStatus,
      ),
    );
  }
}

enum _ServiceMenuAction {
  start,
  stop,
  restart,
  reload,
  enable,
  disable,
  status,
  logs,
}

class _UnitTextSheet extends StatefulWidget {
  const _UnitTextSheet({required this.title, required this.load});

  final String title;
  final Future<String> Function() load;

  @override
  State<_UnitTextSheet> createState() => _UnitTextSheetState();
}

class _UnitTextSheetState extends State<_UnitTextSheet> {
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
      message: 'commonCopiedToClipboard'.tr(),
      title: 'systemdServices'.tr(),
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
          tooltip: 'commonCopy'.tr(),
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
                    'systemdCouldNotLoad'.tr(args: ['${snapshot.error}']),
                    style: TextStyle(color: scheme.error),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonal(
                      onPressed: () => setState(_reload),
                      child: const Text('commonRetry').tr(),
                    ),
                  ),
                ],
              ),
            );
          }
          final text = snapshot.data ?? '';
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

class _ServicesEmpty extends StatelessWidget {
  const _ServicesEmpty({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.filled = false,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
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
            Icon(icon, size: 36, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (onAction != null) ...[
              const SizedBox(height: 16),
              filled
                  ? FilledButton(onPressed: onAction, child: Text(actionLabel))
                  : TextButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ],
        ),
      ),
    );
  }
}
