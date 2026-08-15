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
import 'maidcafe_service.dart';
import 'server_models.dart';
import 'server_providers.dart';
import 'package:solsynth_express/solsynth_express.dart';

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

/// The lightweight MaidCafe entry point for a managed server.
class MaidCafeServerTab extends ConsumerStatefulWidget {
  const MaidCafeServerTab({
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
  ConsumerState<MaidCafeServerTab> createState() => _MaidCafeServerTabState();
}

class _MaidCafeServerTabState extends ConsumerState<MaidCafeServerTab> {
  late final TextEditingController _actionNameController;
  late final TextEditingController _actionCommandController;
  late final TextEditingController _actionArgumentsController;
  late final TextEditingController _portController;
  final _actions = <MaidCafeActionDefinition>[];
  MaidCafeStreamSession? _stream;
  var _streamGeneration = 0;
  var _portEdited = false;
  var _busy = false;
  var _state = _MaidCafeState.checking;
  String? _message;
  String? _streamStatus;
  String? _systemdStatus;
  String? _latestVersion;

  @override
  void initState() {
    super.initState();
    _actionNameController = TextEditingController();
    _actionCommandController = TextEditingController();
    _actionArgumentsController = TextEditingController();
    final cachedPort = _cachedMaidCafePort(widget.server);
    _portController = TextEditingController(
      text: cachedPort == null ? '' : '$cachedPort',
    );
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
    _closeStream();
    super.dispose();
  }

  void _closeStream() {
    _streamGeneration++;
    final stream = _stream;
    _stream = null;
    if (stream != null) Future<void>.microtask(stream.close);
  }

  int? _configuredPort() {
    final value = int.tryParse(_portController.text.trim());
    return value != null && value >= maidCafeMinimumPort && value <= 65535
        ? value
        : null;
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

  Future<void> _probeInstallation() async {
    if (!mounted || !widget.connected || _busy) return;
    setState(() {
      _state = _MaidCafeState.checking;
      _message = null;
      _systemdStatus = null;
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
      final port = await _resolveMaidCafePort(refreshRemote: true);
      final opened = await _openStream(port: port);
      if (opened && mounted) setState(() => _state = _MaidCafeState.running);
    } catch (error) {
      _closeStream();
      if (mounted) {
        setState(() {
          _state = _MaidCafeState.notInstalled;
          _message = managed
              ? 'maidCafeInstallationUnavailable'.tr()
              : 'maidCafeInstallationCheckFailed'.tr();
        });
        if (managed) Future<void>.microtask(_loadSystemdStatus);
      }
    }
  }

  Future<void> _loadSystemdStatus() async {
    try {
      final credential = await ref
          .read(serverRepositoryProvider)
          .credentialFor(widget.server);
      final status = await ref
          .read(connectionManagerProvider)
          .getSystemdUnitStatus(
            widget.server.id,
            unit: 'maidcafe-daemon.service',
            sshUserIsRoot: widget.server.username == 'root',
            sudoPassword: credential.type == CredentialType.password
                ? credential.password
                : null,
          );
      if (mounted) setState(() => _systemdStatus = status);
    } catch (error) {
      if (mounted) setState(() => _systemdStatus = error.toString());
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
    setState(() {
      _actions.add(
        MaidCafeActionDefinition(
          name: name,
          command: command,
          arguments: _actionArgumentsController.text
              .split(',')
              .map((argument) => argument.trim())
              .where((argument) => argument.isNotEmpty)
              .toList(),
        ),
      );
      _actionNameController.clear();
      _actionCommandController.clear();
      _actionArgumentsController.clear();
      _message = null;
    });
    await _syncConfiguration();
  }

  Future<void> _removeAction(MaidCafeActionDefinition action) async {
    setState(() => _actions.remove(action));
    await _syncConfiguration();
  }

  Future<bool> _openStream({int? port}) async {
    final generation = ++_streamGeneration;
    final apiSecret = await ref
        .read(serverRepositoryProvider)
        .maidCafeMetricsSecretFor(widget.server);
    final stream = await MaidCafeStreamSession.open(
      manager: ref.read(connectionManagerProvider),
      server: widget.server,
      port: port ?? await _resolveMaidCafePort(),
      apiSecret: apiSecret,
    );
    try {
      final health = await stream.health();
      final version = health['version']?.toString().trim();
      final versionSuffix = version == null || version.isEmpty
          ? ''
          : ' · v$version';
      if (!mounted || !widget.connected || generation != _streamGeneration) {
        await stream.close();
        return false;
      }
      await _stream?.close();
      if (mounted) {
        setState(() {
          _stream = stream;
          _streamStatus =
              '${'maidCafeStreamConnected'.tr()}$versionSuffix · ${health['id']}';
        });
        return true;
      }
      await stream.close();
      return false;
    } catch (_) {
      await stream.close();
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
      final apiSecret = generateMaidCafeApiSecret();
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
      );
      await _cacheMaidCafePort(port);
      final opened = await _openStream(port: port);
      if (!opened) return;
      if (mounted) {
        setState(() {
          _state = _MaidCafeState.running;
          _latestVersion = null;
          _message = 'maidCafeInstallApplicationSuccess'.tr();
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
    final stream = _stream;
    final version = stream?.version ?? '';
    final apiSecret = generateMaidCafeApiSecret();
    setState(() {
      _busy = true;
      _message = null;
      _stream = null;
    });
    await stream?.close();
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
            daemonId: 'maidkit-${widget.server.id}',
            cloudUrl: '',
            cloudSecret: '',
            version: version,
            apiSecret: apiSecret,
            port: port,
            transport: 'http',
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
      final opened = await _openStream(port: port);
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
    final apiSecret = stream?.apiSecret ?? generateMaidCafeApiSecret();
    _stream = null;
    await stream?.close();
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
            daemonId: 'maidkit-${widget.server.id}',
            cloudUrl: '',
            cloudSecret: '',
            version: version ?? '',
            apiSecret: apiSecret,
            port: port,
            transport: 'http',
            actions: List.unmodifiable(_actions),
          ),
          onOutput: onOutput,
          sshUserIsRoot: widget.server.username == 'root',
          sudoPassword: sudoPassword,
        ),
      );
      await _cacheMaidCafePort(port);
      final opened = await _openStream(port: port);
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
      final metrics = await stream.metrics();
      if (mounted) {
        setState(
          () => _streamStatus =
              '${'maidCafeStreamConnected'.tr()} · CPU ${metrics['cpu_percent']}%',
        );
      }
    } catch (error) {
      Object messageError = error;
      if (identical(_stream, stream)) {
        _stream = null;
        await stream.close();
        try {
          await _openStream();
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
            ],
          ),
          const SizedBox(height: 8),
          Text('maidCafeServerInstallHint'.tr()),
          if (widget.connected) ...[
            Material(
              type: MaterialType.transparency,
              child: TextField(
                controller: _portController,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                onChanged: (_) => _portEdited = true,
                decoration: InputDecoration(
                  labelText: 'maidCafePort'.tr(),
                  helperText: 'maidCafePortHint'.tr(),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (!widget.connected)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.connectionError ?? 'detailConnectToCollect'.tr(),
                    ),
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
            )
          else if (_state == _MaidCafeState.checking)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text('maidCafeInstallChecking'.tr()),
              ],
            )
          else if (_state == _MaidCafeState.conflict)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_message ?? 'maidCafeExistingInstallation'.tr()),
              ),
            )
          else if (_state == _MaidCafeState.notInstalled)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_systemdStatus != null) ...[
                  Text(
                    'maidCafeSystemdStatus'.tr(),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(_systemdStatus!),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _install,
                      icon: const Icon(Symbols.download),
                      label: Text('maidCafeInstallApplication'.tr()),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _showDaemonLogs,
                      icon: const Icon(Symbols.article),
                      label: Text('maidCafeViewDaemonLogs'.tr()),
                    ),
                  ],
                ),
              ],
            )
          else if (_state == _MaidCafeState.running) ...[
            _actionEditor(context),
            const SizedBox(height: 16),
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
                              onPressed: _busy
                                  ? null
                                  : () => _install(updating: true),
                              icon: const Icon(Symbols.download),
                              label: Text('maidCafeUpdateApplication'.tr()),
                            ),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _rotateApiSecret,
                            icon: const Icon(Symbols.key),
                            label: Text('maidCafeRotateApiSecret'.tr()),
                          ),
                          for (final action in _actions)
                            OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _invokeAction(action),
                              icon: const Icon(Symbols.play_arrow),
                              label: Text(action.name),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  Widget _actionEditor(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'maidCafeActions'.tr(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
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
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(action.name),
              subtitle: Text('${action.command} ${action.arguments.join(' ')}'),
              trailing: IconButton(
                tooltip: 'maidCafeRemoveAction'.tr(),
                onPressed: _busy ? null : () => _removeAction(action),
                icon: const Icon(Symbols.delete_outline),
              ),
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
