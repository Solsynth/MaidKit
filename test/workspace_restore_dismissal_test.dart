import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/terminal_tabs_provider.dart';
import 'package:maid_kit/servers/workspace_restore_preferences.dart';
import 'package:maid_kit/servers/workspace_snapshot.dart';

/// A workspace tab holding [contents] in one pane.
WorkspaceTab _tab(String paneId, List<SessionTab> contents) => WorkspaceTab(
  id: contents.isEmpty ? paneId : contents.first.id,
  panes: {paneId: TabPane(id: paneId, tab: contents.firstOrNull)},
  layout: SessionLayoutLeaf(paneId),
  focusedPaneId: paneId,
);

/// The untouched single-dashboard workspace every session starts with.
TerminalTabsState _pristineTabs() => TerminalTabsState(
  tabs: [
    _tab('main', const [DashboardTab()]),
  ],
  selectedTabId: 'dashboard',
);

/// A workspace that already holds something besides the dashboard.
TerminalTabsState _liveTabs() => TerminalTabsState(
  tabs: [
    _tab('main', const [DashboardTab()]),
    _tab('pane-2', const [
      FileManagementTab(id: 'files-1', serverId: 1, serverName: 'Server 1'),
    ]),
  ],
  selectedTabId: 'files-1',
);

StoredWorkspaceSnapshot _storedAt(DateTime updatedAt) =>
    StoredWorkspaceSnapshot(
      WorkspaceSnapshot(
        tabs: [
          WorkspaceTabSnapshot(
            id: 'dashboard',
            layout: const SessionLayoutLeaf('main'),
            focusedPaneId: 'main',
            panes: const {
              'main': WorkspaceContentSnapshot(
                id: 'dashboard',
                kind: WorkspaceTabKind.dashboard,
              ),
            },
          ),
          const WorkspaceTabSnapshot(
            id: 'term-1',
            layout: SessionLayoutLeaf('pane-2'),
            focusedPaneId: 'pane-2',
            panes: {
              'pane-2': WorkspaceContentSnapshot(
                id: 'term-1',
                kind: WorkspaceTabKind.terminal,
                serverId: 1,
              ),
            },
          ),
        ],
        selectedTabId: 'term-1',
      ),
      updatedAt,
    );

void main() {
  group('shouldOfferWorkspaceRestore', () {
    final savedAt = DateTime(2026, 10, 4, 9, 30);

    test('offers an undismissed workspace on a pristine dashboard', () {
      expect(
        shouldOfferWorkspaceRestore(
          tabs: _pristineTabs(),
          stored: _storedAt(savedAt),
          dismissedSnapshotAt: null,
        ),
        isTrue,
      );
    });

    test('stays dismissed for the workspace it was dismissed on', () {
      expect(
        shouldOfferWorkspaceRestore(
          tabs: _pristineTabs(),
          stored: _storedAt(savedAt),
          dismissedSnapshotAt: savedAt,
        ),
        isFalse,
      );
    });

    test('offers a later save again', () {
      expect(
        shouldOfferWorkspaceRestore(
          tabs: _pristineTabs(),
          stored: _storedAt(savedAt.add(const Duration(minutes: 5))),
          dismissedSnapshotAt: savedAt,
        ),
        isTrue,
      );
    });

    test('never offers over a workspace that is already in use', () {
      expect(
        shouldOfferWorkspaceRestore(
          tabs: _liveTabs(),
          stored: _storedAt(savedAt),
          dismissedSnapshotAt: null,
        ),
        isFalse,
      );
    });

    test('offers nothing when no workspace was saved', () {
      final emptyWorkspace = StoredWorkspaceSnapshot(
        const WorkspaceSnapshot(),
        savedAt,
      );
      expect(
        shouldOfferWorkspaceRestore(
          tabs: _pristineTabs(),
          stored: null,
          dismissedSnapshotAt: null,
        ),
        isFalse,
      );
      expect(
        shouldOfferWorkspaceRestore(
          tabs: _pristineTabs(),
          stored: emptyWorkspace,
          dismissedSnapshotAt: null,
        ),
        isFalse,
      );
    });
  });

  group('workspaceRestoreDismissalProvider', () {
    test('remembers a dismissal and applies it on the next launch', () async {
      final settings = InMemoryWorkspaceRestoreSettings();
      final container = ProviderContainer(
        overrides: [
          workspaceRestoreSettingsProvider.overrideWithValue(settings),
        ],
      );
      addTearDown(container.dispose);
      final savedAt = DateTime(2026, 10, 4, 9, 30);

      expect(container.read(workspaceRestoreDismissalProvider), isNull);

      await container
          .read(workspaceRestoreDismissalProvider.notifier)
          .dismiss(savedAt);

      expect(settings.dismissedSnapshotAt, savedAt);
      expect(container.read(workspaceRestoreDismissalProvider), savedAt);

      final relaunched = ProviderContainer(
        overrides: [
          workspaceRestoreSettingsProvider.overrideWithValue(settings),
        ],
      );
      addTearDown(relaunched.dispose);

      expect(relaunched.read(workspaceRestoreDismissalProvider), savedAt);
    });
  });
}
