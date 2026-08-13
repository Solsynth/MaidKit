import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'firewall_models.dart';
import 'server_connection_actions.dart';
import 'server_models.dart';
import 'server_providers.dart';

/// Host firewall management (UFW preferred; also firewalld, nftables, iptables).
class FirewallTab extends ConsumerStatefulWidget {
  const FirewallTab({
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
  ConsumerState<FirewallTab> createState() => _FirewallTabState();
}

class _FirewallTabState extends ConsumerState<FirewallTab> {
  AsyncValue<FirewallStatus> _status = const AsyncValue.loading();
  var _busy = false;

  bool get _isRoot => widget.server.username == 'root';

  @override
  void initState() {
    super.initState();
    if (widget.connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void didUpdateWidget(FirewallTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connected &&
        (!oldWidget.connected || oldWidget.server.id != widget.server.id)) {
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

  Future<void> _load() async {
    if (!mounted || !widget.connected) return;
    setState(() => _status = const AsyncValue.loading());
    try {
      final status = await ref
          .read(connectionManagerProvider)
          .getFirewallStatus(
            widget.server.id,
            sshUserIsRoot: _isRoot,
            sudoPassword: await _sudoPassword(),
          );
      if (mounted) setState(() => _status = AsyncValue.data(status));
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() => _status = AsyncValue.error(error, stackTrace));
      }
    }
  }

  Future<void> _run(
    Future<void> Function() action, {
    required String success,
    bool canRetryConnection = true,
  }) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      showStyledSnackBar(message: success, title: 'firewallFirewall'.tr());
      await _load();
    } catch (error) {
      if (!mounted) return;
      final shouldRetry =
          canRetryConnection &&
          await shouldReconnectAndRetry(context, error, widget.server);
      if (!mounted) return;
      if (shouldRetry) {
        await widget.onConnect();
        if (mounted) {
          await _run(action, success: success, canRetryConnection: false);
        }
        return;
      }
      if (!mounted) return;
      showStyledSnackBar(
        message: error.toString(),
        title: 'firewallActionFailed'.tr(),
        icon: Symbols.error,
        accentColor: Theme.of(context).colorScheme.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleEnabled(bool enabled) async {
    final status = _status.asData?.value;
    if (status == null) return;
    if (!status.backend.supportsRuleEditing) {
      showStyledSnackBar(
        message: 'firewallEnableDisableUnavailable'.tr(),
        title: 'firewallFirewall'.tr(),
      );
      return;
    }
    final approved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (sheetContext) => SheetScaffold(
        titleText: enabled
            ? 'firewallEnableTitle'.tr()
            : 'firewallDisableTitle'.tr(),
        heightFactor: 0.36,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              enabled
                  ? 'firewallEnableConfirm'.tr(args: [status.backend.label])
                  : 'firewallDisableConfirm'.tr(args: [status.backend.label]),
              style: Theme.of(sheetContext).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(sheetContext, false),
                  child: Text('commonCancel'.tr()),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  child: Text(
                    enabled ? 'firewallEnable'.tr() : 'firewallDisable'.tr(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (approved != true || !mounted) return;
    await _run(() async {
      await ref
          .read(connectionManagerProvider)
          .setFirewallEnabled(
            widget.server.id,
            enabled: enabled,
            sshUserIsRoot: _isRoot,
            sudoPassword: await _sudoPassword(),
          );
    }, success: enabled ? 'firewallEnabled'.tr() : 'firewallDisabled'.tr());
  }

  Future<void> _addRule() async {
    final status = _status.asData?.value;
    if (status == null || !status.backend.supportsRuleEditing) return;
    final draft = await _showAddRuleSheet(context);
    if (draft == null || !mounted) return;
    await _run(() async {
      await ref
          .read(connectionManagerProvider)
          .addFirewallRule(
            widget.server.id,
            draft: draft,
            sshUserIsRoot: _isRoot,
            sudoPassword: await _sudoPassword(),
          );
    }, success: 'firewallRuleAdded'.tr());
  }

  Future<void> _deleteRule(FirewallRule rule) async {
    final status = _status.asData?.value;
    if (status == null || !status.backend.supportsRuleEditing) return;
    final approved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (sheetContext) => SheetScaffold(
        titleText: 'firewallDeleteRuleTitle'.tr(),
        heightFactor: 0.36,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              rule.display,
              style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                fontFamily: 'IBM Plex Mono',
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(sheetContext, false),
                  child: Text('commonCancel'.tr()),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  child: Text('commonDelete'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (approved != true || !mounted) return;
    await _run(() async {
      await ref
          .read(connectionManagerProvider)
          .deleteFirewallRule(
            widget.server.id,
            rule: rule,
            sshUserIsRoot: _isRoot,
            sudoPassword: await _sudoPassword(),
          );
    }, success: 'firewallRuleDeleted'.tr());
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.connected) {
      return _FirewallEmpty(
        icon: Symbols.link_off,
        message: widget.connectionError ?? 'firewallConnectToManage'.tr(),
        actionLabel: 'commonConnect'.tr(),
        onAction: widget.onConnect,
        filled: true,
      );
    }

    return _status.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _FirewallEmpty(
        icon: Symbols.error_outline,
        message: 'firewallLoadError'.tr(args: [error.toString()]),
        actionLabel: 'commonRefresh'.tr(),
        onAction: _load,
      ),
      data: (status) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final editable = status.backend.supportsRuleEditing;
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
                        Symbols.shield,
                        size: 20,
                        color: status.active
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        status.backend.label,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(width: 8),
                      _ActiveChip(active: status.active),
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
                      if (editable)
                        Switch(
                          value: status.active,
                          onChanged: _busy
                              ? null
                              : (value) => _toggleEnabled(value),
                        ),
                      IconButton(
                        tooltip: 'commonRefresh'.tr(),
                        visualDensity: VisualDensity.compact,
                        onPressed: _busy ? null : _load,
                        icon: const Icon(Symbols.refresh),
                      ),
                      if (editable)
                        IconButton(
                          tooltip: 'firewallAddRule'.tr(),
                          visualDensity: VisualDensity.compact,
                          onPressed: _busy || !status.active ? null : _addRule,
                          icon: const Icon(Symbols.add),
                        ),
                    ],
                  ),
                  if (status.defaultIncoming != null ||
                      status.defaultOutgoing != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      <String>[
                        if (status.defaultIncoming != null)
                          'firewallDefaultIncoming'.tr(
                            args: [status.defaultIncoming!],
                          ),
                        if (status.defaultOutgoing != null)
                          'firewallDefaultOutgoing'.tr(
                            args: [status.defaultOutgoing!],
                          ),
                        if (status.zones.isNotEmpty)
                          'firewallZone'.tr(args: [status.zones.join(', ')]),
                      ].join(' · '),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (!editable && status.backend != FirewallBackend.none) ...[
                    const SizedBox(height: 6),
                    Text(
                      'firewallReadOnlyView'.tr(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (status.error != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      status.error!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Expanded(
              child: status.backend == FirewallBackend.none
                  ? _FirewallEmpty(
                      icon: Symbols.shield,
                      message: status.error ?? 'firewallNoToolFound'.tr(),
                      actionLabel: 'commonRefresh'.tr(),
                      onAction: _load,
                    )
                  : status.rules.isEmpty
                  ? _FirewallEmpty(
                      icon: Symbols.shield,
                      message: status.active
                          ? 'firewallNoRules'.tr(args: [status.backend.label])
                          : 'firewallInactive'.tr(args: [status.backend.label]),
                      actionLabel: editable && status.active
                          ? 'firewallAddRule'.tr()
                          : 'commonRefresh'.tr(),
                      onAction: editable && status.active ? _addRule : _load,
                    )
                  : ListView.separated(
                      itemCount: status.rules.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: scheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                      itemBuilder: (context, index) {
                        final rule = status.rules[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          leading: Icon(
                            _actionIcon(rule.action),
                            color: _actionColor(scheme, rule.action),
                          ),
                          title: Text(
                            rule.display,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: 'IBM Plex Mono',
                              fontSize: 13,
                            ),
                          ),
                          subtitle: rule.action == null
                              ? null
                              : Text(rule.action!.label),
                          trailing: editable
                              ? IconButton(
                                  tooltip: 'firewallDeleteRuleTooltip'.tr(),
                                  onPressed: _busy
                                      ? null
                                      : () => _deleteRule(rule),
                                  icon: const Icon(Symbols.delete, size: 20),
                                )
                              : Text(
                                  '#${rule.id}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  IconData _actionIcon(FirewallAction? action) => switch (action) {
    FirewallAction.allow => Symbols.check_circle,
    FirewallAction.deny || FirewallAction.drop => Symbols.block,
    FirewallAction.reject => Symbols.cancel,
    null => Symbols.rule,
  };

  Color _actionColor(ColorScheme scheme, FirewallAction? action) =>
      switch (action) {
        FirewallAction.allow => scheme.primary,
        FirewallAction.deny ||
        FirewallAction.drop ||
        FirewallAction.reject => scheme.error,
        null => scheme.onSurfaceVariant,
      };
}

class _ActiveChip extends StatelessWidget {
  const _ActiveChip({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: active
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        active ? 'firewallActive'.tr() : 'firewallInactiveLabel'.tr(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: active ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

Future<FirewallRuleDraft?> _showAddRuleSheet(BuildContext context) {
  return showModalBottomSheet<FirewallRuleDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    builder: (_) => const _AddFirewallRuleSheet(),
  );
}

class _AddFirewallRuleSheet extends StatefulWidget {
  const _AddFirewallRuleSheet();

  @override
  State<_AddFirewallRuleSheet> createState() => _AddFirewallRuleSheetState();
}

class _AddFirewallRuleSheetState extends State<_AddFirewallRuleSheet> {
  final _port = TextEditingController();
  final _source = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  var _action = FirewallAction.allow;
  var _protocol = 'tcp';

  @override
  void dispose() {
    _port.dispose();
    _source.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      FirewallRuleDraft(
        action: _action,
        port: _port.text.trim(),
        protocol: _protocol,
        source: _source.text.trim().isEmpty ? null : _source.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      titleText: 'firewallAddRuleTitle'.tr(),
      heightFactor: 0.68,
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            DropdownButtonFormField<FirewallAction>(
              // ignore: deprecated_member_use
              value: _action,
              decoration: InputDecoration(
                labelText: 'firewallAction'.tr(),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: FirewallAction.allow,
                  child: Text('firewallActionAllow'.tr()),
                ),
                DropdownMenuItem(
                  value: FirewallAction.deny,
                  child: Text('firewallActionDeny'.tr()),
                ),
                DropdownMenuItem(
                  value: FirewallAction.reject,
                  child: Text('firewallActionReject'.tr()),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _action = value);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _port,
              decoration: InputDecoration(
                labelText: 'firewallPortLabel'.tr(),
                hintText: 'firewallPortHint'.tr(),
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'firewallPortRequired'.tr();
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _protocol,
              decoration: InputDecoration(
                labelText: 'firewallProtocol'.tr(),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: 'tcp',
                  child: Text('firewallProtocolTcp'.tr()),
                ),
                DropdownMenuItem(
                  value: 'udp',
                  child: Text('firewallProtocolUdp'.tr()),
                ),
                DropdownMenuItem(
                  value: 'any',
                  child: Text('firewallProtocolAny'.tr()),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _protocol = value);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _source,
              decoration: InputDecoration(
                labelText: 'firewallSourceLabel'.tr(),
                hintText: 'firewallSourceHint'.tr(),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('commonCancel'.tr()),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _submit,
                  child: Text('firewallAddRuleSubmit'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FirewallEmpty extends StatelessWidget {
  const _FirewallEmpty({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.filled = false,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
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
              if (filled)
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Symbols.link),
                  label: Text(actionLabel!),
                )
              else
                OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
