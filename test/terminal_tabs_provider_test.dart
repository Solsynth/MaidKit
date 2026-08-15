import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/terminal_session_adapter.dart';
import 'package:maid_kit/servers/terminal_tabs_provider.dart';

void main() {
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
    );
    notifier.state = TerminalTabsState(
      tabs: [tab],
      panes: {
        'pane-1': const SessionPane(
          id: 'pane-1',
          tabIds: ['terminal-1'],
          selectedTabId: 'terminal-1',
        ),
      },
      layout: const SessionLayoutLeaf('pane-1'),
      focusedPaneId: 'pane-1',
    );

    final now = DateTime.utc(2026, 1, 1);
    notifier.executeSnippet(
      'terminal-1',
      ScriptSnippet(
        id: 1,
        name: 'Deploy',
        script: '  echo start\n./deploy.sh\n\n',
        createdAt: now,
        updatedAt: now,
      ),
    );

    expect(adapter.inputs, ["eval '  echo start\n./deploy.sh'\n"]);
  });
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
