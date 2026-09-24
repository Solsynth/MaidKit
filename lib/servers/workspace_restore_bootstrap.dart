import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'server_providers.dart';
import 'terminal_tabs_provider.dart';

/// Restores the last workspace after the vault unlocks, when enabled.
///
/// Runs after [StartupConnectionBootstrap] in the widget chain; the two
/// coexist because each terminal opens its own SSH client, so a restore does
/// not depend on the main connection pass.
class WorkspaceRestoreBootstrap extends ConsumerStatefulWidget {
  const WorkspaceRestoreBootstrap({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WorkspaceRestoreBootstrap> createState() =>
      _WorkspaceRestoreBootstrapState();
}

class _WorkspaceRestoreBootstrapState
    extends ConsumerState<WorkspaceRestoreBootstrap> {
  var _started = false;

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(workspaceRestoreOnStartupProvider);
    if (enabled && !_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(
            ref.read(terminalTabsProvider.notifier).restoreLastWorkspace(),
          );
        }
      });
    }
    return widget.child;
  }
}
