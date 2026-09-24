import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/data/local/app_database.dart' hide WorkspaceSnapshot;
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

WorkspaceSnapshot _fullSnapshot() {
  return const WorkspaceSnapshot(
    layout: SessionLayoutSplit(
      id: 'split-1',
      axis: SessionSplitAxis.horizontal,
      ratio: 0.5,
      first: SessionLayoutLeaf('main'),
      second: SessionLayoutLeaf('p2'),
    ),
    panes: {
      'main': SessionPane(
        id: 'main',
        tabIds: ['dashboard', 'term-1', 'files-1'],
        selectedTabId: 'term-1',
      ),
      'p2': SessionPane(
        id: 'p2',
        tabIds: ['editor-1', 'detail-1'],
        selectedTabId: 'editor-1',
      ),
    },
    tabs: [
      WorkspaceTabSnapshot(
        id: 'dashboard',
        kind: WorkspaceTabKind.dashboard,
        serverId: -1,
      ),
      WorkspaceTabSnapshot(
        id: 'term-1',
        kind: WorkspaceTabKind.terminal,
        serverId: 1,
        cwd: '/home/builder/proj',
        history: 'user@host:~\$ cd /home/builder/proj\n',
      ),
      WorkspaceTabSnapshot(
        id: 'files-1',
        kind: WorkspaceTabKind.fileManagement,
        serverId: 1,
        path: '/home/builder/proj',
      ),
      WorkspaceTabSnapshot(
        id: 'editor-1',
        kind: WorkspaceTabKind.fileEditor,
        serverId: 1,
        fileName: 'main.go',
        path: '/home/builder/proj/main.go',
        isRemote: true,
      ),
      WorkspaceTabSnapshot(
        id: 'detail-1',
        kind: WorkspaceTabKind.serverDetail,
        serverId: 1,
        initialTab: 2,
        initialComposeProject: 'stack',
      ),
    ],
    focusedPaneId: 'main',
  );
}

void main() {
  group('WorkspaceSnapshot codec', () {
    test('round-trips layout, panes, tabs, and history', () {
      final snapshot = _fullSnapshot();
      final decoded = WorkspaceSnapshot.decode(snapshot.encode());

      expect(decoded, isNotNull);
      expect(decoded!.version, WorkspaceSnapshot.currentVersion);
      expect(decoded.focusedPaneId, 'main');
      expect(decoded.panes.keys, ['main', 'p2']);
      expect(decoded.panes['main']!.tabIds, ['dashboard', 'term-1', 'files-1']);
      expect(decoded.panes['main']!.selectedTabId, 'term-1');
      expect(decoded.panes['p2']!.tabIds, ['editor-1', 'detail-1']);
      expect(decoded.panes['p2']!.selectedTabId, 'editor-1');

      final layout = decoded.layout!;
      expect(layout, isA<SessionLayoutSplit>());
      final split = layout as SessionLayoutSplit;
      expect(split.axis, SessionSplitAxis.horizontal);
      expect(split.ratio, 0.5);
      expect(split.first, const SessionLayoutLeaf('main'));
      expect(split.second, const SessionLayoutLeaf('p2'));

      final terminal = decoded.tabById('term-1')!;
      expect(terminal.kind, WorkspaceTabKind.terminal);
      expect(terminal.cwd, '/home/builder/proj');
      expect(terminal.history, 'user@host:~\$ cd /home/builder/proj\n');

      final editor = decoded.tabById('editor-1')!;
      expect(editor.isRemote, isTrue);
      expect(editor.fileName, 'main.go');

      final detail = decoded.tabById('detail-1')!;
      expect(detail.initialTab, 2);
      expect(detail.initialComposeProject, 'stack');
    });

    test('rejects malformed payloads', () {
      expect(WorkspaceSnapshot.decode('not json'), isNull);
      expect(WorkspaceSnapshot.decode('{"version":99}'), isNull);
      expect(WorkspaceSnapshot.decode('{"version":1,"panes":42}'), isNull);
    });

    test('detects the pristine default and empty workspaces', () {
      expect(_fullSnapshot().isPristineDefault, isFalse);
      expect(const WorkspaceSnapshot().isEmpty, isTrue);
      expect(const WorkspaceSnapshot().isPristineDefault, isFalse);
    });
  });

  group('WorkspaceSnapshot.capture', () {
    test('captures every tab kind with cwd and history', () {
      final server = _server();
      final state = TerminalTabsState(
        tabs: [
          const DashboardTab(),
          ServerDetailTab(
            id: 'detail-1',
            server: server,
            initialTab: 2,
            initialComposeProject: 'stack',
          ),
          MaidCafePayloadSessionTab(id: 'maid-1', server: server),
          TerminalTab(
            id: 'term-1',
            serverId: 1,
            serverName: server.name,
            terminal: _FakeAdapter(
              directory: '/home/builder/proj',
              history: 'history text',
            ),
          ),
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
        ],
        panes: const {
          'main': SessionPane(
            id: 'main',
            tabIds: [
              'dashboard',
              'detail-1',
              'maid-1',
              'term-1',
              'files-1',
              'editor-1',
            ],
            selectedTabId: 'term-1',
          ),
        },
        layout: const SessionLayoutLeaf('main'),
        focusedPaneId: 'main',
      );

      final snapshot = WorkspaceSnapshot.capture(
        state,
        historyFor: (tab) => 'captured:${tab.id}',
      );

      expect(snapshot.panes['main']!.tabIds, hasLength(6));
      expect(snapshot.tabs, hasLength(6));
      final terminal = snapshot.tabById('term-1')!;
      expect(terminal.kind, WorkspaceTabKind.terminal);
      expect(terminal.cwd, '/home/builder/proj');
      expect(terminal.history, 'captured:term-1');
      final detail = snapshot.tabById('detail-1')!;
      expect(detail.initialTab, 2);
      expect(detail.initialComposeProject, 'stack');
      final editor = snapshot.tabById('editor-1')!;
      expect(editor.isRemote, isTrue);
      expect(snapshot.tabById('files-1')!.path, '/home/builder/proj');
    });
  });

  group('resolveWorkspaceSnapshot', () {
    test('maps tabs to live objects and defers terminals', () {
      final resolved = resolveWorkspaceSnapshot(_fullSnapshot(), {
        1: _server(),
      });

      expect(resolved.layout, isA<SessionLayoutSplit>());
      expect(resolved.panes.keys, ['main', 'p2']);
      expect(resolved.panes['main']!.tabIds, [
        'dashboard',
        'files-1',
      ], reason: 'terminals are deferred, not placed');
      expect(resolved.panes['p2']!.tabIds, ['editor-1', 'detail-1']);

      final tabs = resolved.initialTabs;
      expect(tabs.whereType<DashboardTab>(), hasLength(1));
      expect(tabs.whereType<ServerDetailTab>().single.initialTab, 2);
      expect(
        tabs.whereType<ServerDetailTab>().single.initialComposeProject,
        'stack',
      );
      expect(
        tabs.whereType<FileManagementTab>().single.initialPath,
        '/home/builder/proj',
      );
      expect(tabs.whereType<FileEditorTab>().single.isRemote, isTrue);

      final pending = resolved.pendingTerminals.single;
      expect(pending.paneId, 'main');
      expect(pending.serverId, 1);
      expect(pending.cwd, '/home/builder/proj');
      expect(pending.history, 'user@host:~\$ cd /home/builder/proj\n');
      expect(pending.isSerial, isFalse);

      expect(resolved.desiredPaneTabIds['main'], [
        'dashboard',
        'term-1',
        'files-1',
      ]);
      expect(resolved.desiredPaneSelections['main'], 'term-1');
      expect(resolved.focusedPaneId, 'main');
    });

    test('marks serial servers and drops tabs for deleted servers', () {
      final snapshot = const WorkspaceSnapshot(
        panes: {
          'main': SessionPane(
            id: 'main',
            tabIds: ['term-1', 'term-2', 'term-3'],
            selectedTabId: 'term-1',
          ),
        },
        tabs: [
          WorkspaceTabSnapshot(
            id: 'term-1',
            kind: WorkspaceTabKind.terminal,
            serverId: 1,
          ),
          WorkspaceTabSnapshot(
            id: 'term-2',
            kind: WorkspaceTabKind.terminal,
            serverId: 2,
          ),
          WorkspaceTabSnapshot(
            id: 'term-3',
            kind: WorkspaceTabKind.terminal,
            serverId: 99,
          ),
        ],
      );

      final resolved = resolveWorkspaceSnapshot(snapshot, {
        1: _server(id: 1, type: 'serial'),
        2: _server(id: 2, type: 'ssh'),
      });

      expect(resolved.pendingTerminals, hasLength(2));
      expect(resolved.pendingTerminals[0].isSerial, isTrue);
      expect(resolved.pendingTerminals[1].isSerial, isFalse);
      // All three tabs are terminals; the deleted server's tab is dropped and
      // the survivors stay deferred, so the pane has no live tabs yet.
      expect(resolved.panes['main']!.tabIds, isEmpty);
      expect(resolved.desiredPaneTabIds['main'], ['term-1', 'term-2']);
    });
  });
}
