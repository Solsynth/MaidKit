import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:tailscale/tailscale.dart';
import 'package:url_launcher/url_launcher.dart';

import 'tailscale_service.dart';

/// Combined status snapshot for the settings section.
class TailscaleSnapshot {
  const TailscaleSnapshot({
    required this.status,
    required this.nodes,
    this.runtimeError,
  });

  final TailscaleStatus? status;
  final List<TailscaleNode> nodes;

  /// Last native runtime error reported by the embedded engine, if any.
  final TailscaleRuntimeError? runtimeError;
}

/// Live snapshot: refreshes after the initial load and whenever the embedded
/// node transitions state. Null when Tailscale is unsupported.
final tailscaleSnapshotProvider = StreamProvider<TailscaleSnapshot?>((ref) {
  if (!tailscaleSupported) return Stream.value(null);
  final service = ref.watch(tailscaleServiceProvider);
  final controller = StreamController<TailscaleSnapshot?>();
  TailscaleRuntimeError? lastRuntimeError;
  Future<void> refresh() async {
    TailscaleStatus? status;
    var nodes = <TailscaleNode>[];
    try {
      status = await service.status();
    } catch (_) {
      status = null;
    }
    try {
      nodes = await service.nodes();
    } catch (_) {
      nodes = const [];
    }
    if (!controller.isClosed) {
      controller.add(
        TailscaleSnapshot(
          status: status,
          nodes: nodes,
          runtimeError: lastRuntimeError,
        ),
      );
    }
  }

  refresh();
  final stateSubscription = service.onStateChange.listen((_) => refresh());
  final errorSubscription = service.onError.listen((error) {
    // The embedded runtime reports its own failures (DERP loss, engine
    // errors, worker death). Keep the last one visible in the settings UI so
    // connection failures over Tailscale can be diagnosed.
    lastRuntimeError = error;
    refresh();
  });
  ref.onDispose(() async {
    await stateSubscription.cancel();
    await errorSubscription.cancel();
    await controller.close();
  });
  return controller.stream;
});

class TailscaleSettingsSection extends ConsumerWidget {
  const TailscaleSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!tailscaleSupported) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('tailscaleUnsupported'.tr()),
      );
    }
    final snapshot = ref.watch(tailscaleSnapshotProvider).value;
    final status = snapshot?.status;
    final nodeState = status?.state;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            'tailscaleDescription'.tr(),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        if (snapshot?.runtimeError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Symbols.warning,
                  size: 16,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${snapshot!.runtimeError!.code.name}: '
                    '${snapshot.runtimeError!.message}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (status == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          )
        else ...[
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: Icon(switch (nodeState) {
              NodeState.running => Symbols.lan,
              NodeState.starting => Symbols.sync,
              NodeState.needsLogin ||
              NodeState.needsMachineAuth => Symbols.manage_accounts,
              _ => Symbols.lan,
            }),
            title: Text(_stateLabel(context, nodeState)),
            subtitle: Text(
              status.ipv4 != null
                  ? 'tailscaleNodeIp'.tr(args: [status.ipv4!])
                  : 'tailscaleHostname'.tr(args: [status.stableNodeId ?? '']),
            ),
            trailing: switch (nodeState) {
              NodeState.running => TextButton(
                onPressed: () => _signOut(context, ref),
                child: Text('tailscaleSignOut'.tr()),
              ),
              _ => FilledButton.tonal(
                onPressed: () => _signIn(context, ref, status),
                child: Text('tailscaleSignIn'.tr()),
              ),
            },
          ),
          if (status.state == NodeState.needsLogin && status.authUrl != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => launchUrl(status.authUrl!),
                  icon: const Icon(Symbols.open_in_new),
                  label: Text('tailscaleOpenBrowser'.tr()),
                ),
              ),
            ),
        ],
        if (snapshot != null && snapshot.nodes.isNotEmpty) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'tailscaleMachines'.tr(),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          for (final node in snapshot.nodes.where((node) => node.online))
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: const Icon(Symbols.dns, size: 20),
              title: Text(node.hostName),
              subtitle: Text(
                node.tailscaleIPs.where((ip) => !ip.contains(':')).join(', '),
              ),
              trailing: IconButton(
                tooltip: 'tailscaleCopyIp'.tr(),
                icon: const Icon(Symbols.content_copy, size: 18),
                onPressed: () {
                  final ip = node.ipv4;
                  if (ip != null) {
                    Clipboard.setData(ClipboardData(text: ip));
                    showSnackBar('tailscaleIpCopied'.tr());
                  }
                },
              ),
            ),
        ],
        if (status?.needsLogin == true && status?.authUrl == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              'tailscaleAuthKeyHint'.tr(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  String _stateLabel(BuildContext context, NodeState? state) => switch (state) {
    NodeState.running => 'tailscaleConnected'.tr(),
    NodeState.starting => 'tailscaleConnecting'.tr(),
    NodeState.needsLogin => 'tailscaleNeedsLogin'.tr(),
    NodeState.needsMachineAuth => 'tailscaleNeedsApproval'.tr(),
    _ => 'tailscaleNotConnected'.tr(),
  };

  Future<void> _signIn(
    BuildContext context,
    WidgetRef ref,
    TailscaleStatus status,
  ) async {
    final service = ref.read(tailscaleServiceProvider);
    // A pending login URL means the node already has a session; finish it in
    // the browser instead of asking for a key.
    if (status.state == NodeState.needsLogin && status.authUrl != null) {
      await launchUrl(status.authUrl!);
      return;
    }
    final key = await showDialog<String>(
      context: context,
      builder: (context) => const _AuthKeyDialog(),
    );
    if (key == null) return;
    try {
      await service.up(authKey: key);
      ref.invalidate(tailscaleSnapshotProvider);
      if (context.mounted) {
        showSnackBar('tailscaleSignedIn'.tr());
      }
    } catch (error) {
      if (context.mounted) {
        showSnackBar('tailscaleAuthFailed'.tr(args: ['$error']));
      }
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final service = ref.read(tailscaleServiceProvider);
    await service.logout();
    ref.invalidate(tailscaleSnapshotProvider);
  }
}

class _AuthKeyDialog extends StatefulWidget {
  const _AuthKeyDialog();

  @override
  State<_AuthKeyDialog> createState() => _AuthKeyDialogState();
}

class _AuthKeyDialogState extends State<_AuthKeyDialog> {
  final _key = TextEditingController();

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('tailscaleSignInTitle'.tr()),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _key,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'tailscaleAuthKeyLabel'.tr(),
                hintText: 'tskey-auth-…',
              ),
              onSubmitted: (_) => Navigator.pop(context, _key.text.trim()),
            ),
            const SizedBox(height: 8),
            Text(
              'tailscaleAuthKeyHint'.tr(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('commonCancel'.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _key.text.trim()),
          child: Text('tailscaleSignIn'.tr()),
        ),
      ],
    );
  }
}
