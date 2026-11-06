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
    required this.onEventStream,
  }) : _closeTransportHandle = closeTransport,
       _adapterFactoryRef = adapterFactory;

  /// The tmux session this tab mirrors.
  final String sessionName;
  final TmuxControlClient control;
  final int serverId;
  final String serverName;

  /// The transport the control client rides, for the pane's status band.
  final TerminalTransport transport;

  /// Where the transport's event stream comes from; the notifier subscribes it
  /// to [applyEvent] once the tab exists.
  final Stream<TmuxEvent> onEventStream;

  final Future<void> Function() _closeTransportHandle;
  final TerminalSessionAdapterFactory _adapterFactoryRef;

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
  int clientColumns = 120;
  int clientRows = 36;

  /// The tab's layout tree as last projected from tmux.
  SessionLayout? projected;

  final _contentIds = <String, String>{};
  final _panes = <String, _TmuxPaneAttachment>{};
  StreamSubscription<TmuxEvent>? _subscription;
  var _disposed = false;

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

  /// Reports the client's own size to tmux, which sizes the session's windows.
  void reportClientSize(int columns, int rows) {
    if (_disposed || columns <= 0 || rows <= 0) return;
    clientColumns = columns;
    clientRows = rows;
    control.resizeClient(columns, rows);
  }

  /// Starts mirroring: enables the v2 JSON layout and learns the active window.
  ///
  /// `new-layouts` has to be set before tmux reports a layout, otherwise the
  /// `%layout-change` payload is the legacy v1 string this client cannot read
  /// structurally.
  Future<void> initialize() async {
    await control.command('refresh-client -f new-layouts');
    await refreshWindows();
  }

  /// Re-reads the session's windows and follows the active one.
  Future<void> refreshWindows() async {
    if (_disposed) return;
    final TmuxBlockEvent block;
    try {
      block = await control.command(
        "list-windows -F '#{window_id}\\t#{window_index}\\t#{window_name}\\t#{window_active}'",
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
        final layout = tmuxLayoutToSessionLayout(
          event.layout,
          windowId: event.windowId,
        );
        if (layout == null) return;
        projected = layout;
        tabs.applyTmuxLayout(this, layout);
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
        tabs.closeTmuxTab(this, reason: event.reason);
      case TmuxBlockEvent():
        break;
    }
  }

  /// The adapter for [paneId], building it on first use.
  TerminalSessionAdapter adapterFor(String paneId) {
    final existing = _panes[paneId];
    if (existing != null) return existing.adapter;
    final attachment = _TmuxPaneAttachment(
      paneId: paneId,
      adapterFactory: _adapterFactoryRef,
      send: (bytes) => control.sendKeys(paneId, bytes),
      resize: (event) => reportClientSize(event.columns, event.rows),
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

  /// Asks tmux to move the split [splitId] to [ratio] of the client's extent.
  ///
  /// tmux resizes by absolute cell counts, so a drag is quantized to whole
  /// columns or rows. The `%layout-change` that follows replaces the local
  /// ratio, which is why a refused resize snaps back instead of drifting.
  void applySplitRatio(String splitId, double ratio) {
    final layout = projected;
    if (layout == null) return;
    final split = _findSplit(layout, splitId);
    if (split == null) return;
    final firstSide = split.first.paneIds.toList();
    final target = firstSide.lastOrNull;
    if (target == null) return;
    if (split.axis == SessionSplitAxis.horizontal) {
      final columns = ((clientColumns * ratio).floor() - 1).clamp(2, 1 << 20);
      unawaited(control.command('resize-pane -t $target -x $columns'));
      return;
    }
    final rows = ((clientRows * ratio).floor() - 1).clamp(2, 1 << 20);
    unawaited(control.command('resize-pane -t $target -y $rows'));
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
    await _closeTransportHandle();
  }

  /// Ends the tmux session on the host, every process in it.
  Future<void> killSession() async {
    try {
      await control.command('kill-session -t $sessionName');
    } catch (_) {
      // A session that already ended needs no kill.
    }
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

  /// Releases every adapter and the event subscription. The transport is the
  /// caller's to close, because detaching and killing end it differently.
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
  }) : _output = StreamController<Uint8List>.broadcast() {
    adapter = adapterFactory.create();
    binding = TerminalSessionBinding(
      adapter: adapter,
      stdout: _output.stream,
      stderr: const Stream.empty(),
      send: send,
      resize: resize,
    );
  }

  final String paneId;
  final StreamController<Uint8List> _output;
  late final TerminalSessionAdapter adapter;
  late final TerminalSessionBinding binding;

  void write(List<int> bytes) {
    if (_output.isClosed || bytes.isEmpty) return;
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
