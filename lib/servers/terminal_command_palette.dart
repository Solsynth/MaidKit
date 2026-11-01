import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/shared/presentation/deploy_terminal.dart';
import 'package:maid_kit/shared/presentation/maidkit_alert.dart';
import 'package:maid_kit/theme.dart';
import 'port_forward_sheet.dart';
import 'port_forwarding_models.dart';
import 'server_connection_actions.dart';
import 'server_models.dart';
import 'server_providers.dart';
import 'terminal_tabs_provider.dart';
import 'workspace_shortcuts.dart';

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
  final activeTab = tabs.selectedTabContent;
  final activeServer = activeTab == null
      ? null
      : servers.where((server) => server.id == activeTab.serverId).firstOrNull;
  final canSplit = canSplitTab(tabs.selectedTab);
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
      // The palette restores the keyboard as it closes; the new tab's launcher
      // claims it on the frame that builds it, which lands after that restore.
      onNewTab: () {
        close(null);
        ref.read(terminalTabsProvider.notifier).openEmptyTab();
      },
      // The palette hands the keyboard back to whatever had it before, on the
      // frame after it closes; the split therefore runs on the following frame
      // too. Splitting first would let that restore land on the old pane and
      // drag the live-pane marker back with it, so the new pane would open
      // idle instead of live.
      onSplitRight: !canSplit
          ? null
          : () => _splitAfterClose(() => close(null), ref, horizontal: true),
      onSplitDown: !canSplit
          ? null
          : () => _splitAfterClose(() => close(null), ref, horizontal: false),
      onClosePane: tabs.selectedTab == null || !tabs.selectedTab!.hasSplits
          ? null
          : () async {
              final tab = ref.read(terminalTabsProvider).selectedTab;
              if (tab != null) {
                await ref
                    .read(terminalTabsProvider.notifier)
                    .closePaneInTab(tab.id, tab.focusedPaneId);
              }
              close(null);
            },
      onClose: tabs.selectedId == null
          ? null
          : () async {
              await ref
                  .read(terminalTabsProvider.notifier)
                  .closeTab(tabs.selectedId!);
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

/// Closes the palette, then splits on the next frame.
///
/// The palette restores the keyboard to its previous owner as it closes, and a
/// pane reports itself live whenever its content takes the keyboard. Splitting
/// in the same frame would therefore let that restore re-focus the old pane and
/// pull the live marker back off the new one.
void _splitAfterClose(
  void Function() close,
  WidgetRef ref, {
  required bool horizontal,
}) {
  close();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    ref
        .read(terminalTabsProvider.notifier)
        .splitSelectedTab(
          horizontal ? SessionSplitAxis.horizontal : SessionSplitAxis.vertical,
        );
  });
}

/// Where an entry belongs in the list.
///
/// The sections give the unfiltered palette a shape: what acts on the tab you
/// are looking at, what opens a server, and the workspace-wide destinations.
/// A typed query drops the headings so the matches read as one ranked list.
enum _PaletteGroup { tab, servers, workspace }

class _TerminalCommandPalette extends StatefulWidget {
  const _TerminalCommandPalette({
    required this.activeTab,
    required this.servers,
    required this.destinationActions,
    required this.onDismiss,
    required this.onOpen,
    required this.onOpenFiles,
    required this.onNewTab,
    required this.onSplitRight,
    required this.onSplitDown,
    required this.onClosePane,
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

  /// Opens an empty workspace tab, the launcher pane included.
  final VoidCallback onNewTab;

  final VoidCallback? onSplitRight;
  final VoidCallback? onSplitDown;

  /// Closes the focused pane of a split, keeping its siblings.
  final Future<void> Function()? onClosePane;
  final Future<void> Function()? onClose;
  final Future<void> Function()? onDisconnect;

  @override
  State<_TerminalCommandPalette> createState() =>
      _TerminalCommandPaletteState();
}

class _TerminalCommandPaletteState extends State<_TerminalCommandPalette> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  /// Global keys for the rows, so the highlighted one can be scrolled into
  /// view after a keyboard move.
  final _rowKeys = <int, GlobalKey>{};

  var _query = '';
  var _highlighted = 0;

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

  void _setQuery(String value) {
    setState(() {
      _query = value.trim().toLowerCase();
      _highlighted = 0;
    });
  }

  void _moveHighlight(int delta, int count) {
    if (count == 0) return;
    setState(() => _highlighted = (_highlighted + delta) % count);
    final key = _rowKeys[_highlighted];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = key?.currentContext;
      if (context != null && context.mounted) {
        Scrollable.ensureVisible(
          context,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
  }

  List<_TerminalAction> _actions() {
    final activeTab = widget.activeTab;
    final activeServer = activeTab == null
        ? null
        : widget.servers
              .where((server) => server.id == activeTab.serverId)
              .firstOrNull;
    return [
      if (activeServer != null)
        _TerminalAction(
          label: 'sessionsNewTerminalOn'.tr(args: [activeTab!.serverName]),
          icon: Symbols.add,
          group: _PaletteGroup.tab,
          onSelect: () => widget.onOpen(activeServer),
        ),
      if (widget.onOpenFiles != null)
        _TerminalAction(
          label: 'sessionsOpenFileTransfer'.tr(args: [activeTab!.serverName]),
          icon: Symbols.folder,
          group: _PaletteGroup.tab,
          onSelect: widget.onOpenFiles!,
        ),
      _TerminalAction(
        label: 'sessionsNewTab'.tr(),
        icon: Symbols.tab,
        group: _PaletteGroup.tab,
        shortcut: newTabShortcutLabel(),
        onSelect: () async => widget.onNewTab(),
      ),
      if (widget.onSplitRight != null)
        _TerminalAction(
          label: 'sessionsSplitRight'.tr(),
          icon: Symbols.vertical_split,
          group: _PaletteGroup.tab,
          shortcut: splitShortcutLabel(SessionSplitAxis.horizontal),
          onSelect: () async => widget.onSplitRight!(),
        ),
      if (widget.onSplitDown != null)
        _TerminalAction(
          label: 'sessionsSplitDown'.tr(),
          icon: Symbols.horizontal_split,
          group: _PaletteGroup.tab,
          shortcut: splitShortcutLabel(SessionSplitAxis.vertical),
          onSelect: () async => widget.onSplitDown!(),
        ),
      if (widget.onClosePane != null)
        _TerminalAction(
          label: 'sessionsClosePane'.tr(),
          icon: Symbols.tab_close,
          group: _PaletteGroup.tab,
          onSelect: widget.onClosePane!,
        ),
      if (widget.onClose != null)
        _TerminalAction(
          label: 'sessionsCloseThisTab'.tr(),
          icon: Symbols.close,
          group: _PaletteGroup.tab,
          onSelect: widget.onClose!,
        ),
      if (widget.onDisconnect != null)
        _TerminalAction(
          label: 'sessionsCloseAllTabs'.tr(args: [activeTab!.serverName]),
          icon: Symbols.link_off,
          group: _PaletteGroup.tab,
          onSelect: widget.onDisconnect!,
        ),
      for (final server in widget.servers)
        if (server.id != activeTab?.serverId)
          _TerminalAction(
            label: 'sessionsNewTerminalOn'.tr(args: [server.name]),
            icon: Symbols.terminal,
            group: _PaletteGroup.servers,
            hint: server.host,
            onSelect: () => widget.onOpen(server),
          ),
      ...widget.destinationActions,
    ].where((action) => action.label.toLowerCase().contains(_query)).toList();
  }

  KeyEventResult _onKey(
    FocusNode node,
    KeyEvent event,
    List<_TerminalAction> actions,
  ) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _moveHighlight(1, actions.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _moveHighlight(-1, actions.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter
          when actions.isNotEmpty:
        actions[_highlighted.clamp(0, actions.length - 1)].onSelect();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final actions = _actions();
    if (_highlighted >= actions.length) _highlighted = 0;

    // Rows read as one ranked list while searching, and as titled sections —
    // this tab, servers, workspace — when the query is still empty.
    final showSections = _query.isEmpty;
    final rows = <Widget>[];
    _PaletteGroup? previous;
    for (var index = 0; index < actions.length; index++) {
      final action = actions[index];
      if (showSections && action.group != previous) {
        previous = action.group;
        rows.add(_SectionLabel(group: action.group));
      }
      rows.add(
        _ActionRow(
          key: _rowKeys[index] ??= GlobalKey(),
          action: action,
          highlighted: index == _highlighted,
          onTap: () => action.onSelect(),
          onHover: () => setState(() => _highlighted = index),
        ),
      );
    }

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
        child: Focus(
          onKeyEvent: (node, event) => _onKey(node, event, actions),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  MaidKitSpace.md,
                  MaidKitSpace.md,
                  MaidKitSpace.sm,
                  MaidKitSpace.sm,
                ),
                child: Row(
                  children: [
                    Icon(
                      Symbols.search,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: MaidKitSpace.sm),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('command-palette-search'),
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        textInputAction: TextInputAction.done,
                        onChanged: _setQuery,
                        // Enter runs the highlighted entry even when the field
                        // has taken focus back from the list.
                        onSubmitted: (_) {
                          if (actions.isEmpty) return;
                          actions[_highlighted.clamp(0, actions.length - 1)]
                              .onSelect();
                        },
                        decoration: InputDecoration(
                          isDense: true,
                          // The sheet's own top band is the field: no pill,
                          // fill or outline of its own inside it.
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          hintText: 'sessionsSearchActions'.tr(),
                          hintStyle: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    if (_query.isNotEmpty)
                      IconButton(
                        tooltip: 'commonClearSearch'.tr(),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Symbols.close, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _setQuery('');
                          _searchFocusNode.requestFocus();
                        },
                      )
                    else
                      const _Keycap(label: 'Esc'),
                  ],
                ),
              ),
              Divider(height: 1, color: scheme.outlineVariant),
              Flexible(
                child: rows.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: MaidKitSpace.xl,
                          vertical: MaidKitSpace.xxl,
                        ),
                        child: Text(
                          'sessionsNoMatchingActions'.tr(),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(
                          MaidKitSpace.sm,
                          MaidKitSpace.sm,
                          MaidKitSpace.sm,
                          0,
                        ),
                        shrinkWrap: true,
                        children: rows,
                      ),
              ),
              Divider(height: 1, color: scheme.outlineVariant),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: MaidKitSpace.lg,
                  vertical: MaidKitSpace.sm,
                ),
                child: Text(
                  actions.isEmpty
                      ? 'sessionsPaletteNoResultsHint'.tr()
                      : 'sessionsPaletteFooterHint'.tr(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One palette row: icon, name, optional detail and its key chord.
///
/// The highlighted row — typed, hovered or arrow-keyed to — takes a tonal
/// fill so the keyboard's target is always visible, and the whole row keeps a
/// control-sized corner instead of the list's full-bleed rectangle.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    super.key,
    required this.action,
    required this.highlighted,
    required this.onTap,
    required this.onHover,
  });

  final _TerminalAction action;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontWeight: highlighted ? FontWeight.w600 : FontWeight.w500,
    );
    final hint = action.hint;
    final shortcut = action.shortcut;
    return Padding(
      padding: const EdgeInsets.only(bottom: MaidKitSpace.xxs),
      child: ListTile(
        dense: true,
        selected: highlighted,
        selectedTileColor: scheme.secondaryContainer.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: MaidKitRadius.controlRadius,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: MaidKitSpace.sm),
        leading: Icon(
          action.icon,
          size: 20,
          color: highlighted ? scheme.primary : scheme.onSurfaceVariant,
        ),
        title: Text(
          action.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: titleStyle,
        ),
        subtitle: hint == null
            ? null
            : Text(
                hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
        trailing: shortcut == null ? null : _Keycap(label: shortcut),
        onTap: onTap,
        onFocusChange: (focused) {
          if (focused) onHover();
        },
      ),
    );
  }
}

/// A quiet heading above one section of entries.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.group});

  final _PaletteGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MaidKitSpace.sm,
        MaidKitSpace.sm,
        MaidKitSpace.sm,
        MaidKitSpace.xs,
      ),
      child: Text(
        switch (group) {
          _PaletteGroup.tab => 'sessionsPaletteGroupTab'.tr(),
          _PaletteGroup.servers => 'sessionsPaletteGroupServers'.tr(),
          _PaletteGroup.workspace => 'sessionsPaletteGroupWorkspace'.tr(),
        },
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// A chord printed the way a keyboard draws it: a small raised key.
class _Keycap extends StatelessWidget {
  const _Keycap({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: MaidKitSpace.sm,
        vertical: MaidKitSpace.xxs,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(MaidKitRadius.xs),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
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
    this.group = _PaletteGroup.workspace,
    this.hint,
    this.shortcut,
  });

  final String label;
  final IconData icon;

  /// Where the entry sits in the unfiltered list.
  final _PaletteGroup group;

  /// A second line naming the target, e.g. a server's address.
  final String? hint;

  /// The chord that runs this action, printed on the row. Null for actions
  /// that only exist as palette entries.
  final String? shortcut;
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
