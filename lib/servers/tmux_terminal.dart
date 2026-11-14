import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'terminal_session_adapter.dart';
import 'terminal_tabs_provider.dart';
import 'tmux_control_client.dart';
import 'tmux_layout.dart';

/// One live `tmux -CC` client riding an SSH shell channel.
///
/// The process tree it mirrors lives on the host, not in this object: closing
/// the SSH session detaches the client, and the session keeps running until it
/// is killed.
class TmuxSshSession {
  TmuxSshSession({
    required this.id,
    required this.control,
    required Future<void> Function() closeTransport,
    required this.done,
  }) : _closeTransportHandle = closeTransport;

  final String id;
  final TmuxControlClient control;

  /// Completes when the server or the client uses the session up.
  final Future<void> done;

  final Future<void> Function() _closeTransportHandle;

  /// Detaches this client and drops the SSH channel. The tmux session keeps
  /// running on the host.
  Future<void> close() async {
    await control.dispose();
    await _closeTransportHandle();
  }
}

/// Remembers where `tmux` lives per server, so a terminal open does not probe
/// the same host twice in a row.
///
/// A stored `null` means "probed and not installed", which is a real answer:
/// the caller falls back to a plain shell without asking again.
class TmuxPathCache {
  final _paths = <int, String?>{};

  String? cached(int serverId) => _paths[serverId];

  /// Whether this server has been probed already, installed or not.
  bool contains(int serverId) => _paths.containsKey(serverId);

  void store(int serverId, String? path) => _paths[serverId] = path;

  void invalidate(int serverId) => _paths.remove(serverId);
}

/// Resolves the `tmux` binary on [client]'s host, or null when it is absent.
Future<String?> probeTmuxPath(SSHClient client) async {
  try {
    final session = await client.execute('command -v tmux');
    final stdout = await utf8.decoder.bind(session.stdout).join();
    await session.done;
    final path = stdout.trim();
    return path.isEmpty ? null : path;
  } catch (_) {
    return null;
  }
}

/// One tmux session projected into one workspace tab.
///
/// The binding owns the control client, the adapter for every mirrored tmux
/// pane, and the mapping between tmux pane ids and MaidKit content ids. tmux is
/// the authority: the tab's layout tree is a projection of the session's own,
/// and every structural gesture becomes a tmux command whose `%layout-change`
/// answer is what actually re-tiles the screen.
class TmuxTabBinding {
  TmuxTabBinding({
    required this.sessionName,
    required this.control,
    required Future<void> Function() closeTransport,
    required TerminalSessionAdapterFactory adapterFactory,
    required this.serverId,
    required this.serverName,
    required this.transport,
    required Stream<TmuxEvent> onEventStream,
    this.autoFillSecret,
  }) : _closeTransportHandle = closeTransport,
       _adapterFactoryRef = adapterFactory,
       _eventStream = onEventStream;

  /// The SSH password each mirrored pane may autofill at a `sudo` prompt.
  ///
  /// A tmux pane is a real shell, so it needs the same interception the plain
  /// SSH terminal gets: Enter at a genuine password prompt becomes the stored
  /// secret. Panes built later from a layout change use this too.
  final String? autoFillSecret;

  /// The tmux session this tab mirrors.
  final String sessionName;

  /// The client currently riding this session.
  ///
  /// Replaced when a dropped channel is reattached: the panes and their
  /// scrollback stay, and only the connection to tmux changes.
  TmuxControlClient control;
  final int serverId;
  final String serverName;

  /// The transport the control client rides, for the pane's status band.
  final TerminalTransport transport;

  /// Where the transport's event stream comes from; the notifier subscribes it
  /// to [applyEvent] once the tab exists.
  Stream<TmuxEvent> get onEventStream => _eventStream;
  Stream<TmuxEvent> _eventStream;

  Future<void> Function() _closeTransportHandle;
  final TerminalSessionAdapterFactory _adapterFactoryRef;

  /// Whether the connection this session rides has been dropped already.
  ///
  /// A session ends through one of several paths - detaching, killing, or tmux
  /// exiting on its own - and every one of them closes the same transport. The
  /// first close wins so the second cannot tear down a connection that is
  /// already gone.
  var _transportClosed = false;

  /// The workspace tab this session is mounted as, once it is known.
  String? tabId;

  /// The active tmux window whose panes this tab shows.
  String? windowId;

  /// The session's windows as tmux last reported them, for the palette's
  /// window switch.
  final windows = <TmuxWindowInfo>[];

  /// The tmux pane tmux reports as focused in [windowId].
  String? focusedPaneId;

  /// Client geometry, reported to tmux with `refresh-client -C`.
  ///
  /// Zero until a pane has said what it is drawn at. Seeding a guess here would
  /// make the first real report look like "no change" and be suppressed, which
  /// is exactly how a session ends up sized for a grid nobody is looking at.
  int clientColumns = 0;
  int clientRows = 0;

  /// The tab's layout tree as last projected from tmux.
  SessionLayout? projected;

  final _contentIds = <String, String>{};
  final _panes = <String, _TmuxPaneAttachment>{};
  StreamSubscription<TmuxEvent>? _subscription;
  var _disposed = false;

  /// Whether the channel dropped while the session kept running.
  ///
  /// The panes are detached, not dead: their emulators keep the scrollback, and
  /// the session still holds whatever was running in them. Nothing may look up
  /// a pane on tmux until a new client attaches.
  var transportLost = false;

  /// Records a dropped channel, leaving every pane in place.
  void markTransportLost() {
    transportLost = true;
    _subscription?.cancel();
    _subscription = null;
  }

  /// Every mirrored pane's emulator, keyed by tmux pane id.
  Map<String, TerminalSessionAdapter> get adapters => {
    for (final entry in _panes.entries) entry.key: entry.value.adapter,
  };

  /// The MaidKit content id for [paneId], minted on first use.
  String contentIdForPane(String paneId) =>
      _contentIds.putIfAbsent(paneId, () => 'tmux-$sessionName-$paneId');

  /// The tmux pane behind [contentId], when this binding mirrors it.
  String? tmuxPaneForContentId(String contentId) {
    for (final entry in _contentIds.entries) {
      if (entry.value == contentId) return entry.key;
    }
    return null;
  }

  /// Records the size the tmux pane [paneId]'s viewport shows.
  ///
  /// tmux sizes the *whole session* from one client size (`refresh-client -C`),
  /// and then splits that extent among the panes. Each mirrored pane therefore
  /// cannot report itself: with two panes open, whichever reported last would
  /// halve the session and the full-screen programs in both would be told a
  /// width that is not the width they are drawn at - which is how a TUI ends up
  /// wrapping its progress output. The panes are composed back into one client
  /// extent instead, following the layout tree tmux itself gave us.
  void reportPaneSize(String paneId, int columns, int rows) {
    if (_disposed || columns <= 0 || rows <= 0) return;
    final attachment = _panes[paneId];
    if (attachment == null) return;
    if (attachment.columns == columns && attachment.rows == rows) return;
    attachment.columns = columns;
    attachment.rows = rows;
    _recomposeClientSize();
  }

  /// Sums the panes' own sizes back into the client extent tmux expects.
  ///
  /// A horizontal split is two panes side by side, so the client is as wide as
  /// both plus the divider, and as tall as the taller one; a vertical split is
  /// the other way round. Sizes for panes that have not been laid out yet are
  /// ignored rather than guessed.
  void _recomposeClientSize() {
    final layout = projected;
    if (layout == null) return;
    final size = _composeSize(layout);
    if (size == null) return;
    final firstPaint = _pendingAttachPaint;
    _pendingAttachPaint = false;
    if (size.$1 == clientColumns && size.$2 == clientRows && !firstPaint) {
      return;
    }
    clientColumns = size.$1;
    clientRows = size.$2;
    if (firstPaint) {
      // tmux repaints a control-mode client only when its extent actually
      // changes, and a reattach onto a session that already has this extent
      // answers with a `%layout-change` but no pane output: the tab opens
      // blank until a keypress. One cell off and back is a real change, so
      // tmux redraws every pane - alternate-screen programs included, which
      // the scrollback seed deliberately never touches. When the extent
      // genuinely differs this is a harmless second paint.
      control.resizeClient(clientColumns, clientRows - 1);
    }
    control.resizeClient(clientColumns, clientRows);
  }

  /// Whether the first composed client extent must repaint the session.
  ///
  /// Set on attach, cleared by the first [_recomposeClientSize] that has a
  /// full layout to compose.
  var _pendingAttachPaint = false;

  /// The client extent [layout] needs, given what each pane's viewport shows.
  ///
  /// Returns null until every pane in the tree has reported a size, so a
  (int, int)? _composeSize(SessionLayout layout) {
    switch (layout) {
      case SessionLayoutLeaf(paneId: final paneId):
        final attachment = _panes[paneId];
        if (attachment == null ||
            attachment.columns <= 0 ||
            attachment.rows <= 0) {
          return null;
        }
        return (attachment.columns, attachment.rows);
      case SessionLayoutSplit(
        axis: final axis,
        first: final first,
        second: final second,
      ):
        final a = _composeSize(first);
        final b = _composeSize(second);
        if (a == null || b == null) return null;
        return axis == SessionSplitAxis.horizontal
            // Side by side: widths add up (plus the one-cell divider), heights
            // take the taller pane.
            ? (a.$1 + b.$1 + 1, a.$2 > b.$2 ? a.$2 : b.$2)
            : (a.$1 > b.$1 ? a.$1 : b.$1, a.$2 + b.$2 + 1);
    }
  }

  /// Starts mirroring: asks for the JSON layout, learns the active window and
  /// projects that window's current layout.
  ///
  /// The initial layout is *asked for* rather than awaited: tmux emits
  /// `%layout-change` from events only (splitting, resizing, closing a pane),
  /// so attaching to a session nobody has touched yet reports nothing and the
  /// tab would stay empty forever.
  ///
  /// `new-layouts` is requested first so tmux reports the parseable v2 JSON
  /// instead of the legacy format 1 string, but it is best-effort: only recent
  /// tmux knows the flag, and an older build answers with `%error` while
  /// continuing to emit format 1 from both the event and the request. Both
  /// formats are accepted (see [tmuxLayoutToSessionLayout]), so a host that
  /// refuses the flag still mirrors its panes rather than showing an empty tab.
  ///
  /// [tabs] is the workspace that owns the tab, so the initial projection
  /// mounts the session's panes the same way a later event does.
  Future<void> initialize(TerminalTabsNotifier tabs) async {
    try {
      await control.command('refresh-client -f new-layouts');
    } catch (_) {
      // An older tmux refuses the flag; format 1 is handled either way.
    }
    await refreshWindows();
    await refreshLayout(tabs);
    // A freshly attached client is painted the current screen and nothing
    // more, so a session that has been running for a while would open looking
    // as if its earlier output never existed. tmux keeps that output in its own
    // scrollback, so each pane is seeded from there once its layout is known.
    await _seedPaneHistories();
    // The first composed client extent forces a repaint even when it matches
    // the session's: a reattach onto an unchanged geometry answers with a
    // `%layout-change` but no pane output, so the tab would open blank until
    // a keypress. Panes report their sizes after this, which is what triggers
    // the compose.
    _pendingAttachPaint = true;
  }

  /// How many scrollback lines one pane is seeded with on attach.
  ///
  /// tmux's own history limit is far larger, but a tab only has to open with
  /// the recent past in place: replaying thousands of lines through the
  /// emulator costs more than the context is worth, and the live screen follows
  /// immediately.
  static const tmuxHistorySeedLines = 500;

  /// Fills every projected pane's buffer with what tmux has above and on the
  /// screen, so a session opens where it actually left off.
  ///
  /// The visible screen is captured along with the scrollback: a fresh client
  /// is not repainted by tmux when it attaches to an idle session - only new
  /// output draws - so screen-only history would leave the pane blank until
  /// something printed. Capturing from the scrollback through the screen and
  /// replaying it reproduces the terminal the user last saw, prompt included.
  /// Panes that were already seeded keep their buffer, so a reattach costs no
  /// history.
  Future<void> _seedPaneHistories() async {
    for (final paneId in projected?.paneIds ?? const <String>[]) {
      if (_disposed) return;
      final attachment = _panes[paneId];
      if (attachment == null || attachment.seeded) continue;
      // A pane that has already painted live output needs no snapshot: its
      // screen is newer than anything a capture taken now could hold.
      if (attachment.sawOutput) {
        attachment.seeded = true;
        continue;
      }
      final TmuxBlockEvent flags;
      try {
        // A pane running a full-screen program keeps that program on the
        // alternate screen, and the alternate screen is *not* terminal history:
        // it is a live UI whose cursor positions are meaningless once replayed
        // into a fresh emulator, which is how vim and less came out garbled and
        // wrapped. Only the normal screen is seeded.
        flags = await control.command(
          'display-message -p -t $paneId "#{alternate_on}"',
        );
      } catch (_) {
        continue;
      }
      final alternate = (flags.lines.isEmpty ? '' : flags.lines.first).trim();
      if (alternate.isEmpty) continue;
      if (alternate == '1') {
        // No history to give it, but it is seeded: attaching again must not
        // re-ask, and the program repaints itself on the next keypress.
        attachment.seeded = true;
        continue;
      }
      // `capture-pane` returns the whole grid, so the blank rows below the
      // prompt would otherwise be replayed as output and scroll the pane to
      // emptiness. They are trimmed off the tail below.
      final TmuxBlockEvent block;
      try {
        block = await control.command(
          'capture-pane -p -e -t $paneId -S -$tmuxHistorySeedLines',
        );
      } catch (_) {
        // An older tmux without `-e`, or a pane that closed meanwhile: the pane
        // simply starts from its current screen.
        continue;
      }
      attachment.seeded = true;
      // The capture was asked for before its answer arrived, and on a slow
      // link the shell's first paint wins that race. Replaying the older
      // snapshot here writes it at the live cursor, which pushes the real
      // prompt off-screen under a wall of stale rows - the pane looks blank
      // until the next keypress prints something new.
      if (attachment.sawOutput) continue;
      final lines = [...block.lines];
      while (lines.isNotEmpty && lines.last.trim().isEmpty) {
        lines.removeLast();
      }
      if (lines.isEmpty) {
        // An empty screen: nothing to restore, and replaying padding here would
        // be the very whitespace this trims.
        continue;
      }
      // A captured line is one row of a screen, not a text paragraph: it has to
      // start at column zero. Joining with a bare LF leaves the emulator's
      // column where the previous row ended, so every row indents a little
      // further and long captures wrap into extra rows - a session opens
      // stair-stepped, or scrolled past the prompt it was supposed to restore.
      attachment.adapter.replayHistory(lines.join('\r\n'));
    }
  }

  /// Projects the active window's layout as tmux currently reports it.
  ///
  /// A window with no active pane yet reports an empty layout, which parses to
  /// null and is ignored; the `%layout-change` that eventually arrives fills it.
  Future<void> refreshLayout(TerminalTabsNotifier tabs) async {
    if (_disposed) return;
    final windowId = this.windowId;
    if (windowId == null) return;
    final TmuxBlockEvent block;
    try {
      block = await control.command(
        "display-message -p -t $windowId '#{window_layout}'",
      );
    } catch (_) {
      return;
    }
    final json = block.lines.isEmpty ? '' : block.lines.first.trim();
    if (json.isEmpty) return;
    projectLayout(json, windowId, tabs);
  }

  /// Re-reads the session's windows and follows the active one.
  ///
  /// The format string carries real tab characters, not `\t` escapes: tmux does
  /// not expand `\t` inside a format, so a literal backslash-t arrives as its
  /// own two characters. Splitting on that never yields four fields, the active
  /// window stays unknown, and no layout is ever requested — an empty tab with
  /// nothing to report.
  Future<void> refreshWindows() async {
    if (_disposed) return;
    final TmuxBlockEvent block;
    try {
      block = await control.command(
        "list-windows -F '#{window_id}\t#{window_index}\t#{window_name}\t#{window_active}'",
      );
    } catch (_) {
      return;
    }
    final listed = <TmuxWindowInfo>[];
    String? active;
    for (final line in block.lines) {
      final fields = line.split('\t');
      if (fields.length < 4) continue;
      final index = int.tryParse(fields[1].trim());
      if (index == null) continue;
      final isActive = fields[3].trim() == '1';
      listed.add(
        TmuxWindowInfo(index: index, name: fields[2].trim(), active: isActive),
      );
      if (isActive) active = fields[0].trim();
    }
    windows
      ..clear()
      ..addAll(listed);
    if (active == null || active == windowId) return;
    // A new active window means a different set of panes: the old adapters
    // belong to a window the tab no longer shows.
    windowId = active;
    focusedPaneId = null;
    _clearPanes();
    onWindowChanged?.call(active);
  }

  /// Called when the projected window changes, so the workspace can wait for
  /// the new window's layout.
  void Function(String windowId)? onWindowChanged;

  /// Applies one control-mode notification.
  Future<void> applyEvent(TmuxEvent event, TerminalTabsNotifier tabs) async {
    if (_disposed) return;
    switch (event) {
      case TmuxOutputEvent():
        _panes[event.paneId]?.write(event.bytes);
      case TmuxLayoutEvent():
        if (event.windowId != windowId) return;
        projectLayout(event.layout, event.windowId, tabs);
      case TmuxWindowPaneChangedEvent():
        if (event.windowId != windowId) return;
        focusedPaneId = event.paneId;
      case TmuxSessionWindowChangedEvent():
        await refreshWindows();
      case TmuxWindowAddEvent():
      case TmuxWindowCloseEvent():
      case TmuxWindowRenamedEvent():
        await refreshWindows();
      case TmuxSessionChangedEvent():
        break;
      case TmuxExitEvent():
        unawaited(closeTransport());
        if (!event.sessionEnded) {
          // The channel closed without tmux reporting an end: a dropped SSH
          // connection, a sleeping laptop, a daemon socket dying. The session
          // is still on the host with every process in it, so the tab stays
          // and says so instead of disappearing as if the work were gone.
          tabs.markTmuxTransportLost(this);
          return;
        }
        tabs.closeTmuxTab(this, reason: event.reason);
      case TmuxBlockEvent():
        break;
    }
  }

  /// Projects one v2 JSON layout onto the tab this binding owns.
  ///
  /// Both sources land here — the `%layout-change` event and the layout asked
  /// for at attach — so an inline pull and a pushed event produce the same
  /// result. The layout tree only updates when the parse succeeds, so a
  /// malformed cell leaves the current tree alone.
  void projectLayout(String json, String windowId, TerminalTabsNotifier tabs) {
    final layout = tmuxLayoutToSessionLayout(json, windowId: windowId);
    if (layout == null) return;
    projected = layout;
    tabs.applyTmuxLayout(this, layout);
    // The tree just changed: a pane joined, closed or moved, so the client
    // extent the session should be told is different too.
    _recomposeClientSize();
  }

  /// The adapter for [paneId], building it on first use.
  TerminalSessionAdapter adapterFor(String paneId) {
    final existing = _panes[paneId];
    if (existing != null) return existing.adapter;
    final attachment = _TmuxPaneAttachment(
      paneId: paneId,
      adapterFactory: _adapterFactoryRef,
      send: (bytes) => control.sendKeys(paneId, bytes),
      resize: (event) => reportPaneSize(paneId, event.columns, event.rows),
      autoFillSecret: autoFillSecret,
    );
    _panes[paneId] = attachment;
    return attachment.adapter;
  }

  /// Releases the emulator of [paneId], whose tmux pane is gone.
  Future<void> releasePane(String paneId) async {
    final attachment = _panes.remove(paneId);
    _contentIds.remove(paneId);
    if (attachment != null) await attachment.dispose();
  }

  /// Splits the focused pane in tmux. The new pane appears only through the
  /// resulting `%layout-change`, never optimistically.
  void splitFocusedPane(SessionSplitAxis axis) {
    final target = focusedPaneId ?? projected?.paneIds.firstOrNull;
    if (target == null) return;
    unawaited(
      control.command(
        'split-window -t $target ${axis == SessionSplitAxis.horizontal ? '-h' : '-v'} -c "#{pane_current_path}"',
      ),
    );
  }

  /// Asks tmux to move the split [splitId] to [ratio] of its own region.
  ///
  /// tmux resizes by an absolute cell count on one pane, so the ratio has to be
  /// turned into the width the first side should end up with. [ratio] is a
  /// fraction of the split's *region*, which is the client extent only for the
  /// outermost split: a nested split owns just the part of the window its parent
  /// gave it. Measuring the region from the projected tree keeps the drag
  /// honest at any depth - scaling the client extent instead used to hand a
  /// nested split a width taken from the whole window, which shoved the
  /// dividers across the window and collapsed the panes beyond them.
  ///
  /// The `%layout-change` that follows replaces the local ratio, which is why a
  /// refused resize snaps back instead of drifting.
  void applySplitRatio(String splitId, double ratio) {
    final layout = projected;
    if (layout == null) return;
    final split = _findSplit(layout, splitId);
    if (split == null) return;
    final target = split.first.paneIds.lastOrNull;
    if (target == null) return;
    final horizontal = split.axis == SessionSplitAxis.horizontal;
    final extent = _regionExtent(layout, splitId, horizontal: horizontal);
    if (extent == null) return;
    // The divider is one cell of the region, so the first side gets everything
    // up to the boundary the ratio names.
    final boundary = (extent.$1 + ratio * (extent.$2 - 1)).round();
    final width = boundary - extent.$1;
    final command = horizontal ? '-x' : '-y';
    unawaited(
      control.command(
        'resize-pane -t $target $command ${width.clamp(1, 1 << 20)}',
      ),
    );
  }

  /// Where the split [splitId] starts and how much room it owns, in cells.
  ///
  /// Walks the projected tree accumulating each split's share of its parent, so
  /// the answer is the split's own region rather than the whole window. The
  /// start is the client cell coordinate of the region's leading edge; the
  /// extent counts the cells the split distributes, divider included. Null when
  /// the split is not found or the pane sizes have not been laid out yet.
  (int, int)? _regionExtent(
    SessionLayout layout,
    String splitId, {
    required bool horizontal,
  }) {
    final total = horizontal ? clientColumns : clientRows;
    if (total <= 0) return null;
    return _locate(layout, splitId, 0, total, horizontal);
  }

  /// [_regionExtent]'s walk over [node], which occupies [start] plus [extent].
  (int, int)? _locate(
    SessionLayout node,
    String splitId,
    int start,
    int extent,
    bool horizontal,
  ) {
    switch (node) {
      case SessionLayoutLeaf():
        return null;
      case SessionLayoutSplit(
        :final id,
        :final axis,
        :final ratio,
        :final first,
        :final second,
      ):
        if (id == splitId) return (start, extent);
        // The divider is one cell, so the two sides share what is left over.
        final available = extent - 1;
        if (available <= 0) return null;
        final firstExtent = (available * ratio).round().clamp(1, available);
        final sameAxis = (axis == SessionSplitAxis.horizontal) == horizontal;
        if (!sameAxis) {
          // This split runs the other way, so both sides keep [extent].
          return _locate(first, splitId, start, extent, horizontal) ??
              _locate(second, splitId, start, extent, horizontal);
        }
        return _locate(first, splitId, start, firstExtent, horizontal) ??
            _locate(
              second,
              splitId,
              start + firstExtent + 1,
              available - firstExtent,
              horizontal,
            );
    }
  }

  /// Ends the tmux pane [paneId] and the processes in it.
  void closePane(String paneId) {
    unawaited(control.command('kill-pane -t $paneId'));
  }

  /// Detaches this client, leaving the session running on the host.
  Future<void> detach() async {
    try {
      await control.detach();
    } catch (_) {
      // The transport may already be gone; dropping it is the same outcome.
    }
    await closeTransport();
  }

  /// Ends the tmux session on the host, every process in it.
  Future<void> killSession() async {
    try {
      await control.command('kill-session -t $sessionName');
    } catch (_) {
      // A session that already ended needs no kill.
    }
    await closeTransport();
  }

  /// Drops the connection this session rides: the SSH channel or the daemon
  /// socket. Idempotent, because a session ends through one of several paths
  /// (detach, kill, or tmux exiting on its own) and the last one wins.
  Future<void> closeTransport() async {
    if (_transportClosed) return;
    _transportClosed = true;
    await _closeTransportHandle();
  }

  /// The panes of the tabs' own window, in layout leaf order.
  List<String> get paneIds => projected?.paneIds.toList() ?? const [];

  /// Subscribes this binding to its transport's events.
  void listen(TerminalTabsNotifier Function() notifier) {
    _subscription ??= onEventStream.listen((event) {
      final tabs = notifier();
      unawaited(applyEvent(event, tabs));
    });
  }

  /// Points this binding at a freshly attached client for the same session.
  ///
  /// The panes, their emulators and their scrollback are untouched: only the
  /// connection to tmux changes, so a dropped channel costs no history. The new
  /// stream is subscribed before the layout is pulled, or an event arriving
  /// between the pull and the subscribe would be missed.
  Future<void> reattach({
    required TmuxControlClient control,
    required Stream<TmuxEvent> onEventStream,
    required Future<void> Function() closeTransport,
    required TerminalTabsNotifier tabs,
  }) async {
    await _subscription?.cancel();
    _subscription = null;
    this.control = control;
    _eventStream = onEventStream;
    _closeTransportHandle = closeTransport;
    _transportClosed = false;
    transportLost = false;
    listen(() => tabs);
    await initialize(tabs);
  }

  /// Releases every adapter, the event subscription, and the transport.
  ///
  /// Closing here is the guarantee rather than the policy: detach and kill
  /// choose what the host does and then close the same connection, and any
  /// other way a binding is dropped - a failed attach rolled back, a workspace
  /// torn down - must not leave a shell and a tmux client behind. The close is
  /// idempotent, so a path that already ended the transport pays nothing.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    _subscription = null;
    for (final attachment in _panes.values) {
      await attachment.dispose();
    }
    _panes.clear();
    _contentIds.clear();
    await closeTransport();
  }

  void _clearPanes() {
    for (final attachment in _panes.values) {
      unawaited(attachment.dispose());
    }
    _panes.clear();
  }
}

SessionLayoutSplit? _findSplit(SessionLayout layout, String splitId) {
  switch (layout) {
    case SessionLayoutLeaf():
      return null;
    case SessionLayoutSplit(:final id):
      if (id == splitId) return layout;
      return _findSplit(layout.first, splitId) ??
          _findSplit(layout.second, splitId);
  }
}

/// One mirrored tmux pane: its emulator plus the bridge wiring it to the tmux
/// pane's bytes.
class _TmuxPaneAttachment {
  _TmuxPaneAttachment({
    required this.paneId,
    required TerminalSessionAdapterFactory adapterFactory,
    required void Function(Uint8List bytes) send,
    required void Function(TerminalResize resize) resize,
    String? autoFillSecret,
  }) : _output = StreamController<Uint8List>.broadcast() {
    adapter = adapterFactory.create();
    binding = TerminalSessionBinding(
      adapter: adapter,
      stdout: _output.stream,
      stderr: const Stream.empty(),
      send: send,
      resize: resize,
      autoFillSecret: autoFillSecret,
    );
    // The hint above the cursor follows the same watcher the interception
    // uses, per pane, so it shows only where that pane's own prompt is up.
    adapter.bindSudoAutofill(binding.autofillReady);
  }

  final String paneId;
  final StreamController<Uint8List> _output;

  /// Whether tmux's scrollback has already been replayed into this pane.
  var seeded = false;

  /// Whether this pane has already drawn any live output.
  ///
  /// tmux paints a freshly attached client with the screen it missed, and that
  /// paint can beat the scrollback seed's answer. A pane that has already drawn
  /// something must not then be handed a snapshot of what came before it.
  var sawOutput = false;

  /// The grid this pane's own viewport currently shows.
  ///
  /// A mirrored pane is drawn at its own size, not at the session's, so this is
  /// what the pane contributes when the client size is composed below.
  int columns = 0;
  int rows = 0;
  late final TerminalSessionAdapter adapter;
  late final TerminalSessionBinding binding;

  void write(List<int> bytes) {
    if (_output.isClosed || bytes.isEmpty) return;
    sawOutput = true;
    _output.add(Uint8List.fromList(bytes));
  }

  Future<void> dispose() async {
    try {
      await binding.close();
    } catch (_) {}
    try {
      await adapter.dispose();
    } catch (_) {}
    if (!_output.isClosed) unawaited(_output.close());
  }
}

/// One of a session's windows, as tmux reports it.
class TmuxWindowInfo {
  const TmuxWindowInfo({
    required this.index,
    required this.name,
    required this.active,
  });

  final int index;
  final String name;
  final bool active;
}
