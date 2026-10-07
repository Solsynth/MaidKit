import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_openai/dart_openai.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;

import 'package:maid_kit/agent/mcp_client.dart' show withSafeToRunProperty;

import 'agent_cancel_token.dart';
import 'agent_repository.dart';
import 'token_counter.dart';

export 'agent_cancel_token.dart';

enum AgentActionKind {
  command,
  readFile,
  writeFile,
  deleteFile,
  createSnippet,
  runSnippet,
  mcpToolCall,
  getSkill,
}

class AgentSnippetTarget {
  const AgentSnippetTarget({required this.id, required this.name});
  final int id;
  final String name;

  String get description => '$id: $name';
}

class AgentServerTarget {
  const AgentServerTarget({
    required this.id,
    required this.name,
    required this.host,
    required this.username,
  });
  final int id;
  final String name;
  final String host;
  final String username;

  String get description => '$id: $name ($username@$host)';

  /// Same as [description] but without the host, used when address hiding is
  /// enabled so the model never sees an IP it could echo back.
  String get redactedDescription => '$id: $name ($username)';
}

class AgentProposal {
  const AgentProposal({
    required this.kind,
    required this.arguments,
    required this.toolCall,
    required this.assistantMessage,
    this.explanation,
    this.reasoningContent,
  });

  final AgentActionKind kind;
  final Map<String, dynamic> arguments;
  final OpenAIResponseToolCall toolCall;
  final OpenAIChatCompletionChoiceMessageModel assistantMessage;
  final String? explanation;

  /// DeepSeek reasoning models require the assistant's `reasoning_content` to
  /// be passed back verbatim on the next request. Captured during streaming so
  /// the continuation after an approved action can include it.
  final String? reasoningContent;

  int? get serverId => arguments['server_id'] as int?;

  String get title => switch (kind) {
    AgentActionKind.command => 'agentActionRunCommand'.tr(),
    AgentActionKind.readFile => 'agentActionReadFile'.tr(),
    AgentActionKind.writeFile => 'agentActionWriteFile'.tr(),
    AgentActionKind.deleteFile => 'agentActionDeleteFile'.tr(),
    AgentActionKind.createSnippet => 'agentActionCreateSnippet'.tr(),
    AgentActionKind.runSnippet => 'agentActionRunSnippet'.tr(),
    AgentActionKind.mcpToolCall => 'agentActionMcpTool'.tr(),
    AgentActionKind.getSkill => 'agentActionGetSkill'.tr(),
  };

  String get detail => switch (kind) {
    AgentActionKind.command => arguments['command'] as String? ?? '',
    AgentActionKind.readFile ||
    AgentActionKind.deleteFile => arguments['path'] as String? ?? '',
    AgentActionKind.writeFile => arguments['path'] as String? ?? '',
    AgentActionKind.createSnippet =>
      '${arguments['name'] as String? ?? ''}\n\n${arguments['script'] as String? ?? ''}',
    AgentActionKind.runSnippet => 'agentActionSnippetId'.tr(
      args: ['${arguments['snippet_id'] as int? ?? ''}'],
    ),
    AgentActionKind.mcpToolCall => _mcpDetail(),
    AgentActionKind.getSkill => 'agentSkillId'.tr(
      args: ['${arguments['skill_id'] as int? ?? ''}'],
    ),
  };

  String _mcpDetail() {
    final map = Map<String, dynamic>.from(arguments)..remove('safe_to_run');
    return '${toolCall.function?.name}\n${jsonEncode(map)}';
  }

  /// The MCP server id embedded in the qualified tool name
  /// (`mcp_<serverId>__<toolName>`).
  int? get mcpServerId => _mcpServerIdFromName(toolCall.function?.name ?? '');

  static int? _mcpServerIdFromName(String name) {
    if (!name.startsWith('mcp_')) return null;
    final underscore = name.indexOf('__');
    if (underscore < 0) return null;
    return int.tryParse(name.substring(4, underscore));
  }

  /// True when the model flagged the action as safe to run without review, or
  /// the action is read-only by nature.
  bool get safeToRun =>
      arguments['safe_to_run'] as bool? ??
      kind == AgentActionKind.readFile || kind == AgentActionKind.getSkill;
}

class AgentTurn {
  const AgentTurn({
    this.text,
    this.proposal,
    this.assistantMessage,
    this.reasoningContent,
    this.usage,
    this.estimatedPromptTokens = 0,
  });
  final String? text;
  final AgentProposal? proposal;
  final OpenAIChatCompletionChoiceMessageModel? assistantMessage;
  final String? reasoningContent;

  /// What the provider said this call cost, when it said anything at all.
  final AgentTurnUsage? usage;

  /// What the request this call sent was counted at, by the same estimate the
  /// chat's meter uses. It stands in for [usage] on providers that report
  /// nothing, and it is counted from the request itself rather than from the
  /// pieces the caller believes went into it.
  final int estimatedPromptTokens;
}

class _ToolCallAccumulator {
  _ToolCallAccumulator(this.index);
  final int index;
  String? id;
  String? type;
  String? name;
  final arguments = StringBuffer();

  void add(OpenAIResponseToolCall call) {
    id ??= call.id;
    type ??= call.type;
    name ??= call.function?.name;
    final fragment = call.function?.arguments;
    if (fragment != null) arguments.write(fragment);
  }

  OpenAIResponseToolCall build() => OpenAIResponseToolCall.fromMap({
    'id': id,
    'type': type ?? 'function',
    'function': {'name': name, 'arguments': arguments.toString()},
  });
}

class _AgentChatResult {
  const _AgentChatResult({
    required this.message,
    this.reasoningContent,
    this.usage,
    this.estimatedPromptTokens = 0,
  });
  final OpenAIChatCompletionChoiceMessageModel message;
  final String? reasoningContent;
  final AgentTurnUsage? usage;
  final int estimatedPromptTokens;
}

/// A tool exposed by a connected MCP server, projected for the OpenAI request.
/// [name] is the bare MCP tool name; the model sees it qualified as
/// `mcp_<serverId>__<name>` so every server's tools stay unique.
class AgentMcpToolTarget {
  const AgentMcpToolTarget({
    required this.serverId,
    required this.serverName,
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  final int serverId;
  final String serverName;
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  String get qualifiedName => 'mcp_${serverId}__$name';

  static String bareName(String qualifiedName) {
    final separator = qualifiedName.indexOf('__');
    return separator < 0
        ? qualifiedName
        : qualifiedName.substring(separator + 2);
  }

  /// The OpenAI tool declaration for this MCP tool. `safe_to_run` is injected
  /// when the schema allows it so the run policy applies uniformly.
  Map<String, dynamic> toOpenAiToolMap() {
    final parameters =
        withSafeToRunProperty(inputSchema) ??
        Map<String, dynamic>.from(inputSchema);
    return {
      'type': 'function',
      'function': {
        'name': qualifiedName,
        'description': description.isEmpty
            ? 'Tool from MCP server "$serverName".'
            : '$description\nProvided by MCP server "$serverName".',
        'parameters': parameters,
      },
    };
  }
}

/// An enabled skill the model may consult. Listed in the system prompt; full
/// instructions are fetched through the `get_skill` tool.
class AgentSkillTarget {
  const AgentSkillTarget({
    required this.id,
    required this.name,
    required this.description,
  });

  final int id;
  final String name;
  final String description;

  String get descriptionLine =>
      description.isEmpty ? '#$id: $name' : '#$id: $name — $description';
}

/// A live handle to a remote process an agent action started.
///
/// The chat page uses it to answer a prompt (a sudo password, a `[y/N]`
/// question) and to stop a long-running command without cancelling the whole
/// turn. Output itself is delivered through [AgentExecutionSink.onOutput]; the
/// handle only owns the process side.
///
/// It is transport-blind: the two ways this app reaches a host — an SSH channel
/// and a MaidCafe daemon terminal session — each supply the two things the
/// handle does, so the page answers a prompt and stops a command the same way
/// on either.
class AgentExecutionSession {
  AgentExecutionSession({
    required void Function(String line) sendLine,
    required void Function() terminate,
  }) : // The public parameter names are what the callers pass; the private
       // fields keep the handle's own surface to what it does.
       // ignore: prefer_initializing_formals
       _send = sendLine,
       // ignore: prefer_initializing_formals
       _terminate = terminate;

  /// The session of an SSH channel: a keystroke goes to its stdin, and stopping
  /// it signals the remote process and closes the channel.
  AgentExecutionSession.ssh(SSHSession session)
    : _send = ((line) => _writeToSsh(session, line)),
      _terminate = (() => _closeSsh(session));

  static void _writeToSsh(SSHSession session, String line) {
    try {
      session.stdin.add(Uint8List.fromList(utf8.encode('$line\n')));
    } catch (_) {
      // The channel is already gone; the output stream reports the end.
    }
  }

  static void _closeSsh(SSHSession session) {
    try {
      session.kill(SSHSignal.TERM);
    } catch (_) {}
    try {
      session.close();
    } catch (_) {}
  }

  final void Function(String line) _send;
  final void Function() _terminate;
  var _stopped = false;
  var _closed = false;

  /// True once [stop] asked the remote process to terminate, so the caller can
  /// tell a stopped command from one that exited on its own.
  bool get isStopped => _stopped;

  /// Writes [line] and a newline to the process's stdin. A no-op once the
  /// process is gone, so a late keystroke cannot throw into the UI.
  ///
  /// The password of a `sudo` prompt is only ever sent when the user asks for
  /// it: the command being answered was written by the model, so filling it in
  /// automatically would hand the stored secret to whatever prompt appears.
  void sendLine(String line) {
    if (_closed) return;
    _send(line);
  }

  /// Terminates the remote process and closes its channel. The caller's stream
  /// then ends on the output that arrived, so a stopped command becomes a
  /// partial result the turn can continue from instead of an interruption.
  void stop() {
    if (_stopped || _closed) return;
    _stopped = true;
    _terminate();
  }

  /// Marks the process gone, so late input is dropped rather than thrown into
  /// the UI. Called by whoever owns the transport once it reports the end.
  void markClosed() => _closed = true;
}

/// Streaming and interaction hooks for the remote half of an agent action.
///
/// [onOutput] receives output in arrival order, [onSession] receives the live
/// process once it starts so its owner can send input or stop it, and
/// [interactive] allocates a pseudo terminal — without one a command such as
/// `sudo` cannot prompt for a password at all.
class AgentExecutionSink {
  const AgentExecutionSink({
    this.onOutput,
    this.onSession,
    this.interactive = false,
  });

  final void Function(String chunk)? onOutput;
  final void Function(AgentExecutionSession session)? onSession;
  final bool interactive;
}

/// Largest command output kept in memory while it streams, on either transport.
/// The UI log is the reason for a bound at all; what reaches the model is cut
/// shorter still by [limitAgentOutput].
const int maxStreamedAgentCharacters = 64 * 1024;

/// Largest result one action hands back to the model, in characters.
String limitAgentOutput(String value) => value.length <= 12000
    ? value
    : '${value.substring(0, 12000)}\n[output truncated]';

/// The plain text a terminal would show for [value]: escape sequences removed
/// and carriage-return rewrites settled, so a progress line reads as its last
/// frame instead of carrying every frame the process drew.
///
/// A pseudo terminal reports its own `\r\n` line endings and repaints progress
/// in place, neither of which belongs in the result sent to the model or shown
/// in a finished tool card.
String settleTerminalOutput(String value) {
  // Control sequences must not survive into the text, but a bare escape is
  // otherwise kept: the pattern mirrors the terminal's own stripper.
  final plain = value
      .replaceAll(
        RegExp(
          r'\x1B(?:\[[0-9;?]*[ -/]*[@-~]|\][^\x07\x1B]*(?:\x07|\x1B\\)|[@-Z\\-_])',
        ),
        '',
      )
      .replaceAll('\r\n', '\n');
  final settled = StringBuffer();
  var first = true;
  for (final line in plain.split('\n')) {
    if (!first) settled.write('\n');
    first = false;
    final frames = line.split('\r');
    // The last frame is what the line reads as; a frame that came back empty
    // only moved the cursor home, leaving what was already there on screen.
    var frame = frames.last;
    if (frame.isEmpty && frames.length > 1) {
      frame = frames[frames.length - 2];
    }
    settled.write(frame);
  }
  return settled.toString();
}

/// A deliberately small remote-tool boundary. The model can propose actions,
/// but this class never executes one until the UI explicitly calls [execute].
class SshAgentService {
  SshAgentService(
    this._configuration, {
    String personality = '',
    String uiLanguage = 'en',
    this.hideServerAddresses = false,
    this.reasoningEffort,
  }) : _personality = personality.trim(),
       _uiLanguage = uiLanguage.trim().isEmpty ? 'en' : uiLanguage.trim();
  final AgentConfiguration _configuration;
  final String _personality;
  final String _uiLanguage;

  /// When enabled, the system prompt redacts server hosts and instructs the
  /// model to never repeat addresses in its replies (tool calls may still
  /// reference real servers).
  final bool hideServerAddresses;

  /// The `reasoning_effort` every request of this service carries, or null to
  /// send none and leave the choice to the model.
  final String? reasoningEffort;

  static final _safeToRunProperty = OpenAIFunctionProperty.boolean(
    name: 'safe_to_run',
    description:
        'Set to true only when running this action now is safe: it is '
        'read-only, idempotent, or otherwise carries no risk of losing data. '
        'When in doubt, set false so the user can review it.',
  );

  static final _tools = <OpenAIToolModel>[
    _tool('run_command', 'Run one shell command on the selected server', [
      OpenAIFunctionProperty.integer(name: 'server_id', isRequired: true),
      OpenAIFunctionProperty.string(name: 'command', isRequired: true),
      _safeToRunProperty,
    ]),
    _tool('read_file', 'Read a UTF-8 text file from the selected server', [
      OpenAIFunctionProperty.integer(name: 'server_id', isRequired: true),
      OpenAIFunctionProperty.string(name: 'path', isRequired: true),
      _safeToRunProperty,
    ]),
    _tool(
      'write_file',
      'Create or replace a UTF-8 text file on the selected server',
      [
        OpenAIFunctionProperty.integer(name: 'server_id', isRequired: true),
        OpenAIFunctionProperty.string(name: 'path', isRequired: true),
        OpenAIFunctionProperty.string(name: 'content', isRequired: true),
        _safeToRunProperty,
      ],
    ),
    _tool('delete_file', 'Permanently delete a file from the selected server', [
      OpenAIFunctionProperty.integer(name: 'server_id', isRequired: true),
      OpenAIFunctionProperty.string(name: 'path', isRequired: true),
      _safeToRunProperty,
    ]),
    _tool('create_snippet', 'Save a reusable POSIX shell snippet in MaidKit', [
      OpenAIFunctionProperty.string(name: 'name', isRequired: true),
      OpenAIFunctionProperty.string(name: 'script', isRequired: true),
      _safeToRunProperty,
    ]),
    _tool('run_snippet', 'Run a saved MaidKit snippet on the selected server', [
      OpenAIFunctionProperty.integer(name: 'server_id', isRequired: true),
      OpenAIFunctionProperty.integer(name: 'snippet_id', isRequired: true),
      _safeToRunProperty,
    ]),
  ];

  static OpenAIToolModel _tool(
    String name,
    String description,
    List<OpenAIFunctionProperty> parameters,
  ) => OpenAIToolModel(
    type: 'function',
    function: OpenAIFunctionModel.withParameters(
      name: name,
      description: description,
      parameters: parameters,
    ),
  );

  /// The schemas a request advertises: the built-in tools, the enabled MCP
  /// servers' tools, and the skill reader when skills are in play. One place
  /// builds them so a request and its token estimate can never disagree.
  List<Map<String, dynamic>> _toolSchemas(
    List<AgentMcpToolTarget> mcpTools,
    List<AgentSkillTarget> skills,
  ) => [
    for (final tool in _tools) tool.toMap(),
    if (mcpTools.isNotEmpty)
      for (final tool in mcpTools) tool.toOpenAiToolMap(),
    if (skills.isNotEmpty) _getSkillTool.toMap(),
  ];

  static final _getSkillTool = OpenAIToolModel(
    type: 'function',
    function: OpenAIFunctionModel.withParameters(
      name: 'get_skill',
      description:
          'Read the full instructions of a saved skill by its exact '
          'skill_id. Skills contain reusable expertise for common tasks; '
          'call this only when a skill matches the current task.',
      parameters: [
        OpenAIFunctionProperty.integer(name: 'skill_id', isRequired: true),
      ],
    ),
  );

  /// Estimated tokens in the parts of a request that do not move while the
  /// prompt is being written: the system prompt and every tool schema. Callers
  /// count this once per turn and add the history and the draft themselves.
  int estimateStaticTokens({
    required List<AgentServerTarget> servers,
    List<AgentSnippetTarget> snippets = const [],
    List<AgentMcpToolTarget> mcpTools = const [],
    List<AgentSkillTarget> skills = const [],
    String? mcpUnavailable,
  }) =>
      AgentTokenCounter.estimate(
        _systemPrompt(servers, snippets, mcpTools, skills, mcpUnavailable),
      ) +
      AgentTokenCounter.estimateTools(_toolSchemas(mcpTools, skills));

  Future<AgentTurn> request({
    required List<AgentServerTarget> servers,
    List<AgentSnippetTarget> snippets = const [],
    List<AgentMcpToolTarget> mcpTools = const [],
    List<AgentSkillTarget> skills = const [],
    String? mcpUnavailable,

    /// The user message content: a plain string, or the OpenAI multimodal part
    /// list when the turn carries attachments.
    required Object prompt,
    List<Map<String, dynamic>> history = const [],
    void Function(String text)? onText,
    AgentCancelToken? cancelToken,
  }) async {
    final result = await _streamChat(
      [
        _rawMessage(
          'system',
          _systemPrompt(servers, snippets, mcpTools, skills, mcpUnavailable),
        ),
        ...history,
        _rawMessage('user', prompt),
      ],
      onText,
      mcpTools: mcpTools,
      skills: skills,
      cancelToken: cancelToken,
    );
    return _turn(result);
  }

  Future<AgentTurn> continueAfterExecution({
    required List<AgentServerTarget> servers,
    List<AgentSnippetTarget> snippets = const [],
    List<AgentMcpToolTarget> mcpTools = const [],
    List<AgentSkillTarget> skills = const [],
    String? mcpUnavailable,
    required List<Map<String, dynamic>> history,
    required AgentProposal proposal,
    required String result,
    void Function(String text)? onText,
    AgentCancelToken? cancelToken,
  }) async {
    final assistant = proposal.assistantMessage.toMap();
    final reasoningContent = proposal.reasoningContent;
    if (reasoningContent != null && reasoningContent.isNotEmpty) {
      assistant['reasoning_content'] = reasoningContent;
    }
    // The API requires a tool message for every tool call on the assistant
    // message. The model can emit parallel calls, but this app approves one
    // action at a time, so narrow the message down to the approved call.
    assistant['tool_calls'] = [proposal.toolCall.toMap()];
    final resultMessage = await _streamChat(
      [
        _rawMessage(
          'system',
          _systemPrompt(servers, snippets, mcpTools, skills, mcpUnavailable),
        ),
        ...history,
        assistant,
        {
          'role': 'tool',
          'tool_call_id': proposal.toolCall.id ?? 'approved-action',
          'content': result,
        },
      ],
      onText,
      mcpTools: mcpTools,
      skills: skills,
      cancelToken: cancelToken,
    );
    // The API requires the assistant message with its tool call. Reconstruct it
    // from the proposal so no unapproved action is ever replayed.
    return _turn(resultMessage);
  }

  AgentTurn _turn(_AgentChatResult result) {
    final message = result.message;
    final text = message.content?.map((item) => item.text ?? '').join().trim();
    final calls = message.toolCalls;
    if (calls == null || calls.isEmpty) {
      return AgentTurn(
        text: text,
        assistantMessage: message,
        reasoningContent: result.reasoningContent,
        usage: result.usage,
        estimatedPromptTokens: result.estimatedPromptTokens,
      );
    }
    final call = calls.first;
    final function = call.function;
    if (function == null) {
      throw StateError('Agent tool call is missing its function payload');
    }
    final kind = switch (function.name) {
      'run_command' => AgentActionKind.command,
      'read_file' => AgentActionKind.readFile,
      'write_file' => AgentActionKind.writeFile,
      'delete_file' => AgentActionKind.deleteFile,
      'create_snippet' => AgentActionKind.createSnippet,
      'run_snippet' => AgentActionKind.runSnippet,
      'get_skill' => AgentActionKind.getSkill,
      final String name when name.startsWith('mcp_') =>
        AgentActionKind.mcpToolCall,
      _ => throw StateError('Unsupported agent tool: ${function.name}'),
    };
    return AgentTurn(
      text: text,
      assistantMessage: message,
      reasoningContent: result.reasoningContent,
      usage: result.usage,
      estimatedPromptTokens: result.estimatedPromptTokens,
      proposal: AgentProposal(
        kind: kind,
        arguments: Map<String, dynamic>.from(
          jsonDecode(function.arguments ?? '{}') as Map,
        ),
        toolCall: call,
        assistantMessage: message,
        explanation: text?.isEmpty ?? true ? null : text,
        reasoningContent: result.reasoningContent,
      ),
    );
  }

  Future<String> execute(
    SSHClient client,
    AgentProposal proposal, {
    String? snippetScript,
    AgentCancelToken? cancelToken,
    AgentExecutionSink? sink,
  }) => executeProposal(
    client,
    proposal,
    snippetScript: snippetScript,
    cancelToken: cancelToken,
    sink: sink,
  );

  /// Runs the remote half of [proposal] over [client]. Shared by the chat page
  /// and the local MCP server so both entry points execute actions identically.
  static Future<String> executeProposal(
    SSHClient client,
    AgentProposal proposal, {
    String? snippetScript,
    AgentCancelToken? cancelToken,
    AgentExecutionSink? sink,
  }) async {
    try {
      final path = proposal.arguments['path'] as String?;
      switch (proposal.kind) {
        case AgentActionKind.command:
          return await _runSession(
            client,
            proposal.arguments['command'] as String,
            // A PTY is what lets a command that prompts — `sudo`, `read`,
            // a credential helper — ask the user for input at all.
            usePty: sink?.interactive ?? false,
            sink: sink,
            cancelToken: cancelToken,
          );
        case AgentActionKind.runSnippet:
          if (snippetScript == null || snippetScript.trim().isEmpty) {
            throw ArgumentError('The saved snippet is empty.');
          }
          // A snippet's script arrives on stdin, so it must not hold a PTY:
          // the terminal keeps some shells open past end-of-input and the
          // exit status of a snippet has to be deterministic.
          return await _runSession(
            client,
            'sh -s',
            stdin: '$snippetScript\n',
            usePty: false,
            sink: sink,
            cancelToken: cancelToken,
          );
        case AgentActionKind.readFile:
          if (path == null || path.isEmpty) {
            throw ArgumentError('A file path is required to read a file.');
          }
          return await _withSftp(client, cancelToken, (sftp) async {
            final file = await sftp.open(path, mode: SftpFileOpenMode.read);
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
          return await _withSftp(client, cancelToken, (sftp) async {
            final file = await sftp.open(
              path,
              mode:
                  SftpFileOpenMode.write |
                  SftpFileOpenMode.create |
                  SftpFileOpenMode.truncate,
            );
            try {
              await file.writeBytes(
                Uint8List.fromList(
                  utf8.encode(proposal.arguments['content'] as String),
                ),
              );
            } finally {
              await file.close();
            }
            return 'Wrote $path';
          });
        case AgentActionKind.deleteFile:
          if (path == null || path.isEmpty) {
            throw ArgumentError('A file path is required to delete a file.');
          }
          return await _withSftp(client, cancelToken, (sftp) async {
            await sftp.remove(path);
            return 'Deleted $path';
          });
        case AgentActionKind.createSnippet:
          throw UnsupportedError('Snippet creation is handled by the app.');
        case AgentActionKind.mcpToolCall:
        case AgentActionKind.getSkill:
          throw UnsupportedError(
            '${proposal.kind} is executed by the app, not over SSH.',
          );
      }
    } catch (error) {
      if (cancelToken?.isCancelled ?? false) {
        throw const AgentCancelledException();
      }
      rethrow;
    }
  }

  /// Runs one remote process, forwarding its output as it arrives and letting
  /// the sink's owner answer prompts or stop it.
  ///
  /// Output is capped while it is collected: a command that never ends would
  /// otherwise grow both the socket buffer and the UI's log without bound, and
  /// the result the model receives is truncated well below this anyway.
  static Future<String> _runSession(
    SSHClient client,
    String command, {
    String? stdin,
    required bool usePty,
    AgentExecutionSink? sink,
    AgentCancelToken? cancelToken,
  }) async {
    final session = await client.execute(
      command,
      pty: usePty
          ? const SSHPtyConfig(type: 'xterm-256color', width: 120, height: 40)
          : null,
    );
    final handle = AgentExecutionSession.ssh(session);
    sink?.onSession?.call(handle);
    void abort() => handle.stop();
    cancelToken?.register(abort);
    final output = StringBuffer();
    // Malformed bytes are replaced rather than thrown: a command may print
    // binary, and the turn must not fail because of what it printed.
    const decoder = Utf8Decoder(allowMalformed: true);
    void collect(String text) {
      final remaining = maxStreamedAgentCharacters - output.length;
      if (remaining <= 0) return;
      final kept = text.length <= remaining
          ? text
          : text.substring(0, remaining);
      output.write(kept);
      sink?.onOutput?.call(kept);
    }

    final stdoutDone = decoder.bind(session.stdout).listen(collect).asFuture();
    final stderrDone = decoder.bind(session.stderr).listen(collect).asFuture();
    if (stdin != null) {
      session.stdin.add(Uint8List.fromList(utf8.encode(stdin)));
      await session.stdin.close();
    }
    try {
      await session.done;
      await Future.wait([stdoutDone, stderrDone]);
    } finally {
      handle.markClosed();
      cancelToken?.unregister(abort);
    }
    cancelToken?.throwIfCancelled();
    final exitCode = session.exitCode;
    // The status is appended after truncation: what a command was stopped or
    // failed with matters more than the tail of a long dump.
    final status = handle.isStopped
        ? '\n[stopped by user]'
        : exitCode == null || exitCode == 0
        ? ''
        : '\n[exit $exitCode]';
    return '${limitAgentOutput(settleTerminalOutput(output.toString()))}$status';
  }

  /// Opens one SFTP channel for an action and always closes it afterwards.
  ///
  /// [SSHClient.sftp] opens a new SSH session channel on every call. Reusing
  /// the authenticated [SSHClient] does not reuse those channels, so leaving
  /// the [SftpClient] open eventually makes the server reject new channels.
  static Future<T> _withSftp<T>(
    SSHClient client,
    AgentCancelToken? cancelToken,
    Future<T> Function(SftpClient sftp) action,
  ) async {
    final sftp = await client.sftp();
    void closeSftp() {
      unawaited(sftp.close());
    }

    cancelToken?.register(closeSftp);
    try {
      cancelToken?.throwIfCancelled();
      return await action(sftp);
    } finally {
      cancelToken?.unregister(closeSftp);
      await sftp.close();
    }
  }

  /// [content] is what the OpenAI-compatible endpoint accepts under `content`:
  /// a string, or a multimodal part list.
  Map<String, dynamic> _rawMessage(String role, Object content) => {
    'role': role,
    'content': content,
  };

  String _systemPrompt(
    List<AgentServerTarget> servers,
    List<AgentSnippetTarget> snippets,
    List<AgentMcpToolTarget> mcpTools,
    List<AgentSkillTarget> skills,
    String? mcpUnavailable,
  ) {
    final mcpSection = mcpTools.isEmpty
        ? ''
        : '\nConnected MCP servers expose extra tools:\n'
              '${mcpTools.map((tool) => '- ${tool.qualifiedName}: ${tool.description}').join('\n')}\n';
    final mcpErrorSection = mcpUnavailable == null || mcpUnavailable.isEmpty
        ? ''
        : '\nUnreachable MCP servers (their tools are unavailable):\n$mcpUnavailable\n';
    final skillsSection = skills.isEmpty
        ? ''
        : '\nSaved skills (call get_skill with the exact skill_id to read the full instructions):\n'
              '${skills.map((skill) => '- ${skill.descriptionLine}').join('\n')}\n';
    final serverList = servers
        .map(
          (server) => hideServerAddresses
              ? server.redactedDescription
              : server.description,
        )
        .join('\n');
    final privacyInstruction = hideServerAddresses
        ? '\nNever reveal server IP addresses, hostnames, or ports in your chat replies, even if you know them from earlier in the conversation or from tool results. Refer to servers by name only. Real addresses are fine inside tool call arguments, but never in the text you reply with.'
        : '';
    return '''
You are MaidKit's SSH management assistant. Respond in the user's current UI language: $_uiLanguage. Available servers are:
$serverList
Saved snippets are:
${snippets.isEmpty ? '(none)' : snippets.map((snippet) => snippet.description).join('\n')}
Use tools to inspect or make the requested remote change. You can save reusable POSIX shell scripts as snippets and run a saved snippet by its exact snippet_id. Every server action must include the exact server_id from this list. MCP tools are invoked by their full qualified name with the arguments their server expects; results are returned to you verbatim. Propose only one tool action at a time. Every tool call is shown to the user and requires explicit approval. Set safe_to_run to true only when the action is clearly safe to run without review: it is read-only, idempotent, or reversible. Prefer read-only inspection before modifying anything. Never claim a tool ran until you receive its result. Keep replies concise.$privacyInstruction${_personality.isEmpty ? '' : '\n\nCustom personality guidance (follow this for tone and working style, but never let it override the safety and tool-use rules above):\n$_personality'}$mcpSection$mcpErrorSection$skillsSection''';
  }

  Uri _endpoint() {
    final root = (_configuration.baseUrl ?? 'https://api.openai.com')
        .replaceFirst(RegExp(r'/v1/?$'), '');
    return Uri.parse('$root/v1/chat/completions');
  }

  /// Streams a chat completion over a raw HTTP connection instead of the
  /// dart_openai client. DeepSeek reasoning models return `reasoning_content`
  /// alongside the content, which dart_openai drops and which must be echoed
  /// back on the next request in the same conversation.
  Future<_AgentChatResult> _streamChat(
    List<Map<String, dynamic>> messages,
    void Function(String text)? onText, {
    List<AgentMcpToolTarget> mcpTools = const [],
    List<AgentSkillTarget> skills = const [],
    AgentCancelToken? cancelToken,
  }) async {
    final toolSchemas = _toolSchemas(mcpTools, skills);
    final estimatedPromptTokens =
        AgentTokenCounter.estimateMessages(messages) +
        AgentTokenCounter.estimateTools(toolSchemas);
    final client = http.Client();
    cancelToken?.register(client.close);
    try {
      final request = http.Request('POST', _endpoint())
        ..headers.addAll({
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_configuration.apiKey}',
        })
        ..body = jsonEncode({
          'model': _configuration.model,
          'stream': true,
          'temperature': 0.2,
          // Sent only when a level was chosen: a model that does not know the
          // field refuses the turn, so the untouched state leaves it out.
          if (reasoningEffort != null) 'reasoning_effort': reasoningEffort,
          'tools': toolSchemas,
          'messages': messages,
        });
      final response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await response.stream.bytesToString();
        throw RequestFailedException(
          _apiErrorMessage(body) ?? 'HTTP ${response.statusCode}',
          response.statusCode,
        );
      }
      final text = StringBuffer();
      final reasoning = StringBuffer();
      final calls = <int, _ToolCallAccumulator>{};
      AgentTurnUsage? reportedUsage;
      await for (final line
          in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        cancelToken?.throwIfCancelled();
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data.isEmpty || data == '[DONE]') continue;
        final Object? decoded;
        try {
          decoded = jsonDecode(data);
        } catch (_) {
          continue;
        }
        if (decoded is! Map<String, dynamic>) continue;
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          throw RequestFailedException(
            error['message'] as String? ?? 'Request failed',
            response.statusCode,
          );
        }
        // A provider that reports usage does it on the last frame, which
        // carries an empty `choices` list, so this is read before the frame is
        // discarded as a keep-alive.
        reportedUsage =
            AgentTurnUsage.fromJson(decoded['usage']) ?? reportedUsage;
        final choices = decoded['choices'];
        if (choices is! List || choices.isEmpty) continue;
        final choice = choices.first;
        if (choice is! Map<String, dynamic>) continue;
        final delta = choice['delta'];
        if (delta is! Map<String, dynamic>) continue;
        final content = delta['content'];
        if (content is String && content.isNotEmpty) {
          text.write(content);
          onText?.call(text.toString());
        }
        final reasoningContent = delta['reasoning_content'];
        if (reasoningContent is String && reasoningContent.isNotEmpty) {
          reasoning.write(reasoningContent);
        }
        final toolCalls = delta['tool_calls'];
        if (toolCalls is List) {
          for (final call in toolCalls) {
            if (call is! Map<String, dynamic>) continue;
            final index = call['index'];
            if (index is! int) continue;
            final model = OpenAIStreamResponseToolCall.fromMap(call);
            (calls[index] ??= _ToolCallAccumulator(index)).add(model);
          }
        }
      }
      return _AgentChatResult(
        message: OpenAIChatCompletionChoiceMessageModel(
          role: OpenAIChatMessageRole.assistant,
          content: text.isEmpty
              ? null
              : [
                  OpenAIChatCompletionChoiceMessageContentItemModel.text(
                    text.toString(),
                  ),
                ],
          toolCalls: calls.values.map((call) => call.build()).toList(),
        ),
        reasoningContent: reasoning.isEmpty ? null : reasoning.toString(),
        usage: reportedUsage,
        estimatedPromptTokens: estimatedPromptTokens,
      );
    } catch (error) {
      if (cancelToken?.isCancelled ?? false) {
        throw const AgentCancelledException();
      }
      rethrow;
    } finally {
      cancelToken?.unregister(client.close);
      client.close();
    }
  }

  String? _apiErrorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic> && decoded['error'] is Map) {
        final error = decoded['error'] as Map;
        final message = error['message'];
        if (message is String && message.isNotEmpty) return message;
      }
    } catch (_) {
      // Fall back to the raw status code below.
    }
    return null;
  }
}
