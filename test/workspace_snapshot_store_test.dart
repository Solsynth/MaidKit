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
      layout: SessionLayoutLeaf('main'),
      panes: {
        'main': SessionPane(
          id: 'main',
          tabIds: ['dashboard', 'term-1'],
          selectedTabId: 'term-1',
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
          serverId: 3,
          cwd: '/srv/app',
          history: 'history line\n',
        ),
      ],
      focusedPaneId: 'main',
    );

    final emitted = <WorkspaceSnapshot?>[];
    final sub = store.watch().listen(emitted.add);
    addTearDown(sub.cancel);

    await store.save(snapshot);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(emitted.last, isNotNull);
    expect(emitted.last!.tabs, hasLength(2));
    expect(emitted.last!.tabById('term-1')!.cwd, '/srv/app');
    expect(emitted.last!.tabById('term-1')!.history, 'history line\n');

    final loaded = await store.load();
    expect(loaded, isNotNull);
    expect(loaded!.focusedPaneId, 'main');
    expect(loaded.panes['main']!.selectedTabId, 'term-1');
  });

  test('overwrites the previous snapshot on save', () async {
    await store.save(const WorkspaceSnapshot(tabs: []));
    const replacement = WorkspaceSnapshot(
      layout: SessionLayoutLeaf('main'),
      panes: {
        'main': SessionPane(
          id: 'main',
          tabIds: ['dashboard'],
          selectedTabId: 'dashboard',
        ),
      },
      tabs: [
        WorkspaceTabSnapshot(
          id: 'dashboard',
          kind: WorkspaceTabKind.dashboard,
          serverId: -1,
        ),
      ],
    );
    await store.save(replacement);

    final loaded = await store.load();
    expect(loaded, isNotNull);
    expect(loaded!.tabs, hasLength(1));
    expect(loaded.tabs.single.kind, WorkspaceTabKind.dashboard);
  });

  test('returns null before any save and after clear', () async {
    expect(await store.load(), isNull);

    await store.save(const WorkspaceSnapshot(tabs: []));
    await store.clear();

    expect(await store.load(), isNull);
  });
}
