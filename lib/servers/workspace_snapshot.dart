import 'dart:convert';

import 'package:maid_kit/data/local/app_database.dart' hide WorkspaceSnapshot;
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/terminal_tabs_provider.dart';

/// The kind of content captured in a [WorkspaceContentSnapshot].
enum WorkspaceTabKind {
  dashboard,
  serverDetail,
  maidCafePayload,
  terminal,
  fileManagement,
  fileEditor,
  assets,
  projects,
  maidCafeCloud,
  settings;

  bool get isServerScoped => switch (this) {
    dashboard || assets || projects || maidCafeCloud || settings => false,
    serverDetail ||
    maidCafePayload ||
    terminal ||
    fileManagement ||
    fileEditor => true,
  };
}

/// One mounted instance captured in a [WorkspaceSnapshot].
///
/// A single flat shape (kind + optional fields) keeps the codec and the restore
/// switch small. Terminal tabs carry their OSC 7 working directory and
/// plain-text scrollback history; everything else is reconstructed from the
/// server id alone.
class WorkspaceContentSnapshot {
  const WorkspaceContentSnapshot({
    required this.id,
    required this.kind,
    this.serverId = -1,
    this.initialTab = 0,
    this.initialComposeProject,
    this.cwd,
    this.history,
    this.path,
    this.fileName,
    this.isRemote = false,
  });

  final String id;
  final WorkspaceTabKind kind;
  final int serverId;
  final int initialTab;
  final String? initialComposeProject;
  final String? cwd;
  final String? history;
  final String? path;
  final String? fileName;
  final bool isRemote;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'serverId': serverId,
    if (initialTab != 0) 'initialTab': initialTab,
    if (initialComposeProject != null)
      'initialComposeProject': initialComposeProject,
    if (cwd != null) 'cwd': cwd,
    if (history != null) 'history': history,
    if (path != null) 'path': path,
    if (fileName != null) 'fileName': fileName,
    if (isRemote) 'isRemote': isRemote,
  };

  static WorkspaceContentSnapshot? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final kind = WorkspaceTabKind.values
        .where((kind) => kind.name == json['kind'])
        .firstOrNull;
    if (id == null || kind == null) return null;
    return WorkspaceContentSnapshot(
      id: id,
      kind: kind,
      serverId: (json['serverId'] as num?)?.toInt() ?? -1,
      initialTab: (json['initialTab'] as num?)?.toInt() ?? 0,
      initialComposeProject: json['initialComposeProject'] as String?,
      cwd: json['cwd'] as String?,
      history: json['history'] as String?,
      path: json['path'] as String?,
      fileName: json['fileName'] as String?,
      isRemote: json['isRemote'] as bool? ?? false,
    );
  }
}

/// A serializable snapshot of the workspace, for the "restore last session"
/// feature.
///
/// Mirrors [TerminalTabsState]: a list of workspace tabs, each owning its own
/// binary [SessionLayout] tree and the content its panes mount. Credentials
/// never appear — tabs reference servers by id and rehydrate credentials on
/// restore.
class WorkspaceSnapshot {
  const WorkspaceSnapshot({
    this.version = currentVersion,
    this.tabs = const [],
    this.selectedTabId,
  });

  /// Version 2 stores layout per tab. Version 1 stored one layout for the whole
  /// workspace and tab lists inside each pane; [fromJson] converts it.
  static const int currentVersion = 2;

  final int version;
  final List<WorkspaceTabSnapshot> tabs;
  final String? selectedTabId;

  bool get isEmpty => tabs.isEmpty;

  /// Whether this is the pristine single-dashboard default, which must never
  /// overwrite a real snapshot on disk.
  bool get isPristineDefault =>
      tabs.length == 1 &&
      tabs.first.id == 'dashboard' &&
      tabs.first.panes.length == 1 &&
      tabs.first.panes.values.first?.kind == WorkspaceTabKind.dashboard;

  /// Captures [state], invoking [historyFor] to obtain each terminal's
  /// plain-text scrollback (cached by the caller when possible).
  factory WorkspaceSnapshot.capture(
    TerminalTabsState state, {
    required String Function(TerminalTab tab) historyFor,
  }) {
    return WorkspaceSnapshot(
      tabs: [
        for (final tab in state.tabs)
          WorkspaceTabSnapshot(
            id: tab.id,
            layout: tab.layout,
            focusedPaneId: tab.focusedPaneId,
            panes: {
              for (final pane in tab.panes.values)
                pane.id: switch (pane.tab) {
                  null => null,
                  // An agent chat only means something together with its
                  // conversation, which the snapshot does not carry.
                  AgentChatSessionTab() => null,
                  final DashboardTab content => WorkspaceContentSnapshot(
                    id: content.id,
                    kind: WorkspaceTabKind.dashboard,
                  ),
                  final AssetsSessionTab content => WorkspaceContentSnapshot(
                    id: content.id,
                    kind: WorkspaceTabKind.assets,
                    initialTab: content.section.index,
                  ),
                  final ProjectsSessionTab content => WorkspaceContentSnapshot(
                    id: content.id,
                    kind: WorkspaceTabKind.projects,
                  ),
                  final MaidCafeCloudSessionTab content =>
                    WorkspaceContentSnapshot(
                      id: content.id,
                      kind: WorkspaceTabKind.maidCafeCloud,
                    ),
                  final SettingsSessionTab content => WorkspaceContentSnapshot(
                    id: content.id,
                    kind: WorkspaceTabKind.settings,
                  ),
                  final ServerDetailTab content => WorkspaceContentSnapshot(
                    id: content.id,
                    kind: WorkspaceTabKind.serverDetail,
                    serverId: content.serverId,
                    initialTab: content.initialTab,
                    initialComposeProject: content.initialComposeProject,
                  ),
                  final MaidCafePayloadSessionTab content =>
                    WorkspaceContentSnapshot(
                      id: content.id,
                      kind: WorkspaceTabKind.maidCafePayload,
                      serverId: content.serverId,
                    ),
                  final TerminalTab content => WorkspaceContentSnapshot(
                    id: content.id,
                    kind: WorkspaceTabKind.terminal,
                    serverId: content.serverId,
                    cwd: content.terminal.currentDirectory,
                    history: historyFor(content),
                  ),
                  final FileManagementTab content => WorkspaceContentSnapshot(
                    id: content.id,
                    kind: WorkspaceTabKind.fileManagement,
                    serverId: content.serverId,
                    path: content.initialPath,
                  ),
                  final FileEditorTab content => WorkspaceContentSnapshot(
                    id: content.id,
                    kind: WorkspaceTabKind.fileEditor,
                    serverId: content.serverId,
                    fileName: content.fileName,
                    path: content.path,
                    isRemote: content.isRemote,
                  ),
                },
            },
          ),
      ],
      selectedTabId: state.selectedTabId,
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
    'tabs': [for (final tab in tabs) tab.toJson()],
    if (selectedTabId != null) 'selectedTabId': selectedTabId,
  };

  static WorkspaceSnapshot? fromJson(Map<String, dynamic> json) {
    final version = json['version'] as int? ?? 1;
    if (version > currentVersion) return null;
    if (version < 2) return _fromLegacyJson(json);
    final tabsRaw = json['tabs'];
    if (tabsRaw is! List) return null;
    final tabs = <WorkspaceTabSnapshot>[];
    for (final raw in tabsRaw) {
      if (raw is! Map<String, dynamic>) continue;
      final tab = WorkspaceTabSnapshot.fromJson(raw);
      if (tab != null) tabs.add(tab);
    }
    return WorkspaceSnapshot(
      tabs: tabs,
      selectedTabId: json['selectedTabId'] as String?,
    );
  }

  /// Converts the version 1 shape: one layout for the whole workspace, panes
  /// holding ordered tab lists. Each of those tabs becomes a workspace tab with
  /// a single pane, because a workspace tab now owns its own layout and a pane
  /// shows one thing.
  static WorkspaceSnapshot? _fromLegacyJson(Map<String, dynamic> json) {
    final panesRaw = json['panes'];
    final tabsRaw = json['tabs'];
    if (panesRaw is! Map<String, dynamic>) return null;
    final contents = <String, WorkspaceContentSnapshot>{};
    if (tabsRaw is List) {
      for (final raw in tabsRaw) {
        if (raw is! Map<String, dynamic>) continue;
        final content = WorkspaceContentSnapshot.fromJson(raw);
        if (content != null) contents[content.id] = content;
      }
    }
    final focusedPaneId = json['focusedPaneId'] as String?;
    final tabs = <WorkspaceTabSnapshot>[];
    String? selectedTabId;
    for (final entry in panesRaw.entries) {
      final pane = entry.value;
      if (pane is! Map<String, dynamic>) continue;
      final tabIds = pane['tabIds'];
      if (tabIds is! List) continue;
      final selectedTab = pane['selectedTabId'] as String?;
      for (final rawId in tabIds) {
        final content = contents[rawId.toString()];
        if (content == null) continue;
        final paneId = '${entry.key}:${content.id}';
        tabs.add(
          WorkspaceTabSnapshot(
            id: content.id,
            layout: SessionLayoutLeaf(paneId),
            focusedPaneId: paneId,
            panes: {paneId: content},
          ),
        );
        if (entry.key == focusedPaneId &&
            (selectedTab == content.id || selectedTab == null)) {
          selectedTabId = content.id;
        }
      }
    }
    // A legacy save without a focused pane still selected something.
    selectedTabId ??= tabs.firstOrNull?.id;
    return WorkspaceSnapshot(tabs: tabs, selectedTabId: selectedTabId);
  }

  static Map<String, Object?>? layoutToJson(SessionLayout? layout) {
    return switch (layout) {
      null => null,
      SessionLayoutLeaf leaf => {'type': 'leaf', 'paneId': leaf.paneId},
      SessionLayoutSplit split => {
        'type': 'split',
        'axis': split.axis.name,
        'ratio': split.ratio,
        'id': split.id,
        'first': layoutToJson(split.first),
        'second': layoutToJson(split.second),
      },
    };
  }

  static SessionLayout? layoutFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    switch (raw['type']) {
      case 'leaf':
        final paneId = raw['paneId'] as String?;
        if (paneId == null) return null;
        return SessionLayoutLeaf(paneId);
      case 'split':
        final first = raw['first'];
        final second = raw['second'];
        final id = raw['id'] as String?;
        if (id == null ||
            first is! Map<String, dynamic> ||
            second is! Map<String, dynamic>) {
          return null;
        }
        final axis = SessionSplitAxis.values
            .where((axis) => axis.name == raw['axis'])
            .firstOrNull;
        if (axis == null) return null;
        final left = layoutFromJson(first);
        final right = layoutFromJson(second);
        if (left == null || right == null) return null;
        return SessionLayoutSplit(
          id: id,
          axis: axis,
          first: left,
          second: right,
          ratio: (raw['ratio'] as num?)?.toDouble() ?? 0.5,
        );
      default:
        return null;
    }
  }
}

/// One workspace tab captured in a [WorkspaceSnapshot]: its pane arrangement,
/// plus what each pane shows (nothing while a pane waits for a session).
class WorkspaceTabSnapshot {
  const WorkspaceTabSnapshot({
    required this.id,
    required this.layout,
    required this.focusedPaneId,
    this.panes = const {},
  });

  final String id;
  final SessionLayout layout;
  final String focusedPaneId;

  /// Pane id → mounted content. A null value is an empty pane.
  final Map<String, WorkspaceContentSnapshot?> panes;

  Map<String, Object?> toJson() => {
    'id': id,
    'layout': WorkspaceSnapshot.layoutToJson(layout),
    'focusedPaneId': focusedPaneId,
    'panes': {
      for (final entry in panes.entries) entry.key: entry.value?.toJson(),
    },
  };

  static WorkspaceTabSnapshot? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final layout = WorkspaceSnapshot.layoutFromJson(json['layout']);
    final panesRaw = json['panes'];
    if (id == null || layout == null || panesRaw is! Map<String, dynamic>) {
      return null;
    }
    final panes = <String, WorkspaceContentSnapshot?>{};
    for (final entry in panesRaw.entries) {
      final raw = entry.value;
      panes[entry.key] = raw is Map<String, dynamic>
          ? WorkspaceContentSnapshot.fromJson(raw)
          : null;
    }
    final focusedPaneId = json['focusedPaneId'] as String?;
    return WorkspaceTabSnapshot(
      id: id,
      layout: layout,
      focusedPaneId: focusedPaneId != null && panes.containsKey(focusedPaneId)
          ? focusedPaneId
          : (panes.keys.firstOrNull ?? layout.paneIds.first),
      panes: panes,
    );
  }
}

/// A saved [WorkspaceSnapshot] together with the moment it was written.
///
/// The save time is the snapshot's identity for the dashboard: it is what
/// tells the workspace a user dismissed apart from a later one they have not
/// been asked about yet.
class StoredWorkspaceSnapshot {
  const StoredWorkspaceSnapshot(this.snapshot, this.updatedAt);

  final WorkspaceSnapshot snapshot;
  final DateTime updatedAt;
}

/// Whether the dashboard should offer to reopen [stored].
///
/// The offer only makes sense on a pristine workspace — restoring over live
/// tabs would clobber them — and a saved workspace the user dismissed stays
/// dismissed until a later save replaces it.
bool shouldOfferWorkspaceRestore({
  required TerminalTabsState tabs,
  required StoredWorkspaceSnapshot? stored,
  required DateTime? dismissedSnapshotAt,
}) {
  if (!tabs.isPristineDefault) return false;
  if (stored == null || stored.snapshot.isEmpty) return false;
  return dismissedSnapshotAt == null ||
      !dismissedSnapshotAt.isAtSameMomentAs(stored.updatedAt);
}

/// A terminal that needs a live session before its pane can show anything.
class PendingTerminalRestore {
  const PendingTerminalRestore({
    required this.paneId,
    required this.serverId,
    this.cwd,
    this.history,
    this.connectionType = ServerConnectionType.ssh,
  });

  final String paneId;
  final int serverId;
  final String? cwd;
  final String? history;

  /// Transport the terminal was on, so a restored tab reopens the same way.
  final ServerConnectionType connectionType;
}

/// A [WorkspaceSnapshot] resolved against the current server catalog: the tabs
/// that can be shown immediately, and the terminals that need a connection.
class ResolvedWorkspace {
  const ResolvedWorkspace({
    this.initialTabs = const [],
    this.pendingTerminals = const [],
    this.selectedTabId,
  });

  final List<WorkspaceTab> initialTabs;
  final List<PendingTerminalRestore> pendingTerminals;
  final String? selectedTabId;
}

/// Resolves [snapshot] against [serversById].
///
/// Content whose server no longer exists is dropped, which leaves its pane
/// empty rather than dropping the whole tab. Terminals become
/// [PendingTerminalRestore]s that the caller opens once connections are
/// available; their panes exist already and take the session when it lands.
ResolvedWorkspace resolveWorkspaceSnapshot(
  WorkspaceSnapshot snapshot,
  Map<int, Server> serversById,
) {
  final tabs = <WorkspaceTab>[];
  final pendingTerminals = <PendingTerminalRestore>[];
  String? selectedTabId;

  for (final spec in snapshot.tabs) {
    final panes = <String, TabPane>{};
    for (final paneId in spec.layout.paneIds) {
      final content = spec.panes[paneId];
      if (content == null) {
        panes[paneId] = TabPane(id: paneId);
        continue;
      }
      final server = serversById[content.serverId];
      if (content.kind.isServerScoped && server == null) {
        panes[paneId] = TabPane(id: paneId);
        continue;
      }
      if (content.kind == WorkspaceTabKind.terminal) {
        // The pane stays empty until the session connects; the terminal is
        // opened into it below, in snapshot order.
        panes[paneId] = TabPane(id: paneId);
        pendingTerminals.add(
          PendingTerminalRestore(
            paneId: paneId,
            serverId: content.serverId,
            cwd: content.cwd,
            history: content.history,
            connectionType: serverConnectionTypeFromName(
              server!.connectionType,
            ),
          ),
        );
        continue;
      }
      panes[paneId] = TabPane(
        id: paneId,
        tab: _contentFromSnapshot(content, server),
      );
    }
    final tab = WorkspaceTab(
      id: spec.id,
      panes: panes,
      layout: spec.layout,
      focusedPaneId: spec.focusedPaneId,
    );
    tabs.add(tab);
    if (spec.id == snapshot.selectedTabId) selectedTabId = tab.id;
  }

  return ResolvedWorkspace(
    initialTabs: tabs,
    pendingTerminals: pendingTerminals,
    selectedTabId: selectedTabId ?? tabs.firstOrNull?.id,
  );
}

SessionTab _contentFromSnapshot(WorkspaceContentSnapshot spec, Server? server) {
  return switch (spec.kind) {
    WorkspaceTabKind.dashboard => const DashboardTab(),
    WorkspaceTabKind.assets => AssetsSessionTab(
      section: AssetsSection
          .values[spec.initialTab.clamp(0, AssetsSection.values.length - 1)],
    ),
    WorkspaceTabKind.projects => const ProjectsSessionTab(),
    WorkspaceTabKind.maidCafeCloud => const MaidCafeCloudSessionTab(),
    WorkspaceTabKind.settings => const SettingsSessionTab(),
    WorkspaceTabKind.serverDetail => ServerDetailTab(
      id: spec.id,
      server: server!,
      initialTab: spec.initialTab,
      initialComposeProject: spec.initialComposeProject,
    ),
    WorkspaceTabKind.maidCafePayload => MaidCafePayloadSessionTab(
      id: spec.id,
      server: server!,
    ),
    WorkspaceTabKind.fileManagement => FileManagementTab(
      id: spec.id,
      serverId: spec.serverId,
      serverName: server!.name,
      initialPath: spec.path,
    ),
    WorkspaceTabKind.fileEditor => FileEditorTab(
      id: spec.id,
      serverId: spec.serverId,
      serverName: server!.name,
      fileName: spec.fileName ?? '',
      path: spec.path ?? '',
      isRemote: spec.isRemote,
    ),
    // Terminals need a live session, so they never reach this both.
    WorkspaceTabKind.terminal => throw StateError('terminal needs a session'),
  };
}
