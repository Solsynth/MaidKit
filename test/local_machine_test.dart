import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/local_connection_manager.dart';
import 'package:maid_kit/servers/local_machine_preferences.dart';
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/terminal_session_adapter.dart';

void main() {
  test('macOS excludes local-machine management', () {
    expect(localMachineSupported, Platform.isMacOS ? isFalse : isTrue);
  });
  test('local machine preference persists the dashboard toggle', () async {
    final settings = InMemoryLocalMachineSettings();
    final container = ProviderContainer(
      overrides: [localMachineSettingsProvider.overrideWithValue(settings)],
    );
    addTearDown(container.dispose);

    expect(container.read(localMachineEnabledProvider), isFalse);

    await container.read(localMachineEnabledProvider.notifier).setEnabled(true);

    expect(settings.localMachineEnabled, isTrue);
    expect(container.read(localMachineEnabledProvider), isTrue);
  });

  test('the virtual local server uses the reserved id and local transport', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final server = container.read(localMachineServerProvider);

    expect(server.id, localMachineServerId);
    expect(server.connectionType, ServerConnectionType.local.name);
    expect(server.name, isNotEmpty);
  });

  test(
    'collects real statistics and system info on macOS',
    () async {
      if (!Platform.isMacOS) return;
      const collector = LocalMachineMetricsCollector();

      final stats = await collector.collect();

      expect(stats, isNotNull);
      expect(stats!.loadAverage, isNotNull);
      expect(stats.loadAverage5, isNotNull);
      expect(stats.memoryTotalKb, isNotNull);
      expect(stats.memoryAvailableKb, isNotNull);
      expect(stats.uptime, isNotNull);

      final info = await collector.systemInfo();

      expect(info.distribution, contains('macOS'));
      expect(info.kernel, isNotNull);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'opens a local shell that echoes typed commands',
    () async {
      if (!localMachineSupported) return;
      final adapter = _RecordingAdapter();
      final manager = LocalConnectionManager(
        () => _StubAdapterFactory(adapter),
        isEnabled: () => true,
        interval: () => const Duration(days: 1),
        serverName: () => 'test machine',
      );
      addTearDown(manager.dispose);
      final server = Server(
        id: localMachineServerId,
        name: 'test machine',
        host: '127.0.0.1',
        port: 22,
        username: 'tester',
        collectStats: true,
        collectSystemInfo: true,
        connectionType: ServerConnectionType.local.name,
      );

      final handle = await manager.openTerminal(server);
      adapter.sendInput('echo maidkit-local-ok\n');
      final shell =
          Platform.environment['SHELL'] ?? (Platform.isMacOS ? '/bin/zsh' : '');
      final zsh = shell.endsWith('/zsh');
      if (Platform.isMacOS && zsh) {
        adapter.sendInput(
          'if [[ -o warncreateglobal ]]; then '
          'echo maidkit-warning-option-enabled; '
          'else echo maidkit-warning-option-disabled; fi\n',
        );
        adapter.sendInput(
          'setopt warncreateglobal\n'
          'echo maidkit-warning-filter-ok\n',
        );
      }

      final deadline = DateTime.now().add(const Duration(seconds: 15));
      String output = '';
      final expectedMarker = Platform.isMacOS && zsh
          ? 'maidkit-warning-filter-ok'
          : 'maidkit-local-ok';
      while (!output.contains(expectedMarker) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        output = utf8.decode(adapter.received.toBytes(), allowMalformed: true);
      }

      expect(output, contains('maidkit-local-ok'));
      if (Platform.isMacOS && zsh) {
        expect(output, contains('maidkit-warning-option-disabled'));
        expect(output, contains('maidkit-warning-filter-ok'));
        expect(output, isNot(contains('created globally in function')));
      }
      await manager.closeTerminal(handle.id);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
  test(
    'starts a local shell in its requested working directory',
    () async {
      if (!localMachineSupported) return;
      final directory = await Directory.systemTemp.createTemp(
        'maidkit-local-cwd-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final adapter = _RecordingAdapter();
      final manager = LocalConnectionManager(
        () => _StubAdapterFactory(adapter),
        isEnabled: () => true,
        interval: () => const Duration(days: 1),
        serverName: () => 'test machine',
      );
      addTearDown(manager.dispose);
      final server = Server(
        id: localMachineServerId,
        name: 'test machine',
        host: '127.0.0.1',
        port: 22,
        username: 'tester',
        collectStats: true,
        collectSystemInfo: true,
        connectionType: ServerConnectionType.local.name,
      );

      final handle = await manager.openTerminal(
        server,
        initialDirectory: directory.path,
      );
      adapter.sendInput('pwd\n');

      final deadline = DateTime.now().add(const Duration(seconds: 15));
      String output = '';
      while (!output.contains(directory.path) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        output = utf8.decode(adapter.received.toBytes(), allowMalformed: true);
      }

      expect(output, contains(directory.path));
      await manager.closeTerminal(handle.id);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

class _StubAdapterFactory implements TerminalSessionAdapterFactory {
  const _StubAdapterFactory(this.adapter);

  final TerminalSessionAdapter adapter;

  @override
  TerminalSessionAdapter create() => adapter;
}

class _RecordingAdapter implements TerminalSessionAdapter {
  final BytesBuilder received = BytesBuilder();
  final _outgoing = StreamController<Uint8List>.broadcast();

  @override
  Stream<Uint8List> get outgoingBytes => _outgoing.stream;

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
  void write(Uint8List bytes) => received.add(bytes);

  @override
  void sendInput(String text) => _outgoing.add(utf8.encode(text));

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
