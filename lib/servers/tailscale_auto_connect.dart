import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tailscale/tailscale.dart';

import 'tailscale_service.dart';

/// Reconnects the embedded Tailscale node with persisted credentials on app
/// startup.
///
/// A successful sign-in stores the auth key in the vault. After a restart the
/// node reports [NodeState.stopped] until [TailscaleService.up] is called with
/// that key — the UI would otherwise keep asking for a new auth key. This
/// wrapper issues that one reconnect per launch, and skips the work entirely
/// when no credentials are persisted.
class TailscaleAutoConnect extends ConsumerStatefulWidget {
  const TailscaleAutoConnect({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<TailscaleAutoConnect> createState() =>
      _TailscaleAutoConnectState();
}

class _TailscaleAutoConnectState extends ConsumerState<TailscaleAutoConnect> {
  var _attempted = false;

  @override
  Widget build(BuildContext context) {
    if (!_attempted) {
      _attempted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_reconnect());
      });
    }
    return widget.child;
  }

  Future<void> _reconnect() async {
    if (!tailscaleSupported) return;
    final service = ref.read(tailscaleServiceProvider);
    try {
      if (!await service.hasStoredAuthKey()) return;
      final status = await service.status();
      if (status.state == NodeState.stopped) {
        await service.up();
      }
    } catch (_) {
      // The Tailscale settings section surfaces connection state to the user.
    }
  }
}
