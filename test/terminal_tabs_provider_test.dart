import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/terminal_session_adapter.dart';
import 'package:maid_kit/servers/terminal_tabs_provider.dart';

void main() {
  test('a MaidCafe terminal reports the transport it actually uses', () {
    // The status bar names the connection, so the relay — which rides the cloud
    // and needs no reachable daemon — cannot read as a direct connection.
    expect(
      maidCafeTerminalTransport(
        const MaidCafeTerminalTarget(
          baseUrl: 'http://127.0.0.1:8747',
          secret: 'secret',
        ),
      ),
      TerminalTransport.maidCafeDirect,
    );
    expect(
      maidCafeTerminalTransport(
        const MaidCafeTerminalTarget(
          baseUrl: 'https://mkc.solsynth.dev',
          secret: '',
          relayDaemonId: 'daemon-1',
        ),
      ),
      TerminalTransport.maidCafeRelay,
    );
  });

  test('every transport names itself for the tooltip', () {
    for (final transport in TerminalTransport.values) {
      expect(transport.labelKey, startsWith('terminalTransport'));
    }
    // Distinct keys, so no two transports read the same in the tooltip.
    expect(
      TerminalTransport.values.map((t) => t.labelKey).toSet().length,
      TerminalTransport.values.length,
    );
  });

  test('executes a saved snippet in the requested terminal', () {
    final adapter = _RecordingTerminalAdapter();
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(terminalTabsProvider.notifier);
    final tab = TerminalTab(
      id: 'terminal-1',
      serverId: 1,
      serverName: 'Test server',
      terminal: adapter,
      transport: TerminalTransport.ssh,
    );
    notifier.state = TerminalTabsState(
      tabs: [
        WorkspaceTab(
          id: tab.id,
          panes: {'pane-1': TabPane(id: 'pane-1', tab: tab)},
          layout: const SessionLayoutLeaf('pane-1'),
          focusedPaneId: 'pane-1',
        ),
      ],
      selectedTabId: tab.id,
    );

    final now = DateTime.utc(2026, 1, 1);
    notifier.executeSnippet(
      'terminal-1',
      ScriptSnippet(
        id: 1,
        name: 'Deploy',
        script: '  echo start\n./deploy.sh\n\n',
        excludedFromAutocomplete: false,
        dangerous: false,
        createdAt: now,
        updatedAt: now,
      ),
    );

    expect(adapter.inputs, ["eval '  echo start\n./deploy.sh'\n"]);
  });

  test('a split adds a pane to the tab instead of a second tab', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(terminalTabsProvider.notifier);

    notifier.openFileManagement(const _ServerStub());
    notifier.splitSelectedTab(SessionSplitAxis.horizontal);

    final state = container.read(terminalTabsProvider);
    expect(state.tabs, hasLength(2), reason: 'dashboard + the file manager');
    final split = state.tabs.last;
    expect(split.hasSplits, isTrue);
    expect(split.panes, hasLength(2));
    expect(split.layout.paneIds, containsAll(split.panes.keys));
    // The file manager is a view over shared data, so the new pane shows a
    // second instance of it under the same bar entry.
    expect(split.tabs, hasLength(2));
    expect(split.tabs.map((tab) => tab.id).toSet(), hasLength(2));
    expect(split.tabs.every((tab) => tab is FileManagementTab), isTrue);
    expect(state.selectedTabId, split.id);
  });

  test('closing a pane keeps the tab and its other viewport', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(terminalTabsProvider.notifier);

    notifier.openFileManagement(const _ServerStub());
    notifier.splitSelectedTab(SessionSplitAxis.vertical);
    final split = container.read(terminalTabsProvider).tabs.last;
    final kept = split.panes.entries
        .firstWhere((entry) => entry.key != split.focusedPaneId)
        .value;

    await notifier.closePaneInTab(split.id, split.focusedPaneId);

    final state = container.read(terminalTabsProvider);
    expect(state.tabs, hasLength(2));
    final remaining = state.tabs.last;
    expect(remaining.hasSplits, isFalse);
    expect(remaining.panes.values.single.tab!.id, kept.tab!.id);
    expect(state.selectedTabId, remaining.id);
  });

  test('closing a split tab closes every pane it owns', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(terminalTabsProvider.notifier);

    notifier.openFileManagement(const _ServerStub());
    notifier.splitSelectedTab(SessionSplitAxis.horizontal);
    final split = container.read(terminalTabsProvider).tabs.last;

    await notifier.closeTab(split.id);

    final state = container.read(terminalTabsProvider);
    expect(state.tabs, hasLength(1));
    expect(state.tabs.single.tab, isA<DashboardTab>());
    expect(state.selectedTabId, 'dashboard');
  });
}

class _ServerStub extends Server {
  const _ServerStub()
    : super(
        id: 1,
        name: 'Server 1',
        host: '10.0.0.1',
        port: 22,
        username: 'root',
        collectStats: false,
        collectSystemInfo: false,
        connectionType: 'ssh',
        maidCafeTerminalViaCloud: false,
      );
}

class _RecordingTerminalAdapter implements TerminalSessionAdapter {
  final inputs = <String>[];

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
  String? get currentDirectory => null;

  @override
  int get bufferRows => 0;

  @override
  String? dumpHistory({int maxLines = 4000}) => null;

  @override
  void replayHistory(String text) {}

  @override
  SudoPromptReason? get sudoAutofillReady => null;

  @override
  void bindSudoAutofill(Stream<SudoPromptReason?> reasons) {}

  @override
  void write(Uint8List bytes) {}

  @override
  void sendInput(String text) => inputs.add(text);

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
