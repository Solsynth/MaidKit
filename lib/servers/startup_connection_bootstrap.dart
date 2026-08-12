import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'server_models.dart';
import 'server_providers.dart';

class StartupConnectionBootstrap extends ConsumerStatefulWidget {
  const StartupConnectionBootstrap({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<StartupConnectionBootstrap> createState() =>
      _StartupConnectionBootstrapState();
}

class _StartupConnectionBootstrapState
    extends ConsumerState<StartupConnectionBootstrap> {
  var _started = false;

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(connectOnStartupProvider);
    if (enabled && !_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_connectSavedServers());
      });
    }
    return widget.child;
  }

  Future<void> _connectSavedServers() async {
    final repository = ref.read(serverRepositoryProvider);
    final manager = ref.read(connectionManagerProvider);
    final servers = await repository.all();
    final byId = {for (final server in servers) server.id: server};

    Future<void> connectServer(Server server, Set<int> visiting) async {
      if (manager.clientFor(server.id) != null) return;
      if (!visiting.add(server.id)) {
        throw StateError('Jump-host cycle detected at ${server.name}.');
      }
      final jumpHostId = server.jumpHostServerId;
      if (jumpHostId != null) {
        final jumpHost = byId[jumpHostId];
        if (jumpHost == null) {
          throw StateError(
            'Jump host $jumpHostId for ${server.name} no longer exists.',
          );
        }
        if (jumpHost.connectionType != ServerConnectionType.ssh.name) {
          throw StateError('Jump host ${jumpHost.name} is not an SSH server.');
        }
        await connectServer(jumpHost, visiting);
      }
      final credential = await repository.credentialFor(server);
      final proxy = await repository.proxyFor(server);
      await manager.connect(
        server,
        credential,
        (_) async => false,
        knownHostKeyFingerprint: server.hostKeyFingerprint,
        proxy: proxy,
      );
      await repository.markConnected(server.id);
      visiting.remove(server.id);
    }

    for (final server in servers) {
      try {
        await connectServer(server, <int>{});
      } catch (_) {
        // The connection manager exposes the failure state to the server grid.
      }
    }
  }
}
