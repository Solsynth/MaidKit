import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/shared/presentation/deploy_terminal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'maidcafe_install.dart';
import 'maidcafe_stream.dart';
import 'server_models.dart';
import 'server_providers.dart';

enum _MaidCafeState { checking, notInstalled, running, conflict }

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
  final _actions = <MaidCafeActionDefinition>[];
  MaidCafeStreamSession? _stream;
  var _busy = false;
  var _state = _MaidCafeState.checking;
  String? _message;
  String? _streamStatus;

  @override
  void initState() {
    super.initState();
    _actionNameController = TextEditingController();
    _actionCommandController = TextEditingController();
    _actionArgumentsController = TextEditingController();
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
    _closeStream();
    super.dispose();
  }

  void _closeStream() {
    final stream = _stream;
    _stream = null;
    if (stream != null) Future<void>.microtask(stream.close);
  }

  Future<void> _probeInstallation() async {
    if (!mounted || !widget.connected || _busy) return;
    setState(() {
      _state = _MaidCafeState.checking;
      _message = null;
    });
    try {
      final existing = await detectMaidCafeInstallation(
        manager: ref.read(connectionManagerProvider),
        serverId: widget.server.id,
      ).timeout(const Duration(seconds: 20));
      final managed = existing.contains('managed');
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
      await _openStream();
      if (mounted) setState(() => _state = _MaidCafeState.running);
    } catch (error) {
      _closeStream();
      if (mounted) {
        setState(() {
          _state = _MaidCafeState.notInstalled;
          _message = error.toString();
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

  Future<void> _openStream() async {
    final stream = await ref
        .read(connectionManagerProvider)
        .withClient(widget.server.id, MaidCafeStreamSession.open);
    try {
      final health = await stream.health();
      await _stream?.close();
      if (mounted) {
        setState(() {
          _stream = stream;
          _streamStatus = '${'maidCafeStreamConnected'.tr()} · ${health['id']}';
        });
      } else {
        await stream.close();
      }
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
      builder: (context) => AlertDialog(
        title: Text('maidCafeSelectChannel'.tr()),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('maidCafeSelectChannelHint'.tr()),
              const SizedBox(height: 12),
              ListView.separated(
                shrinkWrap: true,
                itemCount: installable.length,
                separatorBuilder: (_, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final channel = installable[index];
                  final release = channel.latest;
                  return ListTile(
                    title: Text(channel.name),
                    subtitle: release == null ? null : Text(release.tagName),
                    onTap: () => Navigator.pop(context, channel.name),
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('maidCafeCancel'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _install() async {
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
      if (existing.isNotEmpty) {
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
      );
      await _openStream();
      if (mounted) {
        setState(() {
          _state = _MaidCafeState.running;
          _message = 'maidCafeInstallApplicationSuccess'.tr();
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
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
    _stream = null;
    await stream?.close();
    try {
      final credential = await ref
          .read(serverRepositoryProvider)
          .credentialFor(widget.server);
      final sudoPassword = credential.type == CredentialType.password
          ? credential.password
          : null;
      final manager = ref.read(connectionManagerProvider);
      await runWithDeployTerminal(
        ref: ref,
        title: 'maidCafeSaveConfiguration'.tr(),
        subtitle: widget.server.name,
        command: 'write MaidCafe configuration · restart SSH stream',
        run: (onOutput) => manager.runPrivilegedScriptSnippet(
          widget.server.id,
          script: buildMaidCafeDaemonConfigScript(
            daemonId: 'maidkit-${widget.server.id}',
            cloudUrl: '',
            cloudSecret: '',
            actions: List.unmodifiable(_actions),
          ),
          sshUserIsRoot: widget.server.username == 'root',
          sudoPassword: sudoPassword,
          onOutput: onOutput,
        ),
      );
      await _openStream();
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
          const SizedBox(height: 20),
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
            FilledButton.icon(
              onPressed: _busy ? null : _install,
              icon: const Icon(Symbols.download),
              label: Text('maidCafeInstallApplication'.tr()),
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
