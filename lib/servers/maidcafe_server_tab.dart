import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/bash.dart' as bash;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/shared/presentation/deploy_terminal.dart';
import 'package:maid_kit/shared/presentation/ansi_log_view.dart';
import 'package:maid_kit/shared/presentation/icon_label_tab.dart';
import 'package:maid_kit/theme.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:styled_widget/styled_widget.dart';

import 'maidcafe_install.dart';
import 'maidcafe_uninstall.dart';
import 'maidcafe_stream.dart';
import 'maidcafe_session_registry.dart';
import 'maidcafe_uploads_tab.dart';
import 'maidcafe_service.dart';
import 'server_models.dart';
import 'terminal_tabs_provider.dart';
import 'server_providers.dart';
import 'package:solsynth_express/solsynth_express.dart';

final maidCafeActionsProvider =
    NotifierProvider<
      MaidCafeActionsNotifier,
      Map<int, List<MaidCafeActionDefinition>>
    >(MaidCafeActionsNotifier.new);

class MaidCafeActionsNotifier
    extends Notifier<Map<int, List<MaidCafeActionDefinition>>> {
  @override
  Map<int, List<MaidCafeActionDefinition>> build() => const {};

  List<MaidCafeActionDefinition> forServer(int serverId) =>
      state[serverId] ?? const [];

  void setForServer(int serverId, List<MaidCafeActionDefinition> actions) {
    state = {...state, serverId: List.unmodifiable(actions)};
  }
}

enum MaidCafeTabMode { installation, payload }

enum _MaidCafeState { checking, notInstalled, running, conflict }

/// Selects one download channel without dismissing the parent sheet.
class MaidCafeInstallChannelPicker extends StatelessWidget {
  const MaidCafeInstallChannelPicker({
    super.key,
    required this.channels,
    required this.selected,
    required this.onSelected,
  });

  final List<DistributionChannel> channels;

  /// Currently selected channel name, if any.
  final String? selected;

  /// Called when the user taps a channel; the picker does not pop itself.
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: math.min(280.0, channels.length * 72.0),
      child: ListView.separated(
        itemCount: channels.length,
        separatorBuilder: (_, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final channel = channels[index];
          final release = channel.latest;
          final isSelected = channel.name == selected;
          return ListTile(
            leading: Icon(
              isSelected
                  ? Symbols.radio_button_checked
                  : Symbols.radio_button_unchecked,
              color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            title: Text(channel.name),
            subtitle: release == null ? null : Text(release.tagName),
            selected: isSelected,
            onTap: () => onSelected(channel.name),
          );
        },
      ),
    );
  }
}

/// MaidCafe installation management or the standalone payload workspace.
class MaidCafeServerTab extends ConsumerStatefulWidget {
  const MaidCafeServerTab({
    super.key,
    required this.server,
    required this.connected,
    required this.connectionError,
    required this.onConnect,
    this.mode = MaidCafeTabMode.installation,
  });

  final Server server;
  final bool connected;
  final String? connectionError;
  final Future<void> Function() onConnect;
  final MaidCafeTabMode mode;

  @override
  ConsumerState<MaidCafeServerTab> createState() => _MaidCafeServerTabState();
}

class _MaidCafeServerTabState extends ConsumerState<MaidCafeServerTab>
    with AutomaticKeepAliveClientMixin {
  late final TextEditingController _newActionNameController;
  late final TextEditingController _newActionDisplayNameController;
  late final CodeController _newActionController;
  late final FocusNode _newActionFocusNode;
  late final TextEditingController _newActionCwdController;
  late final TextEditingController _newActionUserController;
  late final TextEditingController _newActionTimeoutController;
  Map<String, String> _newActionEnvironment = {};
  var _showComposer = false;
  // Last values supplied for an action's {{ name }} template variables, so
  // re-runs start from the previous invocation.
  final Map<String, Map<String, String>> _actionVariableValues = {};
  late final TextEditingController _portController;
  late final TextEditingController _daemonIdController;
  late final TextEditingController _versionController;
  late final TextEditingController _listenHostController;
  late final TextEditingController _cloudUrlController;
  late final TextEditingController _cloudSecretController;
  late final TextEditingController _metricsSecretController;
  late final TextEditingController _metricsIntervalController;
  late final TextEditingController _logsIntervalController;
  late final TextEditingController _requestTimeoutController;
  late final TextEditingController _scriptTimeoutController;
  late final TextEditingController _maxBodyBytesController;
  late final TextEditingController _maxConcurrentRunsController;
  late final MaidCafeSessionRegistry _sessionRegistry;
  MaidCafeStreamSession? _stream;
  var _streamGeneration = 0;
  var _portEdited = false;
  var _busy = false;
  var _transport = 'http';
  String? _message;
  var _state = _MaidCafeState.checking;
  String? _streamStatus;
  String? _latestVersion;
  List<MaidCafeActionDefinition>? _savedActions;
  String? _runningActionName;
  // Alarm thresholds declared in the daemon's alarmsDir fragments. Edited
  // here (the daemon evaluates them locally) and deployed with the config.
  List<MaidCafeAlarmDefinition> _alarms = const [];
  // Raw current /etc/maidcafe/config.toml text, for patch-based saves that
  // preserve everything the app does not model.
  String _serverConfigText = '';
  final Map<String, Map<String, dynamic>> _actionResults = {};
  List<MaidCafeAuditEntry> _auditEntries = const [];
  var _auditLoading = false;
  String? _auditError;
  String? _auditFilter;
  // Guards the build-time auto-load: empty entries are a legitimate state
  // (no runs yet, or the daemon lacks the endpoint), so the trigger must
  // fire once per stream, not on every rebuild — otherwise each failed or
  // empty fetch reschedules itself and the progress bar flashes forever.
  var _auditLoaded = false;

  List<MaidCafeActionDefinition> get _actions =>
      ref.read(maidCafeActionsProvider.notifier).forServer(widget.server.id);

  // The SSH tunnel to the local daemon must outlive tab switches inside the
  // server detail page; keep this state mounted until that page goes away.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _sessionRegistry = ref.read(maidCafeSessionRegistryProvider);
    _sessionRegistry.retain(widget.server);
    _newActionNameController = TextEditingController();
    _newActionDisplayNameController = TextEditingController();
    _newActionController = CodeController(language: bash.bash);
    _newActionFocusNode = FocusNode();
    _newActionCwdController = TextEditingController();
    _newActionUserController = TextEditingController();
    _newActionTimeoutController = TextEditingController();
    final cachedPort = _cachedMaidCafePort(widget.server);
    _portController = TextEditingController(
      text: cachedPort == null ? '' : '$cachedPort',
    );
    _daemonIdController = TextEditingController(
      text: 'maidkit-${widget.server.id}',
    );
    _versionController = TextEditingController();
    _listenHostController = TextEditingController(text: '127.0.0.1');
    _cloudUrlController = TextEditingController();
    _cloudSecretController = TextEditingController();
    _metricsSecretController = TextEditingController();
    _metricsIntervalController = TextEditingController(text: '1m');
    _logsIntervalController = TextEditingController(text: '30s');
    _requestTimeoutController = TextEditingController(text: '10s');
    _scriptTimeoutController = TextEditingController(text: '30s');
    _maxBodyBytesController = TextEditingController(text: '65536');
    _maxConcurrentRunsController = TextEditingController(text: '4');
    if (widget.connected) {
      Future<void>.microtask(_probeInstallation);
    }
  }

  @override
  void didUpdateWidget(MaidCafeServerTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.connected && oldWidget.connected) {
      _closeStream();
      setState(() => _state = _MaidCafeState.checking);
    } else if (widget.connected && !oldWidget.connected) {
      Future<void>.microtask(_probeInstallation);
    }
  }

  @override
  void dispose() {
    _newActionNameController.dispose();
    _newActionDisplayNameController.dispose();
    _newActionController.dispose();
    _newActionFocusNode.dispose();
    _newActionCwdController.dispose();
    _newActionUserController.dispose();
    _newActionTimeoutController.dispose();
    _portController.dispose();
    _daemonIdController.dispose();
    _versionController.dispose();
    _listenHostController.dispose();
    _cloudUrlController.dispose();
    _cloudSecretController.dispose();
    _metricsSecretController.dispose();
    _metricsIntervalController.dispose();
    _logsIntervalController.dispose();
    _requestTimeoutController.dispose();
    _scriptTimeoutController.dispose();
    _maxBodyBytesController.dispose();
    _maxConcurrentRunsController.dispose();
    _closeStream();
    _sessionRegistry.release(widget.server);
    super.dispose();
  }

  void _closeStream() {
    _streamGeneration++;
    _stream = null;
    _sessionRegistry.invalidate(widget.server);
  }

  Future<String?> _sudoPassword() async {
    final credential = await ref
        .read(serverRepositoryProvider)
        .credentialFor(widget.server);
    return credential.type == CredentialType.password
        ? credential.password
        : null;
  }

  int? _configuredPort() {
    final value = int.tryParse(_portController.text.trim());
    return value != null && value >= maidCafeMinimumPort && value <= 65535
        ? value
        : null;
  }

  int _configInt(TextEditingController controller, int fallback) =>
      int.tryParse(controller.text.trim()) ?? fallback;

  String _configText(TextEditingController controller, String fallback) {
    final value = controller.text.trim();
    return value.isEmpty ? fallback : value;
  }

  Future<int> _resolveMaidCafePort({bool refreshRemote = false}) async {
    final configured = _configuredPort();
    if (_portEdited) {
      if (configured == null) {
        throw StateError('maidCafePortInvalid'.tr());
      }
      return configured;
    }
    final cached = _cachedMaidCafePort(widget.server);
    if (!refreshRemote && cached != null) return cached;
    final remote = await readMaidCafeListenPort(
      manager: ref.read(connectionManagerProvider),
      server: widget.server,
      sudoPassword: await _sudoPassword(),
    ).catchError((_) => null);
    final port = remote ?? cached ?? maidCafeDefaultPort;
    if (!_portEdited && mounted) _portController.text = '$port';
    if (remote != null && mounted) {
      await ref
          .read(serverRepositoryProvider)
          .updateMaidCafeConfig(
            widget.server,
            daemonUrl: 'http://127.0.0.1:$remote',
          );
    }
    return port;
  }

  Future<void> _cacheMaidCafePort(int port) async {
    await ref
        .read(serverRepositoryProvider)
        .updateMaidCafeConfig(
          widget.server,
          daemonUrl: 'http://127.0.0.1:$port',
        );
  }

  Future<void> _loadDaemonConfig() async {
    final config = await readMaidCafeConfig(
      manager: ref.read(connectionManagerProvider),
      server: widget.server,
      sudoPassword: await _sudoPassword(),
    );
    if (!mounted) return;
    void setText(TextEditingController controller, String? value) {
      if (value != null && value.isNotEmpty) controller.text = value;
    }

    setText(_daemonIdController, config.id);
    setText(_versionController, config.version);
    setText(_listenHostController, config.listenHost);
    setText(_cloudUrlController, config.cloudUrl);
    setText(_cloudSecretController, config.cloudSecret);
    setText(_metricsSecretController, config.apiSecret);
    setText(_metricsIntervalController, config.metricsInterval);
    setText(_logsIntervalController, config.logsInterval);
    setText(_requestTimeoutController, config.requestTimeout);
    setText(_scriptTimeoutController, config.scriptTimeout);
    if (config.maxBodyBytes != null) {
      _maxBodyBytesController.text = '${config.maxBodyBytes}';
    }
    if (config.maxConcurrentRuns != null) {
      _maxConcurrentRunsController.text = '${config.maxConcurrentRuns}';
    }
    if (config.transport == 'stdio' || config.transport == 'http') {
      _transport = config.transport!;
    }
    ref
        .read(maidCafeActionsProvider.notifier)
        .setForServer(widget.server.id, config.actions);
    _savedActions = List.unmodifiable(config.actions);
    _actionResults.clear();
    _serverConfigText = config.configText;
    _alarms = List.unmodifiable(config.alarms);
  }

  Future<void> _probeInstallation() async {
    if (!mounted || !widget.connected || _busy) return;
    setState(() {
      _state = _MaidCafeState.checking;
      _message = null;
    });
    var managed = false;
    try {
      final existing = await detectMaidCafeInstallation(
        manager: ref.read(connectionManagerProvider),
        serverId: widget.server.id,
      ).timeout(const Duration(seconds: 20));
      managed = existing.contains('managed');
      final conflicts = managed
          ? const <String>[]
          : existing.where((entry) => entry != 'managed').toList();
      if (!managed && conflicts.isNotEmpty) {
        if (mounted) {
          setState(() {
            _state = _MaidCafeState.conflict;
            _message =
                '${'maidCafeExistingInstallation'.tr()}\n'
                '${conflicts.join('\n')}';
          });
        }
        return;
      }
      if (!managed) {
        if (mounted) setState(() => _state = _MaidCafeState.notInstalled);
        return;
      }
      await _loadDaemonConfig();
      final port = await _resolveMaidCafePort(refreshRemote: true);
      // The session registry swallows open failures into a null session, so
      // a down daemon makes _openStream return false instead of throwing;
      // without this branch the tab would stay on `checking` forever. The
      // timeout only guards a hung SSH forward, never the happy path.
      final opened = await _openStream(
        port: port,
        force: true,
      ).timeout(const Duration(seconds: 45));
      if (opened && mounted) {
        setState(() => _state = _MaidCafeState.running);
        Future<void>.microtask(_refreshMetrics);
      } else if (mounted) {
        _closeStream();
        setState(() {
          _state = _MaidCafeState.notInstalled;
          _message = managed
              ? 'maidCafeInstallationUnavailable'.tr()
              : 'maidCafeInstallationCheckFailed'.tr();
        });
      }
    } catch (error) {
      _closeStream();
      if (mounted) {
        setState(() {
          _state = _MaidCafeState.notInstalled;
          _message = managed
              ? 'maidCafeInstallationUnavailable'.tr()
              : 'maidCafeInstallationCheckFailed'.tr();
        });
      }
    }
  }

  void _stageAction(MaidCafeActionDefinition action) {
    // Cards pass copyWith instances, so identity never matches the stored
    // list; the slug is the stable key (uniqueness is enforced on add).
    ref.read(maidCafeActionsProvider.notifier).setForServer(widget.server.id, [
      for (final current in _actions)
        current.name == action.name ? action : current,
    ]);
    // The provider is read (not watched) so changes only land on screen when
    // the widget rebuilds; without this, toggle chips and the dirty footer
    // never reflect a staged edit.
    setState(() {});
  }

  void _addAction() {
    final name = _newActionNameController.text.trim();
    final script = _newActionController.text;
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(name)) {
      setState(() => _message = 'maidCafeActionNameInvalid'.tr());
      return;
    }
    if (_actions.any((action) => action.name == name)) {
      setState(() => _message = 'maidCafeActionNameUnique'.tr());
      return;
    }
    if (script.trim().isEmpty) {
      setState(() => _message = 'maidCafeActionScriptRequired'.tr());
      return;
    }
    final workingDirectory = _newActionCwdController.text.trim();
    if (workingDirectory.isNotEmpty && !workingDirectory.startsWith('/')) {
      setState(() => _message = 'maidCafeActionCwdInvalid'.tr());
      return;
    }
    final user = _newActionUserController.text.trim();
    if (user.isNotEmpty &&
        !RegExp(r'^[A-Za-z_][A-Za-z0-9_.-]*$').hasMatch(user)) {
      setState(() => _message = 'maidCafeActionUserInvalid'.tr());
      return;
    }
    final scriptTimeout = _newActionTimeoutController.text.trim();
    if (scriptTimeout.isNotEmpty &&
        !RegExp(
          r'^(\d+(\.\d+)?(ns|us|µs|ms|s|m|h))+$',
        ).hasMatch(scriptTimeout)) {
      setState(() => _message = 'maidCafeActionTimeoutInvalid'.tr());
      return;
    }
    for (final key in _newActionEnvironment.keys) {
      if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key)) {
        setState(() => _message = 'maidCafeActionEnvKeyInvalid'.tr());
        return;
      }
    }
    ref.read(maidCafeActionsProvider.notifier).setForServer(widget.server.id, [
      ..._actions,
      MaidCafeActionDefinition(
        name: name,
        script: script,
        displayName: _newActionDisplayNameController.text.trim().isEmpty
            ? null
            : _newActionDisplayNameController.text.trim(),
        workingDirectory: workingDirectory.isEmpty ? null : workingDirectory,
        user: user.isEmpty ? null : user,
        scriptTimeout: scriptTimeout.isEmpty ? null : scriptTimeout,
        environment: Map.unmodifiable(_newActionEnvironment),
      ),
    ]);
    setState(() {
      _newActionNameController.clear();
      _newActionDisplayNameController.clear();
      _newActionController.text = '';
      _newActionCwdController.clear();
      _newActionUserController.clear();
      _newActionTimeoutController.clear();
      _newActionEnvironment = {};
      _showComposer = false;
      _message = null;
    });
  }

  void _removeAction(MaidCafeActionDefinition action) {
    ref.read(maidCafeActionsProvider.notifier).setForServer(widget.server.id, [
      for (final current in _actions)
        if (!identical(current, action)) current,
    ]);
    _actionResults.remove(action.name);
  }

  void _discardActionChanges() {
    final saved = _savedActions;
    if (saved == null) return;
    ref
        .read(maidCafeActionsProvider.notifier)
        .setForServer(widget.server.id, saved);
    _actionResults.clear();
    setState(() => _message = null);
  }

  bool get _actionsDirty {
    final saved = _savedActions;
    if (saved == null) return _actions.isNotEmpty;
    if (saved.length != _actions.length) return true;
    for (var i = 0; i < saved.length; i++) {
      if (!_sameAction(saved[i], _actions[i])) return true;
    }
    return false;
  }

  bool _sameAction(MaidCafeActionDefinition a, MaidCafeActionDefinition b) =>
      a.name == b.name &&
      a.script == b.script &&
      a.enabled == b.enabled &&
      a.notifyOnSuccess == b.notifyOnSuccess &&
      a.notifyOnFailure == b.notifyOnFailure &&
      a.displayName == b.displayName &&
      a.workingDirectory == b.workingDirectory &&
      a.user == b.user &&
      a.scriptTimeout == b.scriptTimeout &&
      _sameEnvironment(a.environment, b.environment);

  bool _sameEnvironment(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  /// Connection-only status line: no metrics, no raw daemon ids.
  String _streamStatusLine(MaidCafeStreamSession stream) {
    final version = stream.version;
    final versionSuffix = version == null || version.isEmpty
        ? ''
        : ' · $version';
    return '${'maidCafeStreamConnected'.tr()}$versionSuffix';
  }

  Future<bool> _openStream({int? port, bool force = false}) async {
    final generation = ++_streamGeneration;
    final repository = ref.read(serverRepositoryProvider);
    final apiSecret = await repository.maidCafeMetricsSecretFor(widget.server);
    final resolvedPort = port ?? await _resolveMaidCafePort();
    final stream = await _sessionRegistry.sessionFor(
      widget.server,
      port: resolvedPort,
      force: force,
    );
    if (stream == null) return false;
    try {
      await stream.health();
      if (!mounted || !widget.connected || generation != _streamGeneration) {
        // The session is shared with the realtime tabs; the registry owns its
        // lifecycle, so a stale open is simply abandoned.
        return false;
      }
      if (mounted) {
        setState(() {
          _stream = stream;
          _streamStatus = _streamStatusLine(stream);
          // A fresh stream may be a (re)started daemon; let the next build
          // of the actions tab reload the audit log once.
          _auditLoaded = false;
        });
        // The daemon's config secret is authoritative. Persist it when the
        // stored one was stale so later connections skip the auth fallback;
        // failure here only costs one retried connection later.
        final usedSecret = stream.apiSecret;
        if (usedSecret != null && usedSecret != apiSecret) {
          try {
            await repository.updateMaidCafeConfig(
              widget.server,
              daemonUrl: 'http://127.0.0.1:$resolvedPort',
              metricsSecret: usedSecret,
            );
          } catch (_) {
            // Best effort: keep the working connection regardless.
          }
        }
        return true;
      }
      return false;
    } catch (_) {
      // The shared session is broken; drop it so the next connect reopens.
      _sessionRegistry.invalidate(widget.server);
      rethrow;
    }
  }

  /// Opens the tabbed install sheet: channel → what the script does → the
  /// exact script. Returns the chosen channel name, or null when cancelled.
  Future<String?> _showInstallSheet({
    required bool updating,
    required int port,
    required String apiSecret,
  }) async {
    final channels = await fetchMaidCafeDistributionChannels();
    final installable = channels
        .where(
          (channel) => channel.latest?.artifactFor('linux', 'amd64') != null,
        )
        .toList();
    if (installable.isEmpty) {
      throw StateError('maidCafeNoInstallableChannels'.tr());
    }
    if (!mounted) return null;
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => MaidCafeInstallSheet(
        channels: installable,
        updating: updating,
        transport: _transport,
        scriptBuilder: (channel) => _buildInstallPreviewScript(
          channel: channel,
          port: port,
          apiSecret: apiSecret,
        ),
      ),
    );
  }

  /// Builds the exact install script the flow will run for [channel], so the
  /// sheet can show it before anything touches the server.
  Future<String> _buildInstallPreviewScript({
    required String channel,
    required int port,
    required String apiSecret,
    bool updating = false,
  }) async {
    final artifact = await fetchMaidCafeDistributionArtifact(channel: channel);
    return buildMaidCafeDaemonInstallScript(
      daemonId: _configText(_daemonIdController, 'maidkit-${widget.server.id}'),
      cloudUrl: _cloudUrlController.text.trim(),
      cloudSecret: _cloudSecretController.text,
      artifactUrl: artifact.downloadUrl,
      version: artifact.version,
      transport: _transport,
      listenHost: _configText(_listenHostController, '127.0.0.1'),
      port: port,
      apiSecret: apiSecret,
      metricsInterval: _configText(_metricsIntervalController, '1m'),
      logsInterval: _configText(_logsIntervalController, '30s'),
      requestTimeout: _configText(_requestTimeoutController, '10s'),
      scriptTimeout: _configText(_scriptTimeoutController, '30s'),
      maxBodyBytes: _configInt(_maxBodyBytesController, 65536),
      maxConcurrentRuns: _configInt(_maxConcurrentRunsController, 4),
      actions: List.unmodifiable(_actions),
      alarms: List.unmodifiable(_alarms),
      updateOnly: updating,
    );
  }

  Future<void> _install({bool updating = false}) async {
    if (_busy || !widget.connected) return;
    // The install sheet previews the exact script, which embeds the port;
    // reject an invalid edited port before opening it.
    if (_portEdited && _configuredPort() == null) {
      setState(() => _message = 'maidCafePortInvalid'.tr());
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      // Updates replace only the daemon binary, so the live config is not
      // needed and must not be rewritten; keep the current port.
      final apiSecret =
          updating && _metricsSecretController.text.trim().isNotEmpty
          ? _metricsSecretController.text.trim()
          : generateMaidCafeApiSecret();
      final port = await _resolveMaidCafePort(refreshRemote: updating);
      if (!mounted) return;
      final channel = await _showInstallSheet(
        updating: updating,
        port: port,
        apiSecret: apiSecret,
      );
      if (channel == null) return;
      final manager = ref.read(connectionManagerProvider);
      final existing = await detectMaidCafeInstallation(
        manager: manager,
        serverId: widget.server.id,
      ).timeout(const Duration(seconds: 20));
      if (!updating && !existing.contains('managed') && existing.isNotEmpty) {
        if (mounted) {
          setState(() {
            _state = _MaidCafeState.conflict;
            _message =
                '${'maidCafeExistingInstallation'.tr()}\n'
                '${existing.join('\n')}';
          });
        }
        return;
      }
      final credential = await ref
          .read(serverRepositoryProvider)
          .credentialFor(widget.server);
      final sudoPassword = credential.type == CredentialType.password
          ? credential.password
          : null;
      await installMaidCafeApplication(
        ref: ref,
        server: widget.server,
        channel: channel,
        sudoPassword: sudoPassword,
        port: port,
        apiSecret: apiSecret,
        daemonId: _configText(
          _daemonIdController,
          'maidkit-${widget.server.id}',
        ),
        cloudUrl: _cloudUrlController.text.trim(),
        cloudSecret: _cloudSecretController.text,
        transport: _transport,
        listenHost: _configText(_listenHostController, '127.0.0.1'),
        metricsInterval: _configText(_metricsIntervalController, '1m'),
        logsInterval: _configText(_logsIntervalController, '30s'),
        requestTimeout: _configText(_requestTimeoutController, '10s'),
        scriptTimeout: _configText(_scriptTimeoutController, '30s'),
        maxBodyBytes: _configInt(_maxBodyBytesController, 65536),
        maxConcurrentRuns: _configInt(_maxConcurrentRunsController, 4),
        actions: List.unmodifiable(_actions),
        alarms: List.unmodifiable(_alarms),
        updateOnly: updating,
      );
      await _cacheMaidCafePort(port);
      final opened = await _openStream(port: port, force: true);
      if (!opened) return;
      if (mounted) {
        setState(() {
          _state = _MaidCafeState.running;
          _latestVersion = null;
          _message = 'maidCafeInstallApplicationSuccess'.tr();
        });
        Future<void>.microtask(_refreshMetrics);
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uninstall() async {
    if (_busy || !widget.connected || _state != _MaidCafeState.running) {
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('maidCafeUninstallConfirmTitle'.tr()),
        content: Text('maidCafeUninstallConfirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('commonCancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('maidCafeUninstall'.tr()),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    _closeStream();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final sudoPassword = await _sudoPassword();
      await uninstallMaidCafeApplication(
        ref: ref,
        server: widget.server,
        sudoPassword: sudoPassword,
      );
      if (mounted) {
        setState(() {
          _state = _MaidCafeState.notInstalled;
          _latestVersion = null;
          _message = 'maidCafeUninstallSuccess'.tr();
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showDaemonLogs() async {
    if (!mounted || !widget.connected || _busy) return;
    final manager = ref.read(connectionManagerProvider);
    final credential = await ref
        .read(serverRepositoryProvider)
        .credentialFor(widget.server);
    final sudoPassword = credential.type == CredentialType.password
        ? credential.password
        : null;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _MaidCafeLogsSheet(
        title: 'maidCafeDaemonLogs'.tr(),
        load: () => manager.getSystemdUnitLogs(
          widget.server.id,
          unit: 'maidcafe-daemon.service',
          lines: 200,
          sshUserIsRoot: widget.server.username == 'root',
          sudoPassword: sudoPassword,
        ),
      ),
    );
  }

  Future<void> _rotateApiSecret() async {
    if (_busy || _stream == null || _state != _MaidCafeState.running) return;
    final apiSecret = generateMaidCafeApiSecret();
    _metricsSecretController.text = apiSecret;
    setState(() {
      _busy = true;
      _message = null;
      _stream = null;
    });
    _sessionRegistry.invalidate(widget.server);
    try {
      final credential = await ref
          .read(serverRepositoryProvider)
          .credentialFor(widget.server);
      final sudoPassword = credential.type == CredentialType.password
          ? credential.password
          : null;
      final port = await _resolveMaidCafePort();
      final manager = ref.read(connectionManagerProvider);
      await runWithDeployTerminal(
        ref: ref,
        title: 'maidCafeRotateApiSecret'.tr(),
        subtitle: widget.server.name,
        command: 'write MaidCafe API secret · restart systemd service',
        run: (onOutput) => manager.runPrivilegedScriptSnippet(
          widget.server.id,
          script: buildMaidCafeDaemonConfigScript(
            currentConfig: _serverConfigText,
            daemonId: _configText(
              _daemonIdController,
              'maidkit-${widget.server.id}',
            ),
            cloudUrl: _cloudUrlController.text.trim(),
            cloudSecret: _cloudSecretController.text,
            apiSecret: apiSecret,
            port: port,
            transport: _transport,
            listenHost: _configText(_listenHostController, '127.0.0.1'),
            metricsInterval: _configText(_metricsIntervalController, '1m'),
            logsInterval: _configText(_logsIntervalController, '30s'),
            requestTimeout: _configText(_requestTimeoutController, '10s'),
            scriptTimeout: _configText(_scriptTimeoutController, '30s'),
            maxBodyBytes: _configInt(_maxBodyBytesController, 65536),
            maxConcurrentRuns: _configInt(_maxConcurrentRunsController, 4),
            actions: List.unmodifiable(_actions),
            alarms: List.unmodifiable(_alarms),
          ),
          onOutput: onOutput,
          sshUserIsRoot: widget.server.username == 'root',
          sudoPassword: sudoPassword,
        ),
      );
      await ref
          .read(serverRepositoryProvider)
          .updateMaidCafeConfig(
            widget.server,
            daemonUrl: 'http://127.0.0.1:$port',
            metricsSecret: apiSecret,
          );
      final opened = await _openStream(port: port, force: true);
      if (!opened) return;
      if (mounted) {
        setState(() => _message = 'maidCafeRotateApiSecretSuccess'.tr());
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _state = _MaidCafeState.notInstalled;
          _message = error.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncConfiguration({String? successMessage}) async {
    if (_busy || _stream == null || _state != _MaidCafeState.running) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final stream = _stream;
    final apiSecret = _metricsSecretController.text.trim().isEmpty
        ? stream?.apiSecret ?? generateMaidCafeApiSecret()
        : _metricsSecretController.text.trim();
    _stream = null;
    _sessionRegistry.invalidate(widget.server);
    try {
      final credential = await ref
          .read(serverRepositoryProvider)
          .credentialFor(widget.server);
      final sudoPassword = credential.type == CredentialType.password
          ? credential.password
          : null;
      final port = await _resolveMaidCafePort();
      final manager = ref.read(connectionManagerProvider);
      await runWithDeployTerminal(
        ref: ref,
        title: 'maidCafeSaveConfiguration'.tr(),
        subtitle: widget.server.name,
        command: 'write MaidCafe configuration · restart systemd service',
        run: (onOutput) => manager.runPrivilegedScriptSnippet(
          widget.server.id,
          script: buildMaidCafeDaemonConfigScript(
            currentConfig: _serverConfigText,
            daemonId: _configText(
              _daemonIdController,
              'maidkit-${widget.server.id}',
            ),
            cloudUrl: _cloudUrlController.text.trim(),
            cloudSecret: _cloudSecretController.text,
            apiSecret: apiSecret,
            port: port,
            transport: _transport,
            listenHost: _configText(_listenHostController, '127.0.0.1'),
            metricsInterval: _configText(_metricsIntervalController, '1m'),
            logsInterval: _configText(_logsIntervalController, '30s'),
            requestTimeout: _configText(_requestTimeoutController, '10s'),
            scriptTimeout: _configText(_scriptTimeoutController, '30s'),
            maxBodyBytes: _configInt(_maxBodyBytesController, 65536),
            maxConcurrentRuns: _configInt(_maxConcurrentRunsController, 4),
            actions: List.unmodifiable(_actions),
            alarms: List.unmodifiable(_alarms),
          ),
          onOutput: onOutput,
          sshUserIsRoot: widget.server.username == 'root',
          sudoPassword: sudoPassword,
        ),
      );
      await _cacheMaidCafePort(port);
      await ref
          .read(serverRepositoryProvider)
          .updateMaidCafeConfig(
            widget.server,
            daemonUrl: 'http://127.0.0.1:$port',
            metricsSecret: apiSecret,
          );
      // The config and scripts are on the server; the reopen failure below is
      // connection-only, so the local snapshot is already committed.
      _savedActions = List.unmodifiable(_actions);
      final opened = await _openStream(port: port, force: true);
      if (!opened) return;
      if (mounted) {
        setState(
          () => _message =
              successMessage ?? 'maidCafeSaveConfigurationSuccess'.tr(),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _state = _MaidCafeState.notInstalled;
          _message = error.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkForUpdate() async {
    if (_busy || !widget.connected || _stream == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final latest = await fetchMaidCafeLatestVersion();
      final current = _stream?.version;
      if (mounted) {
        setState(() {
          _latestVersion = latest == current ? null : latest;
          _message = latest == current
              ? 'maidCafeUpToDate'.tr()
              : 'maidCafeUpdateAvailable'.tr(args: [latest]);
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshMetrics() async {
    final stream = _stream;
    if (stream == null || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await stream.metrics();
      if (mounted) {
        setState(() => _streamStatus = _streamStatusLine(stream));
      }
    } catch (error) {
      Object messageError = error;
      if (identical(_stream, stream)) {
        _stream = null;
        _sessionRegistry.invalidate(widget.server);
        try {
          await _openStream(force: true);
        } catch (reconnectError) {
          messageError = reconnectError;
        }
      }
      if (mounted) setState(() => _message = messageError.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendTestNotification() async {
    final stream = _stream;
    if (stream == null || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await stream.sendTestNotification();
      if (mounted) {
        setState(() => _message = 'maidCafeTestNotificationSent'.tr());
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Distinct action names present in the loaded audit entries, sorted.
  List<String> get _auditEntryNames {
    final names = <String>{for (final entry in _auditEntries) entry.name};
    final sorted = names.toList()..sort();
    return sorted;
  }

  /// Audit entries narrowed to the selected action (all when no filter).
  List<MaidCafeAuditEntry> get _visibleAuditEntries {
    final filter = _auditFilter;
    if (filter == null) return _auditEntries;
    return [
      for (final entry in _auditEntries)
        if (entry.name == filter) entry,
    ];
  }

  Future<void> _loadAudit() async {
    final stream = _stream;
    if (stream == null || _busy || _auditLoading) return;
    setState(() {
      _auditLoading = true;
      _auditError = null;
    });
    try {
      final entries = await stream.audit();
      if (mounted) {
        setState(() {
          _auditEntries = entries;
          _auditLoaded = true;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          // Terminal: do not reschedule on failure either, or the page
          // flashes the loader forever against an old daemon. The refresh
          // button retries.
          _auditLoaded = true;
          _auditError = error.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _auditLoading = false);
    }
  }

  /// Opens the full captured log for one audit entry.
  void _showAuditLog(BuildContext context, MaidCafeAuditEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _MaidCafeAuditLogSheet(entry: entry),
    );
  }

  Future<void> _confirmClearAudit() async {
    final stream = _stream;
    if (stream == null || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('maidCafeAuditClearConfirmTitle'.tr()),
        content: Text('maidCafeAuditClearConfirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('maidCafeCancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('maidCafeAuditClear'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await stream.clearAudit();
      if (mounted) {
        setState(() {
          _auditEntries = const [];
          _auditError = null;
          _auditFilter = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _auditError = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _invokeAction(MaidCafeActionDefinition action) async {
    final stream = _stream;
    if (stream == null || _busy) return;
    final variables = maidCafeActionTemplateVariables(action.script);
    Map<String, dynamic>? body;
    if (variables.isNotEmpty) {
      body = await _promptActionVariables(action, variables);
      if (body == null || !mounted) return; // Cancelled.
    }
    setState(() {
      _busy = true;
      _runningActionName = action.name;
    });
    try {
      final result = await stream.invokeAction(
        action.name,
        body: body,
        invokedBy: ref.read(cloudUserProvider).asData?.value?.handle,
      );
      if (mounted) {
        setState(() => _actionResults[action.name] = result);
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _runningActionName = null;
        });
      }
      await _loadAudit();
    }
  }

  /// Collects values for the `{{ name }}` template variables [action.script]
  /// references. Returns the JSON body for the invocation, or null when the
  /// user cancels. Previous values are prefilled.
  Future<Map<String, String>?> _promptActionVariables(
    MaidCafeActionDefinition action,
    List<String> variables,
  ) async {
    final previous = _actionVariableValues[action.name] ?? const {};
    final controllers = <String, TextEditingController>{
      for (final variable in variables)
        variable: TextEditingController(text: previous[variable] ?? ''),
    };
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('maidCafeActionVariables'.tr()),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('maidCafeActionVariablesHint'.tr()),
                for (final variable in variables) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: controllers[variable],
                    autofocus: variable == variables.first,
                    decoration: InputDecoration(
                      labelText: variable,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: variable == variables.last
                        ? (_) => Navigator.pop(dialogContext, {
                            for (final entry in controllers.entries)
                              entry.key: entry.value.text,
                          })
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('maidCafeCancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, {
              for (final entry in controllers.entries)
                entry.key: entry.value.text,
            }),
            child: Text('maidCafeRunAction'.tr()),
          ),
        ],
      ),
    );
    for (final controller in controllers.values) {
      controller.dispose();
    }
    if (values != null) {
      _actionVariableValues[action.name] = values;
    }
    return values;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.mode == MaidCafeTabMode.payload
        ? _buildPayload(context)
        : _buildInstallation(context);
  }

  Widget _buildInstallation(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Symbols.local_cafe, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'maidCafeTitle'.tr(),
                      style: theme.textTheme.titleMedium,
                    ),
                    if (_streamStatus != null)
                      Text(
                        _streamStatus!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Symbols.check_circle, color: scheme.primary),
            ],
          ).padding(bottom: 8),
          if (!widget.connected)
            _connectionPrompt()
          else if (_state == _MaidCafeState.checking)
            _checkingPrompt()
          else if (_state == _MaidCafeState.conflict)
            _conflictPrompt()
          else if (_state == _MaidCafeState.notInstalled)
            _notInstalledPrompt(context)
          else if (_state == _MaidCafeState.running)
            _installationRunning(),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  Widget _buildPayload(BuildContext context) {
    final theme = Theme.of(context);
    final running = widget.connected && _state == _MaidCafeState.running;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: running
              ? _payloadTabs(context)
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: !widget.connected
                      ? _connectionPrompt()
                      : _state == _MaidCafeState.checking
                      ? _checkingPrompt()
                      : _state == _MaidCafeState.conflict
                      ? _conflictPrompt()
                      : _notInstalledPrompt(context),
                ),
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(_message!, style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }

  Widget _payloadTabs(BuildContext context) => DefaultTabController(
    length: 5,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          tabs: [
            IconLabelTab(
              icon: const Icon(Symbols.settings, size: 18),
              label: 'maidCafeConfigTab'.tr(),
            ),
            IconLabelTab(
              icon: const Icon(Symbols.inventory_2, size: 18),
              label: 'maidCafeContainersTab'.tr(),
            ),
            IconLabelTab(
              icon: const Icon(Symbols.speed, size: 18),
              label: 'maidCafeAlarms'.tr(),
            ),
            IconLabelTab(
              icon: const Icon(Symbols.play_arrow, size: 18),
              label: 'maidCafeActions'.tr(),
            ),
            IconLabelTab(
              icon: const Icon(Symbols.receipt_long, size: 18),
              label: 'maidCafeAuditTab'.tr(),
            ),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              _configEditor(context),
              _uploadsTab(context),
              _alarmsTab(context),
              _actionsTab(context),
              _auditTab(context),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _uploadsTab(BuildContext context) {
    final stream = _stream;
    if (stream == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'maidCafeUploadsNeedSession'.tr(),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return MaidCafeUploadsTab(session: stream, onPersist: _persistUploadsPatch);
  }

  /// Persists managed-upload settings by patching the root-owned config over
  /// SSH — the daemon user cannot write /etc/maidcafe/config.toml on
  /// MaidKit-managed hosts — and letting the daemon's config watcher
  /// hot-reload it.
  Future<void> _persistUploadsPatch(Map<String, Object?> patch) async {
    final credential = await ref
        .read(serverRepositoryProvider)
        .credentialFor(widget.server);
    final sudoPassword = credential.type == CredentialType.password
        ? credential.password
        : null;
    final manager = ref.read(connectionManagerProvider);
    final stdio = _transport == 'stdio';
    await runWithDeployTerminal(
      ref: ref,
      title: 'maidCafeContainersTab'.tr(),
      subtitle: widget.server.name,
      command: 'write upload settings',
      run: (onOutput) => manager.runPrivilegedScriptSnippet(
        widget.server.id,
        script:
            buildMaidCafeUploadsPatchScript(
              currentConfig: _serverConfigText,
              values: maidCafeUploadsPatchTomlValues(patch),
              stdio: stdio,
            ) +
            (stdio
                ? ''
                : '\nsystemctl reload maidcafe-daemon 2>/dev/null || true\n'),
        onOutput: onOutput,
        sshUserIsRoot: widget.server.username == 'root',
        sudoPassword: sudoPassword,
      ),
    );
  }

  Widget _actionsTab(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _showComposer = !_showComposer),
                    icon: Icon(_showComposer ? Symbols.close : Symbols.add),
                    label: Text(
                      _showComposer
                          ? 'maidCafeCancel'.tr()
                          : 'maidCafeAddAction'.tr(),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _sendTestNotification,
                    icon: const Icon(Symbols.notifications_active),
                    label: Text('maidCafeSendTestNotification'.tr()),
                  ),
                ],
              ),
              if (_showComposer) ...[
                const SizedBox(height: 8),
                _actionComposer(context),
              ],
              // Stable gap between the composer block and the list: when the
              // composer closes after an add, the first card keeps the same
              // 16px breathing room instead of abutting the add button.
              const SizedBox(height: 16),
              if (_actions.isEmpty && !_showComposer)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'maidCafeNoActions'.tr(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (final action in _actions) ...[
                _MaidCafeActionCard(
                  key: ValueKey('maidcafe-action-${action.name}'),
                  action: action,
                  busy: _busy,
                  running: _runningActionName == action.name,
                  result: _actionResults[action.name],
                  onChanged: _stageAction,
                  onRun: () => _invokeAction(action),
                  onDelete: () => _removeAction(action),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        _actionsFooter(context),
      ],
    );
  }

  Widget _auditTab(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (_stream != null && !_auditLoaded && !_auditLoading) {
      Future<void>.microtask(_loadAudit);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'maidCafeAuditTitle'.tr(),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (_auditEntries.isNotEmpty)
              DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _auditFilter,
                  hint: Text('maidCafeAuditFilter'.tr()),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text('maidCafeAuditAll'.tr()),
                    ),
                    for (final name in _auditEntryNames)
                      DropdownMenuItem<String?>(value: name, child: Text(name)),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _auditFilter = value),
                ),
              ),
            IconButton(
              tooltip: 'maidCafeAuditClear'.tr(),
              onPressed: _busy || _auditEntries.isEmpty
                  ? null
                  : _confirmClearAudit,
              icon: const Icon(Symbols.delete_outline),
            ),
            IconButton(
              tooltip: 'commonRefresh'.tr(),
              onPressed: _busy ? null : _loadAudit,
              icon: const Icon(Symbols.refresh),
            ),
          ],
        ),
        if (_auditLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          )
        else if (_auditError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _auditError!,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          )
        else if (_auditEntries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'maidCafeAuditEmpty'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          )
        else if (_visibleAuditEntries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'maidCafeAuditNoMatches'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final entry in _visibleAuditEntries)
            _MaidCafeAuditRow(
              entry: entry,
              onTap: () => _showAuditLog(context, entry),
            ),
      ],
    );
  }

  Widget _actionComposer(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newActionNameController,
                    enabled: !_busy,
                    decoration: InputDecoration(
                      labelText: 'maidCafeActionSlug'.tr(),
                      hintText: 'deploy-web',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _newActionDisplayNameController,
                    enabled: !_busy,
                    decoration: InputDecoration(
                      labelText: 'maidCafeActionDisplayName'.tr(),
                      hintText: 'Deploy the web app',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _addAction,
                  icon: const Icon(Symbols.add),
                  label: Text('maidCafeAddAction'.tr()),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _MaidCafeScriptField(
              controller: _newActionController,
              focusNode: _newActionFocusNode,
              onChanged: (_) {},
            ),
            const SizedBox(height: 6),
            Text(
              'maidCafeActionScriptHint'.tr(),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            _MaidCafeExecutionSection(
              cwdController: _newActionCwdController,
              userController: _newActionUserController,
              timeoutController: _newActionTimeoutController,
              environment: _newActionEnvironment,
              enabled: !_busy,
              onEnvironmentChanged: (environment) =>
                  setState(() => _newActionEnvironment = environment),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionsFooter(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dirty = _actionsDirty;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            if (dirty) ...[
              Icon(Symbols.circle, size: 8, color: scheme.primary),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                dirty
                    ? 'maidCafeUnsavedChanges'.tr()
                    : 'maidCafeAllChangesSaved'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (dirty) ...[
              OutlinedButton(
                onPressed: _busy ? null : _discardActionChanges,
                child: Text('maidCafeDiscardChanges'.tr()),
              ),
              const SizedBox(width: 8),
            ],
            FilledButton.icon(
              onPressed: dirty && !_busy
                  ? () => _syncConfiguration(
                      successMessage: 'maidCafeSaveActionsSuccess'.tr(),
                    )
                  : null,
              icon: const Icon(Symbols.save),
              label: Text('maidCafeSaveActions'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _connectionPrompt() => Card.outlined(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.connectionError ?? 'detailConnectToCollect'.tr()),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: widget.onConnect,
              icon: const Icon(Symbols.link),
              label: Text('detailConnectForMetrics'.tr()),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _checkingPrompt() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const LinearProgressIndicator(),
      const SizedBox(height: 8),
      Text('maidCafeInstallChecking'.tr()),
    ],
  );

  Widget _conflictPrompt() => Card.outlined(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(_message ?? 'maidCafeExistingInstallation'.tr()),
    ),
  );

  Widget _notInstalledPrompt(BuildContext context) {
    final theme = Theme.of(context);
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'maidCafeNotInstalledTitle'.tr(),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text('maidCafeNotInstalledLead'.tr()),
            const SizedBox(height: 20),
            _sectionLabel(theme, 'maidCafeHowItWorks'.tr()),
            _benefitRow(
              icon: Symbols.dns,
              title: 'maidCafeHowItWorksDaemon'.tr(),
              description: 'maidCafeHowItWorksDaemonDesc'.tr(),
            ),
            _benefitRow(
              icon: Symbols.lock,
              title: 'maidCafeHowItWorksChannel'.tr(),
              description: 'maidCafeHowItWorksChannelDesc'.tr(),
            ),
            const SizedBox(height: 8),
            _sectionLabel(theme, 'maidCafeWhatYouGet'.tr()),
            _benefitRow(
              icon: Symbols.monitoring,
              title: 'maidCafeBenefitOfflineTitle'.tr(),
              description: 'maidCafeBenefitOfflineDesc'.tr(),
            ),
            _benefitRow(
              icon: Symbols.bolt,
              title: 'maidCafeBenefitWebhookTitle'.tr(),
              description: 'maidCafeBenefitWebhookDesc'.tr(),
            ),
            _benefitRow(
              icon: Symbols.restart_alt,
              title: 'maidCafeBenefitAlwaysOnTitle'.tr(),
              description: 'maidCafeBenefitAlwaysOnDesc'.tr(),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _install,
                  icon: const Icon(Symbols.download),
                  label: Text('maidCafeInstallApplication'.tr()),
                ),
                if (_message != null)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _showDaemonLogs,
                    icon: const Icon(Symbols.article),
                    label: Text('maidCafeViewDaemonLogs'.tr()),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _benefitRow({
    required IconData icon,
    required String title,
    required String description,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(description, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _installationRunning() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionLabel(
              theme,
              'maidCafeOperations'.tr(),
            ).padding(horizontal: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _refreshMetrics,
                  icon: const Icon(Symbols.monitoring),
                  label: Text('maidCafeRefreshMetrics'.tr()),
                ),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => ref
                            .read(terminalTabsProvider.notifier)
                            .openMaidCafePayload(widget.server),
                  icon: const Icon(Symbols.local_cafe),
                  label: Text('maidCafeOpenPayloadTab'.tr()),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _showDaemonLogs,
                  icon: const Icon(Symbols.article),
                  label: Text('maidCafeViewDaemonLogs'.tr()),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _checkForUpdate,
                  icon: const Icon(Symbols.update),
                  label: Text('maidCafeCheckUpdate'.tr()),
                ),
                if (_latestVersion != null)
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _install(updating: true),
                    icon: const Icon(Symbols.download),
                    label: Text('maidCafeUpdateApplication'.tr()),
                  ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _rotateApiSecret,
                  icon: const Icon(Symbols.key),
                  label: Text('maidCafeRotateApiSecret'.tr()),
                ),
              ],
            ).padding(horizontal: 16),
            const SizedBox(height: 16),
            Divider(color: scheme.outlineVariant),
            const SizedBox(height: 12),
            _sectionLabel(
              theme,
              'maidCafeDangerZone'.tr(),
            ).padding(horizontal: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'maidCafeUninstallHint'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _uninstall,
                    style: ButtonStyle(
                      foregroundColor: WidgetStatePropertyAll(scheme.error),
                    ),
                    icon: const Icon(Symbols.delete_outline),
                    label: Text('maidCafeUninstall'.tr()),
                  ),
                ),
              ],
            ).padding(horizontal: 16),
          ],
        ),
      ),
    );
  }

  /// Lays out config fields in 1/2/3 columns depending on available width.
  Widget _configFieldGrid(BuildContext context, List<Widget> fields) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 720 ? 3 : (width >= 460 ? 2 : 1);
        final rows = <Widget>[];
        for (var start = 0; start < fields.length; start += columns) {
          final count = math.min(columns, fields.length - start);
          rows.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < columns; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(
                      child: i < count
                          ? fields[start + i]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }

  Widget _configEditor(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _configGroup(
        title: 'maidCafeGroupIdentity'.tr(),
        fields: [
          _configTextField(
            readOnly: true,
            controller: _daemonIdController,
            label: 'maidCafeDaemonId'.tr(),
          ),
          DropdownButtonFormField<String>(
            key: ValueKey(_transport),
            initialValue: _transport,
            decoration: InputDecoration(labelText: 'maidCafeTransport'.tr()),
            items: const [
              DropdownMenuItem(value: 'http', child: Text('HTTP')),
              DropdownMenuItem(value: 'stdio', child: Text('stdio')),
            ],
            onChanged: _busy
                ? null
                : (value) {
                    if (value != null) setState(() => _transport = value);
                  },
          ),
          _configTextField(
            readOnly: true,
            controller: _versionController,
            label: 'maidCafeVersion'.tr(),
          ),
        ],
      ),
      _configGroup(
        title: 'maidCafeGroupNetwork'.tr(),
        fields: [
          _configTextField(
            controller: _listenHostController,
            label: 'maidCafeListenHost'.tr(),
          ),
          _configTextField(
            controller: _portController,
            label: 'maidCafePort'.tr(),
            keyboardType: TextInputType.number,
            onChanged: (_) => _portEdited = true,
          ),
          _configTextField(
            controller: _cloudUrlController,
            label: 'maidCafeCloudUrl'.tr(),
          ),
        ],
      ),
      _configGroup(
        title: 'maidCafeGroupSecrets'.tr(),
        fields: [
          _configTextField(
            controller: _cloudSecretController,
            label: 'maidCafeCloudSecret'.tr(),
            obscureText: true,
          ),
          _configTextField(
            controller: _metricsSecretController,
            label: 'maidCafeMetricsSecret'.tr(),
            obscureText: true,
          ),
        ],
      ),
      _configGroup(
        title: 'maidCafeGroupRuntime'.tr(),
        fields: [
          _configTextField(
            controller: _metricsIntervalController,
            label: 'maidCafeMetricsInterval'.tr(),
          ),
          _configTextField(
            controller: _logsIntervalController,
            label: 'maidCafeLogsInterval'.tr(),
            helperText: 'maidCafeLogsIntervalHint'.tr(),
          ),
          _configTextField(
            controller: _requestTimeoutController,
            label: 'maidCafeRequestTimeout'.tr(),
          ),
          _configTextField(
            controller: _scriptTimeoutController,
            label: 'maidCafeScriptTimeout'.tr(),
          ),
          _configTextField(
            controller: _maxBodyBytesController,
            label: 'maidCafeMaxBodyBytes'.tr(),
            keyboardType: TextInputType.number,
          ),
          _configTextField(
            controller: _maxConcurrentRunsController,
            label: 'maidCafeMaxConcurrentRuns'.tr(),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: _busy ? null : _syncConfiguration,
          icon: const Icon(Symbols.save),
          label: Text('maidCafeSaveConfigButton'.tr()),
        ),
      ),
    ],
  );

  /// Alarm thresholds are edited here, in the daemon's own config: the
  /// daemon evaluates each metric sample locally and reports `daemon.alarm.*`
  /// notifications to the cloud, so nothing here calls the cloud API. Saving
  /// deploys the `<kind>.toml` fragments and restarts the daemon.
  Widget _alarmsTab(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'maidCafeAlarmsHint'.tr(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        if (_alarms.isEmpty)
          Text(
            'maidCafeNoAlarms'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final alarm in _alarms) _alarmChip(context, alarm)],
          ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : () => _editAlarm(context),
            icon: const Icon(Symbols.add),
            label: Text('maidCafeAddAlarm'.tr()),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _busy ? null : _saveAlarms,
            icon: const Icon(Symbols.save),
            label: Text('maidCafeSaveAlarms'.tr()),
          ),
        ),
      ],
    );
  }

  Future<void> _saveAlarms() async {
    if (_busy || _stream == null || _state != _MaidCafeState.running) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    _stream = null;
    _sessionRegistry.invalidate(widget.server);
    try {
      final credential = await ref
          .read(serverRepositoryProvider)
          .credentialFor(widget.server);
      final sudoPassword = credential.type == CredentialType.password
          ? credential.password
          : null;
      final manager = ref.read(connectionManagerProvider);
      final stdio = _transport == 'stdio';
      await runWithDeployTerminal(
        ref: ref,
        title: 'maidCafeAlarms'.tr(),
        subtitle: widget.server.name,
        command: stdio
            ? 'write alarm fragments'
            : 'write alarm fragments · restart systemd service',
        run: (onOutput) => manager.runPrivilegedScriptSnippet(
          widget.server.id,
          script:
              buildMaidCafeAlarmFragmentsScript(
                List.unmodifiable(_alarms),
                stdio: stdio,
              ) +
              (stdio
                  ? ''
                  : '\nsystemctl reload maidcafe-daemon 2>/dev/null || systemctl restart maidcafe-daemon\n'),
          onOutput: onOutput,
          sshUserIsRoot: widget.server.username == 'root',
          sudoPassword: sudoPassword,
        ),
      );
      final port = await _resolveMaidCafePort();
      final opened = await _openStream(port: port, force: true);
      if (!opened) return;
      if (mounted) {
        setState(() => _message = 'maidCafeAlarmsSaved'.tr());
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _state = _MaidCafeState.notInstalled;
          _message = error.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _alarmChip(BuildContext context, MaidCafeAlarmDefinition alarm) {
    final kindLabel = switch (alarm.kind) {
      'cpu_percent' => 'maidCafeCpuAlarm'.tr(),
      'memory_used_percent' => 'maidCafeMemoryAlarm'.tr(),
      'disk_used_percent' => 'maidCafeDiskAlarm'.tr(),
      _ => 'maidCafeContainerAlarm'.tr(),
    };
    final threshold = alarm.kind == 'container_down'
        ? (alarm.target.isEmpty ? '' : ' · ${alarm.target}')
        : ' · ${alarm.threshold.toStringAsFixed(0)}%';
    return InputChip(
      label: Text(
        '$kindLabel$threshold · '
        '${'maidCafeAlarmCooldownLabel'.tr(args: ['${alarm.cooldownSeconds ~/ 60}'])}',
      ),
      onPressed: _busy ? null : () => _editAlarm(context, alarm),
      onDeleted: _busy ? null : () => _removeAlarm(alarm),
      deleteIcon: const Icon(Symbols.close, size: 16),
    );
  }

  Future<void> _editAlarm(
    BuildContext context, [
    MaidCafeAlarmDefinition? existing,
  ]) async {
    final alarm = await showModalBottomSheet<MaidCafeAlarmDefinition>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _AlarmEditorSheet(initial: existing),
    );
    if (alarm == null || !context.mounted) return;
    setState(() {
      // One alarm per kind and target; editing the same condition replaces it.
      _alarms = List.unmodifiable([
        ..._alarms.where(
          (current) =>
              current.kind != alarm.kind || current.target != alarm.target,
        ),
        alarm,
      ]);
    });
  }

  void _removeAlarm(MaidCafeAlarmDefinition alarm) {
    setState(() {
      _alarms = List.unmodifiable(
        _alarms.where((current) => current.kind != alarm.kind),
      );
    });
  }

  Widget _configGroup({required String title, required List<Widget> fields}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _configFieldGrid(context, fields),
        ],
      ),
    );
  }

  Widget _configTextField({
    required TextEditingController controller,
    required String label,
    String? helperText,
    bool readOnly = false,
    bool obscureText = false,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
  }) => TextField(
    controller: controller,
    enabled: !_busy,
    obscureText: obscureText,
    readOnly: readOnly,
    keyboardType: keyboardType,
    style: readOnly
        ? TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.5),
          )
        : null,
    onChanged: onChanged,
    decoration: InputDecoration(labelText: label, helperText: helperText),
  );
}

/// Install/update sheet: channel selection, script explanation, and the exact
/// script, arranged as a stepper. Fresh installs must visit every tab before
/// the install button unlocks; updates only need a channel chosen.
class MaidCafeInstallSheet extends StatefulWidget {
  const MaidCafeInstallSheet({
    super.key,
    required this.channels,
    required this.updating,
    required this.transport,
    required this.scriptBuilder,
  });

  final List<DistributionChannel> channels;
  final bool updating;
  final String transport;

  /// Builds the exact install script for a chosen channel so the user can
  /// review what will run on the server before anything is executed.
  final Future<String> Function(String channel) scriptBuilder;

  @override
  State<MaidCafeInstallSheet> createState() => MaidCafeInstallSheetState();
}

class MaidCafeInstallSheetState extends State<MaidCafeInstallSheet>
    with SingleTickerProviderStateMixin {
  static const _tabCount = 3;

  late final TabController _tabController;
  String? _selectedChannel;
  final Set<int> _visited = <int>{0};
  int _currentTab = 0;
  Future<String>? _scriptFuture;

  bool get _channelChosen => _selectedChannel != null;

  /// Updates skip the review gate; fresh installs must have seen all tabs.
  bool get _reviewed => widget.updating || _visited.length == _tabCount;

  bool get _canInstall => _channelChosen && _reviewed;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    final index = _tabController.index;
    if (index == _currentTab) return;
    _currentTab = index;
    setState(() => _visited.add(index));
  }

  void _selectChannel(String name) {
    setState(() {
      _selectedChannel = name;
      _scriptFuture = null;
    });
    _goTo(1);
  }

  void _goTo(int index) {
    if (index < 0 || index >= _tabCount) return;
    setState(() {
      _currentTab = index;
      _visited.add(index);
    });
    _tabController.animateTo(index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return FractionallySizedBox(
      heightFactor: 0.86,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
            child: Row(
              children: [
                Icon(Symbols.local_cafe, size: 22, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.updating
                        ? 'maidCafeUpdateApplication'.tr()
                        : 'maidCafeInstallApplication'.tr(),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'commonClose'.tr(),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Symbols.close),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TabBar(
            controller: _tabController,
            tabs: [
              Tab(
                icon: const Icon(Symbols.sell, size: 18),
                text: 'maidCafeInstallStepChannel'.tr(),
              ),
              Tab(
                icon: const Icon(Symbols.info, size: 18),
                text: 'maidCafeInstallStepExplain'.tr(),
              ),
              Tab(
                icon: const Icon(Symbols.code, size: 18),
                text: 'maidCafeInstallStepScript'.tr(),
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildChannelTab(context),
                _buildExplainTab(context),
                _buildScriptTab(context),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('maidCafeCancel'.tr()),
                ),
                const Spacer(),
                if (_currentTab > 0)
                  TextButton(
                    onPressed: () => _goTo(_currentTab - 1),
                    child: Text('maidCafeInstallBack'.tr()),
                  ),
                const SizedBox(width: 8),
                if (_currentTab < _tabCount - 1)
                  FilledButton(
                    onPressed: _currentTab == 0 && !_channelChosen
                        ? null
                        : () => _goTo(_currentTab + 1),
                    child: Text('maidCafeInstallNext'.tr()),
                  )
                else
                  FilledButton.icon(
                    onPressed: _canInstall
                        ? () => Navigator.pop(context, _selectedChannel)
                        : null,
                    icon: const Icon(Symbols.download),
                    label: Text(
                      widget.updating
                          ? 'maidCafeUpdateApplication'.tr()
                          : 'maidCafeInstallApplication'.tr(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelTab(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('maidCafeSelectChannelHint'.tr()),
      const SizedBox(height: 12),
      MaidCafeInstallChannelPicker(
        channels: widget.channels,
        selected: _selectedChannel,
        onSelected: _selectChannel,
      ),
    ],
  );

  Widget _buildExplainTab(BuildContext context) {
    final steps = widget.transport == 'stdio' ? _stdioSteps() : _systemdSteps();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('maidCafeInstallExplainLead'.tr()),
        const SizedBox(height: 16),
        for (final step in steps)
          _installStepRow(
            icon: step.$1,
            title: step.$2.tr(),
            description: step.$3.tr(),
          ),
      ],
    );
  }

  List<(IconData, String, String)> _systemdSteps() => const [
    (
      Symbols.download,
      'maidCafeInstallStepCurlTitle',
      'maidCafeInstallStepCurlDesc',
    ),
    (
      Symbols.cloud_download,
      'maidCafeInstallStepDownloadTitle',
      'maidCafeInstallStepDownloadDesc',
    ),
    (
      Symbols.terminal,
      'maidCafeInstallStepBinaryTitle',
      'maidCafeInstallStepBinaryDesc',
    ),
    (
      Symbols.person_add,
      'maidCafeInstallStepUserTitle',
      'maidCafeInstallStepUserDesc',
    ),
    (
      Symbols.tune,
      'maidCafeInstallStepConfigTitle',
      'maidCafeInstallStepConfigDesc',
    ),
    (
      Symbols.power,
      'maidCafeInstallStepSystemdTitle',
      'maidCafeInstallStepSystemdDesc',
    ),
    (
      Symbols.fact_check,
      'maidCafeInstallStepHealthTitle',
      'maidCafeInstallStepHealthDesc',
    ),
  ];

  List<(IconData, String, String)> _stdioSteps() => const [
    (
      Symbols.download,
      'maidCafeInstallStepCurlTitle',
      'maidCafeInstallStepCurlDesc',
    ),
    (
      Symbols.cloud_download,
      'maidCafeInstallStepDownloadTitle',
      'maidCafeInstallStepDownloadDesc',
    ),
    (
      Symbols.terminal,
      'maidCafeInstallStepBinaryTitle',
      'maidCafeInstallStepBinaryDesc',
    ),
    (
      Symbols.tune,
      'maidCafeInstallStepStdioConfigTitle',
      'maidCafeInstallStepStdioConfigDesc',
    ),
    (
      Symbols.code,
      'maidCafeInstallStepStdioNoteTitle',
      'maidCafeInstallStepStdioNoteDesc',
    ),
  ];

  Widget _installStepRow({
    required IconData icon,
    required String title,
    required String description,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(description, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScriptTab(BuildContext context) {
    final theme = Theme.of(context);
    final channel = _selectedChannel;
    if (channel == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'maidCafeInstallSelectChannelFirst'.tr(),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final future = _scriptFuture ??= widget.scriptBuilder(channel);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            'maidCafeInstallScriptNote'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<String>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final error = snapshot.error;
              if (error != null) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: SelectableText('$error'),
                );
              }
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    snapshot.data ?? '',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MaidCafeActionCard extends StatefulWidget {
  const _MaidCafeActionCard({
    super.key,
    required this.action,
    required this.busy,
    required this.running,
    required this.onChanged,
    required this.onRun,
    required this.onDelete,
    this.result,
  });

  final MaidCafeActionDefinition action;
  final bool busy;
  final bool running;
  final Map<String, dynamic>? result;
  final ValueChanged<MaidCafeActionDefinition> onChanged;
  final VoidCallback onRun;
  final VoidCallback onDelete;

  @override
  State<_MaidCafeActionCard> createState() => _MaidCafeActionCardState();
}

class _MaidCafeActionCardState extends State<_MaidCafeActionCard> {
  late final CodeController _scriptController;
  late final TextEditingController _displayNameController;
  late final TextEditingController _cwdController;
  late final TextEditingController _userController;
  late final TextEditingController _timeoutController;
  // The whole card configuration — display name, script body, execution
  // settings and notify toggles — folds away so a configured action reads as
  // a compact run surface. The run result stays visible either way.
  var _configExpanded = false;

  @override
  void initState() {
    super.initState();
    _scriptController = CodeController(
      text: widget.action.script,
      language: bash.bash,
    );
    _displayNameController = TextEditingController(
      text: widget.action.displayName ?? '',
    );
    _cwdController = TextEditingController(
      text: widget.action.workingDirectory ?? '',
    );
    _userController = TextEditingController(text: widget.action.user ?? '');
    _timeoutController = TextEditingController(
      text: widget.action.scriptTimeout ?? '',
    );
  }

  @override
  void didUpdateWidget(_MaidCafeActionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // External changes (reload after reconnect, discard) replace the script;
    // edits that originated here already match and are left alone so the
    // caret is not disturbed.
    if (widget.action.script != _scriptController.text) {
      _scriptController.text = widget.action.script;
    }
    if (widget.action.displayName != _displayNameController.text) {
      _displayNameController.text = widget.action.displayName ?? '';
    }
    if (widget.action.workingDirectory != _cwdController.text) {
      _cwdController.text = widget.action.workingDirectory ?? '';
    }
    if (widget.action.user != _userController.text) {
      _userController.text = widget.action.user ?? '';
    }
    if (widget.action.scriptTimeout != _timeoutController.text) {
      _timeoutController.text = widget.action.scriptTimeout ?? '';
    }
  }

  @override
  void dispose() {
    _scriptController.dispose();
    _displayNameController.dispose();
    _cwdController.dispose();
    _userController.dispose();
    _timeoutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final action = widget.action;
    final variables = maidCafeActionTemplateVariables(action.script);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: _configExpanded
                      ? 'maidCafeActionConfigCollapse'.tr()
                      : 'maidCafeActionConfigExpand'.tr(),
                  onPressed: () =>
                      setState(() => _configExpanded = !_configExpanded),
                  icon: AnimatedRotation(
                    turns: _configExpanded ? 0.5 : 0,
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 150),
                    child: const Icon(Symbols.expand_more),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        action.displayName?.trim().isNotEmpty ?? false
                            ? action.displayName!.trim()
                            : action.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontFamily:
                              action.displayName?.trim().isNotEmpty ?? false
                              ? null
                              : MaidKitFonts.mono,
                        ),
                      ),
                      if ((action.displayName?.trim().isNotEmpty ?? false) &&
                          action.displayName!.trim() != action.name)
                        Text(
                          action.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontFamily: MaidKitFonts.mono,
                          ),
                        ),
                      if (variables.isNotEmpty)
                        Text(
                          variables
                              .map((variable) => '{{ $variable }}')
                              .join('  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontFamily: MaidKitFonts.mono,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: action.enabled,
                  onChanged: widget.busy
                      ? null
                      : (value) =>
                            widget.onChanged(action.copyWith(enabled: value)),
                ),
                IconButton(
                  tooltip: 'maidCafeRunAction'.tr(),
                  onPressed: widget.busy ? null : widget.onRun,
                  icon: widget.running
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Symbols.play_arrow),
                ),
                IconButton(
                  tooltip: 'maidCafeRemoveAction'.tr(),
                  onPressed: widget.busy ? null : widget.onDelete,
                  icon: const Icon(Symbols.delete_outline),
                ),
              ],
            ),
            if (_configExpanded) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _displayNameController,
                enabled: !widget.busy,
                onChanged: (text) => widget.onChanged(
                  action.copyWith(
                    displayName: text.trim().isEmpty ? null : text.trim(),
                  ),
                ),
                decoration: InputDecoration(
                  labelText: 'maidCafeActionDisplayName'.tr(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              _MaidCafeScriptField(
                controller: _scriptController,
                onChanged: (text) =>
                    widget.onChanged(action.copyWith(script: text)),
              ),
              const SizedBox(height: 16),
              _MaidCafeExecutionSection(
                cwdController: _cwdController,
                userController: _userController,
                timeoutController: _timeoutController,
                environment: action.environment,
                enabled: !widget.busy,
                // Configured actions collapse to a compact run surface; the
                // composer (the definition moment) stays expanded.
                initiallyExpanded: false,
                onCwdChanged: (text) => widget.onChanged(
                  action.copyWith(
                    workingDirectory: text.trim().isEmpty ? null : text.trim(),
                  ),
                ),
                onUserChanged: (text) => widget.onChanged(
                  action.copyWith(
                    user: text.trim().isEmpty ? null : text.trim(),
                  ),
                ),
                onTimeoutChanged: (text) => widget.onChanged(
                  action.copyWith(
                    scriptTimeout: text.trim().isEmpty ? null : text.trim(),
                  ),
                ),
                onEnvironmentChanged: (environment) =>
                    widget.onChanged(action.copyWith(environment: environment)),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    label: Text('maidCafeNotifyOnSuccess'.tr()),
                    selected: action.notifyOnSuccess,
                    onSelected: widget.busy
                        ? null
                        : (value) => widget.onChanged(
                            action.copyWith(notifyOnSuccess: value),
                          ),
                  ),
                  FilterChip(
                    label: Text('maidCafeNotifyOnFailure'.tr()),
                    selected: action.notifyOnFailure,
                    onSelected: widget.busy
                        ? null
                        : (value) => widget.onChanged(
                            action.copyWith(notifyOnFailure: value),
                          ),
                  ),
                ],
              ),
            ],
            if (widget.result != null) ...[
              const SizedBox(height: 12),
              _MaidCafeActionResultView(result: widget.result!),
            ],
          ],
        ),
      ),
    );
  }
}

/// Working directory, run-as user, timeout and environment inputs for an
/// action. Collapsible so a configured action's card stays compact; the
/// composer keeps it expanded while a new action is being defined.
class _MaidCafeExecutionSection extends StatefulWidget {
  const _MaidCafeExecutionSection({
    required this.cwdController,
    required this.userController,
    required this.timeoutController,
    required this.environment,
    required this.onEnvironmentChanged,
    this.onCwdChanged,
    this.onUserChanged,
    this.onTimeoutChanged,
    this.enabled = true,
    this.initiallyExpanded = true,
  });

  final TextEditingController cwdController;
  final TextEditingController userController;
  final TextEditingController timeoutController;
  final Map<String, String> environment;
  final ValueChanged<Map<String, String>> onEnvironmentChanged;
  final ValueChanged<String>? onCwdChanged;
  final ValueChanged<String>? onUserChanged;
  final ValueChanged<String>? onTimeoutChanged;
  final bool enabled;
  final bool initiallyExpanded;

  @override
  State<_MaidCafeExecutionSection> createState() =>
      _MaidCafeExecutionSectionState();
}

class _MaidCafeExecutionSectionState extends State<_MaidCafeExecutionSection> {
  late var _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Text(
                  'maidCafeActionExecution'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 150),
                  child: Icon(
                    Symbols.expand_more,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: widget.cwdController,
                  enabled: widget.enabled,
                  onChanged: widget.onCwdChanged,
                  decoration: InputDecoration(
                    labelText: 'maidCafeActionCwd'.tr(),
                    hintText: '/srv/myapp',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: widget.userController,
                  enabled: widget.enabled,
                  onChanged: widget.onUserChanged,
                  decoration: InputDecoration(
                    labelText: 'maidCafeActionUser'.tr(),
                    hintText: 'deploy',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: widget.timeoutController,
                  enabled: widget.enabled,
                  onChanged: widget.onTimeoutChanged,
                  decoration: InputDecoration(
                    labelText: 'maidCafeActionTimeout'.tr(),
                    hintText: '30s',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _MaidCafeEnvEditor(
            environment: widget.environment,
            enabled: widget.enabled,
            onChanged: widget.onEnvironmentChanged,
          ),
          const SizedBox(height: 6),
          Text(
            'maidCafeActionExecutionHint'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// Key/value rows for an action's environment variables. Rows with an empty
/// name are ignored when collecting the map, so a half-filled row never
/// blocks saving; the "Add variable" button appends a fresh row.
class _MaidCafeEnvEditor extends StatefulWidget {
  const _MaidCafeEnvEditor({
    required this.environment,
    required this.onChanged,
    this.enabled = true,
  });

  final Map<String, String> environment;
  final ValueChanged<Map<String, String>> onChanged;
  final bool enabled;

  @override
  State<_MaidCafeEnvEditor> createState() => _MaidCafeEnvEditorState();
}

class _MaidCafeEnvEditorState extends State<_MaidCafeEnvEditor> {
  final List<TextEditingController> _keys = [];
  final List<TextEditingController> _values = [];

  @override
  void initState() {
    super.initState();
    _syncRows();
  }

  @override
  void didUpdateWidget(_MaidCafeEnvEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Rebuild rows only when the environment changed somewhere else
    // (reload, discard); edits that originated here already match.
    if (!_matchesCurrent(widget.environment)) _syncRows();
  }

  @override
  void dispose() {
    _disposeRows();
    super.dispose();
  }

  void _disposeRows() {
    for (final controller in _keys) {
      controller.dispose();
    }
    for (final controller in _values) {
      controller.dispose();
    }
    _keys.clear();
    _values.clear();
  }

  void _syncRows() {
    _disposeRows();
    final entries = widget.environment.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in entries) {
      _keys.add(TextEditingController(text: entry.key));
      _values.add(TextEditingController(text: entry.value));
    }
  }

  Map<String, String> _collect() {
    final result = <String, String>{};
    for (var i = 0; i < _keys.length; i++) {
      final key = _keys[i].text.trim();
      if (key.isNotEmpty) result[key] = _values[i].text;
    }
    return result;
  }

  bool _matchesCurrent(Map<String, String> environment) {
    final collected = _collect();
    if (collected.length != environment.length) return false;
    for (final entry in environment.entries) {
      if (collected[entry.key] != entry.value) return false;
    }
    return true;
  }

  void _notify() => widget.onChanged(_collect());

  void _addRow() {
    setState(() {
      _keys.add(TextEditingController());
      _values.add(TextEditingController());
    });
  }

  void _removeRow(int index) {
    setState(() {
      _keys.removeAt(index).dispose();
      _values.removeAt(index).dispose();
      _notify();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _keys.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _keys[i],
                    enabled: widget.enabled,
                    onChanged: (_) => _notify(),
                    decoration: InputDecoration(
                      labelText: 'maidCafeActionEnvKey'.tr(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _values[i],
                    enabled: widget.enabled,
                    onChanged: (_) => _notify(),
                    decoration: InputDecoration(
                      labelText: 'maidCafeActionEnvValue'.tr(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'maidCafeActionEnvRemove'.tr(),
                  onPressed: widget.enabled ? () => _removeRow(i) : null,
                  icon: const Icon(Symbols.remove_circle_outline, size: 18),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: widget.enabled ? _addRow : null,
            icon: const Icon(Symbols.add, size: 16),
            label: Text('maidCafeActionEnvAdd'.tr()),
          ),
        ),
      ],
    );
  }
}

/// Syntax-highlighted bash editor used for action script bodies.
class _MaidCafeScriptField extends StatelessWidget {
  const _MaidCafeScriptField({
    required this.controller,
    required this.onChanged,
    this.focusNode,
  });

  static const _height = 168.0;

  final CodeController controller;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: _height,
      child: DecoratedBox(
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
                'literal': TextStyle(color: scheme.secondary),
                'built_in': TextStyle(color: scheme.primary),
              },
            ),
            child: CodeField(
              controller: controller,
              focusNode: focusNode,
              expands: true,
              wrap: false,
              padding: const EdgeInsets.all(12),
              textStyle: const TextStyle(
                fontFamily: MaidKitFonts.mono,
                fontSize: 13,
                height: 1.45,
              ),
              gutterStyle: GutterStyle(
                textStyle: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                ),
                showErrors: false,
                showFoldingHandles: false,
              ),
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact one-line execution record from the daemon audit log. Tapping
/// opens the full captured output in a sheet.
class _MaidCafeAuditRow extends StatelessWidget {
  const _MaidCafeAuditRow({required this.entry, required this.onTap});

  final MaidCafeAuditEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ok = entry.ok;
    final invokedBy = entry.invokedBy;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Icon(
              ok ? Symbols.check_circle : Symbols.error,
              size: 18,
              color: ok ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Badge(
                        label: Text(entry.source),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        textColor: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ],
                  ),
                  Tooltip(
                    message: 'invokedBy'.tr(),
                    child: Row(
                      children: [
                        const Icon(Symbols.arrow_right_alt, size: 13),
                        const SizedBox(width: 8),
                        Text(
                          invokedBy ?? 'unknown'.tr(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontFamily: MaidKitFonts.mono,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(Symbols.info, size: 13),
                      const SizedBox(width: 8),
                      Text(
                        'exit ${entry.exitCode} · ${entry.durationMs}ms',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontFamily: MaidKitFonts.mono,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _formatAuditTime(entry.timestamp),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Symbols.chevron_right, size: 16),
          ],
        ),
      ),
    );
  }
}

String _formatAuditTime(DateTime time) {
  final now = DateTime.now();
  final clock =
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
  if (time.year == now.year && time.month == now.month && time.day == now.day) {
    return clock;
  }
  return '${time.month}/${time.day} $clock';
}

/// Compact run result for one action: exit code plus stdout/stderr panes.
class _MaidCafeActionResultView extends StatelessWidget {
  const _MaidCafeActionResultView({required this.result});

  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ok = result['ok'] == true;
    // The daemon responds with snake_case keys; `exit_code` is what the
    // action endpoint returns, not `exitCode`.
    final exitCode = result['exit_code'];
    final stdout = result['stdout']?.toString() ?? '';
    final stderr = result['stderr']?.toString() ?? '';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  ok ? Symbols.check_circle : Symbols.error,
                  size: 18,
                  color: ok ? scheme.primary : scheme.error,
                ),
                const SizedBox(width: 8),
                Text(
                  ok
                      ? 'maidCafeActionCompleted'.tr()
                      : 'maidCafeActionFailed'.tr(),
                  style: theme.textTheme.bodySmall,
                ),
                const Spacer(),
                Text(
                  '${'maidCafeActionExitCode'.tr()} $exitCode',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFamily: MaidKitFonts.mono,
                  ),
                ),
              ],
            ),
            if (stdout.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'maidCafeActionStdout'.tr(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(height: 120, child: AnsiLogView(text: stdout)),
            ],
            if (stderr.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'maidCafeActionStderr'.tr(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(height: 120, child: AnsiLogView(text: stderr)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Full captured log for one audit entry: metadata, then the run's stdout
/// and stderr as recorded by the daemon.
class _MaidCafeAuditLogSheet extends StatelessWidget {
  const _MaidCafeAuditLogSheet({required this.entry});

  final MaidCafeAuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metadata = [
      entry.source,
      if (entry.invokedBy != null && entry.invokedBy!.isNotEmpty)
        entry.invokedBy!,
      'exit ${entry.exitCode}',
      '${entry.durationMs}ms',
      _formatAuditTime(entry.timestamp),
    ].join(' · ');
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.78,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(entry.label, style: theme.textTheme.titleLarge),
                ),
                IconButton(
                  tooltip: 'commonCancel'.tr(),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Symbols.close),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              metadata,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontFamily: MaidKitFonts.mono,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: entry.stdout.isEmpty && entry.stderr.isEmpty
                  ? Center(
                      child: Text(
                        'maidCafeAuditNoOutput'.tr(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (entry.stdout.isNotEmpty) ...[
                          Text(
                            'maidCafeActionStdout'.tr(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: AnsiLogView(
                              text: entry.stdout,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ],
                        if (entry.stderr.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'maidCafeActionStderr'.tr(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: AnsiLogView(
                              text: entry.stderr,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaidCafeLogsSheet extends StatelessWidget {
  const _MaidCafeLogsSheet({required this.title, required this.load});

  final String title;
  final Future<String> Function() load;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * 0.78,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'commonCancel'.tr(),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Symbols.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<String>(
              future: load(),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return SelectableText('${snapshot.error}');
                }
                return AnsiLogView(
                  text: snapshot.data ?? '',
                  borderRadius: BorderRadius.circular(8),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

int? _cachedMaidCafePort(Server server) {
  final value = server.maidCafeDaemonUrl;
  if (value == null || value.isEmpty) return null;
  final port = Uri.tryParse(value)?.port;
  return port == null || port < maidCafeMinimumPort || port > 65535
      ? null
      : port;
}

/// Add/edit sheet for one alarm threshold. Cooldown is entered in minutes
/// and stored as seconds, matching the daemon's `cooldownSeconds` field.
class _AlarmEditorSheet extends StatefulWidget {
  const _AlarmEditorSheet({this.initial});

  final MaidCafeAlarmDefinition? initial;

  @override
  State<_AlarmEditorSheet> createState() => _AlarmEditorSheetState();
}

class _AlarmEditorSheetState extends State<_AlarmEditorSheet> {
  late final TextEditingController _thresholdController;
  late final TextEditingController _targetController;
  late final TextEditingController _cooldownController;
  late String _kind;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _kind = initial?.kind ?? 'cpu_percent';
    _thresholdController = TextEditingController(
      text: initial == null ? '80' : initial.threshold.toStringAsFixed(0),
    );
    _targetController = TextEditingController(text: initial?.target ?? '');
    _cooldownController = TextEditingController(
      text: initial == null ? '5' : '${initial.cooldownSeconds ~/ 60}',
    );
  }

  @override
  void dispose() {
    _thresholdController.dispose();
    _targetController.dispose();
    _cooldownController.dispose();
    super.dispose();
  }

  void _submit() {
    final threshold = double.tryParse(_thresholdController.text.trim()) ?? 0;
    final minutes = int.tryParse(_cooldownController.text.trim());
    if (_kind != 'container_down' && (threshold <= 0 || threshold > 100)) {
      setState(() => _error = 'maidCafeAlarmThresholdInvalid'.tr());
      return;
    }
    if (minutes == null || minutes <= 0) {
      setState(() => _error = 'maidCafeAlarmCooldownInvalid'.tr());
      return;
    }
    Navigator.pop(
      context,
      MaidCafeAlarmDefinition(
        kind: _kind,
        threshold: threshold,
        target: _targetController.text.trim(),
        cooldownSeconds: minutes * 60,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 560,
    child: SheetScaffold(
      titleText: widget.initial == null
          ? 'maidCafeAddAlarm'.tr()
          : 'maidCafeAlarms'.tr(),
      heightFactor: 0.5,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _kind,
            decoration: InputDecoration(labelText: 'maidCafeAlarmKind'.tr()),
            items: const [
              DropdownMenuItem(value: 'cpu_percent', child: Text('CPU')),
              DropdownMenuItem(
                value: 'memory_used_percent',
                child: Text('Memory'),
              ),
              DropdownMenuItem(value: 'disk_used_percent', child: Text('Disk')),
              DropdownMenuItem(
                value: 'container_down',
                child: Text('Container down'),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _kind = value);
            },
          ),
          const SizedBox(height: 12),
          if (_kind == 'container_down')
            TextField(
              controller: _targetController,
              decoration: InputDecoration(
                labelText: 'maidCafeAlarmTarget'.tr(),
                hintText: 'maidCafeAlarmTargetHint'.tr(),
              ),
            )
          else
            TextField(
              controller: _thresholdController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'maidCafeThreshold'.tr(),
                errorText: _error,
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _cooldownController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'maidCafeAlarmCooldown'.tr(),
              errorText: _error,
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
                onPressed: _submit,
                child: Text('maidCafeSave'.tr()),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
