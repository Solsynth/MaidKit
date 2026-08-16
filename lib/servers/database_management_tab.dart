import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:styled_widget/styled_widget.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/shared/presentation/deploy_terminal.dart';
import 'package:maid_kit/shared/presentation/maidkit_alert.dart';
import 'database_models.dart';
import 'maidcafe_service.dart';
import 'maidcafe_session_registry.dart';
import 'maidcafe_stream.dart';
import 'server_connection_actions.dart';
import 'server_models.dart';
import 'server_providers.dart';
import 'systemd_models.dart';

/// Live database health snapshot plus rates derived from the previous one.
typedef _DatabaseMetrics = ({
  DatabaseEngineMetrics entry,
  DatabaseMetricsRates rates,
});

/// Database-layer management: engine inspection, logical backups / restores,
/// quick maintenance, and pgBackRest. Everything runs over the retained SSH
/// session so the tab works with or without a MaidCafe daemon.
class DatabaseManagementTab extends ConsumerStatefulWidget {
  const DatabaseManagementTab({
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
  ConsumerState<DatabaseManagementTab> createState() =>
      _DatabaseManagementTabState();
}

class _DatabaseManagementTabState extends ConsumerState<DatabaseManagementTab> {
  AsyncValue<DatabaseInspectionResult> _result = const AsyncValue.loading();
  DatabaseEngine? _engine;
  final _backupDirectory = TextEditingController();
  var _busy = false;
  var _revision = 0;
  DatabaseEngine? _directoryEngine;

  late final MaidCafeSessionRegistry _sessionRegistry;
  MaidCafeStreamSession? _maidCafeStream;
  StreamSubscription<MaidCafeStreamEvent>? _metricsSubscription;
  var _metricsSseActive = false;
  var _metricsSseAttempted = false;
  DateTime _lastMetricsEvent = DateTime.fromMillisecondsSinceEpoch(0);
  int _metricsSseIntervalSeconds = 10;
  AsyncValue<_DatabaseMetrics?> _metrics = const AsyncValue.data(null);
  DatabaseMetricsSnapshot? _metricsPrevious;
  DateTime? _metricsPreviousAt;
  Timer? _metricsTimer;

  bool get _isRoot => widget.server.username == 'root';

  DatabaseInstance? get _instance {
    final engine = _engine;
    if (engine == null) return null;
    return _result.asData?.value.instanceFor(engine);
  }

  @override
  void initState() {
    super.initState();
    _sessionRegistry = ref.read(maidCafeSessionRegistryProvider);
    _sessionRegistry.retain(widget.server);
    if (widget.connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _load();
        _startMetricsTimer();
        unawaited(_startMetricsSse());
        unawaited(_loadMetrics());
      });
    }
  }

  @override
  void didUpdateWidget(DatabaseManagementTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final serverChanged = oldWidget.server.id != widget.server.id;
    if (serverChanged) {
      _sessionRegistry.release(oldWidget.server);
      _sessionRegistry.retain(widget.server);
      _closeMetricsSse();
      _maidCafeStream = null;
      _metricsSseAttempted = false;
      _metricsPrevious = null;
      _metricsPreviousAt = null;
      _metrics = const AsyncValue.data(null);
    }
    if (widget.connected && (!oldWidget.connected || serverChanged)) {
      if (serverChanged) {
        _engine = null;
        _backupDirectory.clear();
        _result = const AsyncValue.loading();
      }
      _load();
      _startMetricsTimer();
      if (!_metricsSseActive) {
        _metricsSseAttempted = false;
        unawaited(_startMetricsSse());
      }
      unawaited(_loadMetrics());
    } else if (!widget.connected && oldWidget.connected) {
      _closeMetricsSse();
      _metricsTimer?.cancel();
      _metricsTimer = null;
      _metricsSseAttempted = false;
      _sessionRegistry.invalidate(widget.server);
      _maidCafeStream = null;
    }
  }

  @override
  void dispose() {
    _metricsTimer?.cancel();
    _closeMetricsSse();
    _sessionRegistry.release(widget.server);
    _backupDirectory.dispose();
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
    setState(() => _result = const AsyncValue.loading());
    try {
      final result = await ref
          .read(connectionManagerProvider)
          .inspectDatabases(
            widget.server.id,
            sshUserIsRoot: _isRoot,
            sudoPassword: await _sudoPassword(),
          );
      if (!mounted) return;
      setState(() {
        _result = AsyncValue.data(result);
        // Prefer PostgreSQL when present (primary engine), otherwise the
        // first detected engine.
        final selected = _engine;
        final engine = selected != null && result.instanceFor(selected) != null
            ? selected
            : result.instanceFor(DatabaseEngine.postgres) != null
            ? DatabaseEngine.postgres
            : result.instances.firstOrNull?.engine;
        _engine = engine;
        if (engine != null &&
            (engine != _directoryEngine || _backupDirectory.text.isEmpty)) {
          _backupDirectory.text = _defaultBackupDirectory(engine);
          _directoryEngine = engine;
        }
        _revision++;
      });
      unawaited(_loadMetrics(force: true));
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() => _result = AsyncValue.error(error, stackTrace));
      }
    }
  }

  String _defaultBackupDirectory(DatabaseEngine engine) => switch (engine) {
    DatabaseEngine.postgres => '/var/backups/postgresql',
    DatabaseEngine.mysql || DatabaseEngine.mariadb => '/var/backups/mysql',
  };

  void _selectEngine(DatabaseEngine engine) {
    setState(() {
      _engine = engine;
      _directoryEngine = engine;
      _backupDirectory.text = _defaultBackupDirectory(engine);
      _revision++;
      _metricsPrevious = null;
      _metricsPreviousAt = null;
      _metrics = const AsyncValue.data(null);
    });
    unawaited(_loadMetrics(force: true));
  }

  // ---------------------------------------------------------------------
  // Performance metrics (daemon `databaseMetrics` SSE first, SSH fallback)
  // ---------------------------------------------------------------------

  void _startMetricsTimer() {
    _metricsTimer?.cancel();
    _metricsTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _onMetricsTick(),
    );
  }

  Future<void> _onMetricsTick() async {
    if (!mounted || !widget.connected) return;
    if (_metricsSseActive) {
      final silence = DateTime.now().difference(_lastMetricsEvent);
      final timeoutSeconds = _metricsSseIntervalSeconds * 3 >= 15
          ? _metricsSseIntervalSeconds * 3
          : 15;
      if (silence > Duration(seconds: timeoutSeconds)) {
        // The stream stays connected (heartbeats) but stopped delivering
        // data — the daemon collector may be disabled or failing. Fall
        // back to on-demand fetches instead of freezing the cards.
        _metricsSseAttempted = true;
        _closeMetricsSse();
      } else {
        return;
      }
    }
    if (_metricsSubscription == null && !_metricsSseAttempted) {
      await _startMetricsSse();
    }
    if (_metricsSseActive) return;
    await _loadMetrics(force: true);
  }

  Future<void> _loadMetrics({bool force = false}) async {
    if (!mounted || !widget.connected) return;
    if (_metricsSseActive && !force) return;
    final engine = _engine;
    if (engine == null) return;
    if (!force && _metrics.asData?.value == null && !_metrics.isLoading) {
      setState(() => _metrics = const AsyncValue.loading());
    }
    final session = await _ensureMaidCafeStream();
    if (session != null) {
      try {
        final snapshot = parseMaidCafeDatabaseMetrics(
          await session.databaseMetrics(),
        );
        final entry = snapshot.forEngine(engine);
        if (entry != null && mounted) {
          _applyMetrics(snapshot, entry);
          return;
        }
      } catch (_) {
        // Old daemon without /api/v1/database-metrics: fall back to SSH.
      }
    }
    try {
      final snapshot = await ref
          .read(connectionManagerProvider)
          .refreshDatabaseMetrics(
            widget.server.id,
            engine: engine,
            sshUserIsRoot: _isRoot,
            sudoPassword: await _sudoPassword(),
          );
      if (!mounted) return;
      final entry = snapshot?.forEngine(engine);
      if (entry == null) {
        setState(() => _metrics = const AsyncValue.data(null));
        return;
      }
      _applyMetrics(snapshot!, entry);
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() => _metrics = AsyncValue.error(error, stackTrace));
      }
    }
  }

  void _applyMetrics(
    DatabaseMetricsSnapshot snapshot,
    DatabaseEngineMetrics entry,
  ) {
    final engine = _engine;
    if (engine == null || !mounted) return;
    final rates = computeDatabaseRates(
      previous: _metricsPrevious?.forEngine(engine),
      previousAt: _metricsPreviousAt,
      current: entry,
      currentAt: snapshot.collectedAt,
    );
    setState(() {
      _metricsPrevious = snapshot;
      _metricsPreviousAt = snapshot.collectedAt;
      _metrics = AsyncValue.data((entry: entry, rates: rates));
    });
  }

  Future<void> _startMetricsSse() async {
    if (_metricsSubscription != null || _metricsSseAttempted) return;
    final session = await _ensureMaidCafeStream();
    if (session == null || !mounted) return;
    try {
      final events = session.openStream(
        events: const {MaidCafeStreamEventType.databaseMetrics},
      );
      final subscription = events.listen(
        _onMetricsEvent,
        onError: (Object error, StackTrace stackTrace) {
          _metricsSseAttempted = true;
          _closeMetricsSse();
        },
        onDone: () {
          _metricsSseAttempted = true;
          _closeMetricsSse();
        },
      );
      _metricsSubscription = subscription;
    } catch (_) {
      _metricsSseAttempted = true;
      _closeMetricsSse();
    }
  }

  void _onMetricsEvent(MaidCafeStreamEvent event) {
    if (!mounted) return;
    if (event.type == MaidCafeStreamEventType.hello) {
      _lastMetricsEvent = DateTime.now();
      final intervals = event.data['intervals'];
      if (intervals is Map) {
        final seconds = intervals['databaseMetrics'];
        if (seconds is num && seconds > 0) {
          _metricsSseIntervalSeconds = seconds.toInt();
        }
      }
      return;
    }
    if (event.type != MaidCafeStreamEventType.databaseMetrics) return;
    _lastMetricsEvent = DateTime.now();
    final engine = _engine;
    if (engine == null) return;
    final snapshot = parseMaidCafeDatabaseMetrics(event.data);
    final entry = snapshot.forEngine(engine);
    if (entry == null) return;
    setState(() => _metricsSseActive = true);
    _applyMetrics(snapshot, entry);
  }

  Future<MaidCafeStreamSession?> _ensureMaidCafeStream() async {
    final cached = _maidCafeStream;
    if (cached != null && !cached.isClosed) return cached;
    _maidCafeStream = null;
    final session = await _sessionRegistry.sessionFor(widget.server);
    if (session != null) {
      _maidCafeStream = session;
      if (!identical(session, cached)) {
        _metricsSseAttempted = false;
      }
    }
    return session;
  }

  void _closeMetricsSse() {
    final subscription = _metricsSubscription;
    _metricsSubscription = null;
    _metricsSseActive = false;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
  }

  /// Runs a remote database task in the shared deploy terminal, retrying
  /// after a connection drop (mirrors the package tab flow).
  Future<void> _runDbTask({
    required String title,
    required String command,
    required String successMessage,
    required Future<void> Function(void Function(String chunk) onOutput) task,
    Future<void> Function()? after,
    bool canRetryConnection = true,
  }) async {
    setState(() => _busy = true);
    try {
      await runWithDeployTerminal(
        ref: ref,
        title: title,
        subtitle: widget.server.name,
        command: command,
        run: task,
      );
      if (!mounted) return;
      showStyledSnackBar(
        message: successMessage,
        title: title,
        icon: Symbols.check_circle,
        accentColor: Theme.of(context).colorScheme.primary,
      );
      await after?.call();
    } catch (error) {
      if (!mounted) return;
      final shouldRetry =
          canRetryConnection &&
          await shouldReconnectAndRetry(context, error, widget.server);
      if (!mounted) return;
      if (shouldRetry) {
        await widget.onConnect();
        if (mounted) {
          await _runDbTask(
            title: title,
            command: command,
            successMessage: successMessage,
            task: task,
            after: after,
            canRetryConnection: false,
          );
        }
        return;
      }
      showStyledSnackBar(
        message: error.toString(),
        title: title,
        icon: Symbols.error,
        accentColor: Theme.of(context).colorScheme.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restartService(DatabaseInstance instance) async {
    final unit = instance.serviceName;
    if (unit == null) return;
    final approved = await showMaidKitConfirmAlert(
      'dbServiceRestartConfirm'.tr(args: [unit]),
      'dbServiceRestart'.tr(),
      icon: Symbols.restart_alt,
    );
    if (!approved || !mounted) return;
    await _runDbTask(
      title: 'dbServiceRestart'.tr(),
      command: 'systemctl restart $unit',
      successMessage: 'dbServiceRestartSuccess'.tr(),
      task: (onOutput) async {
        await ref
            .read(connectionManagerProvider)
            .runSystemdUnitAction(
              widget.server.id,
              unit: unit,
              action: SystemdUnitAction.restart,
              sshUserIsRoot: _isRoot,
              sudoPassword: await _sudoPassword(),
            );
        onOutput('systemctl restart $unit\n');
      },
      after: _load,
    );
  }

  Future<void> _backupDatabase(DatabaseInstance instance) async {
    final databases = instance.databases;
    if (databases.isEmpty) return;
    final directory = _backupDirectory.text.trim();
    final result = await showModalBottomSheet<String?>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (sheetContext) => _BackupSheet(
        engine: instance.engine,
        databases: databases.map((db) => db.name).toList(),
        initialDirectory: directory,
      ),
    );
    if (result == null || !mounted) return;
    final parts = result.split('\n');
    final database = parts[0];
    final targetDirectory = parts.length > 1 ? parts[1] : directory;
    await _runDbTask(
      title: 'dbBackupDatabase'.tr(args: [database]),
      command: '$database → $targetDirectory',
      successMessage: 'dbBackupSuccess'.tr(),
      task: (onOutput) async {
        final saved = await ref
            .read(connectionManagerProvider)
            .runDatabaseBackup(
              widget.server.id,
              engine: instance.engine,
              database: database,
              directory: targetDirectory,
              sshUserIsRoot: _isRoot,
              sudoPassword: await _sudoPassword(),
              mysqlPassword: await _mysqlPassword(),
              onOutput: onOutput,
            );
        onOutput('\n$saved\n');
      },
      after: _load,
    );
  }

  Future<void> _restoreDatabase(DatabaseInstance instance) async {
    final databases = instance.databases;
    if (databases.isEmpty) return;
    final result = await showModalBottomSheet<_RestoreChoice?>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (sheetContext) => _RestoreSheet(
        server: widget.server,
        engine: instance.engine,
        databases: databases.map((db) => db.name).toList(),
        directory: _backupDirectory.text.trim(),
        isRoot: _isRoot,
      ),
    );
    if (result == null || !mounted) return;
    final approved = await showMaidKitConfirmAlert(
      'dbRestoreConfirm'.tr(args: [result.database, result.file]),
      'dbRestore'.tr(),
      icon: Symbols.restore,
      isDanger: true,
    );
    if (!approved || !mounted) return;
    await _runDbTask(
      title: 'dbRestore'.tr(),
      command: '${result.file} → ${result.database}',
      successMessage: 'dbRestoreSuccess'.tr(),
      task: (onOutput) async {
        return ref
            .read(connectionManagerProvider)
            .restoreDatabaseBackup(
              widget.server.id,
              engine: instance.engine,
              database: result.database,
              file: result.file,
              sshUserIsRoot: _isRoot,
              sudoPassword: await _sudoPassword(),
              mysqlPassword: result.mysqlPassword,
              onOutput: onOutput,
            );
      },
      after: _load,
    );
  }

  Future<void> _runMaintenance(DatabaseInstance instance) async {
    final databases = instance.databases;
    if (databases.isEmpty) return;
    final result = await showModalBottomSheet<_MaintenanceChoice?>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (sheetContext) => _MaintenanceSheet(
        engine: instance.engine,
        databases: databases.map((db) => db.name).toList(),
      ),
    );
    if (result == null || !mounted) return;
    await _runDbTask(
      title: result.action.label,
      command: '${result.database} · ${result.action.label}',
      successMessage: 'dbMaintenanceSuccess'.tr(),
      task: (onOutput) async {
        return ref
            .read(connectionManagerProvider)
            .runDatabaseMaintenance(
              widget.server.id,
              engine: instance.engine,
              database: result.database,
              action: result.action,
              sshUserIsRoot: _isRoot,
              sudoPassword: await _sudoPassword(),
              mysqlPassword: result.mysqlPassword,
              onOutput: onOutput,
            );
      },
      after: _load,
    );
  }

  Future<void> _deleteBackup(DatabaseBackupFile file) async {
    final approved = await showMaidKitConfirmAlert(
      'dbDeleteBackupConfirm'.tr(args: [file.name]),
      'dbDeleteBackup'.tr(),
      icon: Symbols.delete,
      isDanger: true,
    );
    if (!approved || !mounted) return;
    await _runDbTask(
      title: 'dbDeleteBackup'.tr(),
      command: 'rm ${file.path}',
      successMessage: 'dbDeleteBackupSuccess'.tr(),
      task: (onOutput) async {
        return ref
            .read(connectionManagerProvider)
            .deleteDatabaseBackup(
              widget.server.id,
              file: file.path,
              sshUserIsRoot: _isRoot,
              sudoPassword: await _sudoPassword(),
            );
      },
      after: _load,
    );
  }

  Future<void> _pgBackRestBackup(PgBackRestStatus status) async {
    final stanzas = status.stanzas;
    if (stanzas.isEmpty) return;
    final result = await showModalBottomSheet<_PgBackRestBackupChoice?>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (sheetContext) => _PgBackRestBackupSheet(
        stanzas: stanzas.map((stanza) => stanza.name).toList(),
      ),
    );
    if (result == null || !mounted) return;
    await _runDbTask(
      title: 'dbPgBackRestBackupNow'.tr(),
      command: 'pgbackrest --stanza=${result.stanza} --type=${result.type}',
      successMessage: 'dbBackupSuccess'.tr(),
      task: (onOutput) async {
        return ref
            .read(connectionManagerProvider)
            .runPgBackRestBackup(
              widget.server.id,
              stanza: result.stanza,
              type: result.type,
              sshUserIsRoot: _isRoot,
              sudoPassword: await _sudoPassword(),
              onOutput: onOutput,
            );
      },
      after: _load,
    );
  }

  Future<void> _pgBackRestRestore(
    PgBackRestStanza stanza,
    DatabaseInstance? instance,
  ) async {
    final result = await showModalBottomSheet<String?>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (sheetContext) => _PgBackRestRestoreSheet(stanza: stanza),
    );
    if (result == null || !mounted) return;
    final approved = await showMaidKitConfirmAlert(
      'dbPgBackRestRestoreConfirm'.tr(
        args: [stanza.name, instance?.serviceName ?? ''],
      ),
      'dbPgBackRestRestore'.tr(),
      icon: Symbols.restore,
      isDanger: true,
    );
    if (!approved || !mounted) return;
    await _runDbTask(
      title: 'dbPgBackRestRestore'.tr(),
      command: 'pgbackrest --stanza=${stanza.name} restore',
      successMessage: 'dbRestoreSuccess'.tr(),
      task: (onOutput) async {
        return ref
            .read(connectionManagerProvider)
            .runPgBackRestRestore(
              widget.server.id,
              stanza: stanza.name,
              set: result.isEmpty ? null : result,
              serviceUnit: instance?.serviceName,
              sshUserIsRoot: _isRoot,
              sudoPassword: await _sudoPassword(),
              onOutput: onOutput,
            );
      },
      after: _load,
    );
  }

  Future<String?> _mysqlPassword() async {
    final instance = _instance;
    if (instance == null || !instance.engine.isMySqlLike) return null;
    // Passwordless socket / debian.cnf auth is tried first on the host; ask
    // for a password only when the user is running a MySQL-like engine whose
    // databases could not be enumerated without credentials.
    if (instance.error == null) return null;
    final controller = TextEditingController();
    final password = await showMaidKitOverlayDialog<String?>(
      builder: (context, close) => AlertDialog(
        title: Text('dbMysqlPassword'.tr()),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: InputDecoration(hintText: 'dbMysqlPasswordHint'.tr()),
          onSubmitted: (_) => close(controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => close(null),
            child: Text('commonCancel'.tr()),
          ),
          FilledButton(
            onPressed: () => close(controller.text),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    );
    controller.dispose();
    return password == null || password.isEmpty ? null : password;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.connected) {
      return _DbEmptyPanel(
        icon: Symbols.link_off,
        message: widget.connectionError ?? 'dbConnectToManage'.tr(),
        actionLabel: 'commonConnect'.tr(),
        onAction: widget.onConnect,
      );
    }
    return _result.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _DbEmptyPanel(
        icon: Symbols.error_outline,
        message: 'dbInspectError'.tr(args: ['$error']),
        actionLabel: 'commonRetry'.tr(),
        onAction: _load,
      ),
      data: (result) => result.instances.isEmpty
          ? _DbEmptyPanel(
              icon: Symbols.database,
              message: 'dbNoEngines'.tr(),
              actionLabel: 'commonRefresh'.tr(),
              onAction: _load,
            )
          : _buildContent(result),
    );
  }

  Widget _buildContent(DatabaseInspectionResult result) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final instances = result.instances;
    final engine = _engine;
    final instance = engine == null ? null : result.instanceFor(engine);
    final pgBackRest = result.pgBackRest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Text(
                'detailDatabases'.tr(),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (instances.length > 1) ...[
                SegmentedButton<DatabaseEngine>(
                  segments: [
                    for (final instance in instances)
                      ButtonSegment<DatabaseEngine>(
                        value: instance.engine,
                        label: Text(instance.engine.label),
                        icon: Icon(_engineIcon(instance.engine), size: 16),
                      ),
                  ],
                  selected: {?engine},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) =>
                      _selectEngine(selection.first),
                ),
                const SizedBox(width: 8),
              ],
              IconButton(
                tooltip: 'commonRefresh'.tr(),
                visualDensity: VisualDensity.compact,
                onPressed: _busy ? null : _load,
                icon: const Icon(Symbols.refresh),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (instance != null) ...[
                _PerformanceCard(
                  engine: instance.engine,
                  metrics: _metrics,
                  onRefresh: () => _loadMetrics(force: true),
                ),
                const SizedBox(height: 16),
                _InstanceCard(
                  instance: instance,
                  busy: _busy,
                  onRestart: instance.serviceName == null
                      ? null
                      : () => _restartService(instance),
                ),
                const SizedBox(height: 16),
                _DatabasesCard(
                  instance: instance,
                  busy: _busy,
                  onBackup: () => _backupDatabase(instance),
                  onRestore: () => _restoreDatabase(instance),
                  onMaintenance: () => _runMaintenance(instance),
                ),
                const SizedBox(height: 16),
                if (engine == DatabaseEngine.postgres &&
                    pgBackRest.installed) ...[
                  _PgBackRestCard(
                    status: pgBackRest,
                    serviceUnit: instance.serviceName,
                    busy: _busy,
                    onBackup: () => _pgBackRestBackup(pgBackRest),
                    onRestore: (stanza) => _pgBackRestRestore(stanza, instance),
                  ),
                  const SizedBox(height: 16),
                ],
                _BackupsCard(
                  server: widget.server,
                  engine: instance.engine,
                  directoryController: _backupDirectory,
                  revision: _revision,
                  busy: _busy,
                  isRoot: _isRoot,
                  onBackup: () => _backupDatabase(instance),
                  onRestore: (file) => _restoreFile(instance, file),
                  onDelete: (file) => _deleteBackup(file),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _restoreFile(
    DatabaseInstance instance,
    DatabaseBackupFile file,
  ) async {
    final databases = instance.databases;
    if (databases.isEmpty) return;
    final result = await showModalBottomSheet<_RestoreChoice?>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (sheetContext) => _RestoreSheet(
        server: widget.server,
        engine: instance.engine,
        databases: databases.map((db) => db.name).toList(),
        directory: _backupDirectory.text.trim(),
        isRoot: _isRoot,
        initialFile: file.path,
      ),
    );
    if (result == null || !mounted) return;
    final approved = await showMaidKitConfirmAlert(
      'dbRestoreConfirm'.tr(args: [result.database, result.file]),
      'dbRestore'.tr(),
      icon: Symbols.restore,
      isDanger: true,
    );
    if (!approved || !mounted) return;
    await _runDbTask(
      title: 'dbRestore'.tr(),
      command: '${result.file} → ${result.database}',
      successMessage: 'dbRestoreSuccess'.tr(),
      task: (onOutput) async {
        return ref
            .read(connectionManagerProvider)
            .restoreDatabaseBackup(
              widget.server.id,
              engine: instance.engine,
              database: result.database,
              file: result.file,
              sshUserIsRoot: _isRoot,
              sudoPassword: await _sudoPassword(),
              mysqlPassword: result.mysqlPassword,
              onOutput: onOutput,
            );
      },
      after: _load,
    );
  }

  static IconData _engineIcon(DatabaseEngine engine) => switch (engine) {
    DatabaseEngine.postgres => Symbols.database,
    DatabaseEngine.mysql || DatabaseEngine.mariadb => Symbols.storage,
  };
}

String _formatBytes(int? bytes) {
  if (bytes == null) return '—';
  if (bytes >= 1 << 30) {
    return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1 << 20) {
    return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1 << 10) {
    return '${(bytes / (1 << 10)).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}

String _formatTimestamp(DateTime? time) {
  if (time == null) return '—';
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}';
}

String _formatPerSecond(double value) {
  if (value >= 100) return '${value.toStringAsFixed(0)}/s';
  if (value >= 10) return '${value.toStringAsFixed(1)}/s';
  return '${value.toStringAsFixed(2)}/s';
}

String _formatDuration(int seconds) {
  if (seconds < 60) return '${seconds}s';
  if (seconds < 3600) return '${(seconds / 60).toStringAsFixed(0)}m';
  if (seconds < 86400) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    return '${hours}h ${minutes}m';
  }
  final days = seconds ~/ 86400;
  final hours = (seconds % 86400) ~/ 3600;
  return '${days}d ${hours}h';
}

class _PerformanceCard extends StatelessWidget {
  const _PerformanceCard({
    required this.engine,
    required this.metrics,
    required this.onRefresh,
  });

  final DatabaseEngine engine;
  final AsyncValue<_DatabaseMetrics?> metrics;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _DbSection(
      title: 'dbPerformance'.tr(),
      icon: Symbols.monitoring,
      trailing: IconButton(
        tooltip: 'commonRefresh'.tr(),
        visualDensity: VisualDensity.compact,
        onPressed: onRefresh,
        icon: const Icon(Symbols.refresh),
      ),
      child: metrics.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(12),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        error: (error, _) => Row(
          children: [
            Expanded(
              child: Text(
                'dbMetricsError'.tr(args: ['$error']),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton(onPressed: onRefresh, child: Text('commonRetry'.tr())),
          ],
        ),
        data: (data) {
          final value = data;
          if (value == null) {
            return Row(
              children: [
                Expanded(
                  child: Text(
                    'dbMetricsUnavailable'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onRefresh,
                  child: Text('commonRetry'.tr()),
                ),
              ],
            );
          }
          final entry = value.entry;
          final rates = value.rates;
          if (!entry.available) {
            return Text(
              entry.error ?? 'dbMetricsUnavailable'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            );
          }
          return _MetricsBody(engine: engine, entry: entry, rates: rates);
        },
      ),
    );
  }
}

class _MetricsBody extends StatelessWidget {
  const _MetricsBody({
    required this.engine,
    required this.entry,
    required this.rates,
  });

  final DatabaseEngine engine;
  final DatabaseEngineMetrics entry;
  final DatabaseMetricsRates rates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final connections = entry.connections;
    final maxConnections = entry.maxConnections;
    final hitRatio = entry.cacheHitRatio;

    final memoryLabel = engine.isPostgres
        ? 'dbSharedBuffers'.tr()
        : 'dbBufferPool'.tr();
    final memoryValue = engine.isPostgres
        ? _formatBytes(entry.memoryBytes)
        : entry.memoryBytes == null
        ? '—'
        : '${_formatBytes(entry.memoryUsedBytes)} / '
              '${_formatBytes(entry.memoryBytes)}';

    final throughput = engine.isPostgres
        ? (
            label: 'dbTps'.tr(),
            value: rates.transactionsPerSecond == null
                ? '—'
                : _formatPerSecond(rates.transactionsPerSecond!),
          )
        : (
            label: 'dbQps'.tr(),
            value: rates.queriesPerSecond == null
                ? '—'
                : _formatPerSecond(rates.queriesPerSecond!),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            _MetricsTile(
              label: 'dbConnections'.tr(),
              value: connections == null
                  ? '—'
                  : maxConnections == null
                  ? '$connections'
                  : '$connections / $maxConnections',
              progress: connections != null && maxConnections != null
                  ? connections / maxConnections
                  : null,
            ),
            _MetricsTile(
              label: 'dbCacheHitRatio'.tr(),
              value: hitRatio == null
                  ? '—'
                  : '${(hitRatio * 100).toStringAsFixed(1)}%',
              progress: hitRatio,
            ),
            _MetricsTile(
              label: memoryLabel,
              value: memoryValue,
              progress: entry.memoryBytes == null || entry.memoryBytes == 0
                  ? null
                  : (entry.memoryUsedBytes ?? 0) / entry.memoryBytes!,
            ),
            _MetricsTile(label: throughput.label, value: throughput.value),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            for (final (label, value) in [
              if (engine.isPostgres) ...[
                (
                  'dbDeadlocks'.tr(),
                  entry.deadlocks == null ? '—' : '${entry.deadlocks}',
                ),
                (
                  'dbTempBytes'.tr(),
                  entry.tempBytes == null ? '—' : _formatBytes(entry.tempBytes),
                ),
                (
                  'dbRollbacks'.tr(),
                  entry.rollbacks == null ? '—' : '${entry.rollbacks}',
                ),
              ] else ...[
                (
                  'dbSlowQueries'.tr(),
                  entry.slowQueries == null ? '—' : '${entry.slowQueries}',
                ),
                (
                  'dbThreadsRunning'.tr(),
                  entry.threadsRunning == null
                      ? '—'
                      : '${entry.threadsRunning}',
                ),
                (
                  'dbMaxUsedConnections'.tr(),
                  entry.maxUsedConnections == null
                      ? '—'
                      : '${entry.maxUsedConnections}',
                ),
              ],
              (
                'dbUptime'.tr(),
                entry.uptimeSeconds == null
                    ? '—'
                    : _formatDuration(entry.uptimeSeconds!),
              ),
            ])
              Text(
                '$label: $value',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        if (engine.isPostgres && entry.databases.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'dbPerDatabase'.tr(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final db in entry.databases)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${db.name}: ${db.connections ?? 0}',
                    style: theme.textTheme.labelSmall,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _MetricsTile extends StatelessWidget {
  const _MetricsTile({required this.label, required this.value, this.progress});

  final String label;
  final String value;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.titleSmall),
        if (progress != null) ...[
          const SizedBox(height: 4),
          SizedBox(
            width: 120,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress!.clamp(0.0, 1.0),
                minHeight: 4,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _InstanceCard extends StatelessWidget {
  const _InstanceCard({
    required this.instance,
    required this.busy,
    this.onRestart,
  });

  final DatabaseInstance instance;
  final bool busy;
  final VoidCallback? onRestart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final specs = <(String, String)>[
      if (instance.port != null) ('dbPort'.tr(), instance.port!),
      if (instance.socket != null) ('dbSocket'.tr(), instance.socket!),
      if (instance.dataDirectory != null)
        ('dbDataDirectory'.tr(), instance.dataDirectory!),
      if (instance.configFile != null)
        ('dbConfigFile'.tr(), instance.configFile!),
      if (instance.binaryDirectory != null)
        ('dbBinary'.tr(), instance.binaryDirectory!),
    ];
    return _DbSection(
      title: '${instance.engine.label} · ${instance.version ?? ''}',
      icon: _engineIcon(instance.engine),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RunningChip(running: instance.running, enabled: instance.enabled),
          if (onRestart != null) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'dbServiceRestart'.tr(),
              visualDensity: VisualDensity.compact,
              onPressed: busy ? null : onRestart,
              icon: const Icon(Symbols.restart_alt),
            ),
          ],
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (instance.error != null && instance.error!.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                instance.error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              for (final (label, value) in specs)
                _SpecChip(label: label, value: value),
              if (instance.connections != null)
                _SpecChip(
                  label: 'dbConnections'.tr(),
                  value: '${instance.connections}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RunningChip extends StatelessWidget {
  const _RunningChip({required this.running, required this.enabled});

  final bool? running;
  final bool? enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color, background) = switch (running) {
      true => (
        'dbStatusRunning'.tr(),
        scheme.onSecondaryContainer,
        scheme.secondaryContainer,
      ),
      false => (
        'dbStatusStopped'.tr(),
        scheme.onErrorContainer,
        scheme.errorContainer,
      ),
      null => (
        'dbStatusUnknown'.tr(),
        scheme.onSurfaceVariant,
        scheme.surfaceContainerHighest,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: running == true ? scheme.primary : color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _SpecChip extends StatelessWidget {
  const _SpecChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _DatabasesCard extends StatelessWidget {
  const _DatabasesCard({
    required this.instance,
    required this.busy,
    required this.onBackup,
    required this.onRestore,
    required this.onMaintenance,
  });

  final DatabaseInstance instance;
  final bool busy;
  final VoidCallback onBackup;
  final VoidCallback onRestore;
  final VoidCallback onMaintenance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final databases = instance.databases;
    return _DbSection(
      title: 'dbDatabases'.tr(),
      icon: Symbols.inventory_2,
      child: databases.isEmpty
          ? Text(
              instance.error ?? 'dbNoDatabases'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          : Column(
              children: [
                for (final (index, db) in databases.indexed) ...[
                  if (index > 0)
                    Divider(height: 1, color: scheme.outlineVariant),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(db.name, style: theme.textTheme.bodyMedium),
                              const SizedBox(height: 2),
                              Text(
                                [
                                  if (db.owner != null) db.owner!,
                                  if (db.sizeLabel != null) db.sizeLabel!,
                                  if (db.encoding != null) db.encoding!,
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'dbBackup'.tr(),
                          visualDensity: VisualDensity.compact,
                          onPressed: busy ? null : onBackup,
                          icon: const Icon(Symbols.save),
                        ),
                        IconButton(
                          tooltip: 'dbMaintenance'.tr(),
                          visualDensity: VisualDensity.compact,
                          onPressed: busy ? null : onMaintenance,
                          icon: const Icon(Symbols.cleaning_services),
                        ),
                        IconButton(
                          tooltip: 'dbRestore'.tr(),
                          visualDensity: VisualDensity.compact,
                          onPressed: busy ? null : onRestore,
                          icon: const Icon(Symbols.restore),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _BackupsCard extends ConsumerStatefulWidget {
  const _BackupsCard({
    required this.server,
    required this.engine,
    required this.directoryController,
    required this.revision,
    required this.busy,
    required this.isRoot,
    required this.onBackup,
    required this.onRestore,
    required this.onDelete,
  });

  final Server server;
  final DatabaseEngine engine;
  final TextEditingController directoryController;

  /// Bumped by the parent whenever an inspection finished, so the listing
  /// refreshes after backups, restores and deletes.
  final int revision;
  final bool busy;
  final bool isRoot;
  final VoidCallback onBackup;
  final ValueChanged<DatabaseBackupFile> onRestore;
  final ValueChanged<DatabaseBackupFile> onDelete;

  @override
  ConsumerState<_BackupsCard> createState() => _BackupsCardState();
}

class _BackupsCardState extends ConsumerState<_BackupsCard> {
  AsyncValue<List<DatabaseBackupFile>> _files = const AsyncValue.data([]);

  String get _directory => widget.directoryController.text.trim();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_BackupsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.engine != widget.engine ||
        oldWidget.server.id != widget.server.id ||
        oldWidget.revision != widget.revision ||
        oldWidget.directoryController.text != widget.directoryController.text) {
      _load();
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _load() async {
    if (_directory.isEmpty) {
      setState(() => _files = const AsyncValue.data([]));
      return;
    }
    setState(() => _files = const AsyncValue.loading());
    try {
      final files = await ref
          .read(connectionManagerProvider)
          .listDatabaseBackups(
            widget.server.id,
            engine: widget.engine,
            directory: _directory,
            sshUserIsRoot: widget.isRoot,
            sudoPassword: await _sudoPassword(),
          );
      if (!mounted) return;
      setState(() => _files = AsyncValue.data(files));
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() => _files = AsyncValue.error(error, stackTrace));
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _DbSection(
      title: 'dbBackups'.tr(),
      icon: Symbols.backup,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.directoryController,
                  style: theme.textTheme.bodySmall,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '/var/backups/…',
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _load(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'commonRefresh'.tr(),
                visualDensity: VisualDensity.compact,
                onPressed: widget.busy ? null : _load,
                icon: const Icon(Symbols.refresh),
              ),
              FilledButton.icon(
                onPressed: widget.busy ? null : widget.onBackup,
                icon: const Icon(Symbols.save, size: 16),
                label: Text('dbBackupDatabaseShort'.tr()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _files.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (error, _) => Text(
              'dbListBackupsError'.tr(args: ['$error']),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            data: (files) => files.isEmpty
                ? Text(
                    'dbNoBackups'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                : Column(
                    children: [
                      for (final (index, file) in files.indexed) ...[
                        if (index > 0)
                          Divider(height: 1, color: scheme.outlineVariant),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              const Icon(
                                Symbols.description,
                                size: 16,
                                color: null,
                              ).padding(right: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      file.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    Text(
                                      [
                                        if (file.sizeBytes != null)
                                          _formatBytes(file.sizeBytes),
                                        if (file.modifiedLabel != null)
                                          file.modifiedLabel!,
                                      ].join(' · '),
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'dbRestore'.tr(),
                                visualDensity: VisualDensity.compact,
                                onPressed: widget.busy
                                    ? null
                                    : () => widget.onRestore(file),
                                icon: const Icon(Symbols.restore),
                              ),
                              IconButton(
                                tooltip: 'dbDeleteBackup'.tr(),
                                visualDensity: VisualDensity.compact,
                                onPressed: widget.busy
                                    ? null
                                    : () => widget.onDelete(file),
                                icon: const Icon(Symbols.delete),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _PgBackRestCard extends StatelessWidget {
  const _PgBackRestCard({
    required this.status,
    required this.serviceUnit,
    required this.busy,
    required this.onBackup,
    required this.onRestore,
  });

  final PgBackRestStatus status;
  final String? serviceUnit;
  final bool busy;
  final VoidCallback onBackup;
  final ValueChanged<PgBackRestStanza> onRestore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _DbSection(
      title: 'dbPgBackRest'.tr(),
      icon: Symbols.shield,
      trailing: IconButton(
        tooltip: 'dbPgBackRestBackupNow'.tr(),
        visualDensity: VisualDensity.compact,
        onPressed: busy ? null : onBackup,
        icon: const Icon(Symbols.add_task),
      ),
      child: status.stanzas.isEmpty
          ? Text(
              status.error ?? 'dbPgBackRestNoStanzas'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          : Column(
              children: [
                for (final (index, stanza) in status.stanzas.indexed) ...[
                  if (index > 0)
                    Divider(height: 1, color: scheme.outlineVariant),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                stanza.name,
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                            IconButton(
                              tooltip: 'dbPgBackRestRestore'.tr(),
                              visualDensity: VisualDensity.compact,
                              onPressed: busy ? null : () => onRestore(stanza),
                              icon: const Icon(Symbols.restore),
                            ),
                          ],
                        ),
                        if (stanza.repositoryPath != null)
                          Text(
                            '${'dbPgBackRestRepo'.tr()}: ${stanza.repositoryPath}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        const SizedBox(height: 4),
                        if (stanza.backups.isEmpty)
                          Text(
                            'dbPgBackRestNoBackups'.tr(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          )
                        else
                          for (final backup in stanza.backups.take(5))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Icon(
                                    backup.type == 'full'
                                        ? Symbols.verified
                                        : backup.type == 'diff'
                                        ? Symbols.compare_arrows
                                        : Symbols.add,
                                    size: 14,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    backup.label,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    backup.type.toUpperCase(),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: scheme.primary,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    [
                                      _formatBytes(backup.sizeBytes),
                                      _formatTimestamp(backup.timestamp),
                                    ].join(' · '),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _BackupSheet extends StatefulWidget {
  const _BackupSheet({
    required this.engine,
    required this.databases,
    required this.initialDirectory,
  });

  final DatabaseEngine engine;
  final List<String> databases;
  final String initialDirectory;

  @override
  State<_BackupSheet> createState() => _BackupSheetState();
}

class _BackupSheetState extends State<_BackupSheet> {
  late String _database = widget.databases.first;
  late final TextEditingController _directory = TextEditingController(
    text: widget.initialDirectory,
  );

  @override
  void dispose() {
    _directory.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      titleText: 'dbBackupDatabase'.tr(args: [_database]),
      heightFactor: 0.5,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _database,
              decoration: InputDecoration(labelText: 'dbBackupTarget'.tr()),
              items: [
                for (final name in widget.databases)
                  DropdownMenuItem(value: name, child: Text(name)),
              ],
              onChanged: (value) =>
                  setState(() => _database = value ?? _database),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _directory,
              decoration: InputDecoration(
                labelText: 'dbBackupDirectory'.tr(),
                isDense: true,
              ),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('commonCancel'.tr()),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(
                    context,
                    '$_database\n${_directory.text.trim()}',
                  ),
                  icon: const Icon(Symbols.save, size: 16),
                  label: Text('dbBackupRun'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RestoreChoice {
  const _RestoreChoice({
    required this.database,
    required this.file,
    this.mysqlPassword,
  });

  final String database;
  final String file;
  final String? mysqlPassword;
}

class _RestoreSheet extends ConsumerStatefulWidget {
  const _RestoreSheet({
    required this.server,
    required this.engine,
    required this.databases,
    required this.directory,
    required this.isRoot,
    this.initialFile,
  });

  final Server server;
  final DatabaseEngine engine;
  final List<String> databases;
  final String directory;
  final bool isRoot;
  final String? initialFile;

  @override
  ConsumerState<_RestoreSheet> createState() => _RestoreSheetState();
}

class _RestoreSheetState extends ConsumerState<_RestoreSheet> {
  AsyncValue<List<DatabaseBackupFile>> _files = const AsyncValue.loading();
  late String _database = widget.databases.first;
  String? _file;
  final _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    if (widget.directory.isEmpty) {
      setState(() => _files = const AsyncValue.data([]));
      return;
    }
    setState(() => _files = const AsyncValue.loading());
    try {
      final credential = await ref
          .read(serverRepositoryProvider)
          .credentialFor(widget.server);
      final sudoPassword = credential.type == CredentialType.password
          ? credential.password
          : null;
      final files = await ref
          .read(connectionManagerProvider)
          .listDatabaseBackups(
            widget.server.id,
            engine: widget.engine,
            directory: widget.directory,
            sshUserIsRoot: widget.isRoot,
            sudoPassword: sudoPassword,
          );
      if (!mounted) return;
      setState(() {
        _files = AsyncValue.data(files);
        final preselected = widget.initialFile;
        _file =
            preselected != null && files.any((file) => file.path == preselected)
            ? preselected
            : files.isEmpty
            ? null
            : files.first.path;
      });
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() => _files = AsyncValue.error(error, stackTrace));
    }
  }

  @override
  Widget build(BuildContext context) {
    final needsPassword = widget.engine.isMySqlLike;
    return SheetScaffold(
      titleText: 'dbRestore'.tr(),
      heightFactor: 0.6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _database,
              decoration: InputDecoration(labelText: 'dbRestoreInto'.tr()),
              items: [
                for (final name in widget.databases)
                  DropdownMenuItem(value: name, child: Text(name)),
              ],
              onChanged: (value) =>
                  setState(() => _database = value ?? _database),
            ),
            const SizedBox(height: 12),
            _files.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              error: (error, _) => Text(
                'dbListBackupsError'.tr(args: ['$error']),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              data: (files) => files.isEmpty
                  ? Text(
                      'dbNoBackups'.tr(),
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  : DropdownButtonFormField<String>(
                      initialValue: _file,
                      decoration: InputDecoration(
                        labelText: 'dbRestoreFile'.tr(),
                      ),
                      items: [
                        for (final file in files)
                          DropdownMenuItem(
                            value: file.path,
                            child: Text(file.name),
                          ),
                      ],
                      onChanged: (value) => setState(() => _file = value),
                    ),
            ),
            if (needsPassword) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'dbMysqlPassword'.tr(),
                  helperText: 'dbMysqlPasswordHint'.tr(),
                  isDense: true,
                ),
              ),
            ],
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('commonCancel'.tr()),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _file == null
                      ? null
                      : () => Navigator.pop(
                          context,
                          _RestoreChoice(
                            database: _database,
                            file: _file!,
                            mysqlPassword: _password.text.isEmpty
                                ? null
                                : _password.text,
                          ),
                        ),
                  icon: const Icon(Symbols.restore, size: 16),
                  label: Text('dbRestoreRun'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MaintenanceChoice {
  const _MaintenanceChoice({
    required this.database,
    required this.action,
    this.mysqlPassword,
  });

  final String database;
  final DatabaseMaintenanceAction action;
  final String? mysqlPassword;
}

class _MaintenanceSheet extends StatefulWidget {
  const _MaintenanceSheet({required this.engine, required this.databases});

  final DatabaseEngine engine;
  final List<String> databases;

  @override
  State<_MaintenanceSheet> createState() => _MaintenanceSheetState();
}

class _MaintenanceSheetState extends State<_MaintenanceSheet> {
  late String _database = widget.databases.first;
  late DatabaseMaintenanceAction _action = widget.engine.isPostgres
      ? postgresMaintenanceActions.first
      : mysqlMaintenanceActions.first;
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actions = widget.engine.isPostgres
        ? postgresMaintenanceActions
        : mysqlMaintenanceActions;
    final needsPassword = widget.engine.isMySqlLike;
    return SheetScaffold(
      titleText: 'dbMaintenance'.tr(),
      heightFactor: 0.55,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _database,
              decoration: InputDecoration(labelText: 'dbBackupTarget'.tr()),
              items: [
                for (final name in widget.databases)
                  DropdownMenuItem(value: name, child: Text(name)),
              ],
              onChanged: (value) =>
                  setState(() => _database = value ?? _database),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<DatabaseMaintenanceAction>(
              initialValue: _action,
              decoration: InputDecoration(
                labelText: 'dbMaintenanceAction'.tr(),
              ),
              items: [
                for (final action in actions)
                  DropdownMenuItem(
                    value: action,
                    child: Text('${action.label} · ${action.id}'),
                  ),
              ],
              onChanged: (value) => setState(() => _action = value ?? _action),
            ),
            if (needsPassword) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'dbMysqlPassword'.tr(),
                  helperText: 'dbMysqlPasswordHint'.tr(),
                  isDense: true,
                ),
              ),
            ],
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('commonCancel'.tr()),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(
                    context,
                    _MaintenanceChoice(
                      database: _database,
                      action: _action,
                      mysqlPassword: _password.text.isEmpty
                          ? null
                          : _password.text,
                    ),
                  ),
                  icon: const Icon(Symbols.cleaning_services, size: 16),
                  label: Text('dbMaintenanceRun'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PgBackRestBackupChoice {
  const _PgBackRestBackupChoice({required this.stanza, required this.type});

  final String stanza;
  final String type;
}

class _PgBackRestBackupSheet extends StatefulWidget {
  const _PgBackRestBackupSheet({required this.stanzas});

  final List<String> stanzas;

  @override
  State<_PgBackRestBackupSheet> createState() => _PgBackRestBackupSheetState();
}

class _PgBackRestBackupSheetState extends State<_PgBackRestBackupSheet> {
  late String _stanza = widget.stanzas.first;
  String _type = 'full';

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      titleText: 'dbPgBackRestBackupNow'.tr(),
      heightFactor: 0.45,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _stanza,
              decoration: InputDecoration(labelText: 'dbPgBackRestStanza'.tr()),
              items: [
                for (final stanza in widget.stanzas)
                  DropdownMenuItem(value: stanza, child: Text(stanza)),
              ],
              onChanged: (value) => setState(() => _stanza = value ?? _stanza),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: InputDecoration(labelText: 'dbPgBackRestType'.tr()),
              items: [
                DropdownMenuItem(
                  value: 'full',
                  child: Text('dbPgBackRestTypeFull'.tr()),
                ),
                DropdownMenuItem(
                  value: 'incr',
                  child: Text('dbPgBackRestTypeIncremental'.tr()),
                ),
                DropdownMenuItem(
                  value: 'diff',
                  child: Text('dbPgBackRestTypeDifferential'.tr()),
                ),
              ],
              onChanged: (value) => setState(() => _type = value ?? _type),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('commonCancel'.tr()),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(
                    context,
                    _PgBackRestBackupChoice(stanza: _stanza, type: _type),
                  ),
                  icon: const Icon(Symbols.backup, size: 16),
                  label: Text('dbBackupRun'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PgBackRestRestoreSheet extends StatefulWidget {
  const _PgBackRestRestoreSheet({required this.stanza});

  final PgBackRestStanza stanza;

  @override
  State<_PgBackRestRestoreSheet> createState() =>
      _PgBackRestRestoreSheetState();
}

class _PgBackRestRestoreSheetState extends State<_PgBackRestRestoreSheet> {
  String? _set;

  @override
  Widget build(BuildContext context) {
    final backups = widget.stanza.backups;
    return SheetScaffold(
      titleText: 'dbPgBackRestRestore'.tr(),
      heightFactor: 0.45,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String?>(
              initialValue: _set,
              decoration: InputDecoration(
                labelText: 'dbPgBackRestRestoreSet'.tr(),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text('dbPgBackRestLatest'.tr()),
                ),
                for (final backup in backups)
                  DropdownMenuItem<String?>(
                    value: backup.label,
                    child: Text(
                      '${backup.label} (${backup.type.toUpperCase()})',
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _set = value),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('commonCancel'.tr()),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context, _set ?? ''),
                  icon: const Icon(Symbols.restore, size: 16),
                  label: Text('dbRestoreRun'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DbSection extends StatelessWidget {
  const _DbSection({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: theme.textTheme.labelLarge)),
                ?trailing,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _DbEmptyPanel extends StatelessWidget {
  const _DbEmptyPanel({
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: onAction,
              icon: const Icon(Symbols.refresh, size: 16),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

IconData _engineIcon(DatabaseEngine engine) => switch (engine) {
  DatabaseEngine.postgres => Symbols.database,
  DatabaseEngine.mysql || DatabaseEngine.mariadb => Symbols.storage,
};
