import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/snippets/snippet_repository.dart';
import 'server_models.dart';
import 'server_providers.dart';
import 'session_layout.dart';
import 'ssh_connection_manager.dart';
import 'terminal_session_adapter.dart';

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
}

/// Optional close confirmation for dirty file-editor tabs.
final Map<String, Future<bool> Function()> fileEditorCloseGuards = {};

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

class TerminalTab extends SessionTab {
  const TerminalTab({
    required super.id,
    required super.serverId,
    required super.serverName,
    required this.terminal,
  });

  final TerminalSessionAdapter terminal;

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

/// The persistent server overview, shown in the same pane tab system as live
/// terminals and file-management views.
class DashboardTab extends SessionTab {
  const DashboardTab()
    : super(id: 'dashboard', serverId: -1, serverName: 'Dashboard');

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

/// A pane owns a tab strip and shows one selected tab at a time.
///
/// A pane may be empty (`tabIds` is empty); empty panes show the session intro
/// so the user can choose what to open.
class SessionPane {
  const SessionPane({
    required this.id,
    this.tabIds = const [],
    this.selectedTabId,
  });

  final String id;
  final List<String> tabIds;
  final String? selectedTabId;

  bool get isEmpty => tabIds.isEmpty;

  SessionPane copyWith({List<String>? tabIds, String? selectedTabId}) =>
      SessionPane(
        id: id,
        tabIds: tabIds ?? this.tabIds,
        selectedTabId: selectedTabId ?? this.selectedTabId,
      );

  SessionPane withTab(String tabId) =>
      SessionPane(id: id, tabIds: [...tabIds, tabId], selectedTabId: tabId);

  SessionPane withTabAt(String tabId, int index) {
    final ids = [...tabIds]..remove(tabId);
    final insertAt = index.clamp(0, ids.length);
    ids.insert(insertAt, tabId);
    return SessionPane(id: id, tabIds: ids, selectedTabId: tabId);
  }

  SessionPane withoutTab(String tabId) {
    final index = tabIds.indexOf(tabId);
    final nextIds = [...tabIds]..remove(tabId);
    if (nextIds.isEmpty) {
      return SessionPane(id: id, tabIds: const []);
    }
    final String? nextSelected;
    if (selectedTabId == tabId) {
      nextSelected = nextIds[(index - 1).clamp(0, nextIds.length - 1)];
    } else if (nextIds.contains(selectedTabId)) {
      nextSelected = selectedTabId;
    } else {
      nextSelected = nextIds.last;
    }
    return SessionPane(id: id, tabIds: nextIds, selectedTabId: nextSelected);
  }
}

class TerminalTabsState {
  const TerminalTabsState({
    this.tabs = const [],
    this.panes = const {},
    this.layout,
    this.focusedPaneId,
  });

  final List<SessionTab> tabs;
  final Map<String, SessionPane> panes;

  /// Arrangement of panes. Null when no panes are open.
  final SessionLayout? layout;
  final String? focusedPaneId;

  SessionPane? get focusedPane =>
      focusedPaneId == null ? null : panes[focusedPaneId];

  /// Tab selected in the focused pane (drives status bar, palette, etc.).
  SessionTab? get selectedTab {
    final tabId = focusedPane?.selectedTabId;
    if (tabId == null) return null;
    return tabs.where((tab) => tab.id == tabId).firstOrNull;
  }

  String? get selectedId => selectedTab?.id;

  bool get hasSplits => layout?.isSplit ?? false;

  /// Workspace is empty when there are no panes (not merely no tabs).
  bool get isEmpty => panes.isEmpty;
  bool get isNotEmpty => panes.isNotEmpty;

  List<SessionTab> tabsInPane(String paneId) {
    final pane = panes[paneId];
    if (pane == null) return const [];
    final byId = {for (final tab in tabs) tab.id: tab};
    return [for (final id in pane.tabIds) ?byId[id]];
  }

  SessionTab? selectedTabInPane(String paneId) {
    final tabId = panes[paneId]?.selectedTabId;
    if (tabId == null) return null;
    return tabs.where((tab) => tab.id == tabId).firstOrNull;
  }

  String? paneIdForTab(String tabId) {
    for (final pane in panes.values) {
      if (pane.tabIds.contains(tabId)) return pane.id;
    }
    return null;
  }
}

final terminalTabsProvider =
    NotifierProvider<TerminalTabsNotifier, TerminalTabsState>(
      TerminalTabsNotifier.new,
    );

/// Holds live terminal tabs for the entire app lifetime.
///
/// This provider deliberately is not auto-disposed, so terminals continue to
/// receive output while the user visits another workspace page.
class TerminalTabsNotifier extends Notifier<TerminalTabsState> {
  static const _uuid = Uuid();

  @override
  TerminalTabsState build() {
    const dashboard = DashboardTab();
    const pane = SessionPane(
      id: 'main',
      tabIds: ['dashboard'],
      selectedTabId: 'dashboard',
    );
    return const TerminalTabsState(
      tabs: [dashboard],
      panes: {'main': pane},
      layout: SessionLayoutLeaf('main'),
      focusedPaneId: 'main',
    );
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
  }) async {
    if (paneId != null) focusPane(paneId);
    final handle = await _openTerminalHandle(
      server,
      credential,
      approve,
      knownHostKeyFingerprint: knownHostKeyFingerprint,
      initialDirectory: initialDirectory,
      extraInitialScripts: initialScripts,
      proxy: proxy,
    );
    final tab = TerminalTab(
      id: handle.id,
      serverId: server.id,
      serverName: server.name,
      terminal: handle.adapter,
    );
    _insertTab(tab, targetPaneId: paneId);
    _watchTerminalDone(handle);
  }

  /// Opens a terminal over [server]'s local serial port through the bridge
  /// helper.
  Future<void> openSerial(Server server, {String? paneId}) async {
    if (paneId != null) focusPane(paneId);
    final handle = await ref
        .read(serialConnectionManagerProvider)
        .openTerminal(server);
    final tab = TerminalTab(
      id: handle.id,
      serverId: server.id,
      serverName: server.name,
      terminal: handle.adapter,
    );
    _insertTab(tab, targetPaneId: paneId);
    _watchTerminalDone(handle);
  }

  /// Opens a shell on the machine MaidKit runs on, bypassing SSH entirely.
  Future<void> openLocal(
    Server server, {
    String? paneId,
    String? initialDirectory,
  }) async {
    if (paneId != null) focusPane(paneId);
    final handle = await ref
        .read(localConnectionManagerProvider)
        .openTerminal(server, initialDirectory: initialDirectory);
    final tab = TerminalTab(
      id: handle.id,
      serverId: server.id,
      serverName: server.name,
      terminal: handle.adapter,
    );
    _insertTab(tab, targetPaneId: paneId);
    _watchTerminalDone(handle);
  }

  void openFileManagement(
    Server server, {
    String? initialPath,
    String? paneId,
  }) {
    if (paneId != null) focusPane(paneId);
    final tab = FileManagementTab(
      id: 'files-${DateTime.now().microsecondsSinceEpoch}',
      serverId: server.id,
      serverName: server.name,
      initialPath: initialPath ?? server.fileManagementInitialPath,
    );
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
    final existing = state.tabs.whereType<FileEditorTab>().where((tab) {
      return tab.serverId == server.id &&
          tab.path == path &&
          tab.isRemote == isRemote;
    }).firstOrNull;
    if (existing != null) {
      select(existing.id);
      return;
    }
    if (paneId != null) focusPane(paneId);
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

  void openServerDetails(
    Server server, {
    int initialTab = 0,
    String? initialComposeProject,
    String? paneId,
  }) {
    final existing = state.tabs
        .whereType<ServerDetailTab>()
        .where((tab) => tab.serverId == server.id)
        .firstOrNull;
    if (existing != null) {
      select(existing.id);
      return;
    }
    if (paneId != null) focusPane(paneId);
    _insertTab(
      ServerDetailTab(
        id: 'server-${server.id}',
        server: server,
        initialTab: initialTab,
        initialComposeProject: initialComposeProject,
      ),
      targetPaneId: paneId,
    );
  }

  void openMaidCafePayload(Server server, {String? paneId}) {
    final existing = state.tabs
        .whereType<MaidCafePayloadSessionTab>()
        .where((tab) => tab.serverId == server.id)
        .firstOrNull;
    if (existing != null) {
      select(existing.id);
      return;
    }
    if (paneId != null) focusPane(paneId);
    _insertTab(
      MaidCafePayloadSessionTab(
        id: 'maidcafe-payload-${server.id}',
        server: server,
      ),
      targetPaneId: paneId,
    );
  }

  /// Splits the focused pane and opens an empty sibling for the user to fill.
  void splitEmpty(SessionSplitAxis axis) {
    final focusId = state.focusedPaneId;
    final layout = state.layout;
    if (focusId == null || layout == null || !layout.containsPane(focusId)) {
      // No pane yet — create a single empty workspace pane.
      final paneId = _uuid.v4();
      state = TerminalTabsState(
        tabs: state.tabs,
        panes: {paneId: SessionPane(id: paneId)},
        layout: SessionLayoutLeaf(paneId),
        focusedPaneId: paneId,
      );
      return;
    }

    final newPaneId = _uuid.v4();
    final nextLayout = splitPane(
      layout: layout,
      focusedPaneId: focusId,
      newPaneId: newPaneId,
      axis: axis,
      splitId: _uuid.v4(),
    );
    final panes = Map<String, SessionPane>.from(state.panes)
      ..[newPaneId] = SessionPane(id: newPaneId);
    state = TerminalTabsState(
      tabs: state.tabs,
      panes: panes,
      layout: nextLayout,
      focusedPaneId: newPaneId,
    );
  }

  void focusPane(String paneId) {
    if (!state.panes.containsKey(paneId)) return;
    if (state.focusedPaneId == paneId) return;
    state = TerminalTabsState(
      tabs: state.tabs,
      panes: state.panes,
      layout: state.layout,
      focusedPaneId: paneId,
    );
  }

  /// Selects [tabId] within its pane and focuses that pane.
  void select(String tabId) {
    final paneId = state.paneIdForTab(tabId);
    if (paneId == null) return;
    final pane = state.panes[paneId]!;
    final panes = Map<String, SessionPane>.from(state.panes)
      ..[paneId] = pane.copyWith(selectedTabId: tabId);
    state = TerminalTabsState(
      tabs: state.tabs,
      panes: panes,
      layout: state.layout,
      focusedPaneId: paneId,
    );
  }

  /// Moves [tabId] into [toPaneId].
  ///
  /// [toIndex] means “insert before this index” in the destination’s current
  /// order. When null, the tab is appended. Supports reordering within a pane
  /// and moving across panes.
  void moveTab(String tabId, String toPaneId, {int? toIndex}) {
    final fromPaneId = state.paneIdForTab(tabId);
    if (fromPaneId == null) return;
    final toPane = state.panes[toPaneId];
    if (toPane == null) return;

    final panes = Map<String, SessionPane>.from(state.panes);

    if (fromPaneId == toPaneId) {
      final pane = panes[fromPaneId]!;
      final oldIndex = pane.tabIds.indexOf(tabId);
      if (oldIndex < 0) return;
      // Insert-before semantics on the pre-removal list (ReorderableListView style).
      var insertAt = toIndex ?? pane.tabIds.length;
      if (insertAt > pane.tabIds.length) insertAt = pane.tabIds.length;
      // Dropping on self or immediately after self is a no-op.
      if (insertAt == oldIndex || insertAt == oldIndex + 1) {
        // Still select/focus the tab.
        if (pane.selectedTabId != tabId || state.focusedPaneId != toPaneId) {
          panes[fromPaneId] = pane.copyWith(selectedTabId: tabId);
          state = TerminalTabsState(
            tabs: state.tabs,
            panes: panes,
            layout: state.layout,
            focusedPaneId: toPaneId,
          );
        }
        return;
      }
      final ids = [...pane.tabIds]..removeAt(oldIndex);
      if (insertAt > oldIndex) insertAt -= 1;
      ids.insert(insertAt.clamp(0, ids.length), tabId);
      if (_listEquals(ids, pane.tabIds)) return;
      panes[fromPaneId] = SessionPane(
        id: fromPaneId,
        tabIds: ids,
        selectedTabId: tabId,
      );
    } else {
      final fromPane = panes[fromPaneId]!;
      panes[fromPaneId] = fromPane.withoutTab(tabId);
      final dest = panes[toPaneId]!;
      final ids = [...dest.tabIds];
      final insertAt = (toIndex ?? ids.length).clamp(0, ids.length);
      ids.insert(insertAt, tabId);
      panes[toPaneId] = SessionPane(
        id: toPaneId,
        tabIds: ids,
        selectedTabId: tabId,
      );
    }

    state = TerminalTabsState(
      tabs: state.tabs,
      panes: panes,
      layout: state.layout,
      focusedPaneId: toPaneId,
    );
  }

  void setSplitRatio(String splitId, double ratio) {
    final current = state.layout;
    if (current == null) return;
    state = TerminalTabsState(
      tabs: state.tabs,
      panes: state.panes,
      layout: applySplitRatio(current, splitId, ratio),
      focusedPaneId: state.focusedPaneId,
    );
  }

  Future<void> close(String tabId) async {
    final tab = state.tabs.where((tab) => tab.id == tabId).firstOrNull;
    if (tab is DashboardTab) return;
    if (tab is FileEditorTab) {
      final guard = fileEditorCloseGuards[tabId];
      if (guard != null && !await guard()) return;
    }
    if (tab is TerminalTab) {
      await ref.read(connectionManagerProvider).closeTerminal(tabId);
      // Idempotent for SSH terminal ids, closes serial sessions.
      await ref.read(serialConnectionManagerProvider).closeTerminal(tabId);
      // Idempotent for SSH/serial ids, closes local shells.
      await ref.read(localConnectionManagerProvider).closeTerminal(tabId);
    }
    fileEditorCloseGuards.remove(tabId);
    _removeTab(tabId);
  }

  /// Sends a saved shell snippet to the terminal identified by [terminalId].
  ///
  /// The script is passed as one quoted argument to the current shell. This
  /// keeps every line in the shell parser instead of allowing later lines to
  /// become stdin for the first command.
  void executeSnippet(String terminalId, ScriptSnippet snippet) {
    final tab = state.tabs.where((tab) => tab.id == terminalId).firstOrNull;
    if (tab is! TerminalTab) return;

    final script = snippet.script
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trimRight();
    if (script.trim().isEmpty) return;
    final quotedScript = "'${script.replaceAll("'", "'\\''")}'";
    tab.terminal.sendInput('eval $quotedScript\n');
  }

  /// Closes every tab in [paneId] and removes the pane from the layout.
  Future<void> closePane(String paneId) async {
    final pane = state.panes[paneId];
    if (pane == null) return;
    if (pane.tabIds.contains(DashboardTab().id)) return;
    final tabIds = [...pane.tabIds];
    for (final tabId in tabIds) {
      // Route through [close] so dirty file editors can confirm discard.
      await close(tabId);
      // User cancelled closing a dirty editor — keep the pane.
      if (state.tabs.any((tab) => tab.id == tabId)) return;
    }
    if (state.panes.containsKey(paneId)) {
      _removePane(paneId, alsoRemoveTabs: const []);
    }
  }

  Future<void> closeForServer(int serverId) async {
    final tabIds = state.tabs
        .where((tab) => tab.serverId == serverId)
        .map((tab) => tab.id)
        .toList();
    await Future.wait(tabIds.map(close));
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<TerminalSessionHandle> _openTerminalHandle(
    Server server,
    ServerCredential credential,
    HostKeyApproval approve, {
    String? knownHostKeyFingerprint,
    String? initialDirectory,
    List<String>? extraInitialScripts,
    ServerProxy? proxy,
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
        );
  }

  void _insertTab(SessionTab tab, {String? targetPaneId}) {
    final preferredId = targetPaneId ?? state.focusedPaneId;
    final target = preferredId == null ? null : state.panes[preferredId];

    if (target != null) {
      final panes = Map<String, SessionPane>.from(state.panes)
        ..[target.id] = target.withTab(tab.id);
      state = TerminalTabsState(
        tabs: [...state.tabs, tab],
        panes: panes,
        layout: state.layout ?? SessionLayoutLeaf(target.id),
        focusedPaneId: target.id,
      );
      return;
    }

    // First pane: create a single-pane workspace.
    final paneId = _uuid.v4();
    final pane = SessionPane(
      id: paneId,
      tabIds: [tab.id],
      selectedTabId: tab.id,
    );
    state = TerminalTabsState(
      tabs: [...state.tabs, tab],
      panes: {paneId: pane},
      layout: SessionLayoutLeaf(paneId),
      focusedPaneId: paneId,
    );
  }

  void _watchTerminalDone(TerminalSessionHandle handle) {
    unawaited(
      handle.done.then<void>(
        (_) => _removeTab(handle.id),
        onError: (_, _) => _removeTab(handle.id),
      ),
    );
  }

  void _removeTab(String tabId) {
    final tabIndex = state.tabs.indexWhere((tab) => tab.id == tabId);
    if (tabIndex < 0) return;
    _releaseSessionTabViewKey(tabId);

    final paneId = state.paneIdForTab(tabId);
    final tabs = [...state.tabs]..removeAt(tabIndex);
    var panes = Map<String, SessionPane>.from(state.panes);

    if (paneId != null && panes[paneId] != null) {
      // Keep empty panes so the intro can be shown again.
      panes[paneId] = panes[paneId]!.withoutTab(tabId);
    }

    // Drop dangling tab references only; do not remove empty panes here.
    for (final entry in panes.entries.toList()) {
      final validIds = entry.value.tabIds
          .where((id) => tabs.any((t) => t.id == id))
          .toList();
      if (validIds.length != entry.value.tabIds.length) {
        final selected = validIds.contains(entry.value.selectedTabId)
            ? entry.value.selectedTabId
            : (validIds.isEmpty ? null : validIds.last);
        panes[entry.key] = SessionPane(
          id: entry.key,
          tabIds: validIds,
          selectedTabId: selected,
        );
      }
    }

    // If the only remaining state is a single empty pane with no tabs at all
    // in the workspace, clear back to the full empty intro.
    final hasAnyTabs = tabs.isNotEmpty;
    if (!hasAnyTabs && panes.length == 1 && panes.values.first.isEmpty) {
      state = const TerminalTabsState();
      return;
    }

    if (panes.isEmpty) {
      state = const TerminalTabsState();
      return;
    }

    var focusedPaneId = state.focusedPaneId;
    if (focusedPaneId != null && !panes.containsKey(focusedPaneId)) {
      focusedPaneId = panes.keys.firstOrNull;
    }

    state = TerminalTabsState(
      tabs: tabs,
      panes: panes,
      layout: state.layout,
      focusedPaneId: focusedPaneId,
    );
  }

  void _removePane(String paneId, {required List<String> alsoRemoveTabs}) {
    for (final tabId in alsoRemoveTabs) {
      _releaseSessionTabViewKey(tabId);
    }
    final tabs = state.tabs
        .where((tab) => !alsoRemoveTabs.contains(tab.id))
        .toList();
    final panes = Map<String, SessionPane>.from(state.panes)..remove(paneId);
    final previousLayout = state.layout;
    var layout = previousLayout == null
        ? null
        : removePaneFromLayout(previousLayout, paneId);

    var focusedPaneId = state.focusedPaneId == paneId
        ? fallbackPaneAfterRemove(previousLayout, paneId, panes.keys.toList())
        : state.focusedPaneId;

    if (focusedPaneId != null && !panes.containsKey(focusedPaneId)) {
      focusedPaneId = panes.keys.firstOrNull;
    }

    if (panes.isEmpty || layout == null) {
      state = const TerminalTabsState();
      return;
    }

    // Single empty pane left with no tabs → full workspace intro.
    if (tabs.isEmpty && panes.length == 1 && panes.values.first.isEmpty) {
      state = const TerminalTabsState();
      return;
    }

    state = TerminalTabsState(
      tabs: tabs,
      panes: panes,
      layout: layout,
      focusedPaneId: focusedPaneId,
    );
  }
}
