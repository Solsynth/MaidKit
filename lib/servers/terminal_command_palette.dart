import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/shared/presentation/deploy_terminal.dart';
import 'package:maid_kit/shared/presentation/maidkit_alert.dart';
import 'port_forward_sheet.dart';
import 'port_forwarding_models.dart';
import 'server_connection_actions.dart';
import 'server_models.dart';
import 'server_providers.dart';
import 'terminal_tabs_provider.dart';

Future<void> showTerminalCommandPalette(BuildContext context, WidgetRef ref) {
  // The palette renders in an overlay entry that is removed when it closes, so
  // anything that must outlive it (a status sheet, a deploy terminal) opens on
  // this context instead of the palette's own.
  final hostContext = context;
  final tabs = ref.read(terminalTabsProvider);
  // Only the MaidCafe daemon transport opens a terminal in a browser; listing
  // SSH and serial servers there would offer actions that cannot run.
  final servers = (ref.read(serversProvider).asData?.value ?? const <Server>[])
      .where(
        (server) =>
            !kIsWeb ||
            server.connectionType == ServerConnectionType.maidcafe.name,
      )
      .toList();
  final activeTab = tabs.selectedTab;
  final activeServer = activeTab == null
      ? null
      : servers.where((server) => server.id == activeTab.serverId).firstOrNull;
  final canSplit = tabs.isNotEmpty;
  final portForwards = ref.read(portForwardsProvider).asData?.value ?? const [];
  final hiddenDeploys = ref
      .read(deploySessionsProvider)
      .where((session) => !session.modalVisible)
      .toList();
  final deploySessionId = hiddenDeploys.isEmpty ? null : hiddenDeploys.last.id;

  return showMaidKitCommandPalette<void>(
    builder: (context, close) => _TerminalCommandPalette(
      activeTab: activeTab,
      servers: servers,
      destinationActions: _destinationActions(
        hostContext: hostContext,
        ref: ref,
        close: close,
        portForwards: portForwards,
        deploySessionId: deploySessionId,
      ),
      onDismiss: () => close(null),
      onOpen: (server) async {
        await openTerminalFor(context, ref, server);
        close(null);
      },
      onOpenFiles: kIsWeb || activeServer == null
          ? null
          : () async {
              final manager = ref.read(connectionManagerProvider);
              if (manager.clientFor(activeServer.id) == null &&
                  !await connectForStatistics(context, ref, activeServer)) {
                return;
              }
              ref
                  .read(terminalTabsProvider.notifier)
                  .openFileManagement(activeServer);
              close(null);
            },
      onSplitRight: !canSplit
          ? null
          : () {
              ref
                  .read(terminalTabsProvider.notifier)
                  .splitEmpty(SessionSplitAxis.horizontal);
              close(null);
            },
      onSplitDown: !canSplit
          ? null
          : () {
              ref
                  .read(terminalTabsProvider.notifier)
                  .splitEmpty(SessionSplitAxis.vertical);
              close(null);
            },
      onClose: activeTab == null
          ? null
          : () async {
              await ref.read(terminalTabsProvider.notifier).close(activeTab.id);
              close(null);
            },
      onDisconnect: activeTab == null
          ? null
          : () async {
              await ref
                  .read(terminalTabsProvider.notifier)
                  .closeForServer(activeTab.serverId);
              close(null);
            },
    ),
  );
}

class _TerminalCommandPalette extends StatefulWidget {
  const _TerminalCommandPalette({
    required this.activeTab,
    required this.servers,
    required this.destinationActions,
    required this.onDismiss,
    required this.onOpen,
    required this.onOpenFiles,
    required this.onSplitRight,
    required this.onSplitDown,
    required this.onClose,
    required this.onDisconnect,
  });

  final SessionTab? activeTab;
  final List<Server> servers;

  /// Destination tabs and workspace-wide surfaces, offered alongside the
  /// terminal actions.
  final List<_TerminalAction> destinationActions;
  final VoidCallback onDismiss;
  final Future<void> Function(Server server) onOpen;
  final Future<void> Function()? onOpenFiles;
  final VoidCallback? onSplitRight;
  final VoidCallback? onSplitDown;
  final Future<void> Function()? onClose;
  final Future<void> Function()? onDisconnect;

  @override
  State<_TerminalCommandPalette> createState() =>
      _TerminalCommandPaletteState();
}

class _TerminalCommandPaletteState extends State<_TerminalCommandPalette> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final activeTab = widget.activeTab;
    final activeServer = activeTab == null
        ? null
        : widget.servers
              .where((server) => server.id == activeTab.serverId)
              .firstOrNull;
    final actions = [
      if (activeServer != null)
        _TerminalAction(
          label: 'sessionsNewTerminalOn'.tr(args: [activeTab!.serverName]),
          icon: Symbols.add,
          onSelect: () => widget.onOpen(activeServer),
        ),
      if (widget.onOpenFiles != null)
        _TerminalAction(
          label: 'sessionsOpenFileTransfer'.tr(args: [activeTab!.serverName]),
          icon: Symbols.folder,
          onSelect: widget.onOpenFiles!,
        ),
      if (widget.onSplitRight != null)
        _TerminalAction(
          label: 'sessionsSplitRight'.tr(),
          icon: Symbols.vertical_split,
          onSelect: () async => widget.onSplitRight!(),
        ),
      if (widget.onSplitDown != null)
        _TerminalAction(
          label: 'sessionsSplitDown'.tr(),
          icon: Symbols.horizontal_split,
          onSelect: () async => widget.onSplitDown!(),
        ),
      if (widget.onClose != null)
        _TerminalAction(
          label: 'sessionsCloseThisTab'.tr(),
          icon: Symbols.close,
          onSelect: widget.onClose!,
        ),
      if (widget.onDisconnect != null)
        _TerminalAction(
          label: 'sessionsCloseAllTabs'.tr(args: [activeTab!.serverName]),
          icon: Symbols.link_off,
          onSelect: widget.onDisconnect!,
        ),
      for (final server in widget.servers)
        if (server.id != activeTab?.serverId)
          _TerminalAction(
            label: 'sessionsNewTerminalOn'.tr(args: [server.name]),
            icon: Symbols.terminal,
            onSelect: () => widget.onOpen(server),
          ),
      ...widget.destinationActions,
    ].where((action) => action.label.toLowerCase().contains(query)).toList();

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              widget.onDismiss();
              return null;
            },
          ),
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SearchBar(
              controller: _searchController,
              focusNode: _searchFocusNode,
              hintText: 'sessionsSearchActions'.tr(),
              leading: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: CircleAvatar(
                  child: const Icon(Symbols.keyboard_command_key),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: actions.isEmpty
                  ? const SizedBox.shrink()
                  : ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 300),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: actions.length,
                        itemBuilder: (context, index) {
                          final action = actions[index];
                          return ListTile(
                            leading: Icon(action.icon),
                            title: Text(action.label),
                            onTap: () => action.onSelect(),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TerminalAction {
  const _TerminalAction({
    required this.label,
    required this.icon,
    required this.onSelect,
  });

  final String label;
  final IconData icon;
  final Future<void> Function() onSelect;
}

/// Destination tabs plus the port-forward and deploy surfaces that used to sit
/// on the navigation rail. Every action closes the palette first.
List<_TerminalAction> _destinationActions({
  required BuildContext hostContext,
  required WidgetRef ref,
  required void Function(void) close,
  required List<ActivePortForward> portForwards,
  required String? deploySessionId,
}) {
  final notifier = ref.read(terminalTabsProvider.notifier);

  void open(void Function() action) {
    action();
    close(null);
  }

  return [
    _TerminalAction(
      label: 'tabDashboard'.tr(),
      icon: Symbols.dashboard,
      onSelect: () async => open(notifier.openDashboard),
    ),
    _TerminalAction(
      label: 'assetsConnections'.tr(),
      icon: Symbols.dns,
      onSelect: () async => open(notifier.openAssets),
    ),
    _TerminalAction(
      label: 'tabGithub'.tr(),
      icon: Symbols.rocket_launch,
      onSelect: () async =>
          open(() => notifier.openAssets(section: AssetsSection.github)),
    ),
    _TerminalAction(
      label: 'assetsCredentialsTitle'.tr(),
      icon: Symbols.key,
      onSelect: () async =>
          open(() => notifier.openAssets(section: AssetsSection.credentials)),
    ),
    _TerminalAction(
      label: 'tabSnippets'.tr(),
      icon: Symbols.code,
      onSelect: () async =>
          open(() => notifier.openAssets(section: AssetsSection.snippets)),
    ),
    _TerminalAction(
      label: 'tabProjects'.tr(),
      icon: Symbols.deployed_code,
      onSelect: () async => open(notifier.openProjects),
    ),
    _TerminalAction(
      label: 'agentNewConversation'.tr(),
      icon: Symbols.smart_toy,
      onSelect: () async => open(notifier.openAgentChat),
    ),
    _TerminalAction(
      label: 'maidCafeCloudTitle'.tr(),
      icon: Symbols.cloud,
      onSelect: () async => open(notifier.openMaidCafeCloud),
    ),
    _TerminalAction(
      label: 'tabSettings'.tr(),
      icon: Symbols.settings,
      onSelect: () async => open(notifier.openSettings),
    ),
    if (portForwards.isNotEmpty)
      _TerminalAction(
        label: 'activePortForwards'.plural(portForwards.length),
        icon: Symbols.swap_horiz,
        onSelect: () async {
          close(null);
          await showPortForwardSheet(hostContext, portForwards);
        },
      ),
    if (deploySessionId != null)
      _TerminalAction(
        label: 'deployLogLabel'.tr(),
        icon: Symbols.terminal,
        onSelect: () async {
          close(null);
          showDeployTerminal(ref, deploySessionId);
        },
      ),
  ];
}
