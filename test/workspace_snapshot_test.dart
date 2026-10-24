import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/data/local/app_database.dart' hide WorkspaceSnapshot;
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/terminal_session_adapter.dart';
import 'package:maid_kit/servers/terminal_tabs_provider.dart';
import 'package:maid_kit/servers/workspace_snapshot.dart';

Server _server({int id = 1, String type = 'ssh'}) => Server(
  id: id,
  name: 'Server $id',
  host: '10.0.0.$id',
  port: 22,
  username: 'root',
  collectStats: true,
  collectSystemInfo: true,
  connectionType: type,
  maidCafeTerminalViaCloud: false,
);

class _FakeAdapter implements TerminalSessionAdapter {
  _FakeAdapter({this.directory, this.history});

  final String? directory;
  final String? history;

  @override
  int get bufferRows => 100;

  @override
  String? get currentDirectory => directory;

  @override
  String? dumpHistory({int maxLines = 4000}) => history;

  @override
  void replayHistory(String text) {}

  @override
  Stream<Uint8List> get outgoingBytes => const Stream.empty();

  @override
  Stream<TerminalResize> get resizeEvents => const Stream.empty();

  @override
  Stream<bool> get taskRunning => const Stream.empty();

  @override
  Stream<TerminalTaskActivity> get taskActivity => const Stream.empty();

  @override
  bool get isTaskRunning => false;

  @override
  TerminalTaskActivity get currentTaskActivity =>
      const TerminalTaskActivity(running: false);

  @override
  SudoPromptReason? get sudoAutofillReady => null;

  @override
  void bindSudoAutofill(Stream<SudoPromptReason?> reasons) {}

  @override
  void write(Uint8List bytes) {}

  @override
  void sendInput(String text) {}

  @override
  void showKeyboard() {}

  @override
  void hideKeyboard() {}

  @override
  Rect? get cursorGlobalRect => null;

  @override
  Widget buildView({
    bool autofocus = false,
    bool readOnly = false,
    bool showCursor = true,
    VoidCallback? onOpenFileManagement,
    bool? transparentBackground,
    FocusOnKeyEventCallback? onKeyEvent,
  }) => const SizedBox.shrink();

  @override
  int find(String query, {bool caseSensitive = false}) => 0;

  @override
  void findJump(int index) {}

  @override
  void findClear() {}

  @override
  Future<void> dispose() async {}
}

/// One workspace tab per content, except the split one: a tab holding a
/// terminal and a file manager in two panes is the shape this test is about.
WorkspaceSnapshot _fullSnapshot() {
  return const WorkspaceSnapshot(
    tabs: [
      WorkspaceTabSnapshot(
        id: 'dashboard',
        layout: SessionLayoutLeaf('main'),
        focusedPaneId: 'main',
        panes: {
          'main': WorkspaceContentSnapshot(
            id: 'dashboard',
            kind: WorkspaceTabKind.dashboard,
          ),
        },
      ),
      WorkspaceTabSnapshot(
        id: 'term-1',
        layout: SessionLayoutSplit(
          id: 'split-1',
          axis: SessionSplitAxis.horizontal,
          ratio: 0.5,
          first: SessionLayoutLeaf('term-pane'),
          second: SessionLayoutLeaf('files-pane'),
        ),
        focusedPaneId: 'term-pane',
        panes: {
          'term-pane': WorkspaceContentSnapshot(
            id: 'term-1',
            kind: WorkspaceTabKind.terminal,
            serverId: 1,
            cwd: '/home/builder/proj',
            history: 'user@host:~\$ cd /home/builder/proj\n',
          ),
          'files-pane': WorkspaceContentSnapshot(
            id: 'files-1',
            kind: WorkspaceTabKind.fileManagement,
            serverId: 1,
            path: '/home/builder/proj',
          ),
        },
      ),
      WorkspaceTabSnapshot(
        id: 'editor-1',
        layout: SessionLayoutLeaf('editor-pane'),
        focusedPaneId: 'editor-pane',
        panes: {
          'editor-pane': WorkspaceContentSnapshot(
            id: 'editor-1',
            kind: WorkspaceTabKind.fileEditor,
            serverId: 1,
            fileName: 'main.go',
            path: '/home/builder/proj/main.go',
            isRemote: true,
          ),
        },
      ),
      WorkspaceTabSnapshot(
        id: 'detail-1',
        layout: SessionLayoutLeaf('detail-pane'),
        focusedPaneId: 'detail-pane',
        panes: {
          'detail-pane': WorkspaceContentSnapshot(
            id: 'detail-1',
            kind: WorkspaceTabKind.serverDetail,
            serverId: 1,
            initialTab: 2,
            initialComposeProject: 'stack',
          ),
        },
      ),
    ],
    selectedTabId: 'term-1',
  );
}

void main() {
  group('WorkspaceSnapshot codec', () {
    test('round-trips tabs, layouts, and history', () {
      final snapshot = _fullSnapshot();
      final decoded = WorkspaceSnapshot.decode(snapshot.encode());

      expect(decoded, isNotNull);
      expect(decoded!.version, WorkspaceSnapshot.currentVersion);
      expect(decoded.selectedTabId, 'term-1');
      expect(decoded.tabs.map((tab) => tab.id), [
        'dashboard',
        'term-1',
        'editor-1',
        'detail-1',
      ]);

      // The split belongs to the terminal tab, not to the workspace.
      final splitTab = decoded.tabs[1];
      expect(splitTab.focusedPaneId, 'term-pane');
      final layout = splitTab.layout;
      expect(layout, isA<SessionLayoutSplit>());
      final split = layout as SessionLayoutSplit;
      expect(split.axis, SessionSplitAxis.horizontal);
      expect(split.ratio, 0.5);
      expect(split.first, const SessionLayoutLeaf('term-pane'));
      expect(split.second, const SessionLayoutLeaf('files-pane'));
      expect(
        splitTab.panes['files-pane']!.kind,
        WorkspaceTabKind.fileManagement,
      );

      final terminal = splitTab.panes['term-pane']!;
      expect(terminal.kind, WorkspaceTabKind.terminal);
      expect(terminal.cwd, '/home/builder/proj');
      expect(terminal.history, 'user@host:~\$ cd /home/builder/proj\n');

      final editor = decoded.tabs[2].panes['editor-pane']!;
      expect(editor.isRemote, isTrue);
      expect(editor.fileName, 'main.go');

      final detail = decoded.tabs[3].panes['detail-pane']!;
      expect(detail.initialTab, 2);
      expect(detail.initialComposeProject, 'stack');
    });

    test('rejects malformed payloads', () {
      expect(WorkspaceSnapshot.decode('not json'), isNull);
      expect(WorkspaceSnapshot.decode('{"version":99}'), isNull);
      expect(WorkspaceSnapshot.decode('{"version":2,"tabs":42}'), isNull);
    });

    test('reads a version 1 workspace as one tab per pane tab', () {
      // Version 1 kept one layout for the whole workspace and a tab list per
      // pane; the migration turns each of those tabs into its own tab so a
      // saved workspace still opens.
      final legacy = WorkspaceSnapshot.decode(
        '{"version":1,'
        '"layout":{"type":"leaf","paneId":"main"},'
        '"panes":{"main":{"tabIds":["dashboard","term-1"],'
        '"selectedTabId":"term-1"}},'
        '"focusedPaneId":"main",'
        '"tabs":['
        '{"id":"dashboard","kind":"dashboard"},'
        '{"id":"term-1","kind":"terminal","serverId":1,"cwd":"/srv"}'
        ']}',
      );

      expect(legacy, isNotNull);
      expect(legacy!.tabs.map((tab) => tab.id), ['dashboard', 'term-1']);
      expect(legacy.selectedTabId, 'term-1');
      final terminal = legacy.tabs.last.panes.values.single!;
      expect(terminal.kind, WorkspaceTabKind.terminal);
      expect(terminal.cwd, '/srv');
    });

    test('detects the pristine default and empty workspaces', () {
      expect(_fullSnapshot().isPristineDefault, isFalse);
      expect(const WorkspaceSnapshot().isEmpty, isTrue);
      expect(const WorkspaceSnapshot().isPristineDefault, isFalse);
      expect(
        const WorkspaceSnapshot(
          tabs: [
            WorkspaceTabSnapshot(
              id: 'dashboard',
              layout: SessionLayoutLeaf('main'),
              focusedPaneId: 'main',
              panes: {
                'main': WorkspaceContentSnapshot(
                  id: 'dashboard',
                  kind: WorkspaceTabKind.dashboard,
                ),
              },
            ),
          ],
        ).isPristineDefault,
        isTrue,
      );
    });
  });

  group('WorkspaceSnapshot.capture', () {
    test('captures every content kind with cwd and history', () {
      final server = _server();
      final terminal = TerminalTab(
        id: 'term-1',
        serverId: 1,
        serverName: server.name,
        terminal: _FakeAdapter(
          directory: '/home/builder/proj',
          history: 'history text',
        ),
        transport: TerminalTransport.ssh,
      );
      final contents = <SessionTab>[
        const DashboardTab(),
        ServerDetailTab(
          id: 'detail-1',
          server: server,
          initialTab: 2,
          initialComposeProject: 'stack',
        ),
        MaidCafePayloadSessionTab(id: 'maid-1', server: server),
        terminal,
        FileManagementTab(
          id: 'files-1',
          serverId: 1,
          serverName: server.name,
          initialPath: '/home/builder/proj',
        ),
        FileEditorTab(
          id: 'editor-1',
          serverId: 1,
          serverName: server.name,
          fileName: 'main.go',
          path: '/home/builder/proj/main.go',
          isRemote: true,
        ),
      ];
      // One tab holding a split: the terminal and the file manager in two
      // panes.
      final split = WorkspaceTab(
        id: 'term-1',
        panes: {
          'p1': TabPane(id: 'p1', tab: terminal),
          'p2': TabPane(id: 'p2', tab: contents[4]),
        },
        layout: const SessionLayoutSplit(
          id: 'split',
          axis: SessionSplitAxis.vertical,
          first: SessionLayoutLeaf('p1'),
          second: SessionLayoutLeaf('p2'),
        ),
        focusedPaneId: 'p1',
      );
      final state = TerminalTabsState(
        tabs: [
          for (final content in [contents[0], contents[1], contents[2]])
            WorkspaceTab(
              id: content.id,
              panes: {'main': TabPane(id: 'main', tab: content)},
              layout: const SessionLayoutLeaf('main'),
              focusedPaneId: 'main',
            ),
          split,
          WorkspaceTab(
            id: contents[5].id,
            panes: {'main': TabPane(id: 'main', tab: contents[5])},
            layout: const SessionLayoutLeaf('main'),
            focusedPaneId: 'main',
          ),
        ],
        selectedTabId: 'term-1',
      );

      final snapshot = WorkspaceSnapshot.capture(
        state,
        historyFor: (tab) => 'captured:${tab.id}',
      );

      expect(snapshot.tabs, hasLength(5));
      final captured = snapshot.tabs.firstWhere((tab) => tab.id == 'term-1');
      expect(captured.layout, isA<SessionLayoutSplit>());
      expect(captured.panes, hasLength(2));
      final capturedTerminal = captured.panes['p1']!;
      expect(capturedTerminal.kind, WorkspaceTabKind.terminal);
      expect(capturedTerminal.cwd, '/home/builder/proj');
      expect(capturedTerminal.history, 'captured:term-1');
      expect(captured.panes['p2']!.path, '/home/builder/proj');

      final detail = snapshot.tabs
          .firstWhere((tab) => tab.id == 'detail-1')
          .panes['main']!;
      expect(detail.initialTab, 2);
      expect(detail.initialComposeProject, 'stack');
      final editor = snapshot.tabs
          .firstWhere((tab) => tab.id == 'editor-1')
          .panes['main']!;
      expect(editor.isRemote, isTrue);
    });
  });

  group('resolveWorkspaceSnapshot', () {
    test('rebuilds tabs and defers terminals into their panes', () {
      final resolved = resolveWorkspaceSnapshot(_fullSnapshot(), {
        1: _server(),
      });

      expect(resolved.initialTabs.map((tab) => tab.id), [
        'dashboard',
        'term-1',
        'editor-1',
        'detail-1',
      ]);
      expect(resolved.selectedTabId, 'term-1');

      final terminalTab = resolved.initialTabs[1];
      expect(terminalTab.layout, isA<SessionLayoutSplit>());
      expect(terminalTab.focusedPaneId, 'term-pane');
      // The terminal is deferred, so its pane exists but is still empty.
      expect(terminalTab.panes['term-pane']!.isEmpty, isTrue);
      expect(terminalTab.panes['files-pane']!.tab, isA<FileManagementTab>());

      final pending = resolved.pendingTerminals.single;
      expect(pending.paneId, 'term-pane');
      expect(pending.serverId, 1);
      expect(pending.cwd, '/home/builder/proj');
      expect(pending.history, 'user@host:~\$ cd /home/builder/proj\n');
      expect(pending.connectionType, ServerConnectionType.ssh);

      final detail = resolved.initialTabs[3].panes['detail-pane']!.tab;
      expect(detail, isA<ServerDetailTab>());
      expect((detail as ServerDetailTab).initialTab, 2);
      expect(detail.initialComposeProject, 'stack');
    });

    test('marks serial servers and drops content of deleted servers', () {
      const snapshot = WorkspaceSnapshot(
        tabs: [
          WorkspaceTabSnapshot(
            id: 'term-1',
            layout: SessionLayoutLeaf('p1'),
            focusedPaneId: 'p1',
            panes: {
              'p1': WorkspaceContentSnapshot(
                id: 'term-1',
                kind: WorkspaceTabKind.terminal,
                serverId: 1,
              ),
            },
          ),
          WorkspaceTabSnapshot(
            id: 'term-2',
            layout: SessionLayoutLeaf('p2'),
            focusedPaneId: 'p2',
            panes: {
              'p2': WorkspaceContentSnapshot(
                id: 'term-2',
                kind: WorkspaceTabKind.terminal,
                serverId: 2,
              ),
            },
          ),
          WorkspaceTabSnapshot(
            id: 'term-3',
            layout: SessionLayoutLeaf('p3'),
            focusedPaneId: 'p3',
            panes: {
              'p3': WorkspaceContentSnapshot(
                id: 'term-3',
                kind: WorkspaceTabKind.terminal,
                serverId: 99,
              ),
            },
          ),
        ],
        selectedTabId: 'term-1',
      );

      final resolved = resolveWorkspaceSnapshot(snapshot, {
        1: _server(id: 1, type: 'serial'),
        2: _server(id: 2, type: 'ssh'),
      });

      expect(resolved.pendingTerminals, hasLength(2));
      expect(
        resolved.pendingTerminals[0].connectionType,
        ServerConnectionType.serial,
      );
      expect(
        resolved.pendingTerminals[1].connectionType,
        ServerConnectionType.ssh,
      );
      // The deleted server's tab keeps its pane, empty, so the split
      // arrangement the user saved survives.
      expect(resolved.initialTabs, hasLength(3));
      expect(resolved.initialTabs.last.panes['p3']!.isEmpty, isTrue);
    });
  });
}
