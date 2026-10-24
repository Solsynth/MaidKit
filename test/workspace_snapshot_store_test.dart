import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/data/local/app_database.dart' hide WorkspaceSnapshot;
import 'package:maid_kit/servers/terminal_tabs_provider.dart';
import 'package:maid_kit/servers/workspace_snapshot.dart';
import 'package:maid_kit/servers/workspace_snapshot_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        return Directory.systemTemp.path;
      });

  late Directory directory;
  late AppDatabase database;
  late WorkspaceSnapshotStore store;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('workspace_snapshot_test');
    database = AppDatabase(filePath: '${directory.path}/store.sqlite');
    store = WorkspaceSnapshotStore(database);
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test('saves, loads, and watches the last snapshot', () async {
    const snapshot = WorkspaceSnapshot(
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
          layout: SessionLayoutLeaf('pane-2'),
          focusedPaneId: 'pane-2',
          panes: {
            'pane-2': WorkspaceContentSnapshot(
              id: 'term-1',
              kind: WorkspaceTabKind.terminal,
              serverId: 3,
              cwd: '/srv/app',
              history: 'history line\n',
            ),
          },
        ),
      ],
      selectedTabId: 'term-1',
    );

    final emitted = <StoredWorkspaceSnapshot?>[];
    final sub = store.watch().listen(emitted.add);
    addTearDown(sub.cancel);

    final beforeSave = DateTime.now().subtract(const Duration(seconds: 1));
    await store.save(snapshot);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(emitted.last, isNotNull);
    expect(emitted.last!.snapshot.tabs, hasLength(2));
    final terminal = emitted.last!.snapshot.tabs
        .firstWhere((tab) => tab.id == 'term-1')
        .panes['pane-2']!;
    expect(terminal.cwd, '/srv/app');
    expect(terminal.history, 'history line\n');
    // The dashboard identifies a snapshot by its save time, so the row's
    // timestamp must reach consumers.
    expect(emitted.last!.updatedAt.isAfter(beforeSave), isTrue);

    final loaded = await store.load();
    expect(loaded, isNotNull);
    expect(loaded!.snapshot.selectedTabId, 'term-1');
    expect(loaded.snapshot.tabs.last.layout, const SessionLayoutLeaf('pane-2'));
  });

  test('overwrites the previous snapshot on save', () async {
    await store.save(const WorkspaceSnapshot(tabs: []));
    const replacement = WorkspaceSnapshot(
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
      selectedTabId: 'dashboard',
    );
    await store.save(replacement);

    final loaded = await store.load();
    expect(loaded, isNotNull);
    expect(loaded!.snapshot.tabs, hasLength(1));
    expect(
      loaded.snapshot.tabs.single.panes['main']!.kind,
      WorkspaceTabKind.dashboard,
    );
  });

  test('returns null before any save and after clear', () async {
    expect(await store.load(), isNull);

    await store.save(const WorkspaceSnapshot(tabs: []));
    await store.clear();

    expect(await store.load(), isNull);
  });
}
