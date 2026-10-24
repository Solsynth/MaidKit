import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kMiddleMouseButton;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/agent/agent_page.dart';
import 'package:maid_kit/containers/projects_page.dart';
import 'package:maid_kit/shared/presentation/app_scaffold.dart';
import 'package:maid_kit/shared/presentation/tab_navigator.dart';
import 'package:maid_kit/shared/presentation/window_chrome.dart';
import 'package:maid_kit/snippets/snippet_confirmation.dart';
import 'package:maid_kit/snippets/snippet_repository.dart';
import 'package:maid_kit/theme.dart';
import 'assets_page.dart';
import 'maidcafe_cloud_page.dart';
import 'server_connection_actions.dart';
import 'server_detail_page.dart';
import 'session_lookup.dart';
import 'maidcafe_server_tab.dart';
import 'servers_page.dart';
import 'cloud_account_button.dart';
import 'file_editor_tab.dart';
import 'file_management_tab.dart';
import 'notifications_modal.dart';
import 'server_models.dart';
import 'server_providers.dart';
import 'sessions_page.dart';
import 'settings_page.dart';
import 'terminal_command_palette.dart';
import 'terminal_find_host.dart';
import 'terminal_session_adapter.dart';
import 'terminal_sudo_hint.dart';
import 'terminal_tabs_provider.dart';

/// Unified server workspace with dashboard, terminal, and file-management tabs.
///
/// On desktop the top pane tab strip doubles as the window title bar: it is the
/// row that already names the app's work, so it claims the shell's title bar
/// slot instead of leaving a second, mostly empty bar above it.
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
      // The workspace paints edge to edge. The top inset is owned by the pane
      // tab bar (and by the intro when no tabs are open); the bottom inset is
      // owned by whatever ends up on the bottom edge — the terminal status bar
      // pads itself, and a pane with nothing below it reaches the screen bottom
      // instead of leaving a dead band where the old navigation bar used to be.
      useSafeArea: false,
      body: Column(
        children: [
          Expanded(
            child: tabs.isEmpty
                ? SafeArea(
                    top: true,
                    bottom: false,
                    child: SessionIntro(
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
          // Keyed on the terminal id: a dashboard behind the strip keeps its
          // own exit animation instead of the bar swapping to a stale readout.
          AnimatedTerminalStatusBar(
            key: ValueKey(focusedTerminal?.id),
            session: focusedSession,
            terminal: focusedTerminal?.terminal,
            terminalId: focusedTerminal?.id,
            transport: focusedTerminal?.transport,
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
  return sessionForServer(sessions.asData?.value ?? const [], tab.serverId);
}

/// Opens the file management tab for [server]'s side.
Future<void> _openFiles(
  BuildContext context,
  WidgetRef ref,
  Server server, {
  String? paneId,
  String? initialPath,
}) async {
  // The file manager needs SFTP and the local disk.
  if (kIsWeb) return;
  if (server.connectionType != ServerConnectionType.ssh.name) return;
  final manager = ref.read(connectionManagerProvider);
  if (manager.clientFor(server.id) == null &&
      !await connectForStatistics(context, ref, server)) {
    return;
  }
  ref
      .read(terminalTabsProvider.notifier)
      .openFileManagement(server, initialPath: initialPath, paneId: paneId);
}

Future<void> _openFilesForTerminal(
  BuildContext context,
  WidgetRef ref,
  TerminalTab tab,
) async {
  final server = ref
      .read(serversProvider)
      .asData
      ?.value
      .where((item) => item.id == tab.serverId)
      .firstOrNull;
  if (server == null || !context.mounted) return;
  await _openFiles(
    context,
    ref,
    server,
    initialPath: tab.terminal.currentDirectory,
  );
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
        titleBarSlot: true,
      );
    }
    return _LayoutNode(
      node: root,
      tabs: tabs,
      servers: servers,
      atTop: true,
      titleBarSlot: true,
    );
  }
}

class _LayoutNode extends ConsumerWidget {
  const _LayoutNode({
    required this.node,
    required this.tabs,
    required this.servers,
    required this.atTop,
    required this.titleBarSlot,
  });

  final SessionLayout node;
  final TerminalTabsState tabs;
  final AsyncValue<List<Server>> servers;

  /// Whether this subtree's tab bar sits on the top edge of the workspace and
  /// should therefore paint the top safe area with the tab-bar color.
  final bool atTop;

  /// Whether this subtree owns the merged window title bar. Only the first
  /// child of a split can: it is the strip at the top-left of the window.
  final bool titleBarSlot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (node) {
      case SessionLayoutLeaf(:final paneId):
        return _SessionPaneView(
          paneId: paneId,
          tabs: tabs,
          servers: servers,
          atTop: atTop,
          titleBarSlot: titleBarSlot,
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
            titleBarSlot: titleBarSlot,
          ),
          second: _LayoutNode(
            node: second,
            tabs: tabs,
            servers: servers,
            atTop: axis == SessionSplitAxis.horizontal ? atTop : false,
            titleBarSlot: false,
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
    this.titleBarSlot = false,
  });

  final String paneId;
  final TerminalTabsState tabs;
  final AsyncValue<List<Server>> servers;

  /// Whether this pane's tab bar sits on the top edge of the workspace.
  final bool atTop;

  /// Whether this pane's strip is the one merged into the window title bar.
  /// Only the top-left strip of the layout owns that slot.
  final bool titleBarSlot;

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
          // Only the pane's own tab strip — never a workspace-wide bar. On
          // desktop the topmost strip is also the window title bar.
          _PaneTabBar(
            paneId: paneId,
            paneTabs: paneTabs,
            selectedTabId: pane.selectedTabId,
            focused: focused,
            showClosePane: tabs.hasSplits || isEmptyPane,
            fillTopSafeArea: atTop,
            isTitleBar: titleBarSlot && ref.watch(desktopWindowProvider),
          ),
          Expanded(
            // The pane tab bar owns the top safe area; strip it here so tab
            // bodies (dashboard, server detail, editors) don't re-apply the
            // status-bar inset and leave a gap below the tab bar. The bottom
            // inset is stripped for the same reason: a tab body reaches the
            // screen bottom (its own content padding keeps rows clear of the
            // home indicator) unless the terminal status bar occupies the band.
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              removeBottom: true,
              child: isEmptyPane
                  ? SessionIntro(
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
///
/// On desktop the topmost strip is the window title bar, so the height is the
/// title bar height and the two rows collapse into one.
const _paneTabBarHeight = kMaidKitTitleBarHeight;

/// Pane width below which a strip keeps the title of the focused tab only.
///
/// On a narrow pane every title would crowd out the tabs themselves, but icons
/// alone make it hard to tell what is open, so the focused tab keeps its title.
const _paneTabTitleBreakpoint = 768.0;

/// Widest a tab title may draw before it is ellipsized.
const _paneTabTitleMaxWidth = 240.0;

/// How long a tab title takes to expand out of its icon, and collapse back.
const _paneTabTitleDuration = Duration(milliseconds: 160);

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
    this.isTitleBar = false,
  });

  final String paneId;
  final List<SessionTab> paneTabs;
  final String? selectedTabId;
  final bool focused;
  final bool showClosePane;

  /// Whether this tab bar sits on the top edge and should extend its color
  /// into the top safe area instead of leaving a background-colored strip.
  final bool fillTopSafeArea;

  /// Whether this strip is merged into the window title bar: it reserves the
  /// macOS traffic-light inset, drags the window from its empty space, and
  /// carries the window buttons where the OS does not draw them.
  final bool isTitleBar;

  void _acceptTab(WidgetRef ref, _TabDragData data, {int? toIndex}) {
    ref
        .read(terminalTabsProvider.notifier)
        .moveTab(data.tabId, paneId, toIndex: toIndex);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final topInset = MediaQuery.paddingOf(context).top;

    // The strip is the paper the tabs are cut from: the focused pane gets the
    // lighter tone so the selected chip (painted `surface`) lifts off it, and
    // an unfocused pane steps one tone deeper and recedes.
    return Material(
      color: focused ? scheme.surfaceContainerLow : scheme.surfaceContainer,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // A narrow pane keeps one title — the tab the user is on — and lets
          // the others shrink to their icon, so the strip stays scannable
          // instead of hiding tabs behind a scroll.
          final compact = constraints.maxWidth < _paneTabTitleBreakpoint;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (fillTopSafeArea && topInset > 0) SizedBox(height: topInset),
              SizedBox(
                height: _paneTabBarHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The macOS traffic lights sit inside the content view, so
                    // the title bar reserves their room on its leading edge.
                    if (isTitleBar && usesNativeWindowButtons)
                      const SizedBox(width: kMaidKitTrafficLightInset),
                    Expanded(
                      child: _PaneTabStrip(
                        paneId: paneId,
                        paneTabs: paneTabs,
                        selectedTabId: selectedTabId,
                        compact: compact,
                        dragsWindow: isTitleBar,
                        onSelect: (tab) {
                          final notifier = ref.read(
                            terminalTabsProvider.notifier,
                          );
                          notifier.focusPane(paneId);
                          notifier.select(tab.id);
                        },
                        onClose: (tab) => ref
                            .read(terminalTabsProvider.notifier)
                            .close(tab.id),
                        onAccept: (data, insertIndex) =>
                            _acceptTab(ref, data, toIndex: insertIndex),
                      ),
                    ),
                    // Pane splitting lives in the command palette (Shift+Tab,
                    // or the actions button beside this one), which leaves the
                    // strip one scanning row of tabs plus the workspace's own
                    // notifications and account.
                    const NotificationsBellButton(),
                    const CloudAccountButton(),
                    IconButton(
                      tooltip: 'sessionsSessionActions'.tr(),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: _paneTabBarHeight,
                        minHeight: _paneTabBarHeight,
                      ),
                      onPressed: () {
                        ref
                            .read(terminalTabsProvider.notifier)
                            .focusPane(paneId);
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
                    if (!isTitleBar) const SizedBox(width: 4),
                    if (isTitleBar && !usesNativeWindowButtons)
                      // Keep the workspace's own close control apart from the
                      // window close button: side by side they read as one.
                      Container(
                        width: 1,
                        height: 16,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        color: scheme.outlineVariant,
                      ),
                    if (isTitleBar) const MaidKitWindowButtons(),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The tabs of one strip, with the strip's empty space beneath them.
///
/// The empty space is the window's drag surface when the strip is the title
/// bar, and the drop target for tabs dragged out of other panes. It sits
/// *under* the tabs so a drag that starts on a tab still drags that tab; the
/// tab row is shrink-wrapped, so space to its right is not part of it.
class _PaneTabStrip extends StatelessWidget {
  const _PaneTabStrip({
    required this.paneId,
    required this.paneTabs,
    required this.selectedTabId,
    required this.compact,
    required this.dragsWindow,
    required this.onSelect,
    required this.onClose,
    required this.onAccept,
  });

  final String paneId;
  final List<SessionTab> paneTabs;
  final String? selectedTabId;
  final bool compact;
  final bool dragsWindow;
  final void Function(SessionTab tab) onSelect;
  final void Function(SessionTab tab) onClose;
  final void Function(_TabDragData data, int insertIndex) onAccept;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The tabs shrink-wrap, so whatever space is left of the strip belongs to
    // the window: dragging there moves it, and dropping a tab there appends.
    return Row(
      children: [
        Flexible(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            child: Row(
              children: [
                if (paneTabs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      'sessionsNewPane'.tr(),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else ...[
                  for (var index = 0; index < paneTabs.length; index++)
                    _DraggablePaneTab(
                      key: ValueKey(paneTabs[index].id),
                      tab: paneTabs[index],
                      paneId: paneId,
                      selected: paneTabs[index].id == selectedTabId,
                      showTitle:
                          !compact || paneTabs[index].id == selectedTabId,
                      index: index,
                      onSelect: () => onSelect(paneTabs[index]),
                      onClose: () => onClose(paneTabs[index]),
                      onAccept: onAccept,
                    ),
                  // Trailing slot so tabs can be dropped after the last item.
                  _TabDropTail(
                    hovering: false,
                    onAccept: (data) => onAccept(data, paneTabs.length),
                  ),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: DragTarget<_TabDragData>(
            onWillAcceptWithDetails: (details) => details.data.tabId.isNotEmpty,
            onAcceptWithDetails: (details) =>
                onAccept(details.data, paneTabs.length),
            builder: (context, candidate, rejected) {
              final surface = DecoratedBox(
                decoration: BoxDecoration(
                  color: candidate.isEmpty
                      ? null
                      : scheme.primary.withValues(alpha: 0.08),
                ),
                child: const SizedBox.expand(),
              );
              // Only the title bar strip moves the window; a split's lower
              // strips just host the drop target.
              return dragsWindow
                  ? MaidKitWindowDragArea(child: surface)
                  : surface;
            },
          ),
        ),
      ],
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
              ? Center(
                  child: Container(
                    width: 2,
                    height: 20,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(MaidKitRadius.xs),
                    ),
                  ),
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
    required this.showTitle,
    required this.index,
    required this.onSelect,
    required this.onClose,
    required this.onAccept,
  });

  final SessionTab tab;
  final String paneId;
  final bool selected;

  /// Whether this chip draws its title. Narrow panes only expand the focused
  /// tab, so the rest stay icon-sized.
  final bool showTitle;

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
      showTitle: showTitle,
      onSelect: onSelect,
      onClose: onClose,
    );
    final dragData = _TabDragData(tabId: tab.id, fromPaneId: paneId);
    // The chip under the pointer keeps the tab's own shape, so the drag reads
    // as moving this tab rather than a floating tooltip.
    final feedback = Material(
      elevation: 4,
      color: scheme.surface,
      borderRadius: BorderRadius.circular(MaidKitRadius.sm),
      child: SizedBox(
        height: 32,
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
    );
    final isMobile = switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
    final draggable = isMobile
        ? LongPressDraggable<_TabDragData>(
            data: dragData,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: feedback,
            childWhenDragging: Opacity(opacity: 0.35, child: chip),
            child: chip,
          )
        : Draggable<_TabDragData>(
            data: dragData,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: feedback,
            childWhenDragging: Opacity(opacity: 0.35, child: chip),
            child: chip,
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
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(MaidKitRadius.xs),
                  ),
                ),
              draggable,
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
    required this.showTitle,
    required this.onSelect,
    required this.onClose,
  });

  final SessionTab tab;
  final bool selected;
  final bool showTitle;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      height: _paneTabBarHeight,
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons & kMiddleMouseButton != 0) {
            onClose();
          }
        },
        // The selected tab is a tonal capsule sitting on the strip rather than
        // a tab glued to a bottom rule: it keeps the strip's single row height
        // while still reading as the active surface. The fill steps to the
        // raised container tone — darker than the strip in light mode and
        // lighter in dark mode — so selection stays legible either way.
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          // `Ink` paints the selected tab's tonal surface onto the strip's own
          // Material, so the strip stays the only Material in the row and the
          // chip's splash still lands above its fill.
          child: Ink(
            decoration: BoxDecoration(
              color: selected
                  ? scheme.surfaceContainerHigh
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(MaidKitRadius.sm),
            ),
            child: InkWell(
              onTap: onSelect,
              borderRadius: BorderRadius.circular(MaidKitRadius.sm),
              child: Padding(
                padding: const EdgeInsets.only(left: 10, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _TabActivityIcon(
                      tab: tab,
                      color: selected ? scheme.primary : null,
                    ),
                    // Growing the label's width out of the icon is what reads
                    // as the title expanding; the clip keeps the text hidden
                    // while the width is still on its way to zero.
                    ClipRect(
                      child: AnimatedAlign(
                        alignment: Alignment.centerLeft,
                        widthFactor: showTitle ? 1 : 0,
                        duration: _paneTabTitleDuration,
                        curve: Curves.easeOutCubic,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: _paneTabTitleMaxWidth,
                              ),
                              child: Text(
                                _tabLabel(tab),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: selected
                                      ? scheme.onSurface
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // The title gets its own air before the close affordance
                    // so the button never reads as punctuation on the tab's
                    // name. The button is a 24px cell rather than the padded
                    // 48px tap target the theme would give it, which is what
                    // used to swallow the gap and crowd the title.
                    const SizedBox(width: 12),
                    if (tab is! DashboardTab)
                      IconButton(
                        tooltip: 'sessionsCloseTab'.tr(),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(24, 24),
                          maximumSize: const Size(24, 24),
                          padding: EdgeInsets.zero,
                          // The theme's padded tap target inflates this button
                          // to 40px wide inside a 32px chip, which is what used
                          // to crowd the title; shrink-wrap lets the 24px cell
                          // stand.
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: onClose,
                        icon: const Icon(Symbols.close, size: 15),
                      ),
                  ],
                ),
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
    if (tab case AgentChatSessionTab(working: true)) {
      return SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
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
      return TabNavigator(
        key: key,
        tabId: tab.id,
        builder: (_) => const ServerDashboardTab(),
      );
    }
    if (tab is AssetsSessionTab) {
      final assetsTab = tab as AssetsSessionTab;
      final notifier = ref.read(terminalTabsProvider.notifier);
      return TabNavigator(
        key: key,
        tabId: tab.id,
        builder: (_) => AssetsPage(
          initialSection: assetsTab.section,
          onSectionChanged: (section) =>
              notifier.setAssetsSection(tab.id, section),
        ),
      );
    }
    if (tab is ProjectsSessionTab) {
      return TabNavigator(
        key: key,
        tabId: tab.id,
        builder: (_) => const ProjectsPage(),
      );
    }
    if (tab is MaidCafeCloudSessionTab) {
      return TabNavigator(
        key: key,
        tabId: tab.id,
        builder: (_) => const MaidCafeCloudPage(),
      );
    }
    if (tab is SettingsSessionTab) {
      return TabNavigator(
        key: key,
        tabId: tab.id,
        builder: (_) => const SettingsPage(),
      );
    }
    if (tab is AgentChatSessionTab) {
      final notifier = ref.read(terminalTabsProvider.notifier);
      return AgentChatView(
        key: key,
        tabId: tab.id,
        autofocus: autofocus,
        onTitleChanged: (title) => notifier.renameAgentChat(tab.id, title),
        onWorkingChanged: (working) =>
            notifier.setAgentChatWorking(tab.id, working),
      );
    }
    if (tab is ServerDetailTab) {
      final detailTab = tab as ServerDetailTab;
      return TabNavigator(
        key: key,
        tabId: tab.id,
        builder: (_) => ServerDetailPage(
          server: detailTab.server,
          initialTab: detailTab.initialTab,
          initialComposeProject: detailTab.initialComposeProject,
          embedded: true,
        ),
      );
    }
    if (tab is FileManagementTab) {
      return FileManagementTabView(key: key, tab: tab as FileManagementTab);
    }
    if (tab is FileEditorTab) {
      return FileEditorTabView(key: key, tab: tab as FileEditorTab);
    }
    if (tab is MaidCafePayloadSessionTab) {
      final payloadTab = tab as MaidCafePayloadSessionTab;
      final session = ref
          .watch(sessionsProvider)
          .asData
          ?.value
          .where((item) => item.serverId == payloadTab.server.id)
          .firstOrNull;
      return MaidCafeServerTab(
        key: key,
        server: payloadTab.server,
        connected: session?.status == SessionStatus.connected,
        connectionError: session?.error,
        onConnect: () => connectForStatistics(context, ref, payloadTab.server),
        mode: MaidCafeTabMode.payload,
      );
    }
    final terminalTab = tab as TerminalTab;
    return ColoredBox(
      color: ref.watch(transparentTerminalBackgroundProvider)
          ? Colors.transparent
          : const Color(0xFF111315),
      child: ClipRect(
        child: TerminalSudoAutofillHint(
          adapter: terminalTab.terminal,
          child: TerminalFindHost(
            key: key,
            adapter: terminalTab.terminal,
            autofocus: autofocus,
            transparentBackground: ref.watch(
              transparentTerminalBackgroundProvider,
            ),
            onOpenFileManagement: () =>
                unawaited(_openFilesForTerminal(context, ref, terminalTab)),
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
  // The in-terminal quick pick omits snippets the user excluded from
  // terminal autocomplete; the library and agent still see them.
  final snippets = await ref.read(snippetRepositoryProvider).autocomplete();
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
            trailing: snippet.dangerous
                ? Icon(
                    Symbols.warning,
                    size: 18,
                    color: Theme.of(context).colorScheme.error,
                  )
                : null,
          ),
        ),
    ],
  );
  if (selected == null || !context.mounted) return;
  if (!await confirmDangerousSnippet(context, selected)) return;
  if (!context.mounted) return;
  ref.read(terminalTabsProvider.notifier).executeSnippet(terminalId, selected);
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
  SessionTabType.maidCafePayload => Symbols.coffee,
  SessionTabType.terminal => Symbols.terminal,
  SessionTabType.fileManagement => Symbols.folder,
  SessionTabType.fileEditor => Symbols.edit_document,
  SessionTabType.assets => Symbols.inventory_2,
  SessionTabType.projects => Symbols.deployed_code,
  SessionTabType.maidCafeCloud => Symbols.cloud,
  SessionTabType.settings => Symbols.settings,
  SessionTabType.agentChat => Symbols.smart_toy,
};
String _tabLabel(SessionTab tab) {
  if (tab is DashboardTab) return 'tabDashboard'.tr();
  if (tab is FileEditorTab) {
    return tab.isRemote ? '${tab.fileName} · ${tab.serverName}' : tab.fileName;
  }
  if (tab is FileManagementTab) {
    return 'tabFiles'.tr(args: [tab.serverName]);
  }
  if (tab is MaidCafePayloadSessionTab) {
    return '${'maidCafePayloadTab'.tr()} · ${tab.serverName}';
  }
  if (tab is AgentChatSessionTab) {
    return tab.title.isEmpty ? 'agentNewConversation'.tr() : tab.title;
  }
  if (tab is AssetsSessionTab) return 'tabAssets'.tr();
  if (tab is ProjectsSessionTab) return 'tabProjects'.tr();
  if (tab is MaidCafeCloudSessionTab) return 'maidCafeCloudTitle'.tr();
  if (tab is SettingsSessionTab) return 'tabSettings'.tr();
  return tab.serverName;
}

