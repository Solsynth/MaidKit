import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kMiddleMouseButton;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/shared/presentation/app_scaffold.dart';
import 'package:maid_kit/snippets/snippet_repository.dart';
import 'server_connection_actions.dart';
import 'server_detail_page.dart';
import 'servers_page.dart';
import 'file_editor_tab.dart';
import 'file_management_tab.dart';
import 'privacy_preferences.dart';
import 'server_models.dart';
import 'server_providers.dart';
import 'terminal_command_palette.dart';
import 'terminal_find_host.dart';
import 'terminal_session_adapter.dart';
import 'terminal_tabs_provider.dart';

/// Unified server workspace with dashboard, terminal, and file-management tabs.
class SessionsWorkspace extends ConsumerWidget {
  const SessionsWorkspace({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = ref.watch(terminalTabsProvider);
    final sessions = ref.watch(sessionsProvider);
    final servers = ref.watch(serversProvider);
    final focusedTerminal = switch (tabs.selectedTab) {
      final TerminalTab terminal => terminal,
      _ => null,
    };
    final focusedSession = _sessionForTab(sessions, tabs.selectedTab);

    return MaidKitAppScaffold(
      // The pane tab bar paints the top safe area when tabs are open; the
      // intro below pads itself instead, so the whole workspace stays flat.
      topSafeArea: false,
      body: Column(
        children: [
          Expanded(
            child: tabs.isEmpty
                ? SafeArea(
                    top: true,
                    child: _SessionIntro(
                      servers: servers,
                      tabs: tabs,
                      // Full-workspace intro (no pane chrome / no top tab strip).
                      onOpenTerminal: (server) =>
                          openTerminalFor(context, ref, server),
                      onOpenFiles: (server) => _openFiles(context, ref, server),
                    ),
                  )
                : _SessionLayoutView(tabs: tabs, servers: servers),
          ),
          _AnimatedTerminalStatusBar(
            session: focusedSession,
            terminal: focusedTerminal?.terminal,
            terminalId: focusedTerminal?.id,
          ),
        ],
      ),
    );
  }
}

SshSessionInfo? _sessionForTab(
  AsyncValue<List<SshSessionInfo>> sessions,
  SessionTab? tab,
) {
  if (tab == null) return null;
  return sessions.asData?.value
      .where((item) => item.serverId == tab.serverId)
      .firstOrNull;
}

/// Opens the file management tab for [server]'s side. The local machine has
/// no SFTP side and opens straight into the local browser.
Future<void> _openFiles(
  BuildContext context,
  WidgetRef ref,
  Server server, {
  String? paneId,
}) async {
  if (server.connectionType == ServerConnectionType.serial.name) return;
  if (server.connectionType == ServerConnectionType.local.name) {
    ref
        .read(terminalTabsProvider.notifier)
        .openFileManagement(server, paneId: paneId);
    return;
  }
  final manager = ref.read(connectionManagerProvider);
  if (manager.clientFor(server.id) == null &&
      !await connectForStatistics(context, ref, server)) {
    return;
  }
  ref
      .read(terminalTabsProvider.notifier)
      .openFileManagement(server, paneId: paneId);
}

class _SessionLayoutView extends ConsumerWidget {
  const _SessionLayoutView({required this.tabs, required this.servers});

  final TerminalTabsState tabs;
  final AsyncValue<List<Server>> servers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final root = tabs.layout;
    if (root == null) {
      final pane = tabs.focusedPane;
      if (pane == null) return const SizedBox.shrink();
      return _SessionPaneView(
        paneId: pane.id,
        tabs: tabs,
        servers: servers,
        atTop: true,
      );
    }
    return _LayoutNode(node: root, tabs: tabs, servers: servers, atTop: true);
  }
}

class _LayoutNode extends ConsumerWidget {
  const _LayoutNode({
    required this.node,
    required this.tabs,
    required this.servers,
    required this.atTop,
  });

  final SessionLayout node;
  final TerminalTabsState tabs;
  final AsyncValue<List<Server>> servers;

  /// Whether this subtree's tab bar sits on the top edge of the workspace and
  /// should therefore paint the top safe area with the tab-bar color.
  final bool atTop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (node) {
      case SessionLayoutLeaf(:final paneId):
        return _SessionPaneView(
          paneId: paneId,
          tabs: tabs,
          servers: servers,
          atTop: atTop,
        );
      case SessionLayoutSplit(
        :final id,
        :final axis,
        :final first,
        :final second,
        :final ratio,
      ):
        return _ResizableSplit(
          axis: axis,
          ratio: ratio,
          onRatioChanged: (value) =>
              ref.read(terminalTabsProvider.notifier).setSplitRatio(id, value),
          // Horizontal splits (side-by-side) keep both children at the top
          // edge; vertical splits (stacked) only keep the first child there.
          first: _LayoutNode(
            node: first,
            tabs: tabs,
            servers: servers,
            atTop: atTop,
          ),
          second: _LayoutNode(
            node: second,
            tabs: tabs,
            servers: servers,
            atTop: axis == SessionSplitAxis.horizontal ? atTop : false,
          ),
        );
    }
  }
}

class _ResizableSplit extends StatefulWidget {
  const _ResizableSplit({
    required this.axis,
    required this.ratio,
    required this.onRatioChanged,
    required this.first,
    required this.second,
  });

  final SessionSplitAxis axis;
  final double ratio;
  final ValueChanged<double> onRatioChanged;
  final Widget first;
  final Widget second;

  @override
  State<_ResizableSplit> createState() => _ResizableSplitState();
}

class _ResizableSplitState extends State<_ResizableSplit> {
  static const _dividerThickness = 4.0;
  double? _dragRatio;

  double get _ratio => _dragRatio ?? widget.ratio;

  void _onDragUpdate(DragUpdateDetails details, double maxExtent) {
    if (maxExtent <= 0) return;
    final delta = widget.axis == SessionSplitAxis.horizontal
        ? details.delta.dx
        : details.delta.dy;
    final next = clampSplitRatio(_ratio + delta / maxExtent);
    setState(() => _dragRatio = next);
  }

  void _onDragEnd() {
    final ratio = _dragRatio;
    if (ratio != null) {
      widget.onRatioChanged(ratio);
    }
    setState(() => _dragRatio = null);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isHorizontal = widget.axis == SessionSplitAxis.horizontal;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxExtent = isHorizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final available = maxExtent - _dividerThickness;
        final firstExtent = available * _ratio;
        final secondExtent = available - firstExtent;

        final children = <Widget>[
          SizedBox(
            width: isHorizontal ? firstExtent : null,
            height: isHorizontal ? null : firstExtent,
            child: widget.first,
          ),
          MouseRegion(
            cursor: isHorizontal
                ? SystemMouseCursors.resizeColumn
                : SystemMouseCursors.resizeRow,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: isHorizontal
                  ? (d) => _onDragUpdate(d, available)
                  : null,
              onHorizontalDragEnd: isHorizontal ? (_) => _onDragEnd() : null,
              onVerticalDragUpdate: isHorizontal
                  ? null
                  : (d) => _onDragUpdate(d, available),
              onVerticalDragEnd: isHorizontal ? null : (_) => _onDragEnd(),
              child: ColoredBox(
                color: scheme.outlineVariant.withValues(alpha: 0.6),
                child: SizedBox(
                  width: isHorizontal ? _dividerThickness : double.infinity,
                  height: isHorizontal ? double.infinity : _dividerThickness,
                ),
              ),
            ),
          ),
          SizedBox(
            width: isHorizontal ? secondExtent : null,
            height: isHorizontal ? null : secondExtent,
            child: widget.second,
          ),
        ];

        return isHorizontal
            ? Row(children: children)
            : Column(children: children);
      },
    );
  }
}

class _SessionPaneView extends ConsumerWidget {
  const _SessionPaneView({
    required this.paneId,
    required this.tabs,
    required this.servers,
    this.atTop = false,
  });

  final String paneId;
  final TerminalTabsState tabs;
  final AsyncValue<List<Server>> servers;

  /// Whether this pane's tab bar sits on the top edge of the workspace.
  final bool atTop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pane = tabs.panes[paneId];
    if (pane == null) return const SizedBox.shrink();

    final paneTabs = tabs.tabsInPane(paneId);
    final focused = tabs.focusedPaneId == paneId;
    final isEmptyPane = pane.isEmpty;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => ref.read(terminalTabsProvider.notifier).focusPane(paneId),
      child: Column(
        children: [
          // Only the pane's own tab strip — never a workspace-wide bar.
          _PaneTabBar(
            paneId: paneId,
            paneTabs: paneTabs,
            selectedTabId: pane.selectedTabId,
            focused: focused,
            showClosePane: tabs.hasSplits || isEmptyPane,
            fillTopSafeArea: atTop,
          ),
          Expanded(
            // The pane tab bar owns the top safe area; strip it here so tab
            // bodies (dashboard, server detail, editors) don't re-apply the
            // status-bar inset and leave a gap below the tab bar.
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: isEmptyPane
                  ? _SessionIntro(
                      servers: servers,
                      tabs: tabs,
                      compact: true,
                      onOpenTerminal: (server) =>
                          openTerminalFor(context, ref, server, paneId: paneId),
                      onOpenFiles: (server) =>
                          _openFiles(context, ref, server, paneId: paneId),
                    )
                  : _PaneTabStack(
                      paneTabs: paneTabs,
                      selectedTabId: pane.selectedTabId,
                      paneFocused: focused,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared height for each pane tab strip and its tab chips.
const _paneTabBarHeight = 40.0;

class _TabDragData {
  const _TabDragData({required this.tabId, required this.fromPaneId});

  final String tabId;
  final String fromPaneId;
}

class _PaneTabBar extends ConsumerWidget {
  const _PaneTabBar({
    required this.paneId,
    required this.paneTabs,
    required this.selectedTabId,
    required this.focused,
    required this.showClosePane,
    this.fillTopSafeArea = false,
  });

  final String paneId;
  final List<SessionTab> paneTabs;
  final String? selectedTabId;
  final bool focused;
  final bool showClosePane;

  /// Whether this tab bar sits on the top edge and should extend its color
  /// into the top safe area instead of leaving a background-colored strip.
  final bool fillTopSafeArea;

  void _acceptTab(WidgetRef ref, _TabDragData data, {int? toIndex}) {
    ref
        .read(terminalTabsProvider.notifier)
        .moveTab(data.tabId, paneId, toIndex: toIndex);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final topInset = MediaQuery.paddingOf(context).top;

    return Material(
      color: focused ? scheme.surfaceContainerHigh : scheme.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (fillTopSafeArea && topInset > 0) SizedBox(height: topInset),
          SizedBox(
            height: _paneTabBarHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: DragTarget<_TabDragData>(
                    onWillAcceptWithDetails: (details) =>
                        details.data.tabId.isNotEmpty,
                    onAcceptWithDetails: (details) =>
                        _acceptTab(ref, details.data),
                    builder: (context, candidate, rejected) {
                      final hovering = candidate.isNotEmpty;
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          color: hovering
                              ? scheme.primary.withValues(alpha: 0.08)
                              : null,
                        ),
                        child: paneTabs.isEmpty
                            ? Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 12),
                                  child: Text(
                                    hovering
                                        ? 'sessionsDropTabHere'.tr()
                                        : 'sessionsNewPane'.tr(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding: EdgeInsets.zero,
                                // Trailing slot so tabs can be dropped after the last item.
                                itemCount: paneTabs.length + 1,
                                itemBuilder: (context, index) {
                                  if (index == paneTabs.length) {
                                    return _TabDropTail(
                                      hovering: hovering,
                                      onAccept: (data) => _acceptTab(
                                        ref,
                                        data,
                                        toIndex: paneTabs.length,
                                      ),
                                    );
                                  }
                                  final tab = paneTabs[index];
                                  final selected = tab.id == selectedTabId;
                                  return _DraggablePaneTab(
                                    key: ValueKey(tab.id),
                                    tab: tab,
                                    paneId: paneId,
                                    selected: selected,
                                    index: index,
                                    onSelect: () {
                                      ref
                                          .read(terminalTabsProvider.notifier)
                                          .focusPane(paneId);
                                      ref
                                          .read(terminalTabsProvider.notifier)
                                          .select(tab.id);
                                    },
                                    onClose: () => ref
                                        .read(terminalTabsProvider.notifier)
                                        .close(tab.id),
                                    onAccept: (data, insertIndex) => _acceptTab(
                                      ref,
                                      data,
                                      toIndex: insertIndex,
                                    ),
                                  );
                                },
                              ),
                      );
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'sessionsSplitRight'.tr(),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: _paneTabBarHeight,
                    minHeight: _paneTabBarHeight,
                  ),
                  onPressed: () {
                    ref.read(terminalTabsProvider.notifier).focusPane(paneId);
                    ref
                        .read(terminalTabsProvider.notifier)
                        .splitEmpty(SessionSplitAxis.horizontal);
                  },
                  icon: const Icon(Symbols.vertical_split, size: 20),
                ),
                IconButton(
                  tooltip: 'sessionsSplitDown'.tr(),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: _paneTabBarHeight,
                    minHeight: _paneTabBarHeight,
                  ),
                  onPressed: () {
                    ref.read(terminalTabsProvider.notifier).focusPane(paneId);
                    ref
                        .read(terminalTabsProvider.notifier)
                        .splitEmpty(SessionSplitAxis.vertical);
                  },
                  icon: const Icon(Symbols.horizontal_split, size: 20),
                ),
                IconButton(
                  tooltip: 'sessionsSessionActions'.tr(),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: _paneTabBarHeight,
                    minHeight: _paneTabBarHeight,
                  ),
                  onPressed: () {
                    ref.read(terminalTabsProvider.notifier).focusPane(paneId);
                    showTerminalCommandPalette(context, ref);
                  },
                  icon: const Icon(Symbols.add, size: 20),
                ),
                if (showClosePane)
                  IconButton(
                    tooltip: 'sessionsClosePane'.tr(),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: _paneTabBarHeight,
                      minHeight: _paneTabBarHeight,
                    ),
                    onPressed: () => ref
                        .read(terminalTabsProvider.notifier)
                        .closePane(paneId),
                    icon: const Icon(Symbols.close, size: 18),
                  ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TabDropTail extends StatelessWidget {
  const _TabDropTail({required this.hovering, required this.onAccept});

  final bool hovering;
  final void Function(_TabDragData data) onAccept;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<_TabDragData>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidate, rejected) {
        final active = candidate.isNotEmpty || hovering;
        return SizedBox(
          width: 28,
          height: _paneTabBarHeight,
          child: active
              ? Align(
                  child: Container(width: 2, height: 20, color: scheme.primary),
                )
              : null,
        );
      },
    );
  }
}

class _DraggablePaneTab extends StatelessWidget {
  const _DraggablePaneTab({
    super.key,
    required this.tab,
    required this.paneId,
    required this.selected,
    required this.index,
    required this.onSelect,
    required this.onClose,
    required this.onAccept,
  });

  final SessionTab tab;
  final String paneId;
  final bool selected;
  final int index;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final void Function(_TabDragData data, int insertIndex) onAccept;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chip = _PaneTabChip(
      tab: tab,
      selected: selected,
      onSelect: onSelect,
      onClose: onClose,
    );

    return DragTarget<_TabDragData>(
      onWillAcceptWithDetails: (details) => details.data.tabId != tab.id,
      onAcceptWithDetails: (details) {
        // Insert before this tab for stable reordering.
        onAccept(details.data, index);
      },
      builder: (context, candidate, rejected) {
        final showInsert = candidate.isNotEmpty;
        return SizedBox(
          height: _paneTabBarHeight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showInsert)
                Container(
                  width: 2,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  color: scheme.primary,
                ),
              Draggable<_TabDragData>(
                data: _TabDragData(tabId: tab.id, fromPaneId: paneId),
                dragAnchorStrategy: pointerDragAnchorStrategy,
                feedback: Material(
                  elevation: 4,
                  color: scheme.surfaceContainerHighest,
                  child: SizedBox(
                    height: _paneTabBarHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _TabActivityIcon(tab: tab),
                          const SizedBox(width: 6),
                          Text(
                            _tabLabel(tab),
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                childWhenDragging: Opacity(opacity: 0.35, child: chip),
                child: chip,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PaneTabChip extends StatelessWidget {
  const _PaneTabChip({
    required this.tab,
    required this.selected,
    required this.onSelect,
    required this.onClose,
  });

  final SessionTab tab;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: _paneTabBarHeight,
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons & kMiddleMouseButton != 0) {
            onClose();
          }
        },
        child: InkWell(
          onTap: onSelect,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? scheme.primary : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TabActivityIcon(
                    tab: tab,
                    color: selected ? scheme.primary : null,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _tabLabel(tab),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: selected ? scheme.primary : null,
                    ),
                  ),
                  const SizedBox(width: 2),
                  if (tab is! DashboardTab)
                    IconButton(
                      tooltip: 'sessionsCloseTab'.tr(),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      onPressed: onClose,
                      icon: const Icon(Symbols.close, size: 16),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabActivityIcon extends StatelessWidget {
  const _TabActivityIcon({required this.tab, this.color});

  final SessionTab tab;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (tab case TerminalTab(:final terminal)) {
      return StreamBuilder<TerminalTaskActivity>(
        stream: terminal.taskActivity,
        initialData: terminal.currentTaskActivity,
        builder: (context, snapshot) {
          final activity = snapshot.data!;
          if (activity.running) {
            return SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                value: activity.progress,
                strokeWidth: 2,
                color: color,
              ),
            );
          }
          return Icon(Symbols.terminal, size: 16, color: color);
        },
      );
    }
    return Icon(_tabIcon(tab), size: 16, color: color);
  }
}

/// Keeps every tab in the pane mounted so switching/splitting does not reset
/// file-browser or terminal chrome state. [sessionTabViewKey] further preserves
/// that state when a tab moves to another pane or the layout tree reshapes.
class _PaneTabStack extends StatelessWidget {
  const _PaneTabStack({
    required this.paneTabs,
    required this.selectedTabId,
    required this.paneFocused,
  });

  final List<SessionTab> paneTabs;
  final String? selectedTabId;
  final bool paneFocused;

  @override
  Widget build(BuildContext context) {
    if (paneTabs.isEmpty) return const SizedBox.shrink();
    final selectedIndex = paneTabs.indexWhere((tab) => tab.id == selectedTabId);
    final index = selectedIndex < 0 ? 0 : selectedIndex;
    final selectedTab = paneTabs[index];
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final tab in paneTabs.where((tab) => tab.id != selectedTab.id))
          _AnimatedPaneTabContent(
            key: ValueKey(tab.id),
            active: false,
            child: _SessionTabBody(tab: tab, autofocus: false),
          ),
        _AnimatedPaneTabContent(
          key: ValueKey(selectedTab.id),
          active: true,
          child: _SessionTabBody(tab: selectedTab, autofocus: paneFocused),
        ),
      ],
    );
  }
}

/// Keeps inactive views mounted while animating the visible pane tab in and
/// the previous tab out, so terminal and file-management state is retained.
class _AnimatedPaneTabContent extends StatelessWidget {
  const _AnimatedPaneTabContent({
    required this.active,
    required this.child,
    super.key,
  });

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !active,
    child: AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      opacity: active ? 1 : 0,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        offset: active ? Offset.zero : const Offset(0.02, 0),
        child: child,
      ),
    ),
  );
}

class _SessionTabBody extends ConsumerWidget {
  const _SessionTabBody({required this.tab, required this.autofocus});

  final SessionTab tab;
  final bool autofocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // GlobalKey reparents State when this tab moves across the layout tree
    // (split creation, drag between panes, etc.).
    final key = sessionTabViewKey(tab.id);
    if (tab is DashboardTab) {
      return ServerDashboardTab(key: key);
    }
    if (tab is ServerDetailTab) {
      final detailTab = tab as ServerDetailTab;
      return ServerDetailPage(
        key: key,
        server: detailTab.server,
        initialTab: detailTab.initialTab,
        initialComposeProject: detailTab.initialComposeProject,
        embedded: true,
      );
    }
    if (tab is FileManagementTab) {
      return FileManagementTabView(key: key, tab: tab as FileManagementTab);
    }
    if (tab is FileEditorTab) {
      return FileEditorTabView(key: key, tab: tab as FileEditorTab);
    }
    final terminalTab = tab as TerminalTab;
    return ColoredBox(
      color: ref.watch(transparentTerminalBackgroundProvider)
          ? Colors.transparent
          : const Color(0xFF111315),
      child: ClipRect(
        child: TerminalFindHost(
          key: key,
          adapter: terminalTab.terminal,
          autofocus: autofocus,
          transparentBackground: ref.watch(
            transparentTerminalBackgroundProvider,
          ),
          onKeyEvent: (_, event) {
            if (!_isTerminalSnippetShortcut(event)) {
              return KeyEventResult.ignored;
            }
            unawaited(
              _showTerminalSnippetPopover(
                context,
                ref,
                terminalId: terminalTab.id,
                anchorRect: terminalTab.terminal.cursorGlobalRect,
              ),
            );
            return KeyEventResult.handled;
          },
        ),
      ),
    );
  }
}

bool _isTerminalSnippetShortcut(KeyEvent event) {
  if (event is! KeyDownEvent) return false;
  final keyboard = HardwareKeyboard.instance;
  final command = keyboard.isMetaPressed || keyboard.isControlPressed;
  final plus =
      event.logicalKey == LogicalKeyboardKey.add ||
      event.logicalKey == LogicalKeyboardKey.equal;
  return command && plus;
}

Future<void> _showTerminalSnippetPopover(
  BuildContext context,
  WidgetRef ref, {
  required String terminalId,
  Rect? anchorRect,
}) async {
  final snippets = await ref.read(snippetRepositoryProvider).all();
  if (!context.mounted) return;

  if (snippets.isEmpty) {
    await showMenu<void>(
      context: context,
      position: _terminalSnippetMenuPosition(context, anchorRect),
      items: [
        PopupMenuItem<void>(enabled: false, child: Text('snippetsEmpty'.tr())),
      ],
    );
    return;
  }

  final selected = await showMenu<ScriptSnippet>(
    context: context,
    position: _terminalSnippetMenuPosition(context, anchorRect),
    constraints: const BoxConstraints(maxWidth: 380, maxHeight: 420),
    items: [
      PopupMenuItem<ScriptSnippet>(
        enabled: false,
        child: Text(
          'snippetsRun'.tr(),
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      for (final snippet in snippets)
        PopupMenuItem<ScriptSnippet>(
          value: snippet,
          height: 64,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Symbols.code),
            title: Text(
              snippet.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              snippet.script.replaceAll('\n', ' '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
    ],
  );
  if (selected != null && context.mounted) {
    ref
        .read(terminalTabsProvider.notifier)
        .executeSnippet(terminalId, selected);
  }
}

RelativeRect _terminalSnippetMenuPosition(
  BuildContext context,
  Rect? anchorRect,
) {
  final overlay = Overlay.of(context).context.findRenderObject();
  if (overlay is! RenderBox) {
    return const RelativeRect.fromLTRB(16, 16, 16, 16);
  }

  final target = anchorRect;
  if (target != null) {
    final topLeft = overlay.globalToLocal(target.topLeft);
    final bottomRight = overlay.globalToLocal(target.bottomRight);
    return _relativeMenuPosition(
      Rect.fromPoints(topLeft, bottomRight),
      overlay.size,
    );
  }

  final renderTarget = context.findRenderObject();
  if (renderTarget is! RenderBox) {
    return const RelativeRect.fromLTRB(16, 16, 16, 16);
  }
  final topLeft = renderTarget.localToGlobal(Offset.zero, ancestor: overlay);
  return _relativeMenuPosition(topLeft & renderTarget.size, overlay.size);
}

RelativeRect _relativeMenuPosition(Rect anchor, Size overlaySize) {
  const menuWidth = 380.0;
  const menuHeight = 420.0;
  final maxLeft = overlaySize.width > menuWidth + 16
      ? overlaySize.width - menuWidth - 8
      : 8.0;
  final maxTop = overlaySize.height > menuHeight + 16
      ? overlaySize.height - menuHeight - 8
      : 8.0;
  final left = anchor.left.clamp(8.0, maxLeft);
  var top = anchor.bottom + 8;
  if (top > maxTop) {
    top = (anchor.top - menuHeight - 8).clamp(8.0, maxTop);
  }
  return RelativeRect.fromLTRB(
    left,
    top,
    overlaySize.width - left,
    overlaySize.height - top,
  );
}

IconData _tabIcon(SessionTab tab) => switch (tab.type) {
  SessionTabType.dashboard => Symbols.dashboard,
  SessionTabType.serverDetail => Symbols.dns,
  SessionTabType.terminal => Symbols.terminal,
  SessionTabType.fileManagement => Symbols.folder,
  SessionTabType.fileEditor => Symbols.edit_document,
};

String _tabLabel(SessionTab tab) {
  if (tab is DashboardTab) return 'tabDashboard'.tr();
  if (tab is FileEditorTab) {
    return tab.isRemote ? '${tab.fileName} · ${tab.serverName}' : tab.fileName;
  }
  if (tab is FileManagementTab) {
    return 'tabFiles'.tr(args: [tab.serverName]);
  }
  return tab.serverName;
}

class _AnimatedTerminalStatusBar extends StatelessWidget {
  const _AnimatedTerminalStatusBar({
    required this.session,
    required this.terminal,
    required this.terminalId,
  });

  final SshSessionInfo? session;
  final TerminalSessionAdapter? terminal;
  final String? terminalId;

  @override
  Widget build(BuildContext context) {
    final activeTerminal = terminal;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      reverseDuration: const Duration(milliseconds: 140),
      transitionBuilder: (child, animation) {
        final curve = CurvedAnimation(parent: animation, curve: Curves.easeOut);
        return ClipRect(
          child: SizeTransition(
            sizeFactor: curve,
            alignment: Alignment.bottomCenter,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.35),
                end: Offset.zero,
              ).animate(curve),
              child: FadeTransition(opacity: curve, child: child),
            ),
          ),
        );
      },
      child: activeTerminal == null
          ? const SizedBox.shrink(key: ValueKey('no-session'))
          : _TerminalStatusBar(
              key: ValueKey(activeTerminal),
              session: session,
              terminal: activeTerminal,
              terminalId: terminalId!,
            ),
    );
  }
}

class _TerminalStatusBar extends ConsumerStatefulWidget {
  const _TerminalStatusBar({
    required this.session,
    required this.terminal,
    required this.terminalId,
    super.key,
  });

  final SshSessionInfo? session;
  final TerminalSessionAdapter terminal;
  final String terminalId;

  @override
  ConsumerState<_TerminalStatusBar> createState() => _TerminalStatusBarState();
}

class _TerminalStatusBarState extends ConsumerState<_TerminalStatusBar> {
  static const _pingInterval = Duration(seconds: 5);

  Timer? _pingTimer;
  Duration? _latency;
  var _measuringLatency = false;

  @override
  void initState() {
    super.initState();
    _measureLatency();
    _pingTimer = Timer.periodic(_pingInterval, (_) => _measureLatency());
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    super.dispose();
  }

  Future<void> _measureLatency() async {
    if (_measuringLatency) return;
    _measuringLatency = true;
    try {
      final latency = await ref
          .read(connectionManagerProvider)
          .measureTerminalLatency(widget.terminalId);
      if (mounted) setState(() => _latency = latency);
    } finally {
      _measuringLatency = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mutedStyle = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final valueStyle = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final stats = widget.session?.stats;
    final memoryTotalKb = stats?.memoryTotalKb;
    final memoryAvailableKb = stats?.memoryAvailableKb;
    final usedMemoryKb = memoryTotalKb == null || memoryAvailableKb == null
        ? null
        : memoryTotalKb - memoryAvailableKb;
    final memoryRatio =
        usedMemoryKb == null || memoryTotalKb == null || memoryTotalKb == 0
        ? null
        : (usedMemoryKb / memoryTotalKb).clamp(0.0, 1.0);
    final systemLabel = [
      widget.session?.systemInfo?.distribution,
      widget.session?.systemInfo?.kernel,
    ].whereType<String>().join(' · ');

    final segments = <Widget>[
      if (widget.session case final activeSession?)
        _StatusBarIdentity(session: activeSession),
      if (_latency case final latency?)
        _StatusBarMetric(
          icon: Symbols.network_ping,
          tooltip: 'terminalSshPing'.tr(),
          value: '${latency.inMilliseconds} ms',
          valueColor: _statusBarPingColor(latency, scheme),
          mutedStyle: mutedStyle,
          valueStyle: valueStyle,
        ),
      if (stats?.loadAverage case final load?)
        _StatusBarMetric(
          icon: Symbols.speed,
          tooltip: 'detailLoadAverage'.tr(),
          value: load.toStringAsFixed(2),
          valueColor: _statusBarLoadColor(load, scheme),
          mutedStyle: mutedStyle,
          valueStyle: valueStyle,
        ),
      if (usedMemoryKb != null && memoryTotalKb != null)
        _StatusBarMetric(
          icon: Symbols.memory_alt,
          tooltip: 'detailMemory'.tr(),
          value: _formatMemory(usedMemoryKb, memoryTotalKb),
          valueColor: _statusBarMemoryColor(memoryRatio, scheme),
          mutedStyle: mutedStyle,
          valueStyle: valueStyle,
        ),
      if (stats?.uptime case final uptime?)
        _StatusBarMetric(
          icon: Symbols.schedule,
          tooltip: 'detailUptime'.tr(),
          value: _formatUptime(uptime),
          mutedStyle: mutedStyle,
          valueStyle: valueStyle,
        ),
      if (systemLabel.isNotEmpty)
        Tooltip(
          message: systemLabel,
          waitDuration: const Duration(milliseconds: 400),
          child: Text(systemLabel, style: mutedStyle),
        ),
    ];

    return Material(
      color: scheme.surfaceContainerLow,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (defaultTargetPlatform == TargetPlatform.iOS ||
                  defaultTargetPlatform == TargetPlatform.android)
                _TerminalQuickKeys(terminal: widget.terminal),
              if (segments.isNotEmpty)
                SizedBox(
                  height: 28,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    scrollDirection: Axis.horizontal,
                    itemCount: segments.length,
                    separatorBuilder: (_, _) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Center(
                        child: Container(
                          width: 1,
                          height: 12,
                          color: scheme.outlineVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    itemBuilder: (context, index) =>
                        Center(child: segments[index]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TerminalQuickKeys extends StatefulWidget {
  const _TerminalQuickKeys({required this.terminal});

  final TerminalSessionAdapter terminal;

  @override
  State<_TerminalQuickKeys> createState() => _TerminalQuickKeysState();
}

class _TerminalQuickKeysState extends State<_TerminalQuickKeys> {
  static const _commonKeys = [
    ('Ctrl+C', '\u0003'),
    ('Ctrl+D', '\u0004'),
    ('Ctrl+L', '\u000c'),
    ('Tab', '\t'),
    ('Esc', '\u001b'),
    ('↑', '\u001b[A'),
    ('↓', '\u001b[B'),
    ('←', '\u001b[D'),
    ('→', '\u001b[C'),
    ('Enter', '\r'),
  ];

  static const _extraKeys = [
    ('Ctrl+Z', '\u001a'),
    ('Ctrl+A', '\u0001'),
    ('Ctrl+E', '\u0005'),
    ('Ctrl+U', '\u0015'),
    ('PgUp', '\u001b[5~'),
    ('PgDn', '\u001b[6~'),
  ];

  static const _allKeys = [..._commonKeys, ..._extraKeys];

  final _scrollController = ScrollController();
  var _expanded = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _toggle() {
    final expanded = !_expanded;
    setState(() => _expanded = expanded);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(
        expanded ? _scrollController.position.maxScrollExtent : 0,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final terminal = widget.terminal;
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final keys = _expanded ? _allKeys : _commonKeys;

    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: ListView.separated(
                key: ValueKey(_expanded),
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
                scrollDirection: Axis.horizontal,
                itemCount: keys.length,
                separatorBuilder: (_, _) => const SizedBox(width: 4),
                itemBuilder: (context, index) {
                  final (label, input) = keys[index];
                  return TextButton(
                    onPressed: () => terminal.sendInput(input),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: Text(label),
                  );
                },
              ),
            ),
          ),
          IconButton(
            tooltip: keyboardVisible
                ? 'terminalKeyboardHide'.tr()
                : 'terminalKeyboardShow'.tr(),
            onPressed: keyboardVisible
                ? terminal.hideKeyboard
                : terminal.showKeyboard,
            icon: Icon(
              keyboardVisible
                  ? Symbols.keyboard_arrow_down
                  : Symbols.keyboard_arrow_up,
            ),
          ),
          IconButton(
            tooltip: _expanded
                ? 'terminalKeysFewer'.tr()
                : 'terminalKeysMore'.tr(),
            onPressed: _toggle,
            icon: Icon(_expanded ? Symbols.expand_less : Symbols.expand_more),
          ),
        ],
      ),
    );
  }
}

class _StatusBarIdentity extends StatelessWidget {
  const _StatusBarIdentity({required this.session});

  final SshSessionInfo session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (label, color) = switch (session.status) {
      SessionStatus.connected => ('commonConnected'.tr(), scheme.primary),
      SessionStatus.connecting => ('commonConnecting'.tr(), scheme.tertiary),
      SessionStatus.failed => ('commonFailed'.tr(), scheme.error),
      SessionStatus.closed => (
        'commonNotConnected'.tr(),
        scheme.onSurfaceVariant,
      ),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: color)),
        const SizedBox(width: 8),
        Text(
          session.serverName,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _StatusBarMetric extends StatelessWidget {
  const _StatusBarMetric({
    required this.icon,
    required this.tooltip,
    required this.value,
    required this.mutedStyle,
    required this.valueStyle,
    this.valueColor,
  });

  final IconData icon;
  final String tooltip;
  final String value;
  final TextStyle? mutedStyle;
  final TextStyle? valueStyle;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            value,
            style: (valueStyle ?? mutedStyle)?.copyWith(
              color: valueColor ?? valueStyle?.color ?? mutedStyle?.color,
            ),
          ),
        ],
      ),
    );
  }
}

Color? _statusBarLoadColor(double? load, ColorScheme scheme) {
  if (load == null) return null;
  if (load >= 4) return scheme.error;
  if (load >= 2) return scheme.tertiary;
  return null;
}

Color? _statusBarMemoryColor(double? ratio, ColorScheme scheme) {
  if (ratio == null) return null;
  if (ratio >= 0.9) return scheme.error;
  if (ratio >= 0.75) return scheme.tertiary;
  return null;
}

Color? _statusBarPingColor(Duration latency, ColorScheme scheme) {
  if (latency >= const Duration(milliseconds: 250)) return scheme.error;
  if (latency >= const Duration(milliseconds: 100)) return scheme.tertiary;
  return null;
}

String _formatMemory(int usedKb, int totalKb) =>
    '${(usedKb / 1024 / 1024).toStringAsFixed(1)} / ${(totalKb / 1024 / 1024).toStringAsFixed(1)} GB';

String _formatUptime(Duration uptime) {
  final days = uptime.inDays;
  final hours = uptime.inHours.remainder(24);
  final minutes = uptime.inMinutes.remainder(60);
  if (days > 0) return '${days}d ${hours}h';
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}

/// Empty-state server picker used for the full workspace and for empty panes.
class _SessionIntro extends StatelessWidget {
  const _SessionIntro({
    required this.servers,
    required this.tabs,
    required this.onOpenTerminal,
    required this.onOpenFiles,
    this.compact = false,
  });

  final AsyncValue<List<Server>> servers;
  final TerminalTabsState tabs;
  final Future<void> Function(Server server) onOpenTerminal;
  final Future<void> Function(Server server) onOpenFiles;
  final bool compact;

  @override
  Widget build(BuildContext context) => servers.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (error, _) =>
        Center(child: Text('serversLoadError'.tr(args: [error.toString()]))),
    data: (servers) => servers.isEmpty
        ? Center(
            child: FilledButton.icon(
              onPressed: () => AutoTabsRouter.of(context).setActiveIndex(0),
              icon: const Icon(Symbols.add),
              label: Text('serversAddServer'.tr()),
            ),
          )
        : _TerminalServerGrid(
            servers: servers,
            tabs: tabs,
            compact: compact,
            onOpenTerminal: onOpenTerminal,
            onOpenFiles: onOpenFiles,
          ),
  );
}

class _TerminalServerGrid extends ConsumerWidget {
  const _TerminalServerGrid({
    required this.servers,
    required this.tabs,
    required this.onOpenTerminal,
    required this.onOpenFiles,
    this.compact = false,
  });

  final List<Server> servers;
  final TerminalTabsState tabs;
  final Future<void> Function(Server server) onOpenTerminal;
  final Future<void> Function(Server server) onOpenFiles;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hideAddresses = ref.watch(hideServerAddressesProvider);
    return GridView.builder(
      padding: EdgeInsets.all(compact ? 12 : 24),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: compact ? 320 : 380,
        mainAxisExtent: compact ? 168 : 180,
        mainAxisSpacing: compact ? 12 : 16,
        crossAxisSpacing: compact ? 12 : 16,
      ),
      itemCount: servers.length,
      itemBuilder: (context, index) {
        final server = servers[index];
        final openCount = tabs.tabs
            .where((tab) => tab.serverId == server.id)
            .length;
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: EdgeInsets.all(compact ? 12 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Symbols.terminal, size: 22),
                const SizedBox(height: 12),
                Text(
                  server.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  serverAddressLabel(server, hideAddresses: hideAddresses),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                _ServerCardActions(
                  openCount: openCount,
                  onOpenTerminal: () => onOpenTerminal(server),
                  onOpenFiles: () => onOpenFiles(server),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Action row that collapses to icon buttons when the card is narrow (split panes).
class _ServerCardActions extends StatelessWidget {
  const _ServerCardActions({
    required this.openCount,
    required this.onOpenTerminal,
    required this.onOpenFiles,
  });

  final int openCount;
  final VoidCallback onOpenTerminal;
  final VoidCallback onOpenFiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Split panes often leave cards under ~260px — use icon-only actions.
        final narrow = constraints.maxWidth < 260;
        if (narrow) {
          return Row(
            children: [
              Expanded(
                child: Text(
                  'sessionsOpenCount'.tr(args: ['$openCount']),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'sessionsNewTerminal'.tr(),
                visualDensity: VisualDensity.compact,
                onPressed: onOpenTerminal,
                icon: const Icon(Symbols.add, size: 20),
              ),
              IconButton(
                tooltip: 'sessionsOpenFileManagement'.tr(),
                visualDensity: VisualDensity.compact,
                onPressed: onOpenFiles,
                icon: const Icon(Symbols.folder, size: 20),
              ),
            ],
          );
        }
        return Row(
          children: [
            Text(
              'sessionsOpenCount'.tr(args: ['$openCount']),
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: onOpenTerminal,
              icon: const Icon(Symbols.add),
              label: Text('sessionsNewTerminal'.tr()),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'sessionsOpenFileManagement'.tr(),
              onPressed: onOpenFiles,
              icon: const Icon(Symbols.folder),
            ),
          ],
        );
      },
    );
  }
}
