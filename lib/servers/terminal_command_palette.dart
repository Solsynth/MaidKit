import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/shared/presentation/deploy_terminal.dart';
import 'package:maid_kit/shared/services/english_translations.dart';
import 'package:maid_kit/shared/presentation/maidkit_alert.dart';
import 'package:maid_kit/theme.dart';
import 'package:maid_kit/shared/presentation/search_field_suffix.dart';
import 'port_forward_sheet.dart';
import 'port_forwarding_models.dart';
import 'server_connection_actions.dart';
import 'server_models.dart';
import 'server_providers.dart';
import 'servers_page.dart';
import 'terminal_tabs_provider.dart';
import 'tmux_sessions_sheet.dart';
import 'tmux_terminal.dart';
import 'workspace_shortcuts.dart';
import 'workspace_actions.dart';

Future<void> showTerminalCommandPalette(
  BuildContext context,
  WidgetRef ref,
) async {
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
  // Every entry keeps its English name searchable in any locale; the bundle is
  // read at startup, so this is a map lookup rather than a wait.
  final english = EnglishLabels.labels;
  final activeTab = tabs.selectedTabContent;
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
      english: english,
      tmuxForTab: (tabId) =>
          ref.read(terminalTabsProvider.notifier).tmuxForTab(tabId),
      hostContext: hostContext,
      ref: ref,
      extraActions: _paletteOnlyActions(
        hostContext: hostContext,
        ref: ref,
        close: close,
        portForwards: portForwards,
        deploySessionId: deploySessionId,
      ),
      onDismiss: () => close(null),
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
class _TerminalCommandPalette extends StatefulWidget {
  const _TerminalCommandPalette({
    required this.activeTab,
    required this.servers,
    required this.english,
    required this.extraActions,
    required this.onDismiss,
    required this.onOpen,
    required this.onOpenFiles,
    required this.onNewTab,
    required this.onSplitRight,
    required this.onSplitDown,
    required this.onClosePane,
    required this.onClose,
    required this.onDisconnect,
    required this.tmuxForTab,
    required this.hostContext,
    required this.ref,
  });

  final SessionTab? activeTab;
  final List<Server> servers;

  /// The English bundle, so every entry keeps its English name searchable in
  /// any locale.
  final Map<String, String> english;

  /// Surfaces only the palette offers — the port-forward sheet and a hidden
  /// deploy log — on top of the shared destinations and server rows.
  final List<WorkspaceAction> extraActions;
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

  /// The tmux binding behind a tab, when that tab mirrors a session.
  final TmuxTabBinding? Function(String tabId) tmuxForTab;

  /// The palette's own caller context and container, for the surfaces that must
  /// outlive the overlay entry (the background-session sheet).
  final BuildContext hostContext;
  final WidgetRef ref;

  @override
  State<_TerminalCommandPalette> createState() =>
      _TerminalCommandPaletteState();
}

class _TerminalCommandPaletteState extends State<_TerminalCommandPalette> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode(debugLabel: 'Command palette search');

  /// Global keys for the rows, so the highlighted one can be scrolled into
  /// view after a keyboard move.
  final _rowKeys = <int, GlobalKey>{};

  var _query = '';
  var _highlighted = 0;

  /// The rows built by the last frame, which the key handler indexes.
  var _built = const <WorkspaceAction>[];

  @override
  void initState() {
    super.initState();
    // The arrow keys are answered on the field's own node. A text field's node
    // is the first stop of the key event walk, ahead of every ancestor
    // Shortcuts and of the text editing bindings that would otherwise read
    // them as caret moves and keep them.
    _searchFocusNode.onKeyEvent = workspaceActionKeyHandler(
      count: () => _built.length,
      highlighted: () => _highlighted,
      highlight: _highlight,
      run: (index) => _built[index].run?.call(),
    );
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

  void _highlight(int index) {
    if (!mounted) return;
    setState(() => _highlighted = index);
    revealWorkspaceRow(_rowKeys[index]);
  }

  /// Everything the palette offers right now, in section order.
  /// The destinations and the per-server rows come from the shared catalog the
  /// empty-pane launcher uses too, so both surfaces name the same thing the
  /// same way. The active tab's server is skipped: its terminal and files are
  /// already the first two entries here, and listing them twice only made the
  /// list longer to read.
  List<WorkspaceAction> _actions() {
    final activeTab = widget.activeTab;
    final activeServer = activeTab == null
        ? null
        : widget.servers
              .where((server) => server.id == activeTab.serverId)
              .firstOrNull;
    final english = widget.english;
    final hideAddresses = widget.ref.read(hideServerAddressesProvider);
    return [
      if (activeServer != null)
        ...serverActions(
          context: widget.hostContext,
          ref: widget.ref,
          english: english,
          server: activeServer,
          hideAddresses: hideAddresses,
          group: WorkspaceActionGroup.tab,
          includeDetails: false,
          done: widget.onDismiss,
        ),
      _action(
        'sessionsNewTab',
        Symbols.tab,
        widget.onNewTab,
        shortcut: newTabShortcutLabel(),
      ),
      if (widget.ref.read(terminalTabsProvider).tabs.length > 1) ...[
        _action(
          'sessionsNextTab',
          Symbols.keyboard_tab,
          () {
            widget.onDismiss();
            widget.ref.read(terminalTabsProvider.notifier).cycleSelectedTab(1);
          },
          shortcut: tabCycleShortcutLabel(),
        ),
        _action(
          'sessionsPreviousTab',
          Symbols.keyboard_tab,
          () {
            widget.onDismiss();
            widget.ref.read(terminalTabsProvider.notifier).cycleSelectedTab(-1);
          },
          shortcut: tabCycleShortcutLabel(backwards: true),
        ),
      ],
      if (widget.onSplitRight case final split?)
        _action(
          'sessionsSplitRight',
          Symbols.vertical_split,
          split,
          shortcut: splitShortcutLabel(SessionSplitAxis.horizontal),
        ),
      if (widget.onSplitDown case final split?)
        _action(
          'sessionsSplitDown',
          Symbols.horizontal_split,
          split,
          shortcut: splitShortcutLabel(SessionSplitAxis.vertical),
        ),
      if (widget.onClosePane case final close?)
        _action('sessionsClosePane', Symbols.tab_close, close),
      if (widget.onClose case final close?)
        _action('sessionsCloseThisTab', Symbols.close, close),
      if (widget.onDisconnect case final close?)
        _action(
          'sessionsCloseAllTabs',
          Symbols.link_off,
          close,
          args: [activeTab!.serverName],
        ),
      ..._tmuxActions(activeTab, activeServer),
      // One terminal row per other server. Its files and page are their own
      // tabs, and repeating all three per host made the list three times as long
      // for a choice the server's page already offers.
      for (final server in widget.servers)
        if (server.id != activeTab?.serverId)
          ...serverActions(
            context: widget.hostContext,
            ref: widget.ref,
            english: english,
            server: server,
            hideAddresses: hideAddresses,
            includeFiles: false,
            includeDetails: false,
            done: widget.onDismiss,
          ),
      _action(
        'serversAddServer',
        Symbols.add,
        () async {
          widget.onDismiss();
          await showAddServerSheet(widget.hostContext, widget.ref);
        },
        group: WorkspaceActionGroup.workspace,
      ),
      ...workspaceDestinationActions(
        ref: widget.ref,
        english: english,
        done: widget.onDismiss,
      ),
      ...widget.extraActions,
    ].where((action) => action.run != null && action.matches(_query)).toList();
  }

  /// A labeled action whose name comes from the current locale, with the
  /// English text kept as a search alias.
  WorkspaceAction _action(
    String key,
    IconData icon,
    FutureOr<void> Function() run, {
    WorkspaceActionGroup group = WorkspaceActionGroup.tab,
    List<String> args = const [],
    String? shortcut,
  }) {
    return WorkspaceAction(
      label: key.tr(args: args),
      icon: icon,
      group: group,
      shortcut: shortcut,
      aliases: [?englishText(widget.english, key, args: args)],
      run: () async => run(),
    );
  }

  /// The tmux entries, offered only while the selected tab mirrors a session.
  List<WorkspaceAction> _tmuxActions(SessionTab? activeTab, Server? server) {
    if (activeTab is! TerminalTab) return const [];
    final binding = widget.tmuxForTab(activeTab.id);
    if (binding == null || server == null) return const [];
    return [
      _action('sessionsTmuxDetach', Symbols.logout, () async {
        widget.onDismiss();
        await binding.detach();
      }),
      _action('sessionsTmuxKill', Symbols.power_settings_new, () async {
        widget.onDismiss();
        final confirmed = await showMaidKitConfirmAlert(
          'sessionsTmuxKillConfirm'.tr(args: [binding.sessionName]),
          'sessionsTmuxKill'.tr(),
          isDanger: true,
        );
        if (!confirmed) return;
        await binding.killSession();
      }),
      for (final window in binding.windows)
        WorkspaceAction(
          label:
              '${'sessionsTmuxSwitchWindow'.tr()} '
              '${'sessionsTmuxWindow'.tr(args: ['${window.index}'])}',
          icon: Symbols.tab_recent,
          group: WorkspaceActionGroup.tab,
          hint: window.name,
          run: () async {
            widget.onDismiss();
            try {
              await binding.control.command('select-window -t ${window.index}');
            } catch (_) {
              // A window that went away needs no switch.
            }
          },
        ),
      WorkspaceAction(
        label: 'sessionsTmuxBackground'.tr(args: [server.name]),
        icon: Symbols.inventory,
        group: WorkspaceActionGroup.servers,
        aliases: [
          ?englishText(widget.english, 'sessionsTmuxBackground', args: [
            server.name,
          ]),
        ],
        run: () async {
          widget.onDismiss();
          await showTmuxSessionsSheet(widget.hostContext, widget.ref, server);
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final actions = _actions();
    _built = actions;
    if (_highlighted >= actions.length) _highlighted = 0;
    _rowKeys.removeWhere((index, _) => index >= actions.length);

    // Rows read as one ranked list while searching, and as titled sections —
    // this tab, servers, workspace — when the query is still empty.
    final showSections = _query.isEmpty;
    final rows = <Widget>[];
    WorkspaceActionGroup? previous;
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
          onTap: () => action.run?.call(),
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
                        onSubmitted: (_) {
                          if (actions.isEmpty) return;
                          actions[_highlighted.clamp(0, actions.length - 1)]
                              .run
                              ?.call();
                        },
                        // Enter runs the highlighted entry; ↑↓ move it. Both
                        // are answered on this field's node, because the text
                        // editing bindings below would keep the arrows.
                        onChanged: _setQuery,
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
                    // One fixed slot: the clear button and the Escape keycap
                    // are the same size, so the band does not jump when the
                    // first character is typed.
                    SearchFieldSuffix(
                      visible: _query.isNotEmpty,
                      keyHint: 'Esc',
                      onClear: () {
                        _searchController.clear();
                        _setQuery('');
                        _searchFocusNode.requestFocus();
                      },
                    ),
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

  final WorkspaceAction action;
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

  final WorkspaceActionGroup group;

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
          WorkspaceActionGroup.tab => 'sessionsPaletteGroupTab'.tr(),
          WorkspaceActionGroup.servers => 'sessionsPaletteGroupServers'.tr(),
          WorkspaceActionGroup.workspace =>
            'sessionsPaletteGroupWorkspace'.tr(),
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

/// The surfaces only the palette offers: the port-forward sheet and a deploy
/// log hidden behind a closed terminal. Both close the palette first, then open
/// on the host context so they outlive the overlay entry.
List<WorkspaceAction> _paletteOnlyActions({
  required BuildContext hostContext,
  required WidgetRef ref,
  required void Function(void) close,
  required List<ActivePortForward> portForwards,
  required String? deploySessionId,
}) {
  return [
    if (portForwards.isNotEmpty)
      WorkspaceAction(
        label: 'activePortForwards'.plural(portForwards.length),
        icon: Symbols.swap_horiz,
        group: WorkspaceActionGroup.workspace,
        run: () async {
          close(null);
          await showPortForwardSheet(hostContext, portForwards);
        },
      ),
    if (deploySessionId != null)
      WorkspaceAction(
        label: 'deployLogLabel'.tr(),
        icon: Symbols.terminal,
        group: WorkspaceActionGroup.workspace,
        run: () async {
          close(null);
          showDeployTerminal(ref, deploySessionId);
        },
      ),
  ];
}

