import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:maid_kit/data/local/app_database.dart' hide WorkspaceSnapshot;
import 'package:maid_kit/shared/presentation/maidkit_alert.dart';
import 'package:maid_kit/shared/presentation/tab_navigator.dart';
import 'package:maid_kit/snippets/snippet_repository.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'server_models.dart';
import 'server_providers.dart';
import 'session_layout.dart';
import 'ssh_connection_manager.dart';
import 'terminal_session_adapter.dart';
import 'tmux_control_client.dart';
import 'tmux_terminal.dart';
import 'workspace_snapshot.dart';

export 'session_layout.dart';

/// Stable keys so session tab views keep their [State] across pane splits,
/// tab reorders, and moves between panes.
final Map<String, GlobalKey> _sessionTabViewKeys = {};

/// Global key for the interactive body of [tabId] (terminal or file transfer).
GlobalKey sessionTabViewKey(String tabId) => _sessionTabViewKeys.putIfAbsent(
  tabId,
  () => GlobalKey(debugLabel: 'session-tab-$tabId'),
);

void _releaseSessionTabViewKey(String tabId) {
  _sessionTabViewKeys.remove(tabId);
}

enum SessionTabType {
  dashboard,
  serverDetail,
  maidCafePayload,
  terminal,
  fileManagement,
  fileEditor,
  assets,
  projects,
  maidCafeCloud,
  settings,
  agentChat,
}

/// The inner pages of the assets tab, in the order its own tab bar shows them.
///
/// A caller can open the assets tab straight on one of them (a palette entry
/// per page, a deep link), so the section is part of the tab rather than page
/// local state.
enum AssetsSection { connections, github, credentials, snippets }

/// Optional close confirmation for dirty file-editor tabs.
final Map<String, Future<bool> Function()> fileEditorCloseGuards = {};

/// What one pane shows.
///
/// A tab is the document; its panes are viewports onto it, and every pane
/// mounts its own instance because a terminal socket, a file browser's remote
/// listing or an agent conversation cannot be rendered twice. Instances of the
/// same kind therefore carry the same [type] and target while keeping separate
/// [id]s.
sealed class SessionTab {
  const SessionTab({
    required this.id,
    required this.serverId,
    required this.serverName,
  });

  final String id;
  final int serverId;
  final String serverName;
  SessionTabType get type;
}

/// How a terminal is connected, for the status bar to name.
///
/// The cases are the transports this app can open a shell over; a MaidCafe
/// terminal is two of them, because a relayed session rides the cloud and a
/// direct one dials the daemon itself. [tmux] is orthogonal to those on the
/// wire — a tmux client rides either SSH or a daemon socket — and names the
/// session's own transport because that is what the user is looking at: a
/// process tree that outlives the connection.
enum TerminalTransport {
  ssh('terminalTransportSsh'),
  serial('terminalTransportSerial'),
  maidCafeDirect('terminalTransportMaidCafeDirect'),
  maidCafeRelay('terminalTransportMaidCafeRelay'),
  tmux('terminalTransportTmux');

  const TerminalTransport(this.labelKey);

  /// Translation key for the human name, shown in a tooltip.
  final String labelKey;
}

/// The transport a MaidCafe terminal runs over.
///
/// A relayed target goes through the cloud; anything else dials the daemon, on
/// its own address or through the SSH forward that carries a loopback one.
TerminalTransport maidCafeTerminalTransport(MaidCafeTerminalTarget target) =>
    target.isRelayed
    ? TerminalTransport.maidCafeRelay
    : TerminalTransport.maidCafeDirect;

class TerminalTab extends SessionTab {
  const TerminalTab({
    required super.id,
    required super.serverId,
    required super.serverName,
    required this.terminal,
    required this.transport,
    this.tmux,
  });

  final TerminalSessionAdapter terminal;

  /// Which transport serves this terminal. Shown in the status bar, so a
  /// relayed session is distinguishable from a direct one at a glance.
  final TerminalTransport transport;

  /// The tmux binding this pane belongs to, when the pane mirrors a tmux pane.
  ///
  /// One tmux session is one workspace tab, so every pane in it shares the
  /// binding that owns the control client and the adapter for each tmux pane.
  final TmuxTabBinding? tmux;

  @override
  SessionTabType get type => SessionTabType.terminal;
}

class FileManagementTab extends SessionTab {
  const FileManagementTab({
    required super.id,
    required super.serverId,
    required super.serverName,
    this.initialPath,
  });

  /// Remote directory to show on first load (e.g. a linked project folder).
  final String? initialPath;

  @override
  SessionTabType get type => SessionTabType.fileManagement;
}

/// In-pane text editor for a local or remote file.
class FileEditorTab extends SessionTab {
  const FileEditorTab({
    required super.id,
    required super.serverId,
    required super.serverName,
    required this.fileName,
    required this.path,
    required this.isRemote,
  });

  final String fileName;
  final String path;
  final bool isRemote;

  @override
  SessionTabType get type => SessionTabType.fileEditor;
}

/// The persistent server overview, shown in the same tab system as live
/// terminals and file-management views.
///
/// The workspace's home tab carries the plain `dashboard` id; a second instance
/// mounted in a split pane gets an id of its own, because one id is one mounted
/// view.
class DashboardTab extends SessionTab {
  const DashboardTab({super.id = 'dashboard'})
    : super(serverId: -1, serverName: 'Dashboard');

  @override
  SessionTabType get type => SessionTabType.dashboard;
}

class ServerDetailTab extends SessionTab {
  ServerDetailTab({
    required super.id,
    required this.server,
    this.initialTab = 0,
    this.initialComposeProject,
  }) : super(serverId: server.id, serverName: server.name);

  final Server server;
  final int initialTab;
  final String? initialComposeProject;

  @override
  SessionTabType get type => SessionTabType.serverDetail;
}

/// The server-scoped MaidCafe payload and live action workspace.
class MaidCafePayloadSessionTab extends SessionTab {
  MaidCafePayloadSessionTab({required super.id, required this.server})
    : super(serverId: server.id, serverName: server.name);

  final Server server;

  @override
  SessionTabType get type => SessionTabType.maidCafePayload;
}

/// A non-server destination hosted in the tab system.
///
/// These used to be navigation-rail destinations; each one is a singleton tab
/// (there is never a second Projects or Settings tab), so opening an already
/// open destination simply selects it.
sealed class DestinationTab extends SessionTab {
  const DestinationTab({required super.id, required super.serverName})
    : super(serverId: -1);
}

/// Saved connection resources: servers, GitHub, credentials and snippets.
class AssetsSessionTab extends DestinationTab {
  const AssetsSessionTab({
    this.section = AssetsSection.connections,
    super.id = 'assets',
  }) : super(serverName: 'Assets');

  /// The assets page to show. Re-opening the tab on another section switches
  /// to it instead of opening a second assets tab.
  final AssetsSection section;

  AssetsSessionTab copyWith({AssetsSection? section}) =>
      AssetsSessionTab(section: section ?? this.section, id: id);

  @override
  SessionTabType get type => SessionTabType.assets;
}

/// Managed deployment projects.
class ProjectsSessionTab extends DestinationTab {
  const ProjectsSessionTab({super.id = 'projects'})
    : super(serverName: 'Projects');

  @override
  SessionTabType get type => SessionTabType.projects;
}

/// Solarpass account, workspaces and registered MaidCafe daemons.
class MaidCafeCloudSessionTab extends DestinationTab {
  const MaidCafeCloudSessionTab({super.id = 'maidcafe-cloud'})
    : super(serverName: 'MaidCafe');

  @override
  SessionTabType get type => SessionTabType.maidCafeCloud;
}

/// App settings.
class SettingsSessionTab extends DestinationTab {
  const SettingsSessionTab({super.id = 'settings'})
    : super(serverName: 'Settings');

  @override
  SessionTabType get type => SessionTabType.settings;
}

/// One agent chat. The chat itself lives in the tab body; the tab carries the
/// title and in-flight flag so the strip can show them without rebuilding the
/// conversation.
class AgentChatSessionTab extends SessionTab {
  const AgentChatSessionTab({
    required super.id,
    required this.title,
    this.working = false,
  }) : super(serverId: -1, serverName: 'Agent');

  final String title;
  final bool working;

  AgentChatSessionTab copyWith({String? title, bool? working}) =>
      AgentChatSessionTab(
        id: id,
        title: title ?? this.title,
        working: working ?? this.working,
      );

  @override
  SessionTabType get type => SessionTabType.agentChat;
}

/// One viewport of a tab.
///
/// A pane carries the content instance it mounts, or nothing while it waits for
/// the user to pick something in the pane's intro.
class TabPane {
  const TabPane({required this.id, this.tab});

  final String id;

  /// The mounted instance. Null in a pane a split just created.
  final SessionTab? tab;

  bool get isEmpty => tab == null;

  TabPane withTab(SessionTab tab) => TabPane(id: id, tab: tab);
}

/// One workspace tab: a single document plus its own pane layout.
///
/// This is the unit the workspace bar shows. Splitting adds a pane *to this
/// tab*, so a split terminal reads as one tab with two shells rather than as
/// two unrelated tabs; closing the tab closes every pane it owns. The layout
/// tree belongs to the tab, so each tab remembers its own arrangement instead
/// of the workspace keeping one tree for all of them.
class WorkspaceTab {
  const WorkspaceTab({
    required this.id,
    required this.panes,
    required this.layout,
    required this.focusedPaneId,
  });

  /// Stable document identity. It starts as the first content's id and is
  /// kept across splits, so a tab outlives any one pane.
  final String id;

  /// Panes keyed by pane id. The layout's leaves are these ids.
  final Map<String, TabPane> panes;
  final SessionLayout layout;
  final String focusedPaneId;

  TabPane? get focusedPane => panes[focusedPaneId];

  /// The content the bar names: whatever the focused pane shows, else the
  /// first pane that shows anything.
  SessionTab? get tab {
    final focused = focusedPane?.tab;
    if (focused != null) return focused;
    for (final pane in panes.values) {
      if (pane.tab != null) return pane.tab;
    }
    return null;
  }

  /// Every content instance mounted by this tab, in pane order.
  Iterable<SessionTab> get tabs sync* {
    for (final paneId in layout.paneIds) {
      final tab = panes[paneId]?.tab;
      if (tab != null) yield tab;
    }
  }

  bool get hasSplits => layout.isSplit;

  bool get isPristineDashboard =>
      panes.length == 1 &&
      panes.values.first.id == 'main' &&
      tab is DashboardTab &&
      layout is SessionLayoutLeaf;

  String? paneIdForContent(String contentId) {
    for (final pane in panes.values) {
      if (pane.tab?.id == contentId) return pane.id;
    }
    return null;
  }

  WorkspaceTab copyWith({
    Map<String, TabPane>? panes,
    SessionLayout? layout,
    String? focusedPaneId,
  }) => WorkspaceTab(
    id: id,
    panes: panes ?? this.panes,
    layout: layout ?? this.layout,
    focusedPaneId: focusedPaneId ?? this.focusedPaneId,
  );
}

class TerminalTabsState {
  const TerminalTabsState({this.tabs = const [], this.selectedTabId});

  /// Workspace tabs in bar order. Each one owns its pane layout.
  final List<WorkspaceTab> tabs;
  final String? selectedTabId;

  WorkspaceTab? get selectedTab {
    final id = selectedTabId;
    if (id == null) return null;
    for (final tab in tabs) {
      if (tab.id == id) return tab;
    }
    return null;
  }

  /// The content the selected tab is showing (drives status bar, palette).
  SessionTab? get selectedTabContent => selectedTab?.tab;

  String? get selectedId => selectedTab?.id;

  /// Workspace is empty when there are no tabs at all.
  bool get isEmpty => tabs.isEmpty;
  bool get isNotEmpty => tabs.isNotEmpty;

  /// The untouched single-dashboard workspace every session starts with.
  /// Used to decide whether a previous snapshot may be shown for restore
  /// without clobbering a live workspace.
  bool get isPristineDefault =>
      tabs.length == 1 && tabs.first.isPristineDashboard;

  /// Whether any tab is split into more than one pane.
  bool get hasSplits => tabs.any((tab) => tab.hasSplits);

  /// Every mounted content instance in the workspace.
  Iterable<SessionTab> get allTabs => tabs.expand((tab) => tab.tabs);

  WorkspaceTab? tabForContent(String contentId) {
    for (final tab in tabs) {
      if (tab.tab?.id == contentId || tab.paneIdForContent(contentId) != null) {
        return tab;
      }
    }
    return null;
  }

  WorkspaceTab? tabById(String tabId) {
    for (final tab in tabs) {
      if (tab.id == tabId) return tab;
    }
    return null;
  }

  /// The pane [contentId] is mounted in, searched across every tab.
  String? paneIdForContent(String contentId) {
    for (final tab in tabs) {
      final paneId = tab.paneIdForContent(contentId);
      if (paneId != null) return paneId;
    }
    return null;
  }

  SessionTab? contentById(String contentId) {
    for (final tab in tabs) {
      for (final pane in tab.panes.values) {
        if (pane.tab?.id == contentId) return pane.tab;
      }
    }
    return null;
  }
}

final terminalTabsProvider =
    NotifierProvider<TerminalTabsNotifier, TerminalTabsState>(
      TerminalTabsNotifier.new,
    );

/// Whether the servers dashboard is the tab the user is actually looking at.
///
/// The dashboard owns the background statistics refresh — its cards are the
/// readers — and a tab left behind in the strip must not keep dialling hosts
/// nobody is watching. Selected in the focused tab, the same rule the status
/// bar and the command palette use.
final dashboardFocusedProvider = Provider<bool>((ref) {
  final tabs = ref.watch(terminalTabsProvider);
  return tabs.selectedTabContent is DashboardTab;
});

/// Whether [tab] may grow another pane.
///
/// The home dashboard (`dashboard`) is the workspace's floor: it fills the
/// whole pane area and never splits into an empty sibling. Every other tab is
/// a document whose viewports can be added to.
bool canSplitTab(WorkspaceTab? tab) => tab != null && tab.id != 'dashboard';

/// A fresh, unique content id for a second instance of the same kind.
String _instanceId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}';

/// Holds live workspace tabs for the entire app lifetime.
///
/// This provider deliberately is not auto-disposed, so terminals continue to
/// receive output while the user visits another workspace page.
class TerminalTabsNotifier extends Notifier<TerminalTabsState> {
  static const _uuid = Uuid();

  @override
  TerminalTabsState build() {
    _initialized = true;
    ref.onDispose(() {
      _snapshotDebounce?.cancel();
      _snapshotDebounce = null;
      _historyTimer?.cancel();
      _historyTimer = null;
    });
    const dashboard = DashboardTab();
    final tab = _newTab(paneId: 'main', content: dashboard);
    return TerminalTabsState(tabs: [tab], selectedTabId: tab.id);
  }

  // ---------------------------------------------------------------------------
  // Workspace snapshot persistence ("restore last session").
  // ---------------------------------------------------------------------------

  var _initialized = false;
  var _restoring = false;
  Timer? _snapshotDebounce;
  Timer? _historyTimer;
  final _lastBufferRows = <String, int>{};
  final _cachedHistory = <String, String>{};

  /// Cleanups keyed by terminal content id. A daemon terminal opened through a
  /// temporary SSH forward stops that forward here, so it lives exactly as long
  /// as its terminal and no other tab is affected.
  final _tabCleanups = <String, Future<void> Function()>{};

  /// tmux sessions mounted as workspace tabs, keyed by the tab id.
  final _tmuxTabs = <String, TmuxTabBinding>{};

  /// The tmux binding behind [tabId], when that tab mirrors a tmux session.
  TmuxTabBinding? tmuxForTab(String tabId) => _tmuxTabs[tabId];

  /// Every workspace mutation schedules a debounced snapshot save.
  ///
  /// The pristine default is exempt so it never overwrites a real snapshot on
  /// disk, and restores are exempt because they persist once at the end.
  @override
  set state(TerminalTabsState value) {
    super.state = value;
    _onWorkspaceChanged();
  }

  void _onWorkspaceChanged() {
    if (!_initialized || _restoring) return;
    if (state.isPristineDefault) return;
    _scheduleSnapshotSave();
    _ensureHistoryTimer();
  }

  void _scheduleSnapshotSave() {
    _snapshotDebounce?.cancel();
    _snapshotDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(saveSnapshotNow());
    });
  }

  /// Captures and persists the current workspace. Also called from the
  /// window-close hook and after a restore, so it is safe to invoke
  /// repeatedly.
  Future<void> saveSnapshotNow() async {
    if (_restoring || state.isPristineDefault) return;
    try {
      final snapshot = WorkspaceSnapshot.capture(
        state,
        historyFor: _historyFor,
      );
      await ref.read(workspaceSnapshotStoreProvider).save(snapshot);
    } catch (_) {
      // Persisting is best-effort; a failed write must not break the
      // workspace. The next save attempt retries.
    }
  }

  void _ensureHistoryTimer() {
    _historyTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (_restoring || state.isPristineDefault) return;
      if (!state.allTabs.any((tab) => tab is TerminalTab)) return;
      unawaited(saveSnapshotNow());
    });
  }

  /// Plain-text history for [tab], re-captured only when the buffer row count
  /// changed since the last capture (a cheap dirty check for scrolling
  /// output).
  String _historyFor(TerminalTab tab) {
    final rows = tab.terminal.bufferRows;
    if (_lastBufferRows[tab.id] != rows) {
      _lastBufferRows[tab.id] = rows;
      _cachedHistory[tab.id] = tab.terminal.dumpHistory() ?? '';
    }
    return _cachedHistory[tab.id] ?? '';
  }

  /// Restores the workspace saved by the previous session.
  Future<void> restoreLastWorkspace() async {
    final stored = await ref.read(workspaceSnapshotStoreProvider).load();
    if (stored == null) return;
    await restoreWorkspace(stored.snapshot);
  }

  /// Rebuilds [snapshot] into the live workspace: every tab with its pane
  /// arrangement and non-terminal content first, then connections and
  /// terminal sessions as they become available.
  Future<void> restoreWorkspace(WorkspaceSnapshot snapshot) async {
    // A browser has no SSH or serial transport and no file tabs to restore;
    // only MaidCafe WebSocket terminals could reopen, which is not a saved
    // workspace feature there.
    if (kIsWeb || _restoring || snapshot.isEmpty) return;
    _restoring = true;
    try {
      final repository = ref.read(serverRepositoryProvider);
      final servers = await repository.all();
      final byId = {for (final server in servers) server.id: server};
      final resolved = resolveWorkspaceSnapshot(snapshot, byId);

      // Phase 1: structure plus all non-terminal content, immediately.
      state = TerminalTabsState(
        tabs: resolved.initialTabs,
        selectedTabId: resolved.selectedTabId,
      );

      // Phase 2: terminals, opened in parallel per pane and ordered once they
      // all land (or fail).
      if (resolved.pendingTerminals.isEmpty) return;
      for (final pending in resolved.pendingTerminals) {
        await _restoreTerminal(pending, byId);
      }
    } finally {
      _restoring = false;
      // Persist the restored workspace (or whatever succeeded), so the next
      // launch can restore it again.
      unawaited(saveSnapshotNow());
    }
  }

  Future<void> _restoreTerminal(
    PendingTerminalRestore pending,
    Map<int, Server> serversById,
  ) async {
    final server = serversById[pending.serverId];
    if (server == null) return;
    // A tmux terminal reattaches to its session by name; a host that cannot
    // serve it falls back to the plain open below.
    final tmuxSession = pending.tmuxSession;
    if (tmuxSession != null &&
        pending.connectionType != ServerConnectionType.serial) {
      try {
        await openTmuxSession(
          server,
          sessionName: tmuxSession,
          paneId: pending.paneId,
        );
        return;
      } catch (_) {
        // The session may have been killed on the host; a plain terminal is
        // still better than an empty pane.
      }
    }
    try {
      if (pending.connectionType == ServerConnectionType.serial) {
        await openSerial(
          server,
          paneId: pending.paneId,
          initialOutput: pending.history,
        );
        return;
      }
      final repository = ref.read(serverRepositoryProvider);
      if (pending.connectionType == ServerConnectionType.maidcafe) {
        final target = await repository.maidCafeTerminalTargetFor(server);
        if (target == null) return;
        await openMaidCafe(
          server,
          target,
          paneId: pending.paneId,
          initialOutput: pending.history,
        );
        return;
      }
      final credential = await repository.credentialFor(server);
      final proxy = await repository.proxyFor(server);
      await open(
        server,
        credential,
        (_) async => false,
        knownHostKeyFingerprint: server.hostKeyFingerprint,
        initialDirectory: pending.cwd,
        proxy: proxy,
        paneId: pending.paneId,
        initialOutput: pending.history,
      );
    } catch (_) {
      // A failed connection skips that terminal; the rest of the tab restores.
    }
  }

  Future<void> open(
    Server server,
    ServerCredential credential,
    HostKeyApproval approve, {
    String? knownHostKeyFingerprint,
    String? initialDirectory,
    List<String>? initialScripts,
    String? paneId,
    ServerProxy? proxy,
    String? initialOutput,
    AuthChallengeApproval? approveAuth,
  }) async {
    // A browser has no raw socket for SSH channels.
    if (kIsWeb) {
      throw UnsupportedError(
        'SSH terminals are not available in this browser.',
      );
    }
    final handle = await _openTerminalHandle(
      server,
      credential,
      approve,
      knownHostKeyFingerprint: knownHostKeyFingerprint,
      initialDirectory: initialDirectory,
      extraInitialScripts: initialScripts,
      proxy: proxy,
      initialOutput: initialOutput,
      approveAuth: approveAuth,
    );
    final tab = TerminalTab(
      id: handle.id,
      serverId: server.id,
      serverName: server.name,
      terminal: handle.adapter,
      transport: TerminalTransport.ssh,
    );
    _insertTab(tab, targetPaneId: paneId);
    _watchTerminalDone(handle);
  }

  /// Opens a terminal over [server]'s local serial port through the bridge
  /// helper.
  Future<void> openSerial(
    Server server, {
    String? paneId,
    String? initialOutput,
  }) async {
    // Serial ports are a native file-descriptor feature.
    if (kIsWeb) {
      throw UnsupportedError(
        'Serial terminals are not available in this browser.',
      );
    }
    final handle = await ref
        .read(serialConnectionManagerProvider)
        .openTerminal(server, initialOutput: initialOutput);
    final tab = TerminalTab(
      id: handle.id,
      serverId: server.id,
      serverName: server.name,
      terminal: handle.adapter,
      transport: TerminalTransport.serial,
    );
    _insertTab(tab, targetPaneId: paneId);
    _watchTerminalDone(handle);
  }

  /// Opens a terminal over [server]'s MaidCafe daemon WebSocket endpoint.
  ///
  /// [target] carries the resolved endpoint and credential so the caller can
  /// report "not configured" before a socket is opened. [onClose] runs when the
  /// tab goes away — a daemon reached through a temporary SSH forward stops it
  /// there, so the forward lives exactly as long as its terminal.
  Future<void> openMaidCafe(
    Server server,
    MaidCafeTerminalTarget target, {
    String? paneId,
    String? initialOutput,
    Future<void> Function()? onClose,
  }) async {
    final handle = await ref
        .read(maidCafeTerminalConnectionManagerProvider)
        .openTerminal(server, target, initialOutput: initialOutput);
    final tab = TerminalTab(
      id: handle.id,
      serverId: server.id,
      serverName: server.name,
      terminal: handle.adapter,
      transport: maidCafeTerminalTransport(target),
    );
    if (onClose != null) _tabCleanups[handle.id] = onClose;
    _insertTab(tab, targetPaneId: paneId);
    _watchTerminalDone(handle);
  }

  /// Opens [server]'s tmux session as one workspace tab.
  ///
  /// The tab starts with a single empty pane and is filled by the first
  /// `%layout-change` tmux reports: the session's own pane tree is the layout,
  /// so nothing is guessed here. Every pane mounts a [TerminalTab] whose
  /// adapter receives that tmux pane's output, and the binding owns the
  /// control client they all write through.
  Future<void> openTmux(
    Server server, {
    required String sessionName,
    required TmuxControlClient control,
    required Future<void> Function() closeTransport,
    required TerminalTransport transport,
    String? paneId,
  }) async {
    final existing = _tmuxTabs.entries
        .where(
          (entry) =>
              entry.value.sessionName == sessionName &&
              entry.value.serverId == server.id,
        )
        .firstOrNull;
    if (existing != null) {
      select(existing.key);
      // A tab whose channel dropped is still the same session with the same
      // panes and scrollback, so the fresh client reattaches it rather than
      // being thrown away: throwing it away would leave the user looking at a
      // detached terminal that can never come back.
      final previous = existing.value;
      if (previous.transportLost) {
        await previous.reattach(
          control: control,
          onEventStream: control.events,
          closeTransport: closeTransport,
          tabs: this,
        );
      } else {
        await releaseTmuxTransport(control, closeTransport);
      }
      return;
    }
    final binding = TmuxTabBinding(
      sessionName: sessionName,
      control: control,
      closeTransport: closeTransport,
      adapterFactory: ref.read(terminalSessionAdapterFactoryProvider),
      serverId: server.id,
      serverName: server.name,
      transport: transport,
      onEventStream: control.events,
    );
    final placeholderId = _uuid.v4();
    final tab = WorkspaceTab(
      id: placeholderId,
      panes: {placeholderId: TabPane(id: placeholderId)},
      layout: SessionLayoutLeaf(placeholderId),
      focusedPaneId: placeholderId,
    );
    _tmuxTabs[tab.id] = binding..tabId = tab.id;
    state = TerminalTabsState(
      tabs: [...state.tabs, tab],
      selectedTabId: paneId == null ? tab.id : state.selectedTabId,
    );
    if (paneId != null) {
      // The caller reserved a pane for this session. A tmux tab owns its own
      // panes, so the reserved one is dropped instead of staying empty beside
      // the session it was meant to show.
      final owner = _tabOwningPane(paneId);
      if (owner != null && owner.panes[paneId]?.isEmpty == true) {
        _removePane(owner, paneId);
      }
      select(tab.id);
    }
    binding.listen(() => this);
    // A session that yields no pane leaves nothing to mirror, so the tab it
    // opened is rolled back and the failure reported. The caller then falls
    // back to a plain terminal: an empty pane with no explanation is never the
    // outcome the user picked.
    try {
      await binding.initialize(this);
      if (binding.projected == null) {
        throw const TmuxControlException(
          'tmux did not report a layout for this session',
        );
      }
    } catch (_) {
      _tmuxTabs.remove(tab.id);
      if (ref.mounted) _removeTab(tab.id);
      await binding.dispose();
      rethrow;
    }
  }

  /// Opens (or reattaches) [sessionName] on [server] without a UI context.
  ///
  /// Used where no dialog can be shown: a restored workspace, and the
  /// background-session sheet, which has already resolved everything the
  /// transport needs. A session already on screen is selected, not reopened.
  Future<void> openTmuxSession(
    Server server, {
    required String sessionName,
    String? paneId,
  }) async {
    final repository = ref.read(serverRepositoryProvider);
    final target = await repository.maidCafeTerminalTargetFor(server);
    if (target != null) {
      final control = await ref
          .read(maidCafeTerminalConnectionManagerProvider)
          .openTmuxControl(server, target, sessionName: sessionName);
      await openTmux(
        server,
        sessionName: sessionName,
        control: control.control,
        transport: maidCafeTerminalTransport(target),
        closeTransport: control.close,
        paneId: paneId,
      );
      return;
    }
    final manager = ref.read(connectionManagerProvider);
    final tmuxPath =
        manager.tmuxPaths.cached(server.id) ??
        await manager.withClient(server.id, (client) => probeTmuxPath(client));
    manager.tmuxPaths.store(server.id, tmuxPath);
    if (tmuxPath == null) {
      throw const TmuxControlException('tmux is not installed on this host');
    }
    final credential = await repository.credentialFor(server);
    final proxy = await repository.proxyFor(server);
    final session = await manager.openTmuxControl(
      server,
      credential,
      (_) async => false,
      knownHostKeyFingerprint: server.hostKeyFingerprint,
      proxy: proxy,
      tmuxPath: tmuxPath,
      sessionName: sessionName,
      environment: decodeEnvironmentMap(server.environment),
    );
    await openTmux(
      server,
      sessionName: sessionName,
      control: session.control,
      transport: TerminalTransport.tmux,
      closeTransport: session.close,
      paneId: paneId,
    );
  }

  /// Projects [layout] (a tmux window's pane tree) onto the tab [binding] owns.
  ///
  /// Panes that appeared mount a [TerminalTab]; panes that disappeared lose
  /// theirs, adapters included. Re-parsing the same layout yields the same
  /// split ids, so an unchanged layout produces an equal tree and no rebuild.
  void applyTmuxLayout(TmuxTabBinding binding, SessionLayout layout) {
    if (!ref.mounted) return;
    final tabId = binding.tabId;
    if (tabId == null) return;
    final tab = state.tabById(tabId);
    if (tab == null) return;
    final paneIds = layout.paneIds.toList();
    if (paneIds.isEmpty) return;
    final panes = <String, TabPane>{};
    final gone = <String>{};
    for (final paneId in tab.panes.keys) {
      if (!paneIds.contains(paneId)) gone.add(paneId);
    }
    for (final paneId in paneIds) {
      final existing = tab.panes[paneId];
      if (existing?.tab case final TerminalTab content
          when content.tmux == binding) {
        panes[paneId] = existing!;
        continue;
      }
      final tmuxContentId = binding.contentIdForPane(paneId);
      panes[paneId] = TabPane(
        id: paneId,
        tab: TerminalTab(
          id: tmuxContentId,
          serverId: binding.serverId,
          serverName: binding.serverName,
          terminal: binding.adapterFor(paneId),
          transport: binding.transport,
          tmux: binding,
        ),
      );
    }
    for (final paneId in gone) {
      final content = tab.panes[paneId]?.tab;
      if (content != null) _forgetTmuxContent(content.id);
      unawaited(binding.releasePane(paneId));
    }
    final focusedPaneId = panes.containsKey(tab.focusedPaneId)
        ? tab.focusedPaneId
        : binding.focusedPaneId != null &&
              panes.containsKey(binding.focusedPaneId)
        ? binding.focusedPaneId!
        : paneIds.first;
    state = TerminalTabsState(
      tabs: [
        for (final candidate in state.tabs)
          candidate.id == tabId
              ? candidate.copyWith(
                  panes: panes,
                  layout: layout,
                  focusedPaneId: focusedPaneId,
                )
              : candidate,
      ],
      selectedTabId: state.selectedTabId,
    );
  }

  /// Removes a tmux tab whose session already ended.
  ///
  /// No close guard runs: the tmux session is gone, so there is nothing left to
  /// abandon, and the transport only has to be dropped.
  Future<void> closeTmuxTab(TmuxTabBinding binding, {String? reason}) async {
    final tabId = binding.tabId;
    if (!ref.mounted) return;
    if (tabId == null) return;
    _tmuxTabs.remove(tabId);
    final tab = state.tabById(tabId);
    if (tab != null) {
      for (final content in tab.tabs.toList()) {
        _forgetTmuxContent(content.id);
      }
    }
    await binding.dispose();
    // The tab can outlive a disposed workspace only in teardown, where a late
    // exit event must not touch state.
    if (!ref.mounted) return;
    _removeTab(tabId);
    final text = reason == null || reason.trim().isEmpty
        ? 'sessionsTmuxExited'.tr()
        : '${'sessionsTmuxExited'.tr()}: $reason';
    showStyledSnackBar(message: text, icon: Symbols.terminal);
  }

  /// Keeps a tmux tab whose channel dropped, and tells the panes about it.
  ///
  /// The session is still on the host with every process in it, so the tab
  /// stays exactly where it is. Closing it here would claim the work ended and
  /// would abandon a running task the user can still attach to.
  void markTmuxTransportLost(TmuxTabBinding binding) {
    if (!ref.mounted) return;
    final tabId = binding.tabId;
    if (tabId == null) return;
    binding.markTransportLost();
    final tab = state.tabById(tabId);
    if (tab == null) return;
    for (final content in tab.tabs.toList()) {
      if (content is! TerminalTab || content.tmux != binding) continue;
      content.terminal.replayHistory(
        '\r\n${'sessionsTmuxTransportLost'.tr(args: [binding.sessionName])}\r\n',
      );
    }
    showStyledSnackBar(
      message: 'sessionsTmuxTransportLost'.tr(args: [binding.sessionName]),
      title: 'sessionsTmuxStillRunning'.tr(),
      icon: Symbols.link_off,
    );
  }

  /// Drops a tmux transport a caller no longer needs: a second open of a
  /// session already on screen attaches nothing and leaves the extra client.
  Future<void> releaseTmuxTransport(
    TmuxControlClient control,
    Future<void> Function() closeTransport,
  ) async {
    try {
      await control.dispose();
    } catch (_) {}
    try {
      await closeTransport();
    } catch (_) {}
  }

  /// Forgets the view state of one tmux-mirrored pane, which is going away.
  void _forgetTmuxContent(String contentId) {
    _tabCleanups.remove(contentId);
    _releaseSessionTabViewKey(contentId);
    releaseTabNavigator(contentId);
    _lastBufferRows.remove(contentId);
    _cachedHistory.remove(contentId);
  }

  /// Opens [server]'s file manager.
  ///
  /// A named [paneId] mounts into that pane. [splitRight] instead splits the
  /// selected workspace tab to the right of its focused pane and mounts the
  /// file manager in the new pane — what the terminal's context menu does so
  /// the browser appears beside the terminal it was opened from. With neither,
  /// a new workspace tab opens.
  void openFileManagement(
    Server server, {
    String? initialPath,
    String? paneId,
    bool splitRight = false,
  }) {
    // The file manager browses a server over SFTP or the MaidCafe daemon's
    // file API. A browser has no socket for the former, so it needs a daemon
    // route rather than a blanket refusal.
    if (kIsWeb && !server.hasMaidCafeTerminalRoute) return;
    final tab = FileManagementTab(
      id: 'files-${DateTime.now().microsecondsSinceEpoch}',
      serverId: server.id,
      serverName: server.name,
      initialPath: initialPath ?? server.fileManagementInitialPath,
    );
    final owner = splitRight && paneId == null ? state.selectedTab : null;
    if (owner != null && canSplitTab(owner)) {
      _insertTab(
        tab,
        targetPaneId: _splitTab(owner, SessionSplitAxis.horizontal),
      );
      return;
    }
    _insertTab(tab, targetPaneId: paneId);
  }

  /// Opens [path] in a session editor tab. Reuses an existing tab for the same
  /// server + path + local/remote side.
  void openFileEditor({
    required Server server,
    required String path,
    required String fileName,
    required bool isRemote,
    String? paneId,
  }) {
    // The editor reads and writes through dart:io, SFTP or the daemon's file
    // API; a browser can only reach a remote file through the daemon.
    if (kIsWeb && (!isRemote || !server.hasMaidCafeTerminalRoute)) return;
    final existing = state.allTabs.whereType<FileEditorTab>().where((tab) {
      return tab.serverId == server.id &&
          tab.path == path &&
          tab.isRemote == isRemote;
    }).firstOrNull;
    if (existing != null) {
      select(existing.id);
      return;
    }
    final side = isRemote ? 'remote' : 'local';
    _insertTab(
      FileEditorTab(
        id: 'editor-$side-${server.id}-$path',
        serverId: server.id,
        serverName: server.name,
        fileName: fileName,
        path: path,
        isRemote: isRemote,
      ),
      targetPaneId: paneId,
    );
  }

  /// Opens [server]'s detail page, or mounts it in [paneId] when that pane is
  /// the empty one a split just made.
  ///
  /// A named pane is an explicit "mount here": it may hold a page the
  /// workspace already shows elsewhere, so the instance gets an id of its own.
  void openServerDetails(
    Server server, {
    int initialTab = 0,
    String? initialComposeProject,
    String? paneId,
  }) {
    final existing = paneId == null
        ? state.allTabs
              .whereType<ServerDetailTab>()
              .where((tab) => tab.serverId == server.id)
              .firstOrNull
        : null;
    if (existing != null) {
      select(existing.id);
      return;
    }
    _insertTab(
      ServerDetailTab(
        id: paneId == null
            ? 'server-${server.id}'
            : _instanceId('server-${server.id}'),
        server: server,
        initialTab: initialTab,
        initialComposeProject: initialComposeProject,
      ),
      targetPaneId: paneId,
    );
  }

  void openMaidCafePayload(Server server, {String? paneId}) {
    final existing = paneId == null
        ? state.allTabs
              .whereType<MaidCafePayloadSessionTab>()
              .where((tab) => tab.serverId == server.id)
              .firstOrNull
        : null;
    if (existing != null) {
      select(existing.id);
      return;
    }
    _insertTab(
      MaidCafePayloadSessionTab(
        id: paneId == null
            ? 'maidcafe-payload-${server.id}'
            : _instanceId('maidcafe-payload-${server.id}'),
        server: server,
      ),
      targetPaneId: paneId,
    );
  }

  /// Opens [tab] unless that destination is already open, in which case its
  /// tab is selected instead. A named [paneId] takes an instance of its own.
  void _openDestination(DestinationTab tab, {String? paneId}) {
    final existing = paneId == null
        ? state.allTabs
              .whereType<DestinationTab>()
              .where((candidate) => candidate.id == tab.id)
              .firstOrNull
        : null;
    if (existing != null) {
      select(existing.id);
      return;
    }
    _insertTab(tab, targetPaneId: paneId);
  }

  void openAssets({
    AssetsSection section = AssetsSection.connections,
    String? paneId,
  }) {
    final existing = state.allTabs
        .whereType<AssetsSessionTab>()
        .where((tab) => paneId == null || tab.id == 'assets')
        .firstOrNull;
    if (paneId != null) {
      _insertTab(
        AssetsSessionTab(section: section, id: _instanceId('assets')),
        targetPaneId: paneId,
      );
      return;
    }
    if (existing == null) {
      _insertTab(AssetsSessionTab(section: section));
      return;
    }
    if (existing.section != section) {
      _replaceTab(existing.copyWith(section: section));
    }
    select(existing.id);
  }

  /// Records the assets page the user switched to, so re-opening the tab from
  /// the launcher can land back on it.
  void setAssetsSection(String tabId, AssetsSection section) {
    final tab = state.allTabs
        .whereType<AssetsSessionTab>()
        .where((candidate) => candidate.id == tabId)
        .firstOrNull;
    if (tab == null || tab.section == section) return;
    _replaceTab(tab.copyWith(section: section));
  }

  void openProjects({String? paneId}) => _openDestination(
    paneId == null
        ? const ProjectsSessionTab()
        : ProjectsSessionTab(id: _instanceId('projects')),
    paneId: paneId,
  );

  void openMaidCafeCloud({String? paneId}) => _openDestination(
    paneId == null
        ? const MaidCafeCloudSessionTab()
        : MaidCafeCloudSessionTab(id: _instanceId('maidcafe-cloud')),
    paneId: paneId,
  );

  void openSettings({String? paneId}) => _openDestination(
    paneId == null
        ? const SettingsSessionTab()
        : SettingsSessionTab(id: _instanceId('settings')),
    paneId: paneId,
  );

  /// Shows the servers dashboard, opening it again when the workspace was
  /// emptied by closing every other tab. The dashboard is the workspace's home
  /// tab and cannot be closed, so without [paneId] this only ever selects it.
  void openDashboard({String? paneId}) {
    if (paneId != null) {
      _insertTab(
        DashboardTab(id: _instanceId('dashboard')),
        targetPaneId: paneId,
      );
      return;
    }
    final dashboard = state.allTabs.whereType<DashboardTab>().firstOrNull;
    if (dashboard != null) {
      select(dashboard.id);
      return;
    }
    _insertTab(const DashboardTab());
  }

  /// Opens a new agent chat tab — or mounts it in [paneId] — and returns it.
  AgentChatSessionTab openAgentChat({String title = '', String? paneId}) {
    final tab = AgentChatSessionTab(
      id: 'agent-${DateTime.now().microsecondsSinceEpoch}',
      title: title,
    );
    _insertTab(tab, targetPaneId: paneId);
    return tab;
  }

  /// Updates the strip label of an agent chat without touching the live chat
  /// state, which the tab body owns.
  void renameAgentChat(String tabId, String title) {
    final tab = _agentChat(tabId);
    if (tab == null || tab.title == title) return;
    _replaceTab(tab.copyWith(title: title));
  }

  /// Marks an agent chat as streaming so its chip can show activity.
  void setAgentChatWorking(String tabId, bool working) {
    final tab = _agentChat(tabId);
    if (tab == null || tab.working == working) return;
    _replaceTab(tab.copyWith(working: working));
  }

  AgentChatSessionTab? _agentChat(String tabId) => state.allTabs
      .whereType<AgentChatSessionTab>()
      .where((tab) => tab.id == tabId)
      .firstOrNull;

  /// Swaps one mounted instance for an updated one with the same id.
  void _replaceTab(SessionTab content) {
    var changed = false;
    final tabs = [
      for (final tab in state.tabs)
        if (tab.paneIdForContent(content.id) case final paneId?)
          () {
            changed = true;
            return tab.copyWith(
              panes: {
                ...tab.panes,
                paneId: tab.panes[paneId]!.withTab(content),
              },
            );
          }()
        else
          tab,
    ];
    if (!changed) return;
    state = TerminalTabsState(tabs: tabs, selectedTabId: state.selectedTabId);
  }

  /// Splits the selected tab, giving it a second, empty pane.
  ///
  /// The new pane belongs to the same tab — it is a second viewport of it, not
  /// another tab — and always opens on the pane intro, the same picker the
  /// workspace's command palette offers, so the user chooses what goes in it:
  /// a terminal on any host, the file manager, a server page, a destination.
  /// No content is cloned: a terminal and an agent chat own one live session,
  /// and a second view of a page is a decision for the user, not a side
  /// effect of splitting.
  ///
  /// The dashboard never splits: it is the workspace's home catalog and fills
  /// whatever pane it is in.
  void splitSelectedTab(SessionSplitAxis axis) {
    final tab = state.selectedTab;
    if (tab == null) {
      splitEmpty(axis);
      return;
    }
    if (!canSplitTab(tab)) return;
    // A tmux tab's panes are tmux's own: ask tmux to split, and let its
    // `%layout-change` add the pane here.
    final binding = _tmuxTabs[tab.id];
    if (binding != null) {
      binding.splitFocusedPane(axis);
      return;
    }
    _splitTab(tab, axis);
  }

  /// Opens a workspace tab that holds one empty pane, the same intro a split
  /// leaves behind, so Cmd/Ctrl+T starts from the picker instead of cloning
  /// whatever is on screen.
  void openEmptyTab() {
    final paneId = _uuid.v4();
    final next = WorkspaceTab(
      id: _uuid.v4(),
      panes: {paneId: TabPane(id: paneId)},
      layout: SessionLayoutLeaf(paneId),
      focusedPaneId: paneId,
    );
    state = TerminalTabsState(
      tabs: [...state.tabs, next],
      selectedTabId: next.id,
    );
  }

  /// Splits the selected tab into an empty sibling for the user to fill.
  void splitEmpty(SessionSplitAxis axis) {
    final tab = state.selectedTab;
    if (tab == null) {
      // No tab yet — start a workspace tab with one empty pane.
      openEmptyTab();
      return;
    }
    _splitTab(tab, axis);
  }

  /// Adds an empty pane to [tab], beside the focused one, and focuses it,
  /// returning the new pane's id so a caller can mount content straight into
  /// it.
  String _splitTab(WorkspaceTab tab, SessionSplitAxis axis) {
    final paneId = _uuid.v4();
    final nextTab = tab.copyWith(
      panes: {
        ...tab.panes,
        paneId: TabPane(id: paneId),
      },
      layout: splitPane(
        layout: tab.layout,
        focusedPaneId: tab.focusedPaneId,
        newPaneId: paneId,
        axis: axis,
        splitId: _uuid.v4(),
      ),
      focusedPaneId: paneId,
    );
    state = TerminalTabsState(
      tabs: [
        for (final candidate in state.tabs)
          candidate.id == tab.id ? nextTab : candidate,
      ],
      selectedTabId: tab.id,
    );
    return paneId;
  }

  /// Selects the workspace tab that owns [contentId] and focuses its pane.
  ///
  /// [contentId] is a mounted instance (a terminal, an editor, a destination)
  /// or a workspace tab id; both resolve to the tab the bar shows.
  void select(String contentId) {
    final owner = state.tabById(contentId) ?? state.tabForContent(contentId);
    if (owner == null) return;
    final paneId = owner.paneIdForContent(contentId);
    final next = paneId == null ? owner : owner.copyWith(focusedPaneId: paneId);
    state = TerminalTabsState(
      tabs: [
        for (final candidate in state.tabs)
          candidate.id == owner.id ? next : candidate,
      ],
      selectedTabId: owner.id,
    );
  }

  void selectTab(String tabId) {
    if (state.tabById(tabId) == null) return;
    if (state.selectedTabId == tabId) return;
    state = TerminalTabsState(tabs: state.tabs, selectedTabId: tabId);
  }

  void focusPane(String paneId) {
    final tab = state.selectedTab;
    if (tab == null || !tab.panes.containsKey(paneId)) return;
    if (tab.focusedPaneId == paneId) return;
    state = TerminalTabsState(
      tabs: [
        for (final candidate in state.tabs)
          candidate.id == tab.id
              ? candidate.copyWith(focusedPaneId: paneId)
              : candidate,
      ],
      selectedTabId: tab.id,
    );
  }

  /// Trades the slots of two panes of one tab.
  ///
  /// The pane keeps its id, content and state; only the layout leaves move, so
  /// a drag between two viewports rearranges the split instead of recreating
  /// its terminals. Nothing becomes focused: the user is moving a viewport,
  /// not switching to it.
  void swapPanes(String tabId, String fromPaneId, String toPaneId) {
    final tab = state.tabById(tabId);
    if (tab == null || fromPaneId == toPaneId) return;
    if (!tab.panes.containsKey(fromPaneId) ||
        !tab.panes.containsKey(toPaneId)) {
      return;
    }
    final layout = swapPaneSlots(tab.layout, fromPaneId, toPaneId);
    if (layout == tab.layout) return;
    state = TerminalTabsState(
      tabs: [
        for (final candidate in state.tabs)
          candidate.id == tabId
              ? candidate.copyWith(layout: layout)
              : candidate,
      ],
      selectedTabId: state.selectedTabId,
    );
  }

  /// Moves the tab at [fromIndex] so it sits before [toIndex].
  void moveTab(int fromIndex, int toIndex) {
    if (fromIndex < 0 || fromIndex >= state.tabs.length) return;
    if (toIndex < 0 || toIndex > state.tabs.length) return;
    if (fromIndex == toIndex || fromIndex + 1 == toIndex) return;
    final tabs = [...state.tabs];
    final tab = tabs.removeAt(fromIndex);
    tabs.insert(toIndex > fromIndex ? toIndex - 1 : toIndex, tab);
    state = TerminalTabsState(tabs: tabs, selectedTabId: state.selectedTabId);
  }

  void setSplitRatio(String tabId, String splitId, double ratio) {
    final tab = state.tabById(tabId);
    if (tab == null) return;
    // A tmux tab's sizes live in tmux. The ratio is kept locally for the drag,
    // and the `%layout-change` that answers the resize replaces the tree.
    final binding = _tmuxTabs[tabId];
    if (binding != null) {
      binding.applySplitRatio(splitId, ratio);
    }
    state = TerminalTabsState(
      tabs: [
        for (final candidate in state.tabs)
          candidate.id == tabId
              ? candidate.copyWith(
                  layout: applySplitRatio(candidate.layout, splitId, ratio),
                )
              : candidate,
      ],
      selectedTabId: state.selectedTabId,
    );
  }

  /// Asks before a close throws away work that is still in flight.
  ///
  /// A terminal dies with its shell and an agent chat dies with the reply it
  /// is still writing, so both ask first. Every close path — the tab's close
  /// button, Cmd/Ctrl+W, closing a pane — goes through [close], so they all
  /// ask the same question.
  Future<bool> _confirmCloseWhileWorking(SessionTab? tab) async {
    final detaching =
        tab is TerminalTab &&
        tab.tmux != null &&
        ref.read(detachOnCloseProvider);
    final message = switch (tab) {
      TerminalTab(:final terminal, :final tmux, serverName: final name)
          when tmux != null && terminal.currentTaskActivity.running =>
        detaching
            ? 'sessionsCloseTmuxTerminalMessage'.tr(args: [tmux.sessionName])
            : 'sessionsCloseRunningTerminalMessage'.tr(args: [name]),
      TerminalTab(serverName: final name, :final terminal)
          when terminal.currentTaskActivity.running =>
        'sessionsCloseRunningTerminalMessage'.tr(args: [name]),
      AgentChatSessionTab(working: true) =>
        'sessionsCloseWorkingChatMessage'.tr(),
      _ => null,
    };
    if (message == null) return true;
    return showMaidKitConfirmAlert(
      message,
      'sessionsCloseWorkingTabTitle'.tr(),
      isDanger: true,
    );
  }

  /// Closes one mounted instance, which closes its pane when it is the only
  /// thing there.
  Future<void> close(String contentId) async {
    final owner = state.tabForContent(contentId);
    if (owner == null) {
      // A workspace tab id: closing it closes the whole tab, panes included.
      await closeTab(contentId);
      return;
    }
    final paneId = owner.paneIdForContent(contentId);
    if (paneId == null) return;
    await closePaneInTab(owner.id, paneId);
  }

  /// Closes a whole workspace tab, every pane it owns.
  ///
  /// The home dashboard (`dashboard`) is the workspace's floor and stays. A
  /// dashboard mounted in a split pane is ordinary content and closes like any
  /// other.
  Future<void> closeTab(String tabId) async {
    final tab = state.tabById(tabId);
    if (tab == null || tabId == 'dashboard') return;
    for (final content in tab.tabs.toList()) {
      if (!await _confirmCloseWhileWorking(content)) return;
      if (content is FileEditorTab) {
        final guard = fileEditorCloseGuards[content.id];
        if (guard != null && !await guard()) return;
      }
    }
    for (final content in tab.tabs.toList()) {
      await _releaseContent(content);
    }
    _removeTab(tabId);
  }

  /// Closes [paneId] inside [tabId], with the content it shows.
  Future<void> closePaneInTab(String tabId, String paneId) async {
    final tab = state.tabById(tabId);
    final pane = tab?.panes[paneId];
    if (tab == null || pane == null) return;
    if (tabId == 'dashboard') return;
    if (tab.panes.length == 1) {
      await closeTab(tabId);
      return;
    }
    final content = pane.tab;
    if (content != null) {
      if (!await _confirmCloseWhileWorking(content)) return;
      if (content is FileEditorTab) {
        final guard = fileEditorCloseGuards[content.id];
        if (guard != null && !await guard()) return;
      }
    }
    // A tmux pane closes through tmux, which ends its processes; the pane and
    // its adapter disappear on the `%layout-change` that follows. A window
    // holding one pane falls through to the tab close instead, because killing
    // the last pane would end the session.
    final binding = _tmuxTabs[tabId];
    final terminal = content;
    if (binding != null &&
        terminal is TerminalTab &&
        terminal.tmux == binding &&
        tab.panes.length > 1) {
      final tmuxPane = binding.tmuxPaneForContentId(terminal.id) ?? paneId;
      binding.closePane(tmuxPane);
      return;
    }
    // The layout may have changed while the modal was open.
    final current = state.tabById(tabId);
    if (current == null || !current.panes.containsKey(paneId)) return;
    if (content != null) await _releaseContent(content);
    _removePane(current, paneId);
  }

  Future<void> closeForServer(int serverId) async {
    final tabIds = [
      for (final tab in state.tabs)
        if (tab.tabs.any((content) => content.serverId == serverId)) tab.id,
    ];
    await Future.wait(tabIds.map(closeTab));
  }

  /// Sends a saved shell snippet to the terminal identified by [terminalId].
  ///
  /// The script is passed as one quoted argument to the current shell. This
  /// keeps every line in the shell parser instead of allowing later lines to
  /// become stdin for the first command.
  void executeSnippet(String terminalId, ScriptSnippet snippet) {
    final content = state.contentById(terminalId);
    if (content is! TerminalTab) return;

    final script = snippet.script
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trimRight();
    if (script.trim().isEmpty) return;
    final quotedScript = "'${script.replaceAll("'", "'\\''")}'";
    content.terminal.sendInput('eval $quotedScript\n');
  }

  /// Runs the cleanup registered for [content] and forgets its view state.
  ///
  /// A tmux pane's teardown belongs to its whole tab: detaching or killing is
  /// one command for the session, and every pane of that tab goes with it.
  Future<void> _releaseContent(SessionTab content) async {
    final cleanup = _tabCleanups.remove(content.id);
    if (cleanup != null) await cleanup();
    if (content is TerminalTab) {
      final binding = content.tmux;
      if (binding != null) {
        await _teardownTmuxBinding(binding);
      } else {
        await ref.read(connectionManagerProvider).closeTerminal(content.id);
        // Idempotent for SSH terminal ids, closes serial and daemon sessions.
        await ref
            .read(serialConnectionManagerProvider)
            .closeTerminal(content.id);
        await ref
            .read(maidCafeTerminalConnectionManagerProvider)
            .closeTerminal(content.id);
      }
    }
    fileEditorCloseGuards.remove(content.id);
    _releaseSessionTabViewKey(content.id);
    releaseTabNavigator(content.id);
    _lastBufferRows.remove(content.id);
    _cachedHistory.remove(content.id);
  }

  /// Detaches or kills one tmux session, then releases its binding and tab.
  ///
  /// Detaching is the default: the process tree keeps running on the host, so
  /// the session is still there to attach to later. Killing ends it.
  Future<void> _teardownTmuxBinding(TmuxTabBinding binding) async {
    final tabId = binding.tabId;
    if (tabId == null) return;
    if (_tmuxTabs.remove(tabId) == null) return;
    try {
      if (ref.read(detachOnCloseProvider)) {
        await binding.detach();
      } else {
        await binding.killSession();
      }
    } catch (_) {
      // A transport that already dropped needs no detach.
    }
    await binding.dispose();
  }

  Future<TerminalSessionHandle> _openTerminalHandle(
    Server server,
    ServerCredential credential,
    HostKeyApproval approve, {
    String? knownHostKeyFingerprint,
    String? initialDirectory,
    List<String>? extraInitialScripts,
    ServerProxy? proxy,
    String? initialOutput,
    AuthChallengeApproval? approveAuth,
  }) async {
    final repository = ref.read(snippetRepositoryProvider);
    final initialScripts = <String>[];
    for (final id in decodeSnippetIdList(server.initialSnippets)) {
      final snippet = await repository.snippet(id);
      if (snippet != null) initialScripts.add(snippet.script);
    }
    initialScripts.addAll(extraInitialScripts ?? const <String>[]);
    return ref
        .read(connectionManagerProvider)
        .openTerminal(
          server,
          credential,
          approve,
          knownHostKeyFingerprint: knownHostKeyFingerprint,
          initialDirectory: initialDirectory,
          proxy: proxy,
          environment: decodeEnvironmentMap(server.environment),
          initialScripts: initialScripts,
          initialOutput: initialOutput,
          approveAuth: approveAuth,
        );
  }

  WorkspaceTab _newTab({required String paneId, SessionTab? content}) =>
      WorkspaceTab(
        id: content?.id ?? _uuid.v4(),
        panes: {paneId: TabPane(id: paneId, tab: content)},
        layout: SessionLayoutLeaf(paneId),
        focusedPaneId: paneId,
      );

  WorkspaceTab? _tabOwningPane(String paneId) {
    for (final tab in state.tabs) {
      if (tab.panes.containsKey(paneId)) return tab;
    }
    return null;
  }

  /// Mounts [tab] in an empty [targetPaneId] when one is named and still
  /// empty; otherwise it becomes a workspace tab of its own.
  void _insertTab(SessionTab tab, {String? targetPaneId}) {
    final owner = targetPaneId == null ? null : _tabOwningPane(targetPaneId);
    final pane = owner?.panes[targetPaneId];
    if (owner != null && pane != null && pane.isEmpty) {
      state = TerminalTabsState(
        tabs: [
          for (final candidate in state.tabs)
            candidate.id == owner.id
                ? candidate.copyWith(
                    panes: {...owner.panes, pane.id: pane.withTab(tab)},
                    focusedPaneId: pane.id,
                  )
                : candidate,
        ],
        selectedTabId: owner.id,
      );
      return;
    }
    final created = _newTab(paneId: _uuid.v4(), content: tab);
    state = TerminalTabsState(
      tabs: [...state.tabs, created],
      selectedTabId: created.id,
    );
  }

  void _watchTerminalDone(TerminalSessionHandle handle) {
    unawaited(
      handle.done.then<void>(
        (_) => _dropContent(handle.id),
        onError: (_, _) => _dropContent(handle.id),
      ),
    );
  }

  /// Drops a mounted instance whose session ended on its own: no close guard,
  /// no transport teardown, just its pane.
  void _dropContent(String contentId) {
    final owner = state.tabForContent(contentId);
    if (owner == null) return;
    final paneId = owner.paneIdForContent(contentId);
    if (paneId == null) return;
    _tabCleanups.remove(contentId);
    fileEditorCloseGuards.remove(contentId);
    _releaseSessionTabViewKey(contentId);
    releaseTabNavigator(contentId);
    _lastBufferRows.remove(contentId);
    _cachedHistory.remove(contentId);
    if (owner.panes.length == 1) {
      _removeTab(owner.id);
      return;
    }
    _removePane(owner, paneId);
  }

  void _removeTab(String tabId) {
    final index = state.tabs.indexWhere((tab) => tab.id == tabId);
    if (index < 0) return;
    for (final content in state.tabs[index].tabs) {
      _tabCleanups.remove(content.id);
      fileEditorCloseGuards.remove(content.id);
      _releaseSessionTabViewKey(content.id);
      releaseTabNavigator(content.id);
      _lastBufferRows.remove(content.id);
      _cachedHistory.remove(content.id);
    }
    final tabs = [...state.tabs]..removeAt(index);
    if (tabs.isEmpty) {
      state = const TerminalTabsState();
      return;
    }
    final selectedTabId = state.selectedTabId == tabId
        ? tabs[(index - 1).clamp(0, tabs.length - 1)].id
        : state.selectedTabId;
    state = TerminalTabsState(tabs: tabs, selectedTabId: selectedTabId);
  }

  void _removePane(WorkspaceTab tab, String paneId) {
    final layout = removePaneFromLayout(tab.layout, paneId);
    final panes = {...tab.panes}..remove(paneId);
    if (layout == null || panes.isEmpty) {
      _removeTab(tab.id);
      return;
    }
    final focusedPaneId = tab.focusedPaneId == paneId
        ? fallbackPaneAfterRemove(tab.layout, paneId, panes.keys.toList()) ??
              panes.keys.first
        : tab.focusedPaneId;
    state = TerminalTabsState(
      tabs: [
        for (final candidate in state.tabs)
          candidate.id == tab.id
              ? candidate.copyWith(
                  panes: panes,
                  layout: layout,
                  focusedPaneId: focusedPaneId,
                )
              : candidate,
      ],
      selectedTabId: state.selectedTabId,
    );
  }
}
