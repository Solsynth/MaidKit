import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/maidcafe_terminal_connection_manager.dart';
import 'package:maid_kit/servers/remote_file_system.dart';
import 'package:maid_kit/servers/server_models.dart';

import 'ssh_agent_service.dart';

/// What one agent action needs from the host it runs on: a shell to run a
/// command through, and a filesystem to read and write with.
///
/// Two transports implement it and the page picks the one this build can
/// actually open — SSH where a raw socket exists, a MaidCafe daemon where it
/// does not (a browser). Everything above this line (which snippet, which path,
/// what the model asked for) is the same on either, and so is what the action
/// hands back.
abstract interface class AgentHostExecutor {
  /// Runs the remote half of [proposal]. [snippetScript] is the saved snippet
  /// for [AgentActionKind.runSnippet], which a caller reads from its own store.
  Future<String> run(
    AgentProposal proposal, {
    String? snippetScript,
    AgentCancelToken? cancelToken,
    AgentExecutionSink? sink,
  });
}

/// The SSH transport, unchanged: the app's own long-standing path, and the only
/// one a desktop build uses.
class SshAgentHostExecutor implements AgentHostExecutor {
  const SshAgentHostExecutor(this.client);

  final SSHClient client;

  @override
  Future<String> run(
    AgentProposal proposal, {
    String? snippetScript,
    AgentCancelToken? cancelToken,
    AgentExecutionSink? sink,
  }) => SshAgentService.executeProposal(
    client,
    proposal,
    snippetScript: snippetScript,
    cancelToken: cancelToken,
    sink: sink,
  );
}

/// The MaidCafe daemon transport: a terminal session for commands, the daemon's
/// file API for files.
///
/// This is what makes an agent action possible in a browser, where no raw
/// socket can be opened. The daemon has no exec request — its terminal is an
/// interactive login shell on a PTY — so a command is typed into that shell;
/// see [daemonShellPayload] for how that stays immune to what the model wrote,
/// and [_runShell] for how the run finds the end and the exit status.
class MaidCafeAgentHostExecutor implements AgentHostExecutor {
  MaidCafeAgentHostExecutor({
    required this.server,
    required this.target,
    required this.terminals,
    required this.files,
  });

  final Server server;

  /// The route to dial, already resolved by the caller (endpoint, credential,
  /// relay ticket, and the account a terminal may open as).
  final MaidCafeTerminalTarget target;

  final MaidCafeTerminalConnectionManager terminals;

  /// Opens the host's file transport — the daemon's file API, resolved exactly
  /// as the file surfaces resolve it. Lazy because a command never needs it.
  final Future<RemoteFileClient> Function() files;

  @override
  Future<String> run(
    AgentProposal proposal, {
    String? snippetScript,
    AgentCancelToken? cancelToken,
    AgentExecutionSink? sink,
  }) async {
    try {
      final path = proposal.arguments['path'] as String?;
      switch (proposal.kind) {
        case AgentActionKind.command:
          return await _runShell(
            proposal.arguments['command'] as String,
            // Only an action whose prompts somebody can answer keeps the
            // terminal as its stdin; the SSH path draws the same line with its
            // pseudo terminal.
            terminalStdin: sink?.interactive ?? false,
            cancelToken: cancelToken,
            sink: sink,
          );
        case AgentActionKind.runSnippet:
          if (snippetScript == null || snippetScript.trim().isEmpty) {
            throw ArgumentError('The saved snippet is empty.');
          }
          return await _runShell(
            snippetScript,
            // The script travels in the command, so stdin is not the script:
            // it is closed, exactly as the SSH path closes it after writing the
            // script out.
            terminalStdin: false,
            cancelToken: cancelToken,
            sink: sink,
          );
        case AgentActionKind.readFile:
          if (path == null || path.isEmpty) {
            throw ArgumentError('A file path is required to read a file.');
          }
          return await _withFile(cancelToken, (client) async {
            final file = await client.open(path, mode: SftpFileOpenMode.read);
            try {
              return limitAgentOutput(utf8.decode(await file.readBytes()));
            } finally {
              await file.close();
            }
          });
        case AgentActionKind.writeFile:
          if (path == null || path.isEmpty) {
            throw ArgumentError('A file path is required to write a file.');
          }
          final content = proposal.arguments['content'] as String;
          return await _withFile(cancelToken, (client) async {
            final file = await client.open(
              path,
              mode:
                  SftpFileOpenMode.write |
                  SftpFileOpenMode.create |
                  SftpFileOpenMode.truncate,
            );
            try {
              await file.writeBytes(Uint8List.fromList(utf8.encode(content)));
            } finally {
              await file.close();
            }
            return 'Wrote $path';
          });
        case AgentActionKind.deleteFile:
          if (path == null || path.isEmpty) {
            throw ArgumentError('A file path is required to delete a file.');
          }
          return await _withFile(cancelToken, (client) async {
            await client.remove(path);
            return 'Deleted $path';
          });
        case AgentActionKind.createSnippet:
          throw UnsupportedError('Snippet creation is handled by the app.');
        case AgentActionKind.mcpToolCall:
        case AgentActionKind.getSkill:
          throw UnsupportedError(
            '${proposal.kind} is executed by the app, not on the host.',
          );
      }
    } catch (error) {
      if (cancelToken?.isCancelled ?? false) {
        throw const AgentCancelledException();
      }
      rethrow;
    }
  }

  /// Opens the host's file transport for one action and always releases it: the
  /// resolver retains a daemon session per client, so the close is the matching
  /// release.
  Future<String> _withFile(
    AgentCancelToken? cancelToken,
    Future<String> Function(RemoteFileClient client) action,
  ) async {
    final client = await files();
    void closeClient() {
      unawaited(client.close());
    }

    cancelToken?.register(closeClient);
    try {
      cancelToken?.throwIfCancelled();
      return await action(client);
    } finally {
      cancelToken?.unregister(closeClient);
      await client.close();
    }
  }

  /// Runs [script] in one daemon terminal session and returns what it printed.
  ///
  /// Nothing about the session's own chatter is trusted to be quiet: the script
  /// is wrapped in two markers and only what falls between them is the result.
  /// What the shell echoes back — of the payload, of its prompt, of whatever an
  /// operator's `~/.zshrc` draws on every line — lands before the first marker
  /// or after the last one, and is dropped.
  Future<String> _runShell(
    String script, {
    required bool terminalStdin,
    AgentCancelToken? cancelToken,
    AgentExecutionSink? sink,
  }) async {
    final nonce = _newRunNonce();
    final begin = '${_markerPrefix}BEGIN-$nonce###';
    final end = '${_markerPrefix}END-$nonce:';
    final lines = daemonShellPayload(
      script,
      terminalStdin: terminalStdin,
      nonce: nonce,
    ).toList();

    final output = StringBuffer();
    // The session's own noise until the begin marker, and everything after it
    // that has not been classified yet.
    final chatter = StringBuffer();
    final gathered = StringBuffer();
    final ended = Completer<int?>();
    var began = false;
    var searched = 0;
    var matchAt = -1;
    var streamed = 0;
    // Set once the session is open; see the quiet-phase deadline below.
    Timer? quiet;
    const decoder = Utf8Decoder(allowMalformed: true);

    void append(String text) {
      final remaining = maxStreamedAgentCharacters - output.length;
      if (remaining <= 0 || text.isEmpty) return;
      final kept = text.length <= remaining
          ? text
          : text.substring(0, remaining);
      output.write(kept);
      sink?.onOutput?.call(kept);
    }

    /// Hands over everything that cannot still turn into the end marker, so a
    /// marker split across chunks is never mistaken for output. [flush] is for
    /// the end of the run, when nothing more can arrive.
    void deliver({bool flush = false}) {
      if (!began) return;
      final text = gathered.toString();
      final readable = matchAt >= 0
          ? matchAt
          : flush
          ? text.length
          : math.max(0, text.length - (end.length - 1));
      if (readable <= streamed) return;
      final from = streamed;
      streamed = readable;
      append(text.substring(from, readable));
    }

    /// Looks for the end marker, and for the status it carries: the status is
    /// only believed once its own `###` terminator arrived.
    void scan() {
      final text = gathered.toString();
      if (matchAt < 0) {
        final at = text.indexOf(end, searched);
        if (at < 0) {
          searched = math.max(0, text.length - (end.length - 1));
          deliver();
          return;
        }
        matchAt = at;
      }
      final tail = text.substring(matchAt + end.length);
      final close = tail.indexOf('###');
      deliver();
      if (close >= 0 && !ended.isCompleted) {
        ended.complete(int.tryParse(tail.substring(0, close)));
      }
    }

    void feed(String text) {
      if (began) {
        gathered.write(text);
        scan();
        return;
      }
      chatter.write(text);
      // Only the tail can still hold the marker, so the session's own scrollback
      // never grows without bound before it arrives.
      if (chatter.length > _chatterCap) {
        final kept = chatter.toString().substring(
          chatter.length - _chatterRoom,
        );
        chatter
          ..clear()
          ..write(kept);
      }
      final at = chatter.toString().indexOf(begin);
      if (at < 0) return;
      began = true;
      quiet?.cancel();
      feed(chatter.toString().substring(at + begin.length));
    }

    final handle = await terminals.openTerminal(
      server,
      target,
      onOutput: (chunk) => feed(decoder.convert(chunk)),
      onExit: (exitCode) {
        // A script that exits the shell (or a daemon that ends the session)
        // ends the run without the marker; the session's own status stands in.
        if (!ended.isCompleted) ended.complete(exitCode);
      },
    );
    // A shell that never runs the payload — an allowlisted shell without POSIX
    // assignments, say — never prints the begin marker, and holding its complaint
    // back would leave the card empty with nothing to act on. After this long the
    // run gives up on the quiet phase and streams what the session said.
    quiet = Timer(_beginTimeout, () {
      if (began) return;
      began = true;
      final said = chatter.toString();
      chatter.clear();
      gathered.write(said);
      deliver();
    });
    final session = AgentExecutionSession(
      sendLine: (line) => terminals.writeToTerminal(handle.id, '$line\n'),
      terminate: () => unawaited(terminals.closeTerminal(handle.id)),
    );
    sink?.onSession?.call(session);
    void abort() => session.stop();
    cancelToken?.register(abort);
    try {
      for (final line in lines) {
        terminals.writeToTerminal(handle.id, '$line\n');
      }
      final exitCode = await ended.future;
      cancelToken?.throwIfCancelled();
      // A script that exited the shell never printed the end marker, and its
      // output was still inside the hold-back: the run is over, so the tail is
      // the tail.
      deliver(flush: true);
      final body = _trimSessionNoise(settleTerminalOutput(output.toString()));
      final status = session.isStopped
          ? '\n[stopped by user]'
          : exitCode == null || exitCode == 0
          ? ''
          : '\n[exit $exitCode]';
      return '${limitAgentOutput(body)}$status';
    } finally {
      quiet.cancel();
      session.markClosed();
      cancelToken?.unregister(abort);
      await terminals.closeTerminal(handle.id);
    }
  }

  /// Bounds on the session's own chatter before the begin marker: only its tail
  /// can still hold the marker, and this is what keeps a chatty login banner
  /// from being held in memory for the whole run.
  static const _chatterCap = 8192;
  static const _chatterRoom = 512;

  /// How long a session is given to print the begin marker before its own words
  /// are streamed instead of held back.
  static const _beginTimeout = Duration(seconds: 15);

  /// Leading blank lines and trailing blanks are the markers' own framing, not
  /// the script's output.
  static String _trimSessionNoise(String value) =>
      value.replaceFirst(RegExp(r'^[\n\r]+'), '').trimRight();
}

/// The prefix of every marker a run puts in the stream.
const String _markerPrefix = '###MAIDKIT-AGENT-';

/// A token no script can predict, so a run's markers are its own even if the
/// script prints what looks like a marker of another run's.
String _newRunNonce() {
  final random = math.Random();
  return List.generate(
    4,
    (_) => random.nextInt(1 << 16).toRadixString(16).padLeft(4, '0'),
  ).join();
}

/// The lines to type into a daemon terminal session to run [script] there.
///
/// The daemon opens an interactive login shell on a PTY and offers no exec
/// request, so a script can only be typed into that shell. Three properties
/// make that safe:
///
/// * The text is carried as octal escapes of its UTF-8 bytes, accumulated in
///   one shell variable, so nothing the model wrote — quotes, `$`, backticks,
///   here-doc delimiters, newlines — can be reinterpreted by the shell.
/// * Every typed line stays far below the terminal driver's canonical input
///   limit (1024 bytes on BSD, 4096 on Linux), because the escapes are sliced
///   into fixed-size pieces, however long the script is.
/// * [nonce] names the run in the markers around its output, and both markers
///   are printed through `%s` so the shell's *echo* of the typed line cannot
///   contain them: the echoed line holds `%s` where the printed line holds the
///   token. Without that, the app would find its own typing where it looks for
///   the start of the output.
///
/// The last typed line does all the work: it prints the begin marker, runs the
/// decoded script in place, and prints the end marker with the script's status.
/// One line, because anything the shell prints between two lines — a prompt, or
/// a themed `precmd` drawing one — would otherwise land inside the result.
/// [terminalStdin] keeps the terminal as the script's stdin, which is what lets
/// a prompt be answered, and otherwise gives it `/dev/null`, the same stdin the
/// SSH path hands a snippet.
Iterable<String> daemonShellPayload(
  String script, {
  required bool terminalStdin,
  String? nonce,
}) sync* {
  final token = nonce ?? _newRunNonce();
  final name = '__maidkit_script';
  yield "$name=''";
  final encoded = _octalEscapes(script);
  for (var at = 0; at < encoded.length; at += _payloadChunk) {
    final chunk = encoded.substring(
      at,
      math.min(at + _payloadChunk, encoded.length),
    );
    yield "$name=\$$name'$chunk'";
  }
  final stdin = terminalStdin ? '' : ' < /dev/null';
  yield "printf '\\n${_markerPrefix}BEGIN-%s###\\n' $token; "
      'eval "\$(printf %b "\$$name")"$stdin; '
      "printf '\\n${_markerPrefix}END-%s:%s###\\n' $token \"\$?\"";
}

/// Characters of encoded text per typed line, chosen so the whole line stays
/// under the smallest canonical input limit a daemon may run on.
const int _payloadChunk = 900;

/// [value] as `printf %b` octal escapes: every byte becomes `\0` and three
/// octal digits, which no shell reinterprets.
String _octalEscapes(String value) {
  final buffer = StringBuffer();
  for (final byte in utf8.encode(value)) {
    buffer
      ..write(r'\0')
      ..write(byte.toRadixString(8).padLeft(3, '0'));
  }
  return buffer.toString();
}
