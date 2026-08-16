import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'port_forwarding_models.dart';
import 'server_providers.dart';

class PortForwardingTab extends ConsumerStatefulWidget {
  const PortForwardingTab({
    super.key,
    required this.server,
    required this.connected,
  });

  final Server server;
  final bool connected;

  @override
  ConsumerState<PortForwardingTab> createState() => _PortForwardingTabState();
}

class _PortForwardingTabState extends ConsumerState<PortForwardingTab> {
  final _formKey = GlobalKey<FormState>();
  final _bindHost = TextEditingController(text: '127.0.0.1');
  final _bindPort = TextEditingController();
  final _targetHost = TextEditingController(text: '127.0.0.1');
  final _targetPort = TextEditingController();
  var _direction = PortForwardDirection.local;
  var _kind = PortForwardKind.tcp;
  var _saveConfig = false;
  var _autoStartConfig = false;
  var _starting = false;

  @override
  void dispose() {
    _bindHost.dispose();
    _bindPort.dispose();
    _targetHost.dispose();
    _targetPort.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _starting = true);
    final kind = _kind;
    final targetHost = kind == PortForwardKind.tcp
        ? _targetHost.text.trim()
        : '';
    final targetPort = kind == PortForwardKind.tcp
        ? int.parse(_targetPort.text)
        : 0;
    final direction = _direction;
    final bindHost = _bindHost.text.trim();
    final bindPort = int.parse(_bindPort.text);
    try {
      await ref
          .read(connectionManagerProvider)
          .startPortForward(
            server: widget.server,
            direction: direction,
            kind: kind,
            bindHost: bindHost,
            bindPort: bindPort,
            targetHost: targetHost,
            targetPort: targetPort,
          );
      if (_saveConfig) {
        await ref
            .read(serverRepositoryProvider)
            .savePortForwardConfig(
              serverId: widget.server.id,
              direction: direction,
              kind: kind,
              bindHost: bindHost,
              bindPort: bindPort,
              targetHost: targetHost,
              targetPort: targetPort,
              autoStart: _autoStartConfig,
            );
      }
      if (mounted) {
        showSnackBar('portForwardingStarted'.tr());
      }
    } catch (error) {
      if (mounted) {
        showSnackBar('portForwardingStartError'.tr(args: ['$error']));
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _startConfig(PortForwardConfig config) async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      await ref
          .read(connectionManagerProvider)
          .startPortForward(
            server: widget.server,
            direction: PortForwardDirection.values.byName(config.direction),
            kind: PortForwardKind.values.byName(config.kind),
            bindHost: config.bindHost,
            bindPort: config.bindPort,
            targetHost: config.targetHost,
            targetPort: config.targetPort,
          );
      if (mounted) {
        showSnackBar('portForwardingStarted'.tr());
      }
    } catch (error) {
      if (mounted) {
        showSnackBar('portForwardingStartError'.tr(args: ['$error']));
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final forwards =
        (ref.watch(portForwardsProvider).asData?.value ??
                const <ActivePortForward>[])
            .where((forward) => forward.serverId == widget.server.id);
    final savedConfigs =
        ref.watch(portForwardConfigsProvider(widget.server.id)).asData?.value ??
        const <PortForwardConfig>[];
    final scheme = Theme.of(context).colorScheme;
    final directionDescription = switch ((_kind, _direction)) {
      (PortForwardKind.tcp, PortForwardDirection.local) =>
        'portForwardingLocalDesc',
      (PortForwardKind.tcp, PortForwardDirection.remote) =>
        'portForwardingRemoteDesc',
      (PortForwardKind.socks5, _) => 'portForwardingSocks5Desc',
    }.tr();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'portForwarding',
          style: Theme.of(context).textTheme.titleMedium,
        ).tr(),
        const SizedBox(height: 8),
        Text(
          directionDescription,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        if (!widget.connected)
          _ConnectionNotice()
        else
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<PortForwardKind>(
                  segments: [
                    ButtonSegment(
                      value: PortForwardKind.tcp,
                      icon: const Icon(Symbols.swap_horiz),
                      label: Text('portForwardingTcp').tr(),
                    ),
                    ButtonSegment(
                      value: PortForwardKind.socks5,
                      icon: const Icon(Symbols.vpn_lock),
                      label: Text('portForwardingSocks5').tr(),
                    ),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (value) => setState(() {
                    _kind = value.first;
                    // SOCKS5 is a local listener only.
                    if (_kind == PortForwardKind.socks5) {
                      _direction = PortForwardDirection.local;
                    }
                  }),
                ),
                const SizedBox(height: 16),
                if (_kind == PortForwardKind.tcp) ...[
                  SegmentedButton<PortForwardDirection>(
                    segments: [
                      ButtonSegment(
                        value: PortForwardDirection.local,
                        icon: const Icon(Symbols.laptop_mac),
                        label: Text('portForwardingLocal').tr(),
                      ),
                      ButtonSegment(
                        value: PortForwardDirection.remote,
                        icon: const Icon(Symbols.dns),
                        label: Text('portForwardingRemote').tr(),
                      ),
                    ],
                    selected: {_direction},
                    onSelectionChanged: (value) =>
                        setState(() => _direction = value.first),
                  ),
                  const SizedBox(height: 16),
                  _ForwardFields(
                    bindHost: _bindHost,
                    bindPort: _bindPort,
                    targetHost: _targetHost,
                    targetPort: _targetPort,
                    direction: _direction,
                  ),
                ] else
                  _HostPortFields(
                    label: 'portForwardingThisComputerListens',
                    host: _bindHost,
                    port: _bindPort,
                  ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  value: _saveConfig,
                  onChanged: (value) =>
                      setState(() => _saveConfig = value ?? false),
                  title: Text('portForwardingSaveConfig').tr(),
                  subtitle: Text('portForwardingSaveConfigHint').tr(),
                ),
                if (_saveConfig)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    value: _autoStartConfig,
                    onChanged: (value) =>
                        setState(() => _autoStartConfig = value ?? false),
                    title: Text('portForwardingAutoStart').tr(),
                  ),
                FilledButton.icon(
                  onPressed: _starting ? null : _start,
                  icon: _starting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Symbols.play_arrow),
                  label: Text('portForwardingStart').tr(),
                ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        Text(
          'portForwardingSaved',
          style: Theme.of(context).textTheme.titleSmall,
        ).tr(),
        const SizedBox(height: 8),
        if (savedConfigs.isEmpty)
          Text(
            'portForwardingSavedEmpty',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ).tr()
        else
          for (final config in savedConfigs)
            _SavedForwardTile(
              config: config,
              onStart: () => _startConfig(config),
            ),
        const SizedBox(height: 24),
        Text(
          'portForwardingActive',
          style: Theme.of(context).textTheme.titleSmall,
        ).tr(),
        const SizedBox(height: 8),
        if (forwards.isEmpty)
          Text(
            'portForwardingEmpty',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ).tr()
        else
          for (final forward in forwards) _ForwardTile(forward: forward),
      ],
    );
  }
}

class _ConnectionNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Symbols.link_off),
    title: Text('portForwardingConnectToConfigure').tr(),
    subtitle: Text('portForwardingHint').tr(),
  );
}

class _ForwardFields extends StatelessWidget {
  const _ForwardFields({
    required this.bindHost,
    required this.bindPort,
    required this.targetHost,
    required this.targetPort,
    required this.direction,
  });

  final TextEditingController bindHost;
  final TextEditingController bindPort;
  final TextEditingController targetHost;
  final TextEditingController targetPort;
  final PortForwardDirection direction;

  @override
  Widget build(BuildContext context) {
    final listener = direction == PortForwardDirection.local
        ? 'portForwardingThisComputerListens'
        : 'portForwardingServerListens';
    final target = direction == PortForwardDirection.local
        ? 'portForwardingServerTarget'
        : 'portForwardingThisComputerTarget';
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _HostPortFields(label: listener, host: bindHost, port: bindPort),
        _HostPortFields(label: target, host: targetHost, port: targetPort),
      ],
    );
  }
}

class _HostPortFields extends StatelessWidget {
  const _HostPortFields({
    required this.label,
    required this.host,
    required this.port,
  });

  final String label;
  final TextEditingController host;
  final TextEditingController port;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 300,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr(label), style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        TextFormField(
          controller: host,
          decoration: InputDecoration(
            labelText: 'portForwardingHostLabel'.tr(),
          ),
          validator: _hostValidator,
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: port,
          decoration: InputDecoration(
            labelText: 'portForwardingPortLabel'.tr(),
          ),
          keyboardType: TextInputType.number,
          validator: _portValidator,
        ),
      ],
    ),
  );
}

class _SavedForwardTile extends ConsumerWidget {
  const _SavedForwardTile({required this.config, required this.onStart});

  final PortForwardConfig config;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final direction = PortForwardDirection.values.byName(config.direction);
    final kind = PortForwardKind.values.byName(config.kind);
    final summary = kind == PortForwardKind.tcp
        ? '${config.bindHost}:${config.bindPort} → '
              '${config.targetHost}:${config.targetPort}'
        : 'socks5://${config.bindHost}:${config.bindPort}';
    final repository = ref.read(serverRepositoryProvider);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        kind == PortForwardKind.socks5
            ? Symbols.vpn_lock
            : direction == PortForwardDirection.local
            ? Symbols.laptop_mac
            : Symbols.dns,
      ),
      title: Text(summary),
      subtitle: config.autoStart ? Text('portForwardingAutoStart'.tr()) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: config.autoStart,
            onChanged: (value) =>
                repository.setPortForwardConfigAutoStart(config.id, value),
          ),
          IconButton(
            tooltip: 'portForwardingStart'.tr(),
            onPressed: onStart,
            icon: const Icon(Symbols.play_arrow),
          ),
          IconButton(
            tooltip: 'portForwardingDelete'.tr(),
            onPressed: () => repository.deletePortForwardConfig(config.id),
            icon: const Icon(Symbols.delete_outline),
          ),
        ],
      ),
    );
  }
}

class _ForwardTile extends ConsumerWidget {
  const _ForwardTile({required this.forward});

  final ActivePortForward forward;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final managedReason = 'portForwardingManagedByMaidCafe'.tr();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        forward.kind == PortForwardKind.socks5
            ? Symbols.vpn_lock
            : forward.direction == PortForwardDirection.local
            ? Symbols.laptop_mac
            : Symbols.dns,
      ),
      title: Text('${forward.label} · ${forward.summary}'),
      subtitle: Text(
        forward.isManaged
            ? '${'portForwardingRunningOnThisComputer'.tr()}\n$managedReason'
            : forward.direction == PortForwardDirection.local
            ? 'portForwardingRunningOnThisComputer'.tr()
            : 'portForwardingRunningOn'.tr(args: [forward.serverName]),
      ),
      trailing: forward.isManaged
          ? Tooltip(message: managedReason, child: const Icon(Symbols.lock))
          : IconButton(
              tooltip: 'portForwardingStop'.tr(),
              onPressed: () => ref
                  .read(connectionManagerProvider)
                  .stopPortForward(forward.id),
              icon: const Icon(Symbols.stop_circle),
            ),
    );
  }
}

String? _hostValidator(String? value) => value == null || value.trim().isEmpty
    ? 'portForwardingHostRequired'.tr()
    : null;

String? _portValidator(String? value) {
  final port = int.tryParse(value ?? '');
  return port == null || port < 1 || port > 65535
      ? 'portForwardingPortRequired'.tr()
      : null;
}
