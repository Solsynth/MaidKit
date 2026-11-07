// Reading a host's tmux sessions over SSH. The failure this guards against is
// silent: `SSHSession.stdout` is a byte stream, so joining it without decoding
// produces `[99, 97, ...]`, which parses to no rows and looks exactly like a
// host that has no sessions.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/servers/tmux_sessions.dart';

class _FakeSession implements SSHSession {
  _FakeSession(this.output);

  final String output;

  @override
  Stream<Uint8List> get stdout =>
      Stream.value(Uint8List.fromList(utf8.encode(output)));

  @override
  Future<void> get done => Future<void>.value();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('only stdout and done are read in this test');
}

class _FakeClient implements SSHClient {
  _FakeClient(this.session);

  final SSHSession session;

  @override
  Future<SSHSession> execute(
    String command, {
    SSHPtyConfig? pty,
    SSHX11Config? x11,
    Map<String, String>? environment,
  }) async => session;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('no other SSH call runs in this test');
}

void main() {
  test('sessions are decoded from the byte stream, not stringified', () async {
    final sessions = await readTmuxSessionsOverSsh(
      _FakeClient(
        _FakeSession(
          'work\t2\t1700000000\t1\n'
          'bg\t1\t1700000100\t0\n',
        ),
      ),
    );
    expect(sessions.map((session) => session.name), ['work', 'bg']);
    expect(sessions.first.windows, 2);
    expect(sessions.first.attached, 1);
  });

  test('a host with no sessions lists none', () async {
    expect(
      await readTmuxSessionsOverSsh(_FakeClient(_FakeSession(''))),
      isEmpty,
    );
  });
}
