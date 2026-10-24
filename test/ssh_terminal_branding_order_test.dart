import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/ssh_connection_manager.dart';
import 'package:maid_kit/servers/terminal_session_adapter.dart';

void main() {
  test(
    'the terminal opens its shell before probing the branding dialect',
    () async {
      final transport = _FakeTransport();
      final manager = SshConnectionManager(
        () => _AdapterFactory(),
        connect: transport.connect,
      );
      addTearDown(manager.dispose);

      final handle = await manager.openTerminal(
        _server,
        const ServerCredential.password('secret'),
        (_) async => true,
      );
      addTearDown(() => manager.closeTerminal(handle.id));

      // PAM prints the login banner only for the first session on a connection.
      // A dialect probe issued ahead of the shell would consume it, dropping the
      // motd, the distribution welcome, and any auto-run login output (issue
      // #105).
      expect(transport.requests.first, 'shell');
      expect(transport.requests.where((r) => r == 'exec'), isNotEmpty);
      // No TERM_PROGRAM was sent as an SSH environment request; the shell
      // reports it from the branding command instead.
      expect(transport.shellEnvironment, isNull);

      // The branding command still reaches the shell.
      expect(transport.written.join(), contains('export TERM_PROGRAM=MaidKit'));
    },
  );

  test('no dialect probe runs when the branding toggle is off', () async {
    final transport = _FakeTransport();
    final manager = SshConnectionManager(
      () => _AdapterFactory(),
      connect: transport.connect,
      brandingEnvironmentEnabled: () => false,
    );
    addTearDown(manager.dispose);

    final handle = await manager.openTerminal(
      _server,
      const ServerCredential.password('secret'),
      (_) async => true,
    );
    addTearDown(() => manager.closeTerminal(handle.id));

    expect(transport.requests, ['shell']);
    expect(transport.written.join(), isNot(contains('TERM_PROGRAM')));
  });
}

const _server = Server(
  id: 1,
  name: 'ubuntu',
  host: 'ubuntu.example',
  port: 22,
  username: 'tester',
  collectStats: false,
  collectSystemInfo: false,
  connectionType: 'ssh',
  maidCafeTerminalViaCloud: false,
);

/// Records the session requests the manager issues, in order.
class _FakeTransport {
  final requests = <String>[];
  final written = <String>[];
  Map<String, String>? shellEnvironment;

  Future<SSHClient> connect(
    Server server,
    ServerCredential credential,
    HostKeyApproval approve, {
    String? knownHostKeyFingerprint,
    void Function(String? methods)? onAuthMethods,
    AuthChallengeApproval? approveAuth,
    ServerProxy? proxy,
  }) async => _FakeClient(this);

  /// Answers a dialect probe with a POSIX login shell.
  SSHSession answerExec(String command) {
    requests.add('exec');
    final passwd = command.startsWith('getent')
        ? 'tester:x:1000:1000::/home/tester:/bin/bash\n'
        : '';
    return _FakeSession(stdoutText: passwd);
  }

  SSHSession openShell(Map<String, String>? environment) {
    requests.add('shell');
    shellEnvironment = environment;
    return _FakeSession(writeSink: written.add);
  }
}

class _FakeClient implements SSHClient {
  _FakeClient(this._transport);

  final _FakeTransport _transport;

  @override
  Future<SSHSession> execute(
    String command, {
    SSHPtyConfig? pty,
    SSHX11Config? x11,
    Map<String, String>? environment,
  }) async => _transport.answerExec(command);

  @override
  Future<SSHSession> shell({
    SSHPtyConfig? pty,
    SSHX11Config? x11,
    Map<String, String>? environment,
  }) async => _transport.openShell(environment);

  @override
  bool get isClosed => false;

  @override
  Future<void> get done => Completer<void>().future;

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeSession implements SSHSession {
  _FakeSession({this.stdoutText = '', this.writeSink});

  final String stdoutText;
  final void Function(String text)? writeSink;

  @override
  Stream<Uint8List> get stdout =>
      Stream.value(Uint8List.fromList(utf8.encode(stdoutText)));

  @override
  Stream<Uint8List> get stderr => const Stream.empty();

  @override
  Future<void> get done => Future<void>.value();

  @override
  void write(Uint8List data) => writeSink?.call(utf8.decode(data));

  @override
  void resizeTerminal(
    int width,
    int height, [
    int pixelWidth = 0,
    int pixelHeight = 0,
  ]) {}

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _AdapterFactory implements TerminalSessionAdapterFactory {
  @override
  TerminalSessionAdapter create() => _Adapter();
}

class _Adapter implements TerminalSessionAdapter {
  final _outgoing = StreamController<Uint8List>.broadcast();
  final _resizes = StreamController<TerminalResize>.broadcast();

  @override
  Stream<Uint8List> get outgoingBytes => _outgoing.stream;

  @override
  Stream<TerminalResize> get resizeEvents => _resizes.stream;

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
  }) => const SizedBox();

  @override
  int find(String query, {bool caseSensitive = false}) => 0;

  @override
  void findJump(int index) {}

  @override
  void findClear() {}

  @override
  Future<void> dispose() async {}
}
