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
    return '${toolCall.function.name}\n${jsonEncode(map)}';
  }

  /// The MCP server id embedded in the qualified tool name
  /// (`mcp_<serverId>__<toolName>`).
  int? get mcpServerId => _mcpServerIdFromName(toolCall.function.name ?? '');

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
  });
  final String? text;
  final AgentProposal? proposal;
  final OpenAIChatCompletionChoiceMessageModel? assistantMessage;
  final String? reasoningContent;
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
    name ??= call.function.name;
    final fragment = call.function.arguments;
    if (fragment != null) arguments.write(fragment);
  }

  OpenAIResponseToolCall build() => OpenAIResponseToolCall.fromMap({
    'id': id,
    'type': type ?? 'function',
    'function': {'name': name, 'arguments': arguments.toString()},
  });
}

class _AgentChatResult {
  const _AgentChatResult({required this.message, this.reasoningContent});
  final OpenAIChatCompletionChoiceMessageModel message;
  final String? reasoningContent;
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

/// A deliberately small remote-tool boundary. The model can propose actions,
/// but this class never executes one until the UI explicitly calls [execute].
class SshAgentService {
  SshAgentService(
    this._configuration, {
    String personality = '',
    String uiLanguage = 'en',
    this.hideServerAddresses = false,
  }) : _personality = personality.trim(),
       _uiLanguage = uiLanguage.trim().isEmpty ? 'en' : uiLanguage.trim();
  final AgentConfiguration _configuration;
  final String _personality;
  final String _uiLanguage;

  /// When enabled, the system prompt redacts server hosts and instructs the
  /// model to never repeat addresses in its replies (tool calls may still
  /// reference real servers).
  final bool hideServerAddresses;

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

  Future<AgentTurn> request({
    required List<AgentServerTarget> servers,
    List<AgentSnippetTarget> snippets = const [],
    List<AgentMcpToolTarget> mcpTools = const [],
    List<AgentSkillTarget> skills = const [],
    String? mcpUnavailable,
    required String prompt,
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
      );
    }
    final call = calls.first;
    final kind = switch (call.function.name) {
      'run_command' => AgentActionKind.command,
      'read_file' => AgentActionKind.readFile,
      'write_file' => AgentActionKind.writeFile,
      'delete_file' => AgentActionKind.deleteFile,
      'create_snippet' => AgentActionKind.createSnippet,
      'run_snippet' => AgentActionKind.runSnippet,
      'get_skill' => AgentActionKind.getSkill,
      final String name when name.startsWith('mcp_') =>
        AgentActionKind.mcpToolCall,
      _ => throw StateError('Unsupported agent tool: ${call.function.name}'),
    };
    return AgentTurn(
      text: text,
      assistantMessage: message,
      reasoningContent: result.reasoningContent,
      proposal: AgentProposal(
        kind: kind,
        arguments: Map<String, dynamic>.from(
          jsonDecode(call.function.arguments) as Map,
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
  }) => executeProposal(
    client,
    proposal,
    snippetScript: snippetScript,
    cancelToken: cancelToken,
  );

  /// Runs the remote half of [proposal] over [client]. Shared by the chat page
  /// and the local MCP server so both entry points execute actions identically.
  static Future<String> executeProposal(
    SSHClient client,
    AgentProposal proposal, {
    String? snippetScript,
    AgentCancelToken? cancelToken,
  }) async {
    SSHSession? session;
    void closeSession() {
      session?.close();
    }

    cancelToken?.register(closeSession);
    try {
      final path = proposal.arguments['path'] as String?;
      switch (proposal.kind) {
        case AgentActionKind.command:
          session = await client.execute(
            proposal.arguments['command'] as String,
          );
          cancelToken?.throwIfCancelled();
          final output = await utf8.decoder.bind(session.stdout).join();
          final error = await utf8.decoder.bind(session.stderr).join();
          await session.done;
          cancelToken?.throwIfCancelled();
          return _limit('$output$error');
        case AgentActionKind.runSnippet:
          if (snippetScript == null || snippetScript.trim().isEmpty) {
            throw ArgumentError('The saved snippet is empty.');
          }
          session = await client.execute('sh -s');
          session.stdin.add(
            Uint8List.fromList(utf8.encode('$snippetScript\n')),
          );
          await session.stdin.close();
          final output = await utf8.decoder.bind(session.stdout).join();
          final error = await utf8.decoder.bind(session.stderr).join();
          await session.done;
          cancelToken?.throwIfCancelled();
          return _limit('$output$error');
        case AgentActionKind.readFile:
          if (path == null || path.isEmpty) {
            throw ArgumentError('A file path is required to read a file.');
          }
          return await _withSftp(client, cancelToken, (sftp) async {
            final file = await sftp.open(path, mode: SftpFileOpenMode.read);
            try {
              return _limit(utf8.decode(await file.readBytes()));
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
    } finally {
      cancelToken?.unregister(closeSession);
    }
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

  static String _limit(String value) => value.length <= 12000
      ? value
      : '${value.substring(0, 12000)}\n[output truncated]';

  Map<String, dynamic> _rawMessage(String role, String text) => {
    'role': role,
    'content': text,
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
          'tools': [
            for (final tool in _tools) tool.toMap(),
            if (mcpTools.isNotEmpty)
              for (final tool in mcpTools) tool.toOpenAiToolMap(),
            if (skills.isNotEmpty) _getSkillTool.toMap(),
          ],
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
