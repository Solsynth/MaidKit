import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kMiddleMouseButton, kPrimaryButton;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/agent/agent_page.dart';
import 'package:maid_kit/containers/projects_page.dart';
import 'package:maid_kit/shared/presentation/app_scaffold.dart';
import 'package:maid_kit/shared/presentation/panel.dart';
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
import 'pane_launcher.dart';
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
import 'workspace_shortcuts.dart';

/// Unified server workspace with dashboard, terminal, and file-management tabs.
///
/// One tab strip runs across the top of the workspace and lists every tab in
/// the session, whichever pane owns it. On desktop that strip sits below the
/// window's title bar band, which owns the window drag: keeping the two rows
/// separate means a tab drag can never also move the window. Panes below carry
/// their own body and, for a terminal, its own status bar — never a strip of
/// their own.
class SessionsWorkspace extends ConsumerWidget {
  const SessionsWorkspace({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = ref.watch(terminalTabsProvider);
    final sessions = ref.watch(sessionsProvider);
    final servers = ref.watch(serversProvider);

    return MaidKitAppScaffold(
      // The workspace paints edge to edge. The top inset is owned by the tab
      // bar (and by the intro when no tabs are open); the bottom inset is
      // owned by whatever ends up on the bottom edge — a pane's terminal
      // status bar pads itself, and a pane with nothing below it reaches the
      // screen bottom instead of leaving a dead band where the old navigation
      // bar used to be.
      useSafeArea: false,
      body: tabs.isEmpty
          ? const SafeArea(
              top: true,
              bottom: false,
              // With no tab open there is nothing to mount into, so the same
              // launcher opens a tab of its own.
              child: PaneLauncher(paneId: null),
            )
          : Column(
              children: [
                _WorkspaceTabBar(tabs: tabs),
                Expanded(
                  child: _SessionLayoutView(
                    tabs: tabs,
                    servers: servers,
                    sessions: sessions,
                  ),
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
  bool splitRight = false,
}) async {
  // Reached from a terminal, so this path stays SSH-only; a browser has no
  // socket to hold the SFTP session the file manager browses with.
  if (kIsWeb) return;
  if (server.connectionType != ServerConnectionType.ssh.name) return;
  final manager = ref.read(connectionManagerProvider);
  if (manager.clientFor(server.id) == null &&
      !await connectForStatistics(context, ref, server)) {
    return;
  }
  ref
      .read(terminalTabsProvider.notifier)
      .openFileManagement(
        server,
        initialPath: initialPath,
        paneId: paneId,
        splitRight: splitRight,
      );
}

/// Opens the terminal's directory in the file manager beside it: the context
/// menu's entry splits the workspace tab to the right instead of pushing yet
/// another tab, so the browser and its shell share the view.
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
  // A right-click does not focus a pane, so anchor the split to the pane that
  // actually holds this terminal before opening beside it.
  ref.read(terminalTabsProvider.notifier).select(tab.id);
  await _openFiles(
    context,
    ref,
    server,
    initialPath: tab.terminal.currentDirectory,
    splitRight: true,
  );
}

/// The pane arrangement of every workspace tab, with only the selected one
/// showing.
///
/// Each tab owns its layout, so switching tabs switches the whole pane area: a
/// split terminal keeps its two shells while another tab opens single-pane.
/// Every tab stays mounted — invisible ones transparent and untouchable — so a
/// terminal keeps its scrollback, an editor its scroll position and a file
/// browser its loaded directory across switches.
class _SessionLayoutView extends ConsumerWidget {
  const _SessionLayoutView({
    required this.tabs,
    required this.servers,
    required this.sessions,
  });

  final TerminalTabsState tabs;
  final AsyncValue<List<Server>> servers;
  final AsyncValue<List<SshSessionInfo>> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tabs.tabs.isEmpty) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final tab in tabs.tabs)
          _AnimatedPaneTabContent(
            key: ValueKey('tab-layout-${tab.id}'),
            active: tabs.selectedTabId == tab.id,
            // The pane area fills edge-to-edge flatly; a subtle top 1px border
            // separates the workspace tab bar from the content panes.
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.45),
                    width: 1,
                  ),
                ),
              ),
              child: _LayoutNode(
                tab: tab,
                node: tab.layout,
                active: tabs.selectedTabId == tab.id,
                servers: servers,
                sessions: sessions,
              ),
            ),
          ),
      ],
    );
  }
}

class _LayoutNode extends ConsumerWidget {
  const _LayoutNode({
    required this.tab,
    required this.node,
    required this.active,
    required this.servers,
    required this.sessions,
  });

  final WorkspaceTab tab;
  final SessionLayout node;

  /// Whether this tab is the workspace's selected one.
  ///
  /// A hidden tab leaves the focus tree, so its terminals can hand the
  /// keyboard back on the way out instead of holding it under a surface the
  /// user cannot see.
  final bool active;
  final AsyncValue<List<Server>> servers;
  final AsyncValue<List<SshSessionInfo>> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (node) {
      case SessionLayoutLeaf(:final paneId):
        return _SessionPaneView(
          // Keyed by pane, a swap moves the whole viewport between slots with
          // its launcher and status band intact instead of trading their
          // element state by position.
          key: ValueKey('pane-$paneId'),
          tab: tab,
          paneId: paneId,
          focused: tab.focusedPaneId == paneId,
          servers: servers,
          active: active,
          sessions: sessions,
          // A split's panes can be dragged into each other's slot and closed on
          // their own; the single pane *is* the tab.
          movable: tab.hasSplits,
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
          onRatioChanged: (value) => ref
              .read(terminalTabsProvider.notifier)
              .setSplitRatio(tab.id, id, value),
          first: _LayoutNode(
            tab: tab,
            node: first,
            active: active,
            servers: servers,
            sessions: sessions,
          ),
          second: _LayoutNode(
            tab: tab,
            node: second,
            active: active,
            servers: servers,
            sessions: sessions,
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
  /// Visual width of the splitter line between two panes.
  static const double _dividerWidth = 1.0;

  /// Hit target width centered over the divider line for easy pointer grabbing.
  static const double _hitTargetExtent = 10.0;

  double? _dragRatio;
  bool _hovering = false;

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
    final isHorizontal = widget.axis == SessionSplitAxis.horizontal;
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxExtent = isHorizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final available = maxExtent - _dividerWidth;
        final firstExtent = (available * _ratio).clamp(60.0, available - 60.0);
        final secondExtent = available - firstExtent;

        final children = <Widget>[
          SizedBox(
            width: isHorizontal ? firstExtent : null,
            height: isHorizontal ? null : firstExtent,
            child: widget.first,
          ),
          SizedBox(
            width: isHorizontal ? _dividerWidth : double.infinity,
            height: isHorizontal ? double.infinity : _dividerWidth,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: (_hovering || _dragRatio != null)
                        ? scheme.primary
                        : scheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                Positioned(
                  left: isHorizontal
                      ? -(_hitTargetExtent - _dividerWidth) / 2
                      : 0,
                  right: isHorizontal
                      ? -(_hitTargetExtent - _dividerWidth) / 2
                      : 0,
                  top: isHorizontal
                      ? 0
                      : -(_hitTargetExtent - _dividerWidth) / 2,
                  bottom: isHorizontal
                      ? 0
                      : -(_hitTargetExtent - _dividerWidth) / 2,
                  child: MouseRegion(
                    cursor: isHorizontal
                        ? SystemMouseCursors.resizeColumn
                        : SystemMouseCursors.resizeRow,
                    onEnter: (_) => setState(() => _hovering = true),
                    onExit: (_) => setState(() => _hovering = false),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: isHorizontal
                          ? (d) => _onDragUpdate(d, available)
                          : null,
                      onHorizontalDragEnd:
                          isHorizontal ? (_) => _onDragEnd() : null,
                      onVerticalDragUpdate: isHorizontal
                          ? null
                          : (d) => _onDragUpdate(d, available),
                      onVerticalDragEnd:
                          isHorizontal ? null : (_) => _onDragEnd(),
                    ),
                  ),
                ),
              ],
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

/// One pane of a workspace tab: exactly one content viewport in its own panel,
/// plus the status band that viewport needs.
///
/// A pane shows one thing — a terminal, an editor, a page — because a tab is
/// the document and its panes are viewports. The panel is the unit of
/// separation between panes: the gutter around it is what divides the
/// workspace, so no rule is drawn between panes.
class _SessionPaneView extends ConsumerWidget {
  const _SessionPaneView({
    super.key,
    required this.tab,
    required this.paneId,
    required this.focused,
    required this.active,
    required this.servers,
    required this.sessions,
    this.movable = false,
  });

  final WorkspaceTab tab;
  final String paneId;
  final bool focused;

  /// Whether this pane's tab is the workspace's selected one.
  ///
  /// A pane under a hidden tab is still built — its terminal keeps running —
  /// but it must not claim the keyboard on the user's behalf.
  final bool active;
  final AsyncValue<List<Server>> servers;
  final AsyncValue<List<SshSessionInfo>> sessions;

  /// Whether this pane can be dragged into a sibling's slot.
  ///
  /// Only a split has slots to trade: with one pane there is nowhere to put
  /// it, and the tab bar already moves whole tabs.
  final bool movable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pane = tab.panes[paneId];
    if (pane == null) return const SizedBox.shrink();

    final content = pane.tab;
    final terminal = switch (content) {
      final TerminalTab terminal => terminal,
      _ => null,
    };

    if (!movable) {
      return _paneView(context, ref, content, terminal, highlighted: false);
    }
    // The handle is the pane's grab strip and any sibling is the drop target:
    // releasing over one trades the two viewports' slots. Nothing is cloned,
    // so a move cannot duplicate a live terminal.
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != paneId,
      onAcceptWithDetails: (details) => ref
          .read(terminalTabsProvider.notifier)
          .swapPanes(tab.id, details.data, paneId),
      builder: (context, candidate, rejected) {
        final accepting = candidate.isNotEmpty;
        final view = _paneView(
          context,
          ref,
          content,
          terminal,
          highlighted: accepting,
        );
        // The terminal pane integrates its drag handle directly inside its
        // header bar rather than floating a pill over terminal text.
        if (terminal != null) return view;
        return Stack(
          children: [
            view,
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Center(
                child: _PaneDragHandle(
                  paneId: paneId,
                  active: focused,
                  accepting: accepting,
                  // The middle button is the desktop's "kill" gesture, the
                  // same one the tab bar answers to, so the grab strip also
                  // closes the pane it belongs to.
                  onClose: () => ref
                      .read(terminalTabsProvider.notifier)
                      .closePaneInTab(tab.id, paneId),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _paneView(
    BuildContext context,
    WidgetRef ref,
    SessionTab? content,
    TerminalTab? terminal, {
    required bool highlighted,
  }) {
    // A pane becomes the live one as soon as it is touched or its content takes
    // the keyboard. A plain tap handler is not enough: a terminal, a list and an
    // editor all claim their own press, so the tap would be lost and the pane
    // would keep reading as idle while its terminal already had the keyboard.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (!hasFocus) return;
        ref.read(terminalTabsProvider.notifier).focusPane(paneId);
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          if (event.buttons & kPrimaryButton == 0) return;
          ref.read(terminalTabsProvider.notifier).focusPane(paneId);
        },
        child: MaidKitPanel(
          margin: EdgeInsets.zero,
          flat: true,
          // The focused pane reads as the live one; the others dim, the same
          // way an unfocused window does.
          emphasized: focused,
          highlighted: highlighted,
          child: Column(
            children: [
              if (terminal != null)
                _TerminalPaneHeader(
                  tab: tab,
                  paneId: paneId,
                  terminal: terminal,
                  focused: focused,
                  movable: movable,
                  accepting: highlighted,
                ),
              Expanded(
                // The workspace bar owns the top safe area; strip it here so
                // tab bodies don't re-apply the status-bar inset and leave a
                // gap below the bar. The bottom inset belongs to the status
                // band below, so the body does not double it.
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  removeBottom: true,
                  child: content == null
                      ? PaneLauncher(
                          paneId: paneId,
                          compact: true,
                          // A hidden tab's node is excluded, so this claim is
                          // dropped there and no switch can summon the keyboard.
                          focused: focused,
                        )
                      : _TerminalFocusRestore(
                          adapter: terminal?.terminal,
                          active: active && focused,
                          child: _SessionTabBody(
                            tab: content,
                            // A hidden tab's node is excluded, so this claim is
                            // dropped there; coming back restores focus through
                            // _TerminalFocusRestore, which runs on every switch.
                            autofocus: focused,
                          ),
                        ),
                ),
              ),
              // The status band belongs to the pane, not the window: in a
              // split every terminal pane reads out its own terminal instead
              // of only the focused one. Keyed on the terminal id, a pane
              // that shows something else collapses it in place.
              AnimatedTerminalStatusBar(
                key: ValueKey(terminal?.id),
                session: _sessionForTab(sessions, content),
                terminal: terminal?.terminal,
                terminalId: terminal?.id,
                transport: terminal?.transport,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TerminalPaneHeader extends ConsumerWidget {
  const _TerminalPaneHeader({
    required this.tab,
    required this.paneId,
    required this.terminal,
    required this.focused,
    required this.movable,
    required this.accepting,
  });

  final WorkspaceTab tab;
  final String paneId;
  final TerminalTab terminal;
  final bool focused;
  final bool movable;
  final bool accepting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: MaidKitSpace.sm),
      child: Row(
        children: [
          Icon(
            Symbols.terminal,
            size: 16,
            color: focused ? scheme.primary : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              terminal.serverName.isNotEmpty
                  ? terminal.serverName
                  : 'terminalPaneTitle'.tr(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: focused ? FontWeight.w600 : FontWeight.w500,
                color: focused ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (movable)
            Expanded(
              child: Center(
                child: _PaneDragHandle(
                  paneId: paneId,
                  active: focused,
                  accepting: accepting,
                  onClose: () => ref
                      .read(terminalTabsProvider.notifier)
                      .closePaneInTab(tab.id, paneId),
                ),
              ),
            )
          else
            const Spacer(),
          IconButton(
            tooltip: 'terminalRunSnippetTooltip'.tr(),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: const Icon(Symbols.code, size: 16),
            onPressed: () => unawaited(
              _showTerminalSnippetPopover(
                context,
                ref,
                terminalId: terminal.id,
                anchorRect: terminal.terminal.cursorGlobalRect,
              ),
            ),
          ),
          IconButton(
            tooltip: 'terminalSplitRightTooltip'.tr(),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: const Icon(Symbols.splitscreen, size: 16),
            onPressed: () => ref
                .read(terminalTabsProvider.notifier)
                .splitSelectedTab(SessionSplitAxis.horizontal),
          ),
          if (movable)
            IconButton(
              tooltip: 'terminalClosePaneTooltip'.tr(),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: const Icon(Symbols.close, size: 16),
              onPressed: () => ref
                  .read(terminalTabsProvider.notifier)
                  .closePaneInTab(tab.id, paneId),
            ),
        ],
      ),
    );
  }
}

/// The pane's grab strip: a short bar at the top centre of its sheet.
///
/// It replaces the corner close button, so the only thing drawn over a pane's
/// content is the affordance that moves it. Dragging the bar carries the pane;
/// dropping it on a sibling swaps their slots — an explicit gesture, unlike a
/// tab bar where a drag may also be a reorder. A middle click on the bar
/// closes the pane — the same gesture the tab bar's close affordance answers
/// to — and closing is always still listed in the workspace's command palette,
/// next to closing the tab it belongs to.
class _PaneDragHandle extends StatelessWidget {
  const _PaneDragHandle({
    required this.paneId,
    required this.active,
    required this.accepting,
    required this.onClose,
  });

  final String paneId;

  /// Whether this handle belongs to the focused pane, so the live sheet names
  /// itself with the accent the panel's hairline uses.
  final bool active;

  /// Whether a dragged pane is hovering this slot.
  final bool accepting;

  /// Closes the pane this handle belongs to.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The bar has to read on paper and on a terminal's own dark backdrop alike,
    // so it uses the neutral outline ramp rather than an on-surface tone.
    final color = accepting
        ? scheme.primary
        : scheme.outline.withValues(alpha: active ? 0.6 : 0.35);
    final feedback = Material(
      color: Colors.transparent,
      child: _HandleBar(color: scheme.primary, width: 40),
    );
    final bar = Listener(
      // The middle button is the desktop's "kill" gesture, the same one the
      // workspace tab bar answers to. It is a pointer event, not a drag: the
      // Draggable above only claims the primary button, so the two never
      // compete.
      onPointerDown: (event) {
        if (event.buttons & kMiddleMouseButton != 0) onClose();
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: _HandleBar(
          color: accepting ? scheme.primary : color,
          width: accepting ? 40 : 28,
        ),
      ),
    );
    return Draggable<String>(
      data: paneId,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: feedback,
      // The handle stays in its slot while the pane is carried, dimmed, so the
      // pane it belongs to is still named during the drag.
      childWhenDragging: Opacity(opacity: 0.4, child: bar),
      child: Tooltip(
        message: 'sessionsMovePane'.tr(),
        waitDuration: const Duration(milliseconds: 600),
        child: bar,
      ),
    );
  }
}

/// The grab bar itself: a hit target tall enough to aim at, with a short
/// rounded line drawn inside it.
class _HandleBar extends StatelessWidget {
  const _HandleBar({required this.color, required this.width});

  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: MaidKitSpace.lg,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          width: width,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(MaidKitRadius.pill),
          ),
        ),
      ),
    );
  }
}

/// Shared height of the workspace tab bar and its tab chips.
///
/// The bar is a row of its own, below the window's title bar band: the band
/// moves the window, this row moves tabs, and neither gesture can be mistaken
/// for the other.
const _tabBarHeight = kMaidKitTabStripHeight;

/// Bar width below which the strip keeps the title of the selected tab only.
///
/// On a narrow window every title would crowd out the tabs themselves, but
/// icons alone make it hard to tell what is open, so the selected tab keeps
/// its title.
const _tabTitleBreakpoint = 768.0;

/// Widest a tab title may draw before it is ellipsized.
const _tabTitleMaxWidth = 240.0;

/// How long a tab title takes to expand out of its icon, and collapse back.
const _tabTitleDuration = Duration(milliseconds: 160);

class _TabDragData {
  const _TabDragData({required this.tabId});

  /// The workspace tab being dragged.
  final String tabId;
}

/// The workspace's single tab strip.
///
/// It lists every tab in the session in one row, whichever pane owns it, so
/// the workspace reads as one set of documents rather than one strip per pane.
/// The row sits below the window's title bar band; it never draws the window's
/// own controls — those belong to the band.
class _WorkspaceTabBar extends ConsumerWidget {
  const _WorkspaceTabBar({required this.tabs});

  final TerminalTabsState tabs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final topInset = MediaQuery.paddingOf(context).top;

    // The bar is the paper the tabs are cut from; the selected chip paints a
    // raised tone on it so the active document steps out of the row.
    return Material(
      color: scheme.surfaceContainerLowest,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // A narrow window keeps one title — the tab the user is on — and
          // lets the others shrink to their icon, so the strip stays scannable
          // instead of hiding tabs behind a scroll.
          final compact = constraints.maxWidth < _tabTitleBreakpoint;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (topInset > 0) SizedBox(height: topInset),
              SizedBox(
                height: _tabBarHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _WorkspaceTabStrip(tabs: tabs, compact: compact),
                    ),
                    // Pane splitting lives in the command palette (Shift+Tab,
                    // or this button), which leaves the strip one scanning row
                    // of tabs plus the workspace's own notifications and
                    // account controls.
                    const NotificationsBellButton(),
                    const CloudAccountButton(),
                    IconButton(
                      tooltip: 'sessionsSessionActions'.tr(),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: _tabBarHeight,
                        minHeight: _tabBarHeight,
                      ),
                      onPressed: () => showTerminalCommandPalette(context, ref),
                      icon: const Icon(Symbols.add, size: 20),
                    ),
                    const SizedBox(width: 4),
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

/// The workspace's tabs, with the strip's empty space beside them.
///
/// The empty space is the drop target for a tab dragged to the end of the
/// row. It sits *under* the tabs so a drag that starts on a tab still drags
/// that tab; the tab row is shrink-wrapped, so space to its right is not part
/// of it.
class _WorkspaceTabStrip extends ConsumerWidget {
  const _WorkspaceTabStrip({required this.tabs, required this.compact});

  final TerminalTabsState tabs;
  final bool compact;

  void _move(WidgetRef ref, String tabId, int toIndex) {
    final fromIndex = tabs.tabs.indexWhere((tab) => tab.id == tabId);
    if (fromIndex < 0) return;
    ref.read(terminalTabsProvider.notifier).moveTab(fromIndex, toIndex);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final entries = <Widget>[];
    for (var index = 0; index < tabs.tabs.length; index++) {
      final tab = tabs.tabs[index];
      final selected = tabs.selectedTabId == tab.id;
      entries.add(
        _TabEntry(
          key: ValueKey('tab-${tab.id}'),
          tab: tab,
          selected: selected,
          // A narrow bar keeps the selected entry's title and lets the rest
          // fall back to their icon plus pane count.
          showTitle: !compact || selected,
          onSelect: () =>
              ref.read(terminalTabsProvider.notifier).selectTab(tab.id),
          onClose: () =>
              ref.read(terminalTabsProvider.notifier).closeTab(tab.id),
          onAcceptBefore: (data) => _move(ref, data.tabId, index),
        ),
      );
    }

    // The tabs take the width they need and no more. The row is measured from
    // its intrinsic width and clamped to the strip, so it fills the bar while
    // there is room and scrolls inside its own width when there is not; the
    // slot is a flex, and a `flex: 1` pair would hand the tabs half the strip
    // for ever instead. Whatever the tabs leave over is the drop target for
    // appending one.
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth),
            child: IntrinsicWidth(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...entries,
                    // Trailing slot so tabs can be dropped after the last item.
                    _TabDropTail(
                      hovering: false,
                      onAccept: (data) =>
                          _move(ref, data.tabId, tabs.tabs.length),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: DragTarget<_TabDragData>(
              onWillAcceptWithDetails: (details) =>
                  details.data.tabId.isNotEmpty,
              onAcceptWithDetails: (details) =>
                  _move(ref, details.data.tabId, tabs.tabs.length),
              builder: (context, candidate, rejected) => DecoratedBox(
                decoration: BoxDecoration(
                  color: candidate.isEmpty
                      ? null
                      : scheme.primary.withValues(alpha: 0.08),
                ),
                child: const SizedBox.expand(),
              ),
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
          height: _tabBarHeight,
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

/// One bar entry: a workspace tab, plus how many panes it is split into.
///
/// The entry is the tab, not one of its viewports: a split terminal shows as a
/// single entry with a pane count, and its close button closes every pane the
/// tab owns.
class _TabEntry extends StatelessWidget {
  const _TabEntry({
    super.key,
    required this.tab,
    required this.selected,
    required this.showTitle,
    required this.onSelect,
    required this.onClose,
    required this.onAcceptBefore,
  });

  final WorkspaceTab tab;
  final bool selected;

  /// Whether this entry draws its title. A narrow bar only expands the title of
  /// the selected entry, so the rest stay icon-sized with their count.
  final bool showTitle;

  final VoidCallback onSelect;
  final VoidCallback onClose;
  final void Function(_TabDragData data) onAcceptBefore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final content = tab.tab;
    final paneCount = tab.panes.length;
    final chip = _TabChip(
      tab: tab,
      paneCount: paneCount,
      selected: selected,
      showTitle: showTitle,
      onSelect: onSelect,
      onClose: onClose,
    );
    final dragData = _TabDragData(tabId: tab.id);
    final isMobile = switch (theme.platform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
    // The chip under the pointer keeps the entry's own shape, so the drag reads
    // as moving this tab rather than as a floating tooltip.
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
              if (tab.panes.length > 1)
                const Icon(Symbols.splitscreen, size: 16)
              else if (content != null)
                _TabActivityIcon(tab: content)
              else
                Icon(_emptyPaneIcon(tab), size: 16),
              const SizedBox(width: 6),
              Text(
                _workspaceTabLabel(tab),
                style: theme.textTheme.labelMedium,
              ),
              if (paneCount > 1) ...[
                const SizedBox(width: 6),
                _PaneCountBadge(count: paneCount),
              ],
            ],
          ),
        ),
      ),
    );
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
      onAcceptWithDetails: (details) => onAcceptBefore(details.data),
      builder: (context, candidate, rejected) {
        return SizedBox(
          height: _tabBarHeight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (candidate.isNotEmpty)
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

/// How many panes a bar entry occupies, when that is more than one.
class _PaneCountBadge extends StatelessWidget {
  const _PaneCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Tooltip(
      message: 'sessionsPaneCountTooltip'.tr(args: ['$count']),
      child: Container(
        constraints: const BoxConstraints(minWidth: 16),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(MaidKitRadius.xs),
        ),
        child: Text(
          '$count',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSecondaryContainer,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.tab,
    required this.paneCount,
    required this.selected,
    required this.showTitle,
    required this.onSelect,
    required this.onClose,
  });

  /// The workspace tab this entry stands for.
  final WorkspaceTab tab;
  final int paneCount;
  final bool selected;
  final bool showTitle;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final content = tab.tab;
    // The workspace floor is the home dashboard tab; a dashboard mounted in a
    // split pane is ordinary content and closes with its pane.
    final closeable = tab.id != 'dashboard';
    return SizedBox(
      height: _tabBarHeight,
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons & kMiddleMouseButton != 0 && closeable) {
            onClose();
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          // The selected entry is a raised capsule on the bar's paper, so the
          // active document steps out of the row by tone alone — no rule, no
          // outline around it.
          child: Ink(
            decoration: BoxDecoration(
              color: selected ? scheme.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(MaidKitRadius.sm),
            ),
            child: InkWell(
              onTap: onSelect,
              borderRadius: BorderRadius.circular(MaidKitRadius.sm),
              child: Padding(
                // A closeable chip's right inset is the gap before its close
                // button; without one, the title needs the same air on both
                // sides instead of ending flush against the capsule edge.
                padding: EdgeInsets.only(left: 10, right: closeable ? 4 : 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (tab.panes.length > 1)
                      Icon(
                        Symbols.splitscreen,
                        size: 16,
                        color: selected ? scheme.primary : null,
                      )
                    else if (content == null)
                      Icon(
                        _emptyPaneIcon(tab),
                        size: 16,
                        color: selected ? scheme.primary : null,
                      )
                    else
                      _TabActivityIcon(
                        tab: content,
                        color: selected ? scheme.primary : null,
                      ),
                    // Growing the label's width out of the icon is what reads
                    // as the title expanding; the clip keeps the text hidden
                    // while the width is still on its way to zero.
                    ClipRect(
                      child: AnimatedAlign(
                        alignment: Alignment.centerLeft,
                        widthFactor: showTitle ? 1 : 0,
                        duration: _tabTitleDuration,
                        curve: Curves.easeOutCubic,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: _tabTitleMaxWidth,
                              ),
                              child: Text(
                                _workspaceTabLabel(tab),
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
                    // The count stays visible when the title collapses, so a
                    // split tab is still identifiable on a narrow bar.
                    if (paneCount > 1) ...[
                      const SizedBox(width: 6),
                      _PaneCountBadge(count: paneCount),
                    ],
                    if (closeable) ...[
                      // The title gets its own air before the close affordance
                      // so the button never reads as punctuation on the name.
                      const SizedBox(width: 12),
                      IconButton(
                        tooltip: 'sessionsCloseTab'.tr(),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(24, 24),
                          maximumSize: const Size(24, 24),
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: onClose,
                        icon: const Icon(Symbols.close, size: 15),
                      ),
                    ],
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
                // At 16 px a track ring is heavier than the arc it backs; the
                // chip only has to say "running".
                backgroundColor: Colors.transparent,
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

/// Animates the pane's visible tab in and the previous one out.
class _AnimatedPaneTabContent extends StatelessWidget {
  const _AnimatedPaneTabContent({
    required this.active,
    required this.child,
    super.key,
  });

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) => ExcludeFocus(
    // A hidden tab stays mounted so its terminal keeps its scrollback, but it
    // must not keep the focus tree: a terminal still holding focus under an
    // invisible tab keeps the soft keyboard raised and eats the typing meant
    // for the tab on screen. Excluding releases the focus it held; a desktop
    // terminal takes it back when the tab returns, mobile waits for a tap
    // because focus is what raises its keyboard.
    excluding: !active,
    child: IgnorePointer(
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
    ),
  );
}

class _SessionTabBody extends ConsumerWidget {
  const _SessionTabBody({required this.tab, required this.autofocus});

  final SessionTab tab;
  final bool autofocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The pane paints the card (see `_SessionPaneView`); the tab body is just
    // its content, so a terminal and a dashboard share one surface and the
    // status band sits inside the same card.
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
    // Watched, not read: the app's brightness can change under a live
    // session, and the terminal only repaints when it is rebuilt with the
    // palette that matches the new theme.
    final colorScheme = ref.watch(terminalColorSchemeProvider);
    final transparent = ref.watch(transparentTerminalBackgroundProvider);
    return ColoredBox(
      color: transparent ? Colors.transparent : colorScheme.background,
      child: ClipRect(
        child: TerminalSudoAutofillHint(
          adapter: terminalTab.terminal,
          child: TerminalFindHost(
            key: key,
            adapter: terminalTab.terminal,
            autofocus: autofocus,
            transparentBackground: transparent,
            colorScheme: colorScheme,
            onOpenFileManagement: () =>
                unawaited(_openFilesForTerminal(context, ref, terminalTab)),
            onKeyEvent: (_, event) {
              // Where Ctrl is the command modifier the renderer would encode
              // Ctrl+T as `^T` and keep it, so the new-tab chord has to be
              // answered before the remote shell sees it. Cmd+T on Apple
              // platforms falls through to the window shell instead.
              if (isNewTabShortcut(event)) {
                ref.read(terminalTabsProvider.notifier).openEmptyTab();
                return KeyEventResult.handled;
              }
              // The terminal would otherwise encode the chord for the remote
              // shell (Ctrl+D is its end-of-input) and keep the event.
              if (splitShortcutAxis(event) case final axis?) {
                ref.read(terminalTabsProvider.notifier).splitSelectedTab(axis);
                return KeyEventResult.handled;
              }
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

/// The workspace tab's title in the bar, naming its server session or split tools.
String _workspaceTabLabel(WorkspaceTab tab) {
  if (tab.panes.isEmpty) return 'sessionsNewTab'.tr();
  if (tab.panes.length == 1) {
    final content = tab.panes.values.first.tab;
    return content == null ? _emptyPaneLabel(tab) : _tabLabel(content);
  }

  // Split tab: check servers and tool combination
  final serverNames = tab.panes.values
      .map((p) => p.tab?.serverName)
      .where((s) => s != null && s.isNotEmpty)
      .toSet();

  final hasTerminal = tab.panes.values.any((p) => p.tab is TerminalTab);
  final hasFiles = tab.panes.values.any((p) => p.tab is FileManagementTab);
  final hasEditor = tab.panes.values.any((p) => p.tab is FileEditorTab);

  if (serverNames.length == 1) {
    final server = serverNames.first!;
    if (hasTerminal && hasFiles) {
      return 'tabSplitTerminalSftp'.tr(args: [server]);
    }
    if (hasTerminal && hasEditor) {
      return '$server (Terminal + Editor)';
    }
    return 'tabSplitWithCount'.tr(args: [server, '${tab.panes.length}']);
  }

  if (hasTerminal && hasFiles) {
    return 'Terminal + SFTP';
  }

  final active = tab.tab;
  if (active != null) {
    return _tabLabel(active);
  }
  return 'sessionsNewPane'.tr();
}

/// The bar label for a pane that has no content yet.
///
/// A tab opened by Cmd/Ctrl+T holds one empty pane and reads as a new tab; a
/// pane a split added to an existing tab reads as that new pane. The bar names
/// the tab, so the distinction is what the user just did.
String _emptyPaneLabel(WorkspaceTab tab) =>
    tab.panes.length == 1 ? 'sessionsNewTab'.tr() : 'sessionsNewPane'.tr();

/// The icon a contentless pane shows in the bar, matching its label.
IconData _emptyPaneIcon(WorkspaceTab tab) =>
    tab.panes.length == 1 ? Symbols.tab : Symbols.splitscreen;

/// Hands the keyboard back to a terminal when its tab becomes the visible one.
///
/// A hidden tab leaves the focus tree (see [_AnimatedPaneTabContent]), so the
/// terminal that owned the keyboard before the switch comes back unfocused. On
/// desktop the keystrokes would then go to the window shell, so the terminal
/// takes focus again. On mobile it deliberately does not: focus is what raises
/// the soft keyboard, and switching tabs is not a request to type — tapping the
/// content is.
class _TerminalFocusRestore extends StatefulWidget {
  const _TerminalFocusRestore({
    required this.adapter,
    required this.active,
    required this.child,
  });

  final TerminalSessionAdapter? adapter;

  /// Whether this terminal is the one the user is looking at.
  final bool active;
  final Widget child;

  @override
  State<_TerminalFocusRestore> createState() => _TerminalFocusRestoreState();
}

class _TerminalFocusRestoreState extends State<_TerminalFocusRestore> {
  static bool get _keyboardIsThePoint =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  @override
  void didUpdateWidget(_TerminalFocusRestore oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active || oldWidget.active) return;
    final adapter = widget.adapter;
    if (adapter == null || _keyboardIsThePoint) return;
    // After the frame: the exclusion lifts during this build, and a focus
    // request made against a still-excluded node would be dropped.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active) adapter.showKeyboard();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
