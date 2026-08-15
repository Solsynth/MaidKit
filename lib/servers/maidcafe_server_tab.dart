import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/shared/presentation/deploy_terminal.dart';
import 'package:maid_kit/shared/presentation/ansi_log_view.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'maidcafe_install.dart';
import 'maidcafe_stream.dart';
import 'maidcafe_session_registry.dart';
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

class MaidCafeInstallChannelPicker extends StatelessWidget {
  const MaidCafeInstallChannelPicker({
    super.key,
    required this.channels,
    required this.onSelected,
  });

  final List<DistributionChannel> channels;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: math.min(280.0, channels.length * 72.0),
    child: ListView.separated(
      itemCount: channels.length,
      separatorBuilder: (_, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final channel = channels[index];
        final release = channel.latest;
        return ListTile(
          title: Text(channel.name),
          subtitle: release == null ? null : Text(release.tagName),
          onTap: () => onSelected(channel.name),
        );
      },
    ),
  );
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
  late final TextEditingController _actionNameController;
  late final TextEditingController _actionCommandController;
  late final TextEditingController _actionArgumentsController;
  late final TextEditingController _portController;
  late final TextEditingController _daemonIdController;
  late final TextEditingController _versionController;
  late final TextEditingController _listenHostController;
  late final TextEditingController _cloudUrlController;
  late final TextEditingController _cloudSecretController;
  late final TextEditingController _metricsSecretController;
  late final TextEditingController _metricsIntervalController;
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
    _actionNameController = TextEditingController();
    _actionCommandController = TextEditingController();
    _actionArgumentsController = TextEditingController();
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
    _actionNameController.dispose();
    _actionCommandController.dispose();
    _actionArgumentsController.dispose();
    _portController.dispose();
    _daemonIdController.dispose();
    _versionController.dispose();
    _listenHostController.dispose();
    _cloudUrlController.dispose();
    _cloudSecretController.dispose();
    _metricsSecretController.dispose();
    _metricsIntervalController.dispose();
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
      final opened = await _openStream(port: port, force: true);
      if (opened && mounted) {
        setState(() => _state = _MaidCafeState.running);
        Future<void>.microtask(_refreshMetrics);
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

  Future<void> _addAction() async {
    final name = _actionNameController.text.trim();
    final command = _actionCommandController.text.trim();
    if (name.isEmpty || command.isEmpty || !command.startsWith('/')) {
      setState(() => _message = 'maidCafeActionCommandRequired'.tr());
      return;
    }
    if (_actions.any((action) => action.name == name)) {
      setState(() => _message = 'maidCafeActionNameUnique'.tr());
      return;
    }
    ref.read(maidCafeActionsProvider.notifier).setForServer(widget.server.id, [
      ..._actions,
      MaidCafeActionDefinition(
        name: name,
        command: command,
        arguments: _actionArgumentsController.text
            .split(',')
            .map((argument) => argument.trim())
            .where((argument) => argument.isNotEmpty)
            .toList(),
      ),
    ]);
    setState(() {
      _actionNameController.clear();
      _actionCommandController.clear();
      _actionArgumentsController.clear();
      _message = null;
    });
    await _syncConfiguration();
  }

  Future<void> _removeAction(MaidCafeActionDefinition action) async {
    ref.read(maidCafeActionsProvider.notifier).setForServer(widget.server.id, [
      for (final current in _actions)
        if (!identical(current, action)) current,
    ]);
    await _syncConfiguration();
  }

  Future<void> _updateAction(
    MaidCafeActionDefinition action, {
    bool? enabled,
    bool? notifyOnSuccess,
    bool? notifyOnFailure,
  }) async {
    ref.read(maidCafeActionsProvider.notifier).setForServer(widget.server.id, [
      for (final current in _actions)
        identical(current, action)
            ? MaidCafeActionDefinition(
                name: current.name,
                command: current.command,
                arguments: current.arguments,
                enabled: enabled ?? current.enabled,
                notifyOnSuccess: notifyOnSuccess ?? current.notifyOnSuccess,
                notifyOnFailure: notifyOnFailure ?? current.notifyOnFailure,
              )
            : current,
    ]);
    await _syncConfiguration();
  }

  /// Connection-only status line: no metrics, no raw daemon ids.
  String _streamStatusLine(MaidCafeStreamSession stream) {
    final version = stream.version;
    final versionSuffix = version == null || version.isEmpty
        ? ''
        : ' · v$version';
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

  Future<String?> _chooseInstallChannel() async {
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
    return showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'maidCafeSelectChannel'.tr(),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text('maidCafeSelectChannelHint'.tr()),
                const SizedBox(height: 12),
                MaidCafeInstallChannelPicker(
                  channels: installable,
                  onSelected: (channel) => Navigator.pop(context, channel),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('maidCafeCancel'.tr()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _install({bool updating = false}) async {
    if (_busy || !widget.connected) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final channel = await _chooseInstallChannel();
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
      if (updating) await _loadDaemonConfig();
      final apiSecret =
          updating && _metricsSecretController.text.trim().isNotEmpty
          ? _metricsSecretController.text.trim()
          : generateMaidCafeApiSecret();
      final port = await _resolveMaidCafePort(refreshRemote: updating);
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
        requestTimeout: _configText(_requestTimeoutController, '10s'),
        scriptTimeout: _configText(_scriptTimeoutController, '30s'),
        maxBodyBytes: _configInt(_maxBodyBytesController, 65536),
        maxConcurrentRuns: _configInt(_maxConcurrentRunsController, 4),
        actions: List.unmodifiable(_actions),
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
    final stream = _stream;
    final version = stream?.version ?? '';
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
            daemonId: _configText(
              _daemonIdController,
              'maidkit-${widget.server.id}',
            ),
            cloudUrl: _cloudUrlController.text.trim(),
            cloudSecret: _cloudSecretController.text,
            version: _configText(_versionController, version),
            apiSecret: apiSecret,
            port: port,
            transport: _transport,
            listenHost: _configText(_listenHostController, '127.0.0.1'),
            metricsInterval: _configText(_metricsIntervalController, '1m'),
            requestTimeout: _configText(_requestTimeoutController, '10s'),
            scriptTimeout: _configText(_scriptTimeoutController, '30s'),
            maxBodyBytes: _configInt(_maxBodyBytesController, 65536),
            maxConcurrentRuns: _configInt(_maxConcurrentRunsController, 4),
            actions: List.unmodifiable(_actions),
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

  Future<void> _syncConfiguration() async {
    if (_busy || _stream == null || _state != _MaidCafeState.running) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final stream = _stream;
    final version = stream?.version;
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
            daemonId: _configText(
              _daemonIdController,
              'maidkit-${widget.server.id}',
            ),
            cloudUrl: _cloudUrlController.text.trim(),
            cloudSecret: _cloudSecretController.text,
            version: _configText(_versionController, version ?? ''),
            apiSecret: apiSecret,
            port: port,
            transport: _transport,
            listenHost: _configText(_listenHostController, '127.0.0.1'),
            metricsInterval: _configText(_metricsIntervalController, '1m'),
            requestTimeout: _configText(_requestTimeoutController, '10s'),
            scriptTimeout: _configText(_scriptTimeoutController, '30s'),
            maxBodyBytes: _configInt(_maxBodyBytesController, 65536),
            maxConcurrentRuns: _configInt(_maxConcurrentRunsController, 4),
            actions: List.unmodifiable(_actions),
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
      final opened = await _openStream(port: port, force: true);
      if (!opened) return;
      if (mounted) {
        setState(() => _message = 'maidCafeSaveConfigurationSuccess'.tr());
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

  Future<void> _invokeAction(MaidCafeActionDefinition action) async {
    final stream = _stream;
    if (stream == null || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await stream.invokeAction(action.name);
      if (mounted) {
        setState(
          () => _message =
              '${'maidCafeActionCompleted'.tr()}: ${result['stdout'] ?? ''}',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
              Text('maidCafeTitle'.tr(), style: theme.textTheme.titleLarge),
              const Spacer(),
              IconButton(
                tooltip: 'maidCafePayloadTab'.tr(),
                onPressed: widget.connected
                    ? () => ref
                          .read(terminalTabsProvider.notifier)
                          .openMaidCafePayload(widget.server)
                    : null,
                icon: const Icon(Symbols.code),
              ),
            ],
          ),
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
    length: 2,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          tabs: [
            Tab(
              icon: const Icon(Symbols.settings, size: 18),
              text: 'maidCafeConfigTab'.tr(),
            ),
            Tab(
              icon: const Icon(Symbols.play_arrow, size: 18),
              text: 'maidCafeActions'.tr(),
            ),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [_configEditor(context), _actionsTab(context)],
          ),
        ),
      ],
    ),
  );

  Widget _actionsTab(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_streamStatus != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_streamStatus!),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final action in _actions)
                        OutlinedButton.icon(
                          onPressed: _busy ? null : () => _invokeAction(action),
                          icon: const Icon(Symbols.play_arrow),
                          label: Text(action.name),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        _actionEditor(context),
      ],
    ),
  );

  Widget _connectionPrompt() => Card(
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

  Widget _conflictPrompt() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(_message ?? 'maidCafeExistingInstallation'.tr()),
    ),
  );

  Widget _notInstalledPrompt(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'maidCafeNotInstalledTitle'.tr(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text('maidCafeNotInstalledLead'.tr()),
          const SizedBox(height: 16),
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

  Widget _installationRunning() => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_streamStatus != null) Text(_streamStatus!),
          const SizedBox(height: 8),
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
          ),
        ],
      ),
    ),
  );

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
    bool obscureText = false,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
  }) => TextField(
    controller: controller,
    enabled: !_busy,
    obscureText: obscureText,
    keyboardType: keyboardType,
    onChanged: onChanged,
    decoration: InputDecoration(labelText: label),
  );
  Widget _actionEditor(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('maidCafeActionsHint'.tr()),
          const SizedBox(height: 12),
          TextField(
            controller: _actionNameController,
            enabled: !_busy,
            decoration: InputDecoration(labelText: 'maidCafeActionName'.tr()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _actionCommandController,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: 'maidCafeActionCommand'.tr(),
              helperText: 'maidCafeActionCommandHint'.tr(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _actionArgumentsController,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: 'maidCafeActionArguments'.tr(),
              helperText: 'maidCafeActionArgumentsHint'.tr(),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _addAction,
              icon: const Icon(Symbols.add),
              label: Text('maidCafeAddAction'.tr()),
            ),
          ),
          for (final action in _actions)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(action.name),
                  subtitle: Text(
                    '${action.command} ${action.arguments.join(' ')}',
                  ),
                  trailing: IconButton(
                    tooltip: 'maidCafeRemoveAction'.tr(),
                    onPressed: _busy ? null : () => _removeAction(action),
                    icon: const Icon(Symbols.delete_outline),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('maidCafeActionEnabled'.tr()),
                  value: action.enabled,
                  onChanged: _busy
                      ? null
                      : (value) => _updateAction(action, enabled: value),
                ),
                Wrap(
                  spacing: 16,
                  children: [
                    FilterChip(
                      label: Text('maidCafeNotifyOnSuccess'.tr()),
                      selected: action.notifyOnSuccess,
                      onSelected: _busy
                          ? null
                          : (value) =>
                                _updateAction(action, notifyOnSuccess: value),
                    ),
                    FilterChip(
                      label: Text('maidCafeNotifyOnFailure'.tr()),
                      selected: action.notifyOnFailure,
                      onSelected: _busy
                          ? null
                          : (value) =>
                                _updateAction(action, notifyOnFailure: value),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    ),
  );
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
