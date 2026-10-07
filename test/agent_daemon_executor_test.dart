import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_openai/dart_openai.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/agent/agent_host_executor.dart';
import 'package:maid_kit/agent/ssh_agent_service.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/maidcafe_terminal_connection_manager.dart';
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/ssh_connection_manager.dart';
import 'package:maid_kit/servers/terminal_session_adapter.dart';

/// The daemon has no exec request, so the executor types its script into an
/// interactive shell. These tests put a real `/bin/sh` behind the frames, which
/// is what proves the two things that matter: the text cannot be reinterpreted
/// by the shell it is typed into, and the run's result is the script's output,
/// not the session's own chatter.
void main() {
  group('the payload typed into the daemon shell', () {
    test('carries the script byte for byte through a real shell', () async {
      // Everything a shell would otherwise act on: quotes, expansions, escape
      // sequences that are *not* escapes here, and newlines.
      const script =
          "echo 'single' \"double\" \$HOME "
          '`id` \\\\ \\n\n'
          "cat <<'__maidkit_script'\n"
          'not a delimiter for us\n'
          '__maidkit_script\n'
          "printf 'a\\nb'\n";

      final lines = daemonShellPayload(
        script,
        terminalStdin: false,
        nonce: 'deadbeef',
      ).toList();
      // The assignments, without the run that would execute the script instead
      // of letting the test read back what the shell decoded.
      final body =
          '${lines.take(lines.length - 1).join('\n')}\n'
          'printf %b "\$__maidkit_script"';
      final decoded = await Process.run('/bin/sh', ['-c', body]);

      expect(decoded.exitCode, 0);
      expect(decoded.stdout, script);
    });

    test(
      'runs the script between its markers and reports its status',
      () async {
        const script = "echo 'single' \"double\"\nprintf 'a\\nb\\n'\nfalse\n";
        final payload = daemonShellPayload(
          script,
          terminalStdin: false,
          nonce: 'deadbeef',
        ).join('\n');
        final run = await Process.run('/bin/sh', ['-c', payload]);

        final body = run.stdout
            .replaceAll('###MAIDKIT-AGENT-BEGIN-deadbeef###\n', '')
            .replaceAll(RegExp(r'\n###MAIDKIT-AGENT-END-deadbeef:\d+###'), '')
            .trim();
        expect(body, 'single double\na\nb');
        // The status the end marker carries is the script's, not the shell's.
        expect(
          RegExp(r'END-deadbeef:(\d+)###').firstMatch(run.stdout)?.group(1),
          '1',
        );
      },
    );

    test('cannot be mistaken for the markers by what the shell echoes', () {
      final lines = daemonShellPayload(
        'echo hi',
        terminalStdin: true,
        nonce: 'deadbeef',
      ).toList();

      // A terminal echoes the typed line back; the markers are printed through
      // `%s`, so the echoed text never contains what the run looks for.
      expect(lines.last, contains('BEGIN-%s###'));
      expect(lines.last, contains('END-%s:%s###'));
      expect(lines.last, isNot(contains('BEGIN-deadbeef###')));
      expect(lines.last, isNot(contains('END-deadbeef:')));
    });

    test('slices a long script into lines a terminal can carry', () {
      final lines = daemonShellPayload(
        'x' * 4000,
        terminalStdin: true,
      ).toList();

      // One line per chunk, plus the assignment and the run itself.
      expect(lines.length, greaterThan(20));
      expect(
        lines.every((line) => line.length < 1024),
        isTrue,
        reason: 'a canonical input line over the terminal limit is dropped',
      );
    });

    test('closes the script stdin when nobody can see a prompt', () {
      final interactive = daemonShellPayload(
        'echo hi',
        terminalStdin: true,
      ).last;
      expect(interactive, isNot(contains('/dev/null')));

      // A snippet's stdin is not its script here, so it is closed rather than
      // handed the terminal.
      expect(
        daemonShellPayload('echo hi', terminalStdin: false).last,
        contains('")" < /dev/null;'),
      );
    });
  });

  group('running an action over a daemon session', () {
    late _ShellDaemon daemon;
    late MaidCafeAgentHostExecutor executor;

    setUp(() {
      daemon = _ShellDaemon();
      executor = MaidCafeAgentHostExecutor(
        server: _server(),
        target: const MaidCafeTerminalTarget(
          baseUrl: 'https://daemon.example',
          secret: 'metrics-secret',
        ),
        terminals: daemon,
        files: () async => throw UnimplementedError('no file action here'),
      );
    });

    tearDown(() => daemon.dispose());

    test('returns the command output, not the session framing', () async {
      final streamed = StringBuffer();
      final result = await executor.run(
        _command('echo hello; echo world'),
        sink: AgentExecutionSink(interactive: false, onOutput: streamed.write),
      );

      expect(result.trim(), 'hello\nworld');
      // The readiness marker, the prompt and the app's own typing are the
      // session's, and none of them reach the model.
      expect(result, isNot(contains('###')));
      expect(result, isNot(contains('__maidkit_script')));
      expect(streamed.toString(), isNot(contains('###')));
    });

    test('reports the command exit status', () async {
      final result = await executor.run(
        _command('echo before; exit 3'),
        sink: const AgentExecutionSink(interactive: false),
      );

      expect(result.trim(), 'before\n[exit 3]');
    });

    test('runs a saved snippet with its stdin closed', () async {
      final result = await executor.run(
        AgentProposal(
          kind: AgentActionKind.runSnippet,
          arguments: const {'snippet_id': 1, 'server_id': 1},
          toolCall: _call('run_snippet'),
          assistantMessage: _message(),
        ),
        snippetScript: 'cat | wc -c',
        sink: const AgentExecutionSink(interactive: false),
      );

      // `cat` on a closed stdin prints nothing, so the count is zero: the
      // snippet does not inherit the session as its input.
      expect(result.trim(), '0');
    });

    test('publishes the live session so a prompt can be answered', () async {
      final sessions = <AgentExecutionSession>[];
      final seen = StringBuffer();
      final pending = executor.run(
        _command(
          'echo ready-for-answer-please-type-something-then-press-enter; '
          'read answer; echo "got:\$answer"',
        ),
        sink: AgentExecutionSink(
          interactive: true,
          onSession: sessions.add,
          onOutput: seen.write,
        ),
      );

      // The answer is typed once the script is on screen and waiting for it,
      // which is when the card offers the input field.
      await _until(
        () =>
            sessions.isNotEmpty && seen.toString().contains('ready-for-answer'),
      );
      expect(sessions, hasLength(1));
      expect(sessions.single.isStopped, isFalse);
      sessions.single.sendLine('answered');

      expect((await pending).trim(), contains('got:answered'));
    });
  });
}

Server _server() => const Server(
  id: 1,
  name: 'build host',
  host: 'build.example',
  port: 22,
  username: 'builder',
  collectStats: true,
  collectSystemInfo: false,
  connectionType: 'ssh',
  maidCafeTerminalViaCloud: false,
);

AgentProposal _command(String command) => AgentProposal(
  kind: AgentActionKind.command,
  arguments: {'command': command, 'server_id': 1},
  toolCall: _call('run_command'),
  assistantMessage: _message(),
);

OpenAIResponseToolCall _call(String name) => OpenAIResponseToolCall.fromMap({
  'id': 'call-1',
  'type': 'function',
  'function': {'name': name, 'arguments': '{}'},
});

OpenAIChatCompletionChoiceMessageModel _message() =>
    OpenAIChatCompletionChoiceMessageModel(
      role: OpenAIChatMessageRole.assistant,
      content: null,
      toolCalls: const [],
    );

/// Waits for [condition] to hold, polling briefly.
Future<void> _until(bool Function() condition) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('the condition never held');
}

/// A daemon terminal session with a real `/bin/sh` behind it: what the executor
/// types is fed to the shell, what the shell prints comes back as session
/// output, and the shell's exit status comes back as the session's exit code.
///
/// It stands in for the transport, not for the shell: everything the executor
/// depends on — line execution, quoting, `exec`, the exit status — is a real
/// shell's behaviour.
class _ShellDaemon implements MaidCafeTerminalConnectionManager {
  Process? _shell;
  final _typed = <String>[];
  var _closed = false;

  @override
  Future<TerminalSessionHandle> openTerminal(
    Server server,
    MaidCafeTerminalTarget target, {
    String? initialOutput,
    void Function(Uint8List chunk)? onOutput,
    void Function(int? exitCode)? onExit,
  }) async {
    final shell = await Process.start('/bin/sh', const []);
    _shell = shell;
    // The daemon flushes a session's last output before it reports the exit, so
    // the fake waits for the pipe to close first: a caller that reads the
    // status must still see everything the shell wrote.
    final stdoutDone = Completer<void>();
    shell.stdout.listen(
      (chunk) => onOutput?.call(Uint8List.fromList(chunk)),
      onDone: () {
        if (!stdoutDone.isCompleted) stdoutDone.complete();
      },
    );
    unawaited(() async {
      await stdoutDone.future;
      final code = await shell.exitCode;
      if (_closed) return;
      _closed = true;
      onExit?.call(code);
    }());
    return TerminalSessionHandle(
      id: 'maidcafe-test',
      adapter: _NoAdapter(),
      done: Completer<void>().future,
    );
  }

  @override
  void writeToTerminal(String terminalId, String text) {
    _typed.add(text);
    _shell?.stdin.add(utf8.encode(text));
  }

  @override
  Future<void> closeTerminal(String terminalId) async {
    if (_closed) return;
    _closed = true;
    _shell?.kill(ProcessSignal.sigkill);
  }

  /// What the executor typed into the session, for the tests that need to see
  /// the payload itself.
  List<String> get typed => List.unmodifiable(_typed);

  /// Replaces the manager's own teardown; the test owns one session only.
  @override
  Future<void> dispose() async {
    await closeTerminal('maidcafe-test');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoAdapter implements TerminalSessionAdapter {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('this session has no view');
}
