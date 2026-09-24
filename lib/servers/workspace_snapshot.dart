import 'dart:convert';

import 'package:maid_kit/data/local/app_database.dart' hide WorkspaceSnapshot;
import 'package:maid_kit/servers/terminal_tabs_provider.dart';

/// The kind of workspace tab captured in a [WorkspaceTabSnapshot].
enum WorkspaceTabKind {
  dashboard,
  serverDetail,
  maidCafePayload,
  terminal,
  fileManagement,
  fileEditor;

  static WorkspaceTabKind? tryParse(String? raw) {
    for (final kind in WorkspaceTabKind.values) {
      if (kind.name == raw) return kind;
    }
    return null;
  }
}

/// One tab captured in a [WorkspaceSnapshot].
///
/// A single flat shape (kind + optional fields) keeps the codec and the
/// restore switch small. Terminal tabs carry their OSC 7 working directory
/// and plain-text scrollback history; everything else is reconstructed from
/// the server id alone.
class WorkspaceTabSnapshot {
  const WorkspaceTabSnapshot({
    required this.id,
    required this.kind,
    required this.serverId,
    this.cwd,
    this.history,
    this.path,
    this.fileName,
    this.isRemote = false,
    this.initialTab = 0,
    this.initialComposeProject,
  });

  final String id;
  final WorkspaceTabKind kind;
  final int serverId;

  /// Terminal: last OSC 7 working directory, if the shell reported one.
  final String? cwd;

  /// Terminal: plain-text scrollback history.
  final String? history;

  /// File-management / file-editor remote path.
  final String? path;

  /// File-editor file name.
  final String? fileName;

  /// File-editor side.
  final bool isRemote;

  /// Server-detail initial tab index.
  final int initialTab;

  /// Server-detail initial compose project.
  final String? initialComposeProject;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'serverId': serverId,
    if (cwd != null) 'cwd': cwd,
    if (history != null) 'history': history,
    if (path != null) 'path': path,
    if (fileName != null) 'fileName': fileName,
    if (isRemote) 'isRemote': isRemote,
    if (initialTab != 0) 'initialTab': initialTab,
    if (initialComposeProject != null)
      'initialComposeProject': initialComposeProject,
  };

  static WorkspaceTabSnapshot? fromJson(Map<String, dynamic> json) {
    final kind = WorkspaceTabKind.tryParse(json['kind'] as String?);
    final id = json['id'] as String?;
    final serverId = json['serverId'] as int?;
    if (kind == null || id == null || serverId == null) return null;
    return WorkspaceTabSnapshot(
      id: id,
      kind: kind,
      serverId: serverId,
      cwd: json['cwd'] as String?,
      history: json['history'] as String?,
      path: json['path'] as String?,
      fileName: json['fileName'] as String?,
      isRemote: json['isRemote'] as bool? ?? false,
      initialTab: json['initialTab'] as int? ?? 0,
      initialComposeProject: json['initialComposeProject'] as String?,
    );
  }
}

/// A serializable snapshot of the terminal workspace, for the "restore last
/// session" feature.
///
/// Mirrors [TerminalTabsState]: a binary [SessionLayout] tree of panes, each
/// owning an ordered tab strip with a selection. Credentials never appear —
/// tabs reference servers by id and rehydrate credentials on restore.
class WorkspaceSnapshot {
  const WorkspaceSnapshot({
    this.version = currentVersion,
    this.layout,
    this.panes = const {},
    this.tabs = const [],
    this.focusedPaneId,
  });

  static const int currentVersion = 1;

  final int version;
  final SessionLayout? layout;
  final Map<String, SessionPane> panes;
  final List<WorkspaceTabSnapshot> tabs;
  final String? focusedPaneId;

  bool get isEmpty => panes.isEmpty;

  /// Whether this is the pristine single-dashboard default, which must never
  /// overwrite a real snapshot on disk.
  bool get isPristineDefault =>
      panes.length == 1 &&
      panes.values.first.id == 'main' &&
      panes.values.first.tabIds.length == 1 &&
      panes.values.first.tabIds.first == 'dashboard' &&
      tabs.length == 1 &&
      tabs.first.kind == WorkspaceTabKind.dashboard &&
      layout is SessionLayoutLeaf;

  WorkspaceTabSnapshot? tabById(String id) {
    for (final tab in tabs) {
      if (tab.id == id) return tab;
    }
    return null;
  }

  /// Captures [state], invoking [historyFor] to obtain each terminal's
  /// plain-text scrollback (cached by the caller when possible).
  factory WorkspaceSnapshot.capture(
    TerminalTabsState state, {
    required String Function(TerminalTab tab) historyFor,
  }) {
    final tabs = <WorkspaceTabSnapshot>[
      for (final tab in state.tabs)
        switch (tab) {
          DashboardTab() => WorkspaceTabSnapshot(
            id: tab.id,
            kind: WorkspaceTabKind.dashboard,
            serverId: tab.serverId,
          ),
          ServerDetailTab() => WorkspaceTabSnapshot(
            id: tab.id,
            kind: WorkspaceTabKind.serverDetail,
            serverId: tab.serverId,
            initialTab: tab.initialTab,
            initialComposeProject: tab.initialComposeProject,
          ),
          MaidCafePayloadSessionTab() => WorkspaceTabSnapshot(
            id: tab.id,
            kind: WorkspaceTabKind.maidCafePayload,
            serverId: tab.serverId,
          ),
          TerminalTab() => WorkspaceTabSnapshot(
            id: tab.id,
            kind: WorkspaceTabKind.terminal,
            serverId: tab.serverId,
            cwd: tab.terminal.currentDirectory,
            history: historyFor(tab),
          ),
          FileManagementTab() => WorkspaceTabSnapshot(
            id: tab.id,
            kind: WorkspaceTabKind.fileManagement,
            serverId: tab.serverId,
            path: tab.initialPath,
          ),
          FileEditorTab() => WorkspaceTabSnapshot(
            id: tab.id,
            kind: WorkspaceTabKind.fileEditor,
            serverId: tab.serverId,
            fileName: tab.fileName,
            path: tab.path,
            isRemote: tab.isRemote,
          ),
        },
    ];
    return WorkspaceSnapshot(
      layout: state.layout,
      panes: state.panes,
      tabs: tabs,
      focusedPaneId: state.focusedPaneId,
    );
  }

  String encode() => jsonEncode(toJson());

  static WorkspaceSnapshot? decode(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      return fromJson(json);
    } on FormatException {
      return null;
    }
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'layout': _layoutToJson(layout),
    'panes': {
      for (final entry in panes.entries)
        entry.key: {
          'tabIds': entry.value.tabIds,
          if (entry.value.selectedTabId != null)
            'selectedTabId': entry.value.selectedTabId,
        },
    },
    'tabs': [for (final tab in tabs) tab.toJson()],
    if (focusedPaneId != null) 'focusedPaneId': focusedPaneId,
  };

  static WorkspaceSnapshot? fromJson(Map<String, dynamic> json) {
    final version = json['version'] as int? ?? currentVersion;
    if (version > currentVersion) return null;
    final layoutRaw = json['layout'];
    final layout = layoutRaw == null
        ? null
        : _layoutFromJson(layoutRaw as Map<String, dynamic>);
    final panesRaw = json['panes'];
    if (panesRaw is! Map<String, dynamic>) return null;
    final panes = <String, SessionPane>{};
    for (final entry in panesRaw.entries) {
      final pane = entry.value;
      if (pane is! Map<String, dynamic>) return null;
      final tabIds = pane['tabIds'];
      if (tabIds is! List) return null;
      panes[entry.key] = SessionPane(
        id: entry.key,
        tabIds: [for (final id in tabIds) id.toString()],
        selectedTabId: pane['selectedTabId'] as String?,
      );
    }
    final tabsRaw = json['tabs'];
    final tabs = <WorkspaceTabSnapshot>[];
    if (tabsRaw is List) {
      for (final raw in tabsRaw) {
        if (raw is! Map<String, dynamic>) continue;
        final tab = WorkspaceTabSnapshot.fromJson(raw);
        if (tab != null) tabs.add(tab);
      }
    }
    return WorkspaceSnapshot(
      version: version,
      layout: layout,
      panes: panes,
      tabs: tabs,
      focusedPaneId: json['focusedPaneId'] as String?,
    );
  }

  static Map<String, Object?>? _layoutToJson(SessionLayout? layout) {
    return switch (layout) {
      null => null,
      SessionLayoutLeaf leaf => {'type': 'leaf', 'paneId': leaf.paneId},
      SessionLayoutSplit split => {
        'type': 'split',
        'axis': split.axis.name,
        'ratio': split.ratio,
        'id': split.id,
        'first': _layoutToJson(split.first),
        'second': _layoutToJson(split.second),
      },
    };
  }

  static SessionLayout? _layoutFromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'leaf':
        final paneId = json['paneId'] as String?;
        if (paneId == null) return null;
        return SessionLayoutLeaf(paneId);
      case 'split':
        final first = json['first'];
        final second = json['second'];
        final id = json['id'] as String?;
        if (id == null ||
            first is! Map<String, dynamic> ||
            second is! Map<String, dynamic>) {
          return null;
        }
        final axis = SessionSplitAxis.values
            .where((axis) => axis.name == json['axis'])
            .firstOrNull;
        if (axis == null) return null;
        final left = _layoutFromJson(first);
        final right = _layoutFromJson(second);
        if (left == null || right == null) return null;
        return SessionLayoutSplit(
          id: id,
          axis: axis,
          first: left,
          second: right,
          ratio: (json['ratio'] as num?)?.toDouble() ?? 0.5,
        );
      default:
        return null;
    }
  }
}

/// A terminal tab that needs a live session before it can be opened.
class PendingTerminalRestore {
  const PendingTerminalRestore({
    required this.paneId,
    required this.serverId,
    this.cwd,
    this.history,
    this.isSerial = false,
  });

  final String paneId;
  final int serverId;
  final String? cwd;
  final String? history;
  final bool isSerial;
}

/// A [WorkspaceSnapshot] resolved against the current server catalog: which
/// tabs can be opened immediately and which terminals need connections.
class ResolvedWorkspace {
  const ResolvedWorkspace({
    this.layout,
    this.panes = const {},
    this.initialTabs = const [],
    this.pendingTerminals = const [],
    this.desiredPaneTabIds = const {},
    this.desiredPaneSelections = const {},
    this.focusedPaneId,
  });

  final SessionLayout? layout;
  final Map<String, SessionPane> panes;
  final List<SessionTab> initialTabs;
  final List<PendingTerminalRestore> pendingTerminals;

  /// Complete desired tab order per pane (including already-placed tabs).
  final Map<String, List<String>> desiredPaneTabIds;

  /// Desired selection per pane after restoration.
  final Map<String, String?> desiredPaneSelections;

  final String? focusedPaneId;
}

/// Resolves [snapshot] against [serversById].
///
/// Tabs whose server no longer exists are dropped. Every other tab is mapped
/// to a live [SessionTab]; terminals become [PendingTerminalRestore]s that
/// the caller opens once connections are available.
ResolvedWorkspace resolveWorkspaceSnapshot(
  WorkspaceSnapshot snapshot,
  Map<int, Server> serversById,
) {
  final panes = <String, SessionPane>{};
  final initialTabs = <SessionTab>[];
  final pendingTerminals = <PendingTerminalRestore>[];
  final desiredTabIds = <String, List<String>>{};
  final desiredSelections = <String, String?>{};

  for (final paneEntry in snapshot.panes.entries) {
    final pane = paneEntry.value;
    final resolvedIds = <String>[];
    final desiredIds = <String>[];
    for (final tabId in pane.tabIds) {
      final spec = snapshot.tabById(tabId);
      if (spec == null) continue;
      final server = serversById[spec.serverId];
      if (spec.kind != WorkspaceTabKind.dashboard && server == null) continue;
      // Full desired order, including deferred terminals: the restore flow
      // moves terminals into these slots once they connect.
      desiredIds.add(tabId);

      switch (spec.kind) {
        case WorkspaceTabKind.dashboard:
          initialTabs.add(DashboardTab());
          resolvedIds.add(DashboardTab().id);
        case WorkspaceTabKind.serverDetail:
          initialTabs.add(
            ServerDetailTab(
              id: spec.id,
              server: server!,
              initialTab: spec.initialTab,
              initialComposeProject: spec.initialComposeProject,
            ),
          );
          resolvedIds.add(spec.id);
        case WorkspaceTabKind.maidCafePayload:
          initialTabs.add(
            MaidCafePayloadSessionTab(id: spec.id, server: server!),
          );
          resolvedIds.add(spec.id);
        case WorkspaceTabKind.terminal:
          pendingTerminals.add(
            PendingTerminalRestore(
              paneId: pane.id,
              serverId: spec.serverId,
              cwd: spec.cwd,
              history: spec.history,
              isSerial: server!.connectionType == 'serial',
            ),
          );
          // The tab id is reserved in [desiredPaneTabIds] and re-inserted by
          // the caller once the terminal connects; it must not appear in the
          // pane before a live tab exists for it.
        case WorkspaceTabKind.fileManagement:
          initialTabs.add(
            FileManagementTab(
              id: spec.id,
              serverId: spec.serverId,
              serverName: server!.name,
              initialPath: spec.path,
            ),
          );
          resolvedIds.add(spec.id);
        case WorkspaceTabKind.fileEditor:
          initialTabs.add(
            FileEditorTab(
              id: spec.id,
              serverId: spec.serverId,
              serverName: server!.name,
              fileName: spec.fileName ?? '',
              path: spec.path ?? '',
              isRemote: spec.isRemote,
            ),
          );
          resolvedIds.add(spec.id);
      }
    }
    panes[pane.id] = SessionPane(
      id: pane.id,
      tabIds: resolvedIds,
      selectedTabId: resolvedIds.contains(pane.selectedTabId)
          ? pane.selectedTabId
          : (resolvedIds.isEmpty ? null : resolvedIds.last),
    );
    desiredTabIds[pane.id] = desiredIds;
    // The snapshot selection may name a deferred terminal; [select] ignores
    // ids without a live tab, so restoring it after connections is safe.
    desiredSelections[pane.id] = pane.selectedTabId;
  }

  return ResolvedWorkspace(
    layout: snapshot.layout,
    panes: panes,
    initialTabs: initialTabs,
    pendingTerminals: pendingTerminals,
    desiredPaneTabIds: desiredTabIds,
    desiredPaneSelections: desiredSelections,
    focusedPaneId: snapshot.focusedPaneId,
  );
}
