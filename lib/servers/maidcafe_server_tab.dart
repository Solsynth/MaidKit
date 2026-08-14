import 'package:easy_localization/easy_localization.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'maidcafe_install.dart';
import 'maidcafe_stream.dart';
import 'server_models.dart';
import 'server_providers.dart';

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
  String? _message;
  String? _streamStatus;

  @override
  void initState() {
    super.initState();
    _actionNameController = TextEditingController();
    _actionCommandController = TextEditingController();
    _actionArgumentsController = TextEditingController();
  }

  @override
  void didUpdateWidget(MaidCafeServerTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.connected && oldWidget.connected) {
      _closeStream();
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

  void _addAction() {
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

  Future<void> _install() async {
    if (_busy || !widget.connected) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final credential = await ref
          .read(serverRepositoryProvider)
          .credentialFor(widget.server);
      final sudoPassword = credential.type == CredentialType.password
          ? credential.password
          : null;
      await installMaidCafeApplication(
        ref: ref,
        server: widget.server,
        sudoPassword: sudoPassword,
        actions: List.unmodifiable(_actions),
      );
      try {
        await _openStream();
        if (mounted) {
          setState(() => _message = 'maidCafeInstallApplicationSuccess'.tr());
        }
      } catch (error) {
        if (mounted) {
          setState(
            () =>
                _message = '${'maidCafeInstallApplicationSuccess'.tr()} $error',
          );
        }
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshMetrics() async {
    final stream = _stream;
    if (stream == null) return;
    try {
      final metrics = await stream.metrics();
      if (mounted) {
        setState(
          () => _streamStatus =
              '${'maidCafeStreamConnected'.tr()} · CPU ${metrics['cpu_percent']}%',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
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
          else ...[
            _actionEditor(context),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _install,
              icon: const Icon(Symbols.download),
              label: Text('maidCafeInstallApplication'.tr()),
            ),
            if (_streamStatus != null) ...[
              const SizedBox(height: 16),
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
                onPressed: _busy
                    ? null
                    : () => setState(() => _actions.remove(action)),
                icon: const Icon(Symbols.delete_outline),
              ),
            ),
        ],
      ),
    ),
  );
}
