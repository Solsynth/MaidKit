import 'dart:async';
import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:dart_openai/dart_openai.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:markdown_widget/markdown_widget.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/shared/presentation/app_scaffold.dart';
import 'package:maid_kit/theme.dart';
import 'package:maid_kit/shared/presentation/maidkit_alert.dart';
import 'package:maid_kit/servers/server_connection_actions.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/snippets/snippet_repository.dart';
import 'package:maid_kit/agent/mcp_client.dart';
import 'package:maid_kit/agent/mcp_config_parser.dart';
import 'package:maid_kit/agent/mcp_repository.dart';
import 'package:maid_kit/agent/skill_repository.dart';
import 'package:maid_kit/agent/skill_registry.dart';
import 'agent_input_focus.dart';
import 'conversation_store.dart';
import 'personality_service.dart';
import 'agent_repository.dart';
import 'agent_run_policy.dart';
import 'ssh_agent_service.dart';

class _AgentProviderPreset {
  const _AgentProviderPreset(this.name, this.baseUrl, this.models);
  final String name;
  final String baseUrl;
  final List<String> models;
}

const _providerPresets = [
  _AgentProviderPreset('OpenAI', 'https://api.openai.com', [
    'gpt-4o-mini',
    'gpt-4.1-mini',
  ]),
  _AgentProviderPreset('DeepSeek', 'https://api.deepseek.com', [
    'deepseek-v4-flash',
    'deepseek-v4-pro',
  ]),
  _AgentProviderPreset('OpenRouter', 'https://openrouter.ai/api', [
    'anthropic/claude-sonnet-4',
    'deepseek/deepseek-chat',
    'openai/gpt-4o-mini',
  ]),
  _AgentProviderPreset('Ollama', 'http://localhost:11434', [
    'llama3.2',
    'qwen2.5-coder',
    'deepseek-r1',
  ]),
];

List<String> _presetModelsFor(AgentProvider provider) {
  for (final preset in _providerPresets) {
    if (preset.name == provider.name || preset.baseUrl == provider.baseUrl) {
      return preset.models;
    }
  }
  return const [];
}

@RoutePage()
class AgentPage extends ConsumerStatefulWidget {
  const AgentPage({super.key});
  @override
  ConsumerState<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends ConsumerState<AgentPage> {
  final _prompt = TextEditingController();
  final _promptFocus = FocusNode();
  final _showSidebar = ValueNotifier<bool>(false);
  final _messages = <_AgentMessage>[];
  // OpenAI tool calls need their complete protocol history (assistant call and
  // matching tool result) to be meaningful on the next request. The rendered
  // chat messages alone cannot provide that because tool-call IDs are omitted.
  final _agentContext = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _pendingContext = const [];
  final _queuedPrompts = <_QueuedPrompt>[];
  final _messagesScroll = ScrollController();
  AgentProposal? _proposal;
  bool _reconnectRequired = false;
  bool _showScrollToBottom = false;
  String? _pendingPrompt;
  int? _activeProviderId;
  int? _activeModelId;
  int? _conversationId;
  bool _ghost = false;
  bool _working = false;
  bool _personalityProviderProvisioned = false;
  AgentCancelToken? _activeToken;
  // MCP tools and skills gathered when a turn starts. Reused for the
  // continuation after an approved action so the model always sees the same
  // tool set across the request/execute/continue cycle.
  List<AgentMcpToolTarget> _activeMcpTools = const [];
  List<AgentSkillTarget> _activeSkills = const [];
  String? _activeMcpUnavailable;

  @override
  void initState() {
    super.initState();
    _restoreSelection();
    _messagesScroll.addListener(_updateScrollToBottomVisibility);
    _promptFocus.addListener(
      () => ref
          .read(agentInputFocusedProvider.notifier)
          .setFocused(_promptFocus.hasFocus),
    );
    _promptFocus.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      if (event.logicalKey != LogicalKeyboardKey.enter) {
        return KeyEventResult.ignored;
      }
      if (HardwareKeyboard.instance.isShiftPressed) {
        _insertNewLine();
      } else {
        _submitPrompt();
      }
      return KeyEventResult.handled;
    };
  }

  void _insertNewLine() {
    final text = _prompt.text;
    final selection = _prompt.selection;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;
    final newText = text.replaceRange(start, end, '\n');
    _prompt.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + 1),
    );
  }

  Future<void> _restoreSelection() async {
    final selection = await ref.read(agentSelectionProvider.future);
    if (!mounted || selection.providerId == null) return;
    setState(() {
      _activeProviderId = selection.providerId;
      _activeModelId = selection.modelId;
    });
  }

  void _persistSelection() {
    ref
        .read(agentSelectionProvider.notifier)
        .select(providerId: _activeProviderId, modelId: _activeModelId);
  }

  @override
  void dispose() {
    _showSidebar.dispose();
    _messagesScroll.removeListener(_updateScrollToBottomVisibility);
    _messagesScroll.dispose();
    _promptFocus.dispose();
    _prompt.dispose();
    super.dispose();
  }

  void _interrupt() => _activeToken?.cancel();

  void _updateScrollToBottomVisibility() {
    if (!_messagesScroll.hasClients) return;
    _setScrollToBottomVisibility(_messagesScroll.position);
  }

  void _setScrollToBottomVisibility(ScrollMetrics position) {
    if (!position.hasContentDimensions) return;
    final visible = position.pixels < position.maxScrollExtent - 64;
    if (visible == _showScrollToBottom || !mounted) return;
    setState(() => _showScrollToBottom = visible);
  }

  void _scrollToLatest() {
    if (!_messagesScroll.hasClients) return;
    _messagesScroll.animateTo(
      _messagesScroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  /// Scrolls the chat list to the bottom when the user is already near it,
  /// so new tokens and tool results stay in view while streaming.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_messagesScroll.hasClients) return;
      final position = _messagesScroll.position;
      if (!position.hasContentDimensions) return;
      final maxScroll = position.maxScrollExtent;
      if (maxScroll <= 0) return;
      if (position.pixels >= maxScroll - 64) {
        position.animateTo(
          maxScroll,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
      _updateScrollToBottomVisibility();
    });
  }

  Future<void> _submitPrompt() async {
    if (_working) {
      _queuePrompt();
      return;
    }
    await _send();
  }

  void _queuePrompt() {
    final text = _prompt.text.trim();
    final servers = ref.read(serversProvider).asData?.value ?? const <Server>[];
    if (text.isEmpty || servers.isEmpty || _proposal != null) return;
    setState(() {
      _queuedPrompts.add(_QueuedPrompt(text));
      _prompt.clear();
    });
    _promptFocus.requestFocus();
  }

  Future<void> _steerQueuedPrompt(int index) async {
    if (index < 0 || index >= _queuedPrompts.length) return;
    final queued = _queuedPrompts.removeAt(index);
    if (_working) {
      setState(() => _queuedPrompts.insert(0, queued));
      // A steer is deliberately sent on the next request, not appended to an
      // already-running request. Cancelling here makes that next request start
      // as soon as the current turn has unwound.
      _activeToken?.cancel();
      return;
    }
    if (mounted) setState(() {});
    await _runPrompt(queued.text);
  }

  void _removeQueuedPrompt(int index) {
    if (index < 0 || index >= _queuedPrompts.length) return;
    setState(() => _queuedPrompts.removeAt(index));
  }

  Future<void> _drainQueuedPrompts() async {
    final servers = ref.read(serversProvider).asData?.value ?? const <Server>[];
    if (!mounted ||
        _working ||
        _proposal != null ||
        _queuedPrompts.isEmpty ||
        servers.isEmpty) {
      return;
    }
    final queued = _queuedPrompts.removeAt(0);
    setState(() {});
    await _runPrompt(queued.text);
  }

  Future<void> _send() async {
    final text = _prompt.text.trim();
    final servers = ref.read(serversProvider).asData?.value ?? const <Server>[];
    if (text.isEmpty || servers.isEmpty || _working || _proposal != null) {
      return;
    }
    await _runPrompt(text);
  }

  Future<void> _runPrompt(String text) async {
    final servers = ref.read(serversProvider).asData?.value ?? const <Server>[];
    if (text.isEmpty || servers.isEmpty || _working || _proposal != null) {
      return;
    }
    final targets = _serverTargets(servers);
    final snippets = await ref.read(snippetRepositoryProvider).all();
    if (!mounted) return;
    final conversationContext = List<Map<String, dynamic>>.from(_agentContext);
    setState(() {
      _working = true;
      _pendingPrompt = text;
      _pendingContext = [
        ...conversationContext,
        _rawContextMessage('user', text),
      ];
      _messages.add(_AgentMessage.user(text));
      _prompt.clear();
    });
    _scrollToBottom();
    try {
      final config = await _configuration();
      if (config == null) {
        if (mounted) await _showProviderEditor();
        return;
      }
      final personality = await ref.read(agentPersonalityProvider.future);
      if (!mounted) return;
      final (mcpTools, skillTargets, mcpUnavailable) =
          await _gatherCapabilities();
      if (!mounted) return;
      _activeMcpTools = mcpTools;
      _activeSkills = skillTargets;
      _activeMcpUnavailable = mcpUnavailable;
      var streamedMessageIndex = -1;
      final cancelToken = AgentCancelToken();
      _activeToken = cancelToken;
      final turn =
          await SshAgentService(
            config,
            personality: personality,
            uiLanguage: context.locale.toLanguageTag(),
            hideServerAddresses: ref.read(hideServerAddressesProvider),
          ).request(
            servers: targets,
            snippets: _snippetTargets(snippets),
            mcpTools: mcpTools,
            skills: skillTargets,
            mcpUnavailable: mcpUnavailable,
            prompt: text,
            history: conversationContext,
            onText: (streamedText) {
              if (!mounted) return;
              setState(() {
                final message = _AgentMessage.assistant(streamedText);
                if (streamedMessageIndex < 0) {
                  _messages.add(message);
                  streamedMessageIndex = _messages.length - 1;
                } else {
                  _messages[streamedMessageIndex] = message;
                }
              });
              _scrollToBottom();
            },
            cancelToken: cancelToken,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        if (streamedMessageIndex < 0 &&
            turn.text != null &&
            turn.text!.isNotEmpty) {
          _messages.add(_AgentMessage.assistant(turn.text!));
        }
      });
      _scrollToBottom();
      await _handleTurn(turn);
    } on AgentCancelledException {
      if (mounted) {
        setState(
          () => _messages.add(_AgentMessage.assistant('agentInterrupted'.tr())),
        );
        _scrollToBottom();
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _messages.add(
            _AgentMessage.assistant('agentError'.tr(args: [error.toString()])),
          ),
        );
        _scrollToBottom();
      }
    } finally {
      _activeToken = null;
      if (mounted) {
        setState(() => _working = false);
        await _persistConversation();
        await _drainQueuedPrompts();
      }
    }
  }

  Future<void> _approve([
    AgentProposal? proposal,
    bool autoApproved = false,
  ]) async {
    final approvedProposal = proposal ?? _proposal;
    if (approvedProposal == null || _pendingPrompt == null) {
      return;
    }
    setState(() => _working = true);
    try {
      final config = await _configuration();
      final servers =
          ref.read(serversProvider).asData?.value ?? const <Server>[];
      if (config == null) {
        throw StateError('agentProviderGone'.tr());
      }
      if (!mounted) {
        return;
      }
      SSHClient? client;
      final serverId = approvedProposal.serverId;
      if (serverId != null) {
        final server = servers
            .where((server) => server.id == serverId)
            .firstOrNull;
        if (server == null) {
          throw StateError('agentServerGone'.tr());
        }
        if (ref.read(connectionManagerProvider).clientFor(server.id) == null &&
            !await connectForStatistics(context, ref, server)) {
          if (mounted) setState(() => _reconnectRequired = true);
          return;
        }
        client = ref.read(connectionManagerProvider).clientFor(server.id);
        if (client == null) {
          if (mounted) setState(() => _reconnectRequired = true);
          return;
        }
      }
      _reconnectRequired = false;
      final personality = await ref.read(agentPersonalityProvider.future);
      if (!mounted) return;
      final agent = SshAgentService(
        config,
        personality: personality,
        uiLanguage: context.locale.toLanguageTag(),
        hideServerAddresses: ref.read(hideServerAddressesProvider),
      );
      final cancelToken = AgentCancelToken();
      _activeToken = cancelToken;
      final result = await _executeProposal(
        agent,
        client,
        approvedProposal,
        cancelToken,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(
          _AgentMessage.tool(
            '${approvedProposal.title}:\n$result',
            autoApproved: autoApproved,
          ),
        );
        _proposal = null;
        _reconnectRequired = false;
      });
      _scrollToBottom();
      var streamedMessageIndex = -1;
      final turn = await agent.continueAfterExecution(
        servers: _serverTargets(servers),
        snippets: _snippetTargets(
          await ref.read(snippetRepositoryProvider).all(),
        ),
        mcpTools: _activeMcpTools,
        skills: _activeSkills,
        mcpUnavailable: _activeMcpUnavailable,
        history: _pendingContext,
        proposal: approvedProposal,
        result: result,
        onText: (streamedText) {
          if (!mounted) return;
          setState(() {
            final message = _AgentMessage.assistant(streamedText);
            if (streamedMessageIndex < 0) {
              _messages.add(message);
              streamedMessageIndex = _messages.length - 1;
            } else {
              _messages[streamedMessageIndex] = message;
            }
          });
          _scrollToBottom();
        },
        cancelToken: cancelToken,
      );
      if (!mounted) {
        return;
      }
      _agentContext
        ..clear()
        ..addAll(_pendingContext)
        ..add(_proposalContextMessage(approvedProposal))
        ..add({
          'role': 'tool',
          'tool_call_id': approvedProposal.toolCall.id ?? 'approved-action',
          'content': result,
        });
      _pendingContext = List<Map<String, dynamic>>.from(_agentContext);
      setState(() {
        if (streamedMessageIndex < 0 &&
            turn.text != null &&
            turn.text!.isNotEmpty) {
          _messages.add(_AgentMessage.assistant(turn.text!));
        }
      });
      await _handleTurn(turn);
    } on AgentCancelledException {
      if (mounted) {
        setState(() {
          _messages.add(_AgentMessage.assistant('agentActionInterrupted'.tr()));
          _proposal = null;
          _reconnectRequired = false;
        });
        _scrollToBottom();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _messages.add(
            _AgentMessage.assistant(
              'agentActionFailed'.tr(args: [error.toString()]),
            ),
          );
          _proposal = null;
          _reconnectRequired = false;
        });
      }
    } finally {
      _activeToken = null;
      if (mounted) {
        setState(() => _working = false);
        await _persistConversation();
        await _drainQueuedPrompts();
      }
    }
  }

  List<AgentServerTarget> _serverTargets(List<Server> servers) => [
    for (final server in servers)
      AgentServerTarget(
        id: server.id,
        name: server.name,
        host: server.host,
        username: server.username,
      ),
  ];

  List<AgentSnippetTarget> _snippetTargets(List<ScriptSnippet> snippets) => [
    for (final snippet in snippets)
      AgentSnippetTarget(id: snippet.id, name: snippet.name),
  ];

  /// Collects the tools of every enabled MCP server and the enabled skills at
  /// the start of a turn. A broken server never blocks the chat: its tools
  /// are dropped and the failure is surfaced to the model in the system
  /// prompt instead.
  Future<(List<AgentMcpToolTarget>, List<AgentSkillTarget>, String?)>
  _gatherCapabilities() async {
    final mcpTools = <AgentMcpToolTarget>[];
    final mcpErrors = <String>[];
    final servers =
        ref.read(mcpServersProvider).asData?.value ?? const <McpServer>[];
    for (final server in servers.where((server) => server.enabled)) {
      try {
        final client = await ref
            .read(mcpClientManagerProvider)
            .clientFor(server);
        final tools = await client.listTools();
        mcpTools.addAll([
          for (final tool in tools)
            AgentMcpToolTarget(
              serverId: server.id,
              serverName: server.name,
              name: tool.name,
              description: tool.description,
              inputSchema: tool.inputSchema,
            ),
        ]);
      } catch (error) {
        mcpErrors.add('${server.name}: $error');
      }
    }
    final skills = await ref.read(skillRepositoryProvider).all();
    final skillTargets = [
      for (final skill in skills.where((skill) => skill.enabled))
        AgentSkillTarget(
          id: skill.id,
          name: skill.name,
          description: skill.description,
        ),
    ];
    return (
      mcpTools,
      skillTargets,
      mcpErrors.isEmpty ? null : mcpErrors.join('\n'),
    );
  }

  Future<String> _executeProposal(
    SshAgentService agent,
    SSHClient? client,
    AgentProposal proposal,
    AgentCancelToken cancelToken,
  ) async {
    final snippets = ref.read(snippetRepositoryProvider);
    switch (proposal.kind) {
      case AgentActionKind.createSnippet:
        final name = proposal.arguments['name'] as String? ?? '';
        final script = proposal.arguments['script'] as String? ?? '';
        if (name.trim().isEmpty || script.trim().isEmpty) {
          throw ArgumentError('agentSnippetNameScriptRequired'.tr());
        }
        final id = await snippets.save(name: name, script: script);
        return 'agentSnippetCreated'.tr(args: ['$id', name.trim()]);
      case AgentActionKind.runSnippet:
        final snippetId = proposal.arguments['snippet_id'] as int?;
        if (snippetId == null) {
          throw ArgumentError('agentSnippetIdRequired'.tr());
        }
        final snippet = await snippets.snippet(snippetId);
        if (snippet == null) {
          throw StateError('agentSnippetGone'.tr(args: ['$snippetId']));
        }
        return agent.execute(
          _requireClient(client),
          proposal,
          snippetScript: snippet.script,
          cancelToken: cancelToken,
        );
      case AgentActionKind.command:
      case AgentActionKind.readFile:
      case AgentActionKind.writeFile:
      case AgentActionKind.deleteFile:
        return agent.execute(
          _requireClient(client),
          proposal,
          cancelToken: cancelToken,
        );
      case AgentActionKind.mcpToolCall:
        final serverId = proposal.mcpServerId;
        if (serverId == null) {
          throw StateError('agentMcpServerGone'.tr());
        }
        final server = ref
            .read(mcpServersProvider)
            .asData
            ?.value
            .where((server) => server.id == serverId)
            .firstOrNull;
        if (server == null) {
          throw StateError('agentMcpServerGone'.tr());
        }
        final clientForServer = await ref
            .read(mcpClientManagerProvider)
            .clientFor(server);
        final result = await clientForServer.callTool(
          AgentMcpToolTarget.bareName(proposal.toolCall.function.name ?? ''),
          Map<String, dynamic>.from(proposal.arguments)..remove('safe_to_run'),
          cancelToken: cancelToken,
        );
        return _formatMcpResult(result);
      case AgentActionKind.getSkill:
        final skillId = proposal.arguments['skill_id'] as int?;
        if (skillId == null) {
          throw ArgumentError('agentSkillIdRequired'.tr());
        }
        final skill = await ref.read(skillRepositoryProvider).skill(skillId);
        if (skill == null) {
          throw StateError('agentSkillGone'.tr(args: ['$skillId']));
        }
        return _limitMcpText('Skill "${skill.name}":\n\n${skill.content}');
    }
  }

  String _formatMcpResult(McpToolResult result) {
    var text = result.text;
    if (text.isEmpty) {
      text = result.content.isEmpty
          ? '(empty result)'
          : jsonEncode(result.content);
    }
    if (result.isError) text = 'MCP tool error:\n$text';
    return _limitMcpText(text);
  }

  static String _limitMcpText(String value) => value.length <= 12000
      ? value
      : '${value.substring(0, 12000)}\n[output truncated]';

  SSHClient _requireClient(SSHClient? client) =>
      client ?? (throw StateError('agentRequiresConnection'.tr()));

  Future<void> _handleTurn(AgentTurn turn) async {
    final proposal = turn.proposal;
    if (proposal == null) {
      _agentContext
        ..clear()
        ..addAll(_pendingContext)
        ..add(
          _assistantContextMessage(
            turn.assistantMessage,
            turn.text,
            turn.reasoningContent,
          ),
        );
      _pendingContext = List<Map<String, dynamic>>.from(_agentContext);
      setState(() => _proposal = null);
      return;
    }
    final policy =
        ref.read(agentRunPolicyProvider).value ?? AgentRunPolicy.alwaysAsk;
    final shouldAutoRun = switch (policy) {
      AgentRunPolicy.alwaysApprove => true,
      AgentRunPolicy.autoReview => proposal.safeToRun,
      AgentRunPolicy.alwaysAsk => false,
    };
    if (shouldAutoRun) {
      await _approve(proposal, true);
    } else {
      setState(() {
        _proposal = proposal;
        _reconnectRequired = false;
      });
    }
  }

  Future<void> _declineProposal() async {
    if (_working) return;
    setState(() {
      _messages.add(_AgentMessage.assistant('agentActionDeclined'.tr()));
      _proposal = null;
      _reconnectRequired = false;
    });
    _scrollToBottom();
    _agentContext
      ..clear()
      ..addAll(_pendingContext)
      ..add(_rawContextMessage('assistant', 'agentActionDeclined'.tr()));
    _pendingContext = List<Map<String, dynamic>>.from(_agentContext);
    await _persistConversation();
    await _drainQueuedPrompts();
  }

  Future<void> _persistConversation() async {
    if (_ghost || _messages.isEmpty) return;
    final snapshot = List<_AgentMessage>.of(_messages);
    final id = _conversationId;
    final providerId = _activeProviderId;
    final modelId = _activeModelId;
    final savedId = await ref
        .read(conversationStoreProvider)
        .saveConversation(
          AgentConversationDraft(
            title: _conversationTitle(snapshot),
            providerId: providerId,
            modelId: modelId,
            messages: [
              for (final message in snapshot)
                AgentConversationMessage(
                  role: _roleName(message.kind),
                  text: message.text,
                ),
            ],
          ),
          id: id,
        );
    if (!mounted || _ghost) return;
    setState(() => _conversationId = savedId);
  }

  Future<void> _startNewConversation() async {
    if (_working) return;
    await _persistConversation();
    setState(() {
      _queuedPrompts.clear();
      _messages.clear();
      _agentContext.clear();
      _pendingContext = const [];
      _conversationId = null;
      _proposal = null;
      _reconnectRequired = false;
      _pendingPrompt = null;
    });
    _showSidebar.value = false;
    _promptFocus.requestFocus();
  }

  Future<void> _setGhost(bool value) async {
    if (_working) return;
    if (value) {
      setState(() {
        _ghost = true;
        _conversationId = null;
      });
      return;
    }
    setState(() => _ghost = false);
    await _persistConversation();
  }

  Future<void> _loadConversation(int id) async {
    if (_working || _conversationId == id) return;
    await _persistConversation();
    final conversation = await ref
        .read(conversationStoreProvider)
        .conversation(id);
    if (!mounted || conversation == null) return;
    setState(() {
      _queuedPrompts.clear();
      _messages
        ..clear()
        ..addAll([
          for (final message in conversation.messages)
            _AgentMessage(message.text, _roleKind(message.role)),
        ]);
      _agentContext
        ..clear()
        ..addAll(_contextFromMessages(_messages));
      _pendingContext = List<Map<String, dynamic>>.from(_agentContext);
      _conversationId = conversation.id;
      _ghost = false;
      _activeProviderId = conversation.providerId;
      _activeModelId = conversation.modelId;
      _proposal = null;
      _reconnectRequired = false;
      _pendingPrompt = null;
    });
    _persistSelection();
    _showSidebar.value = false;
  }

  Future<void> _deleteConversation(AgentConversation conversation) async {
    if (_working) return;
    final confirmed = await showMaidKitConfirmAlert(
      'agentDeleteConversationConfirm'.tr(args: [conversation.title]),
      'agentDeleteConversation'.tr(),
      icon: Symbols.delete_outline,
      isDanger: true,
    );
    if (!confirmed) return;
    await ref
        .read(conversationStoreProvider)
        .deleteConversation(conversation.id);
    if (mounted && _conversationId == conversation.id) {
      setState(() {
        _queuedPrompts.clear();
        _messages.clear();
        _agentContext.clear();
        _pendingContext = const [];
        _conversationId = null;
        _proposal = null;
        _reconnectRequired = false;
        _pendingPrompt = null;
      });
    }
  }

  Future<void> _showProviderEditor([AgentProvider? existing]) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (sheetContext) => _AgentProviderEditorSheet(
        existing: existing,
        onSave: (draft) async {
          try {
            await ref
                .read(agentRepositoryProvider)
                .save(draft, id: existing?.id);
            if (sheetContext.mounted) Navigator.pop(sheetContext);
          } catch (error) {
            showMaidKitErrorAlert(
              error,
              title: 'agentCouldNotSaveProvider'.tr(),
            );
          }
        },
      ),
    );
  }

  Future<void> _showCapabilitiesSheet() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    builder: (_) => const _AgentCapabilitiesSheet(),
  );

  Future<void> _deleteProvider(AgentProvider provider) async {
    final confirmed = await showMaidKitConfirmAlert(
      'agentDeleteProviderConfirm'.tr(args: [provider.name]),
      'agentDeleteProvider'.tr(),
      icon: Symbols.delete_outline,
      isDanger: true,
    );
    if (!confirmed) return;
    await ref.read(agentRepositoryProvider).delete(provider.id);
    if (mounted && _activeProviderId == provider.id) {
      setState(() => _activeProviderId = null);
    }
  }

  Future<void> _showAddModelSheet(AgentProvider provider) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        useRootNavigator: true,
        builder: (sheetContext) => _AgentModelEditorSheet(
          onSave: (model) async {
            try {
              await ref
                  .read(agentRepositoryProvider)
                  .addModel(provider.id, model);
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            } catch (error) {
              showMaidKitErrorAlert(error, title: 'agentCouldNotAddModel'.tr());
            }
          },
          presets: _presetModelsFor(provider),
        ),
      );

  Future<void> _deleteModel(AgentProviderModel model) async {
    final confirmed = await showMaidKitConfirmAlert(
      'agentRemoveModelConfirm'.tr(args: [model.model]),
      'agentRemoveModel'.tr(),
      icon: Symbols.delete_outline,
      isDanger: true,
    );
    if (!confirmed) return;
    await ref.read(agentRepositoryProvider).deleteModel(model.id);
    if (mounted && _activeModelId == model.id) {
      setState(() => _activeModelId = null);
    }
  }

  Future<AgentConfiguration?> _configuration() async {
    final configuration = await ref
        .read(agentRepositoryProvider)
        .configuration(_activeProviderId, _activeModelId);
    if (configuration?.baseUrl != PersonalityService.productionBaseUrl) {
      return configuration;
    }
    final accessToken = await ref.read(cloudSyncServiceProvider).accessToken();
    if (accessToken == null) return configuration;
    final fixedAgentId = await ref.read(agentPersonalityAgentProvider.future);
    return AgentConfiguration(
      providerId: configuration!.providerId,
      providerName: configuration.providerName,
      apiKey: accessToken,
      baseUrl: configuration.baseUrl,
      model: fixedAgentId,
    );
  }

  Future<void> _ensurePersonalityProvider() async {
    final accessToken = await ref.read(cloudSyncServiceProvider).accessToken();
    if (accessToken == null || !mounted) return;
    final fixedAgentId = await ref.read(agentPersonalityAgentProvider.future);
    if (!mounted) return;
    await ref
        .read(agentRepositoryProvider)
        .ensurePersonalityProvider(accessToken, models: [fixedAgentId]);
  }

  @override
  Widget build(BuildContext context) {
    final cloudUser = ref.watch(cloudUserProvider).asData?.value;
    if (cloudUser != null && !_personalityProviderProvisioned) {
      _personalityProviderProvisioned = true;
      unawaited(_ensurePersonalityProvider());
    }
    if (cloudUser == null) _personalityProviderProvisioned = false;
    final servers =
        ref.watch(serversProvider).asData?.value ?? const <Server>[];
    final mcpServers =
        ref.watch(mcpServersProvider).asData?.value ?? const <McpServer>[];
    final providers =
        ref.watch(agentProvidersProvider).asData?.value ??
        const <AgentProvider>[];
    final conversations =
        ref.watch(agentConversationsProvider).asData?.value ??
        const <AgentConversation>[];
    final selectedProviderId =
        _activeProviderId ?? (providers.isEmpty ? null : providers.first.id);
    final models = selectedProviderId == null
        ? const <AgentProviderModel>[]
        : ref
                  .watch(agentProviderModelsProvider(selectedProviderId))
                  .asData
                  ?.value ??
              const <AgentProviderModel>[];
    final selectedModelId =
        _activeModelId ?? (models.isEmpty ? null : models.first.id);
    if (providers.isNotEmpty &&
        _activeProviderId != null &&
        !providers.any((provider) => provider.id == _activeProviderId)) {
      _activeProviderId = null;
      _activeModelId = null;
      _persistSelection();
    }
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final selectors = _buildProviderModelSelectors(
          providers: providers,
          models: models,
          selectedProviderId: selectedProviderId,
          selectedModelId: selectedModelId,
          compact: compact,
        );
        final historyButton = IconButton(
          tooltip: 'agentConversations'.tr(),
          onPressed: () => _showSidebar.value = !_showSidebar.value,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Symbols.history),
        );
        final capabilitiesButton = IconButton(
          tooltip: 'agentCapabilities'.tr(),
          onPressed: () => _showCapabilitiesSheet(),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Symbols.extension),
        );
        return MaidKitAppScaffold(
          appBar: AppBar(
            actions: [
              if (compact)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [...selectors, historyButton, capabilitiesButton],
                  ),
                )
              else ...[
                ...selectors,
                historyButton,
                capabilitiesButton,
              ],
              const SizedBox(width: 8),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: ResponsiveSidebar(
                isLeft: false,
                showSidebar: _showSidebar,
                sidebarWidth: 360,
                minWideSidebarWidth: 300,
                maxWideSidebarWidth: 400,
                minMainContentWidth: 480,
                sidebarBackgroundColor: scheme.surface,
                sidebarElevation: 0,
                sidebarContent: _buildConversationSidebar(
                  conversations: conversations,
                  scheme: scheme,
                ),
                mainContent: _buildChatColumn(
                  servers: servers,
                  mcpServers: mcpServers,
                  scheme: scheme,
                  compact: compact,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildProviderModelSelectors({
    required List<AgentProvider> providers,
    required List<AgentProviderModel> models,
    required int? selectedProviderId,
    required int? selectedModelId,
    required bool compact,
  }) {
    final selectedProvider = selectedProviderId == null
        ? null
        : providers
              .where((provider) => provider.id == selectedProviderId)
              .firstOrNull;
    final selectedModel = selectedModelId == null
        ? null
        : models.where((model) => model.id == selectedModelId).firstOrNull;
    final isManagedPersonalityProvider =
        selectedProvider?.baseUrl == PersonalityService.productionBaseUrl;
    final modelEntries = <_DropdownEntry>[
      for (final model in models)
        _DropdownEntry(value: model.id, label: model.model),
    ];
    return [
      const SizedBox(width: 4),
      _AppBarDropdown(
        label: 'agentAiProvider'.tr(),
        value: selectedProviderId,
        entries: [
          for (final provider in providers)
            _DropdownEntry(value: provider.id, label: provider.name),
        ],
        enabled: !_working,
        compact: compact,
        onChanged: (id) => setState(() {
          _activeProviderId = id;
          _activeModelId = null;
          _persistSelection();
        }),
        actions: [
          _DropdownAction(
            label: 'agentAddProvider'.tr(),
            icon: Symbols.add,
            onSelected: () => _showProviderEditor(),
          ),
          _DropdownAction(
            label: 'agentEditProvider'.tr(),
            icon: Symbols.edit,
            onSelected: () => _showProviderEditor(selectedProvider!),
            enabled: selectedProvider != null && !isManagedPersonalityProvider,
          ),
          _DropdownAction(
            label: 'agentDeleteProviderAction'.tr(),
            icon: Symbols.delete_outline,
            onSelected: () => _deleteProvider(selectedProvider!),
            enabled: selectedProvider != null && !isManagedPersonalityProvider,
          ),
        ],
      ),
      if (!isManagedPersonalityProvider) ...[
        const SizedBox(width: 8),
        _AppBarDropdown(
          label: 'agentModel'.tr(),
          value: selectedModelId,
          entries: modelEntries,
          enabled: !_working && selectedProviderId != null,
          compact: compact,
          onChanged: (id) => setState(() {
            _activeModelId = id;
            _persistSelection();
          }),
          actions: [
            _DropdownAction(
              label: 'agentAddModel'.tr(),
              icon: Symbols.add,
              onSelected: () => _showAddModelSheet(selectedProvider!),
              enabled: selectedProvider != null,
            ),
            _DropdownAction(
              label: 'agentRemoveModel'.tr(),
              icon: Symbols.delete_outline,
              onSelected: () => _deleteModel(selectedModel!),
              enabled: selectedModel != null,
            ),
          ],
        ),
      ],
      const SizedBox(width: 8),
    ];
  }

  Widget _buildConversationSidebar({
    required List<AgentConversation> conversations,
    required ColorScheme scheme,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'agentChats'.tr(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'agentNewConversation'.tr(),
                onPressed: _working ? null : _startNewConversation,
                icon: const Icon(Symbols.add),
              ),
              IconButton(
                tooltip: 'commonClose'.tr(),
                onPressed: () => _showSidebar.value = false,
                icon: const Icon(Symbols.close),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'agentGhostConversation'.tr(),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Switch(value: _ghost, onChanged: _working ? null : _setGhost),
            ],
          ),
        ),
        const Divider(height: 1),
        const SizedBox(height: 4),
        Expanded(
          child: conversations.isEmpty
              ? Center(
                  child: Text(
                    'agentNoConversations'.tr(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: conversations.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (_, index) {
                    final conversation = conversations[index];
                    return _ConversationTile(
                      conversation: conversation,
                      selected: conversation.id == _conversationId,
                      onTap: () => _loadConversation(conversation.id),
                      onDelete: () => _deleteConversation(conversation),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildChatColumn({
    required List<Server> servers,
    required List<McpServer> mcpServers,
    required ColorScheme scheme,
    required bool compact,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 16 : 24, 0, compact ? 16 : 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _buildMessageList(
                    servers: servers,
                    mcpServers: mcpServers,
                    scheme: scheme,
                  ),
                ),
                if (_showScrollToBottom)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: FloatingActionButton.small(
                      heroTag: 'agent-scroll-to-bottom',
                      tooltip: 'agentScrollToLatest'.tr(),
                      onPressed: _scrollToLatest,
                      child: const Icon(Symbols.arrow_downward),
                    ),
                  ),
              ],
            ),
          ),
          if (_queuedPrompts.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildQueuedPrompts(scheme),
          ],
          const SizedBox(height: 12),
          Material(
            elevation: 2,
            color: scheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide.none,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _prompt,
                      focusNode: _promptFocus,
                      enabled: _proposal == null,
                      keyboardType: TextInputType.multiline,
                      maxLines: 5,
                      minLines: 1,
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      onSubmitted: (_) => _submitPrompt(),
                      decoration: InputDecoration(
                        hintText: 'agentPromptHint'.tr(),
                        hintMaxLines: 1,
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  if (_working)
                    IconButton(
                      tooltip: 'commonStop'.tr(),
                      onPressed: _interrupt,
                      icon: const Icon(Symbols.stop),
                    ),
                  IconButton(
                    tooltip: _working
                        ? 'agentQueueMessage'.tr()
                        : 'agentSendMessage'.tr(),
                    color: scheme.primary,
                    onPressed: _proposal != null ? null : _submitPrompt,
                    icon: Icon(_working ? Symbols.schedule : Symbols.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueuedPrompts(ColorScheme scheme) {
    return Material(
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 176),
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: _queuedPrompts.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final queued = _queuedPrompts[index];
            return ListTile(
              dense: true,
              leading: const Icon(Symbols.schedule, size: 20),
              title: Text(
                queued.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text('agentQueuedMessage'.tr()),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'agentSteerMessage'.tr(),
                    onPressed: () => _steerQueuedPrompt(index),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Symbols.arrow_upward, size: 18),
                  ),
                  IconButton(
                    tooltip: 'agentRemoveQueuedMessage'.tr(),
                    onPressed: () => _removeQueuedPrompt(index),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Symbols.close, size: 18),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMessageList({
    required List<Server> servers,
    required List<McpServer> mcpServers,
    required ColorScheme scheme,
  }) {
    final pendingProposal = _proposal;
    final showThinking = _working && pendingProposal == null;
    final serverName = pendingProposal == null
        ? ''
        : pendingProposal.kind == AgentActionKind.mcpToolCall
        ? mcpServers
                  .where((server) => server.id == pendingProposal.mcpServerId)
                  .map((server) => server.name)
                  .firstOrNull ??
              'agentUnavailableServer'.tr()
        : pendingProposal.serverId == null
        ? 'MaidKit'
        : servers
                  .where((server) => server.id == pendingProposal.serverId)
                  .map((server) => server.name)
                  .firstOrNull ??
              'agentUnavailableServer'.tr();
    if (_messages.isEmpty && pendingProposal == null) {
      return Center(
        child: Text(
          _ghost ? 'agentGhostHint'.tr() : 'agentEmptyHint'.tr(),
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        _setScrollToBottomVisibility(notification.metrics);
        return false;
      },
      child: ListView.separated(
        padding: const EdgeInsets.only(top: 16),
        controller: _messagesScroll,
        itemCount:
            _messages.length +
            (pendingProposal != null ? 1 : 0) +
            (showThinking ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, index) {
          if (pendingProposal != null && index == _messages.length) {
            return _ProposalCard(
              proposal: pendingProposal,
              serverName: serverName,
              working: _working,
              reconnectRequired: _reconnectRequired,
              onApprove: _approve,
              onDecline: _declineProposal,
            );
          }
          if (showThinking &&
              index == _messages.length + (pendingProposal != null ? 1 : 0)) {
            return const _AgentThinkingIndicator();
          }
          return _MessageCard(message: _messages[index]);
        },
      ),
    );
  }

  static String _roleName(_MessageKind kind) => switch (kind) {
    _MessageKind.user => 'user',
    _MessageKind.tool => 'tool',
    _MessageKind.assistant => 'assistant',
  };

  static _MessageKind _roleKind(String? role) => switch (role) {
    'user' => _MessageKind.user,
    'tool' => _MessageKind.tool,
    _ => _MessageKind.assistant,
  };

  static Map<String, dynamic> _rawContextMessage(String role, String text) => {
    'role': role,
    'content': text,
  };

  static Map<String, dynamic> _assistantContextMessage(
    OpenAIChatCompletionChoiceMessageModel? message, [
    String? fallbackText,
    String? reasoningContent,
  ]) {
    final result =
        message?.toMap() ?? _rawContextMessage('assistant', fallbackText ?? '');
    if (result['tool_calls'] case final List calls when calls.isEmpty) {
      result.remove('tool_calls');
    }
    if (reasoningContent != null && reasoningContent.isNotEmpty) {
      result['reasoning_content'] = reasoningContent;
    }
    return result;
  }

  static Map<String, dynamic> _proposalContextMessage(AgentProposal proposal) {
    final result = _assistantContextMessage(
      proposal.assistantMessage,
      proposal.explanation,
      proposal.reasoningContent,
    );
    // Subsequent requests must include a result for every listed tool call.
    // Only this call was approved and executed.
    result['tool_calls'] = [proposal.toolCall.toMap()];
    return result;
  }

  static List<Map<String, dynamic>> _contextFromMessages(
    List<_AgentMessage> messages,
  ) => [
    for (final message in messages)
      _rawContextMessage(
        message.kind == _MessageKind.user ? 'user' : 'assistant',
        message.kind == _MessageKind.tool
            ? 'Tool result from an earlier action:\n${message.text}'
            : message.text,
      ),
  ];

  static String _conversationTitle(List<_AgentMessage> messages) {
    final firstUser = messages
        .where((message) => message.kind == _MessageKind.user)
        .firstOrNull;
    final text = (firstUser?.text ?? 'agentDefaultConversationTitle'.tr())
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return text.length <= 48 ? text : '${text.substring(0, 48)}…';
  }
}

class _AgentMessage {
  const _AgentMessage(this.text, this.kind, {this.autoApproved = false});
  const _AgentMessage.user(String text) : this(text, _MessageKind.user);
  const _AgentMessage.assistant(String text)
    : this(text, _MessageKind.assistant);
  const _AgentMessage.tool(String text, {bool autoApproved = false})
    : this(text, _MessageKind.tool, autoApproved: autoApproved);
  final String text;
  final _MessageKind kind;
  final bool autoApproved;
}

class _QueuedPrompt {
  const _QueuedPrompt(this.text);

  final String text;
}

class _DropdownAction {
  const _DropdownAction({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelected;
  final bool enabled;
}

class _DropdownEntry {
  const _DropdownEntry({required this.value, required this.label});

  final int value;
  final String label;
}

class _AppBarDropdown extends StatelessWidget {
  const _AppBarDropdown({
    required this.label,
    required this.value,
    required this.entries,
    required this.onChanged,
    this.enabled = true,
    this.actions = const [],
    this.compact = false,
  });

  final String label;
  final int? value;
  final List<_DropdownEntry> entries;
  final ValueChanged<int> onChanged;
  final bool enabled;
  final List<_DropdownAction> actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = entries.any((entry) => entry.value == value)
        ? value
        : null;
    return Tooltip(
      message: label,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 2 : 4,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DropdownButton<int>(
          value: selected,
          isDense: true,
          itemHeight: null,
          underline: const SizedBox.shrink(),
          borderRadius: BorderRadius.circular(8),
          menuWidth: compact ? 220 : null,
          style: theme.textTheme.bodyMedium,
          icon: const Icon(Symbols.expand_more, size: 18),
          hint: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          items: [
            for (final entry in entries)
              DropdownMenuItem(
                value: entry.value,
                enabled: enabled,
                child: _DropdownEntryLabel(entry: entry, compact: compact),
              ),
            if (actions.isNotEmpty) ...[
              for (var index = 0; index < actions.length; index++)
                DropdownMenuItem(
                  value: -index - 1,
                  enabled: actions[index].enabled,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(actions[index].icon, size: 18),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          actions[index].label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
          onChanged: (id) {
            if (id == null) return;
            if (id < 0) {
              actions[-id - 1].onSelected();
              return;
            }
            onChanged(id);
          },
          selectedItemBuilder: (context) => [
            for (final entry in entries)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!compact) ...[
                    Text(
                      label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: compact ? 96 : 180),
                    child: Text(entry.label, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            if (actions.isNotEmpty)
              for (var index = 0; index < actions.length; index++)
                const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }
}

class _DropdownEntryLabel extends StatelessWidget {
  const _DropdownEntryLabel({required this.entry, this.compact = false});

  final _DropdownEntry entry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 120 : 220),
      child: Text(entry.label, overflow: TextOverflow.ellipsis),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });
  final AgentConversation conversation;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.surfaceContainerHighest : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      conversation.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _relativeTime(conversation.updatedAt),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                IconButton(
                  tooltip: 'agentDeleteConversation'.tr(),
                  onPressed: onDelete,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Symbols.delete_outline, size: 18),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentProviderEditorSheet extends StatefulWidget {
  const _AgentProviderEditorSheet({
    required this.existing,
    required this.onSave,
  });
  final AgentProvider? existing;
  final Future<void> Function(AgentProviderDraft draft) onSave;

  @override
  State<_AgentProviderEditorSheet> createState() =>
      _AgentProviderEditorSheetState();
}

class _AgentModelEditorSheet extends StatefulWidget {
  const _AgentModelEditorSheet({required this.onSave, required this.presets});
  final Future<void> Function(String model) onSave;
  final List<String> presets;

  @override
  State<_AgentModelEditorSheet> createState() => _AgentModelEditorSheetState();
}

class _AgentModelEditorSheetState extends State<_AgentModelEditorSheet> {
  final _model = TextEditingController();
  var _saving = false;

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(_model.text);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SheetScaffold(
    titleText: 'agentAddModel'.tr(),
    heightFactor: 0.36,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text('agentModelIdentifierHint'.tr()),
        const SizedBox(height: 20),
        if (widget.presets.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            decoration: InputDecoration(labelText: 'agentPresetModel'.tr()),
            items: [
              for (final model in widget.presets)
                DropdownMenuItem(value: model, child: Text(model)),
            ],
            onChanged: (model) {
              if (model != null) _model.text = model;
            },
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _model,
          autofocus: true,
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(
            labelText: 'agentModelIdentifier'.tr(),
            hintText: 'agentModelIdentifierExample'.tr(),
          ),
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text('agentAddModel'.tr()),
          ),
        ),
      ],
    ),
  );
}

class _AgentProviderEditorSheetState extends State<_AgentProviderEditorSheet> {
  late final _name = TextEditingController(
    text: widget.existing?.name ?? 'OpenAI',
  );
  final _key = TextEditingController();
  late final _endpoint = TextEditingController(
    text: widget.existing?.baseUrl ?? 'https://api.openai.com',
  );
  late final _model = TextEditingController(
    text: widget.existing?.model ?? 'gpt-4o-mini',
  );
  var _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _key.dispose();
    _endpoint.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(
        AgentProviderDraft(
          name: _name.text,
          apiKey: _key.text,
          baseUrl: _endpoint.text,
          model: _model.text,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SheetScaffold(
    titleText: widget.existing == null
        ? 'agentAddAiProvider'.tr()
        : 'agentEditAiProvider'.tr(),
    heightFactor: 0.72,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text('agentProviderInfo'.tr()),
        const SizedBox(height: 20),
        DropdownButtonFormField<_AgentProviderPreset>(
          decoration: InputDecoration(labelText: 'agentProviderPreset'.tr()),
          items: [
            for (final preset in _providerPresets)
              DropdownMenuItem(value: preset, child: Text(preset.name)),
          ],
          onChanged: (preset) {
            if (preset == null) return;
            setState(() {
              _name.text = preset.name;
              _endpoint.text = preset.baseUrl;
              _model.text = preset.models.first;
            });
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: 'agentProviderName'.tr()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _key,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: widget.existing == null
                ? 'agentApiKey'.tr()
                : 'agentApiKeyKeepCurrent'.tr(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _endpoint,
          keyboardType: TextInputType.url,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: 'agentBaseUrl'.tr()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _model,
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(labelText: 'agentModel'.tr()),
        ),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Symbols.save),
            label: Text('agentSaveProvider'.tr()),
          ),
        ),
      ],
    ),
  );
}

enum _MessageKind { user, assistant, tool }

String _relativeTime(DateTime time) {
  final local = time.toLocal();
  final difference = DateTime.now().difference(local);
  if (difference.inMinutes < 1) return 'agentJustNow'.tr();
  if (difference.inHours < 1) {
    return 'agentMinutesAgo'.tr(args: ['${difference.inMinutes}']);
  }
  if (difference.inDays < 1) {
    return 'agentHoursAgo'.tr(args: ['${difference.inHours}']);
  }
  if (difference.inDays < 7) {
    return 'agentDaysAgo'.tr(args: ['${difference.inDays}']);
  }
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});
  final _AgentMessage message;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (message.kind == _MessageKind.tool) {
      return Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: _ToolCallCard(
            text: message.text,
            autoApproved: message.autoApproved,
          ),
        ),
      );
    }
    final color = switch (message.kind) {
      _MessageKind.user => scheme.secondaryContainer,
      _MessageKind.tool => scheme.surfaceContainerHighest,
      _MessageKind.assistant => scheme.surfaceContainerLow,
    };
    return Align(
      alignment: message.kind == _MessageKind.user
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: message.kind == _MessageKind.assistant
            // This follows Island's MarkdownTextContent implementation while
            // keeping MaidKit independent of Island's app-level package.
            ? _buildMarkdown(context)
            : SelectableText(message.text),
      ),
    );
  }

  Widget _buildMarkdown(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final base = isDark
        ? MarkdownConfig.darkConfig
        : MarkdownConfig.defaultConfig;
    return MarkdownBlock(
      data: message.text,
      selectable: true,
      config: base.copy(
        configs: [
          PConfig(textStyle: theme.textTheme.bodyMedium!),
          PreConfig(
            textStyle: const TextStyle(fontSize: 13),
            styleNotMatched: const TextStyle(fontSize: 13),
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          CodeConfig(
            style: TextStyle(backgroundColor: scheme.surfaceContainerHighest),
          ),
          TableConfig(
            wrapper: (child) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: child,
            ),
          ),
          LinkConfig(
            style: TextStyle(
              color: scheme.primary,
              decoration: TextDecoration.underline,
            ),
          ),
        ],
      ),
      generator: MarkdownGenerator(
        linesMargin: const EdgeInsets.symmetric(vertical: 4),
      ),
    );
  }
}

class _ToolCallCard extends StatelessWidget {
  const _ToolCallCard({required this.text, this.autoApproved = false});
  final String text;
  final bool autoApproved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final separator = text.indexOf('\n');
    final title = separator < 0
        ? text
        : text.substring(0, separator).replaceFirst(RegExp(r':\s*$'), '');
    final content = separator < 0 ? '' : text.substring(separator + 1);
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      backgroundColor: scheme.surfaceContainerHighest,
      collapsedBackgroundColor: scheme.surfaceContainerHighest,
      visualDensity: VisualDensity.compact,
      title: Row(
        children: [
          Icon(Symbols.terminal, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
          if (autoApproved) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'agentAutoApproved'.tr(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
      children: [
        SelectableText(
          content,
          style: TextStyle(
            fontFamily: MaidKitFonts.mono,
            fontSize: 12,
            height: 1.4,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.proposal,
    required this.serverName,
    required this.working,
    required this.reconnectRequired,
    required this.onApprove,
    required this.onDecline,
  });

  final AgentProposal proposal;
  final String serverName;
  final bool working;
  final bool reconnectRequired;
  final VoidCallback onApprove;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Icon(Symbols.terminal, size: 16, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    proposal.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  proposal.detail,
                  style: TextStyle(
                    fontFamily: MaidKitFonts.mono,
                    fontSize: 12,
                    height: 1.4,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'agentTarget'.tr(args: [serverName]),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: working ? null : onApprove,
                      icon: Icon(
                        reconnectRequired
                            ? Symbols.refresh
                            : Symbols.play_arrow,
                      ),
                      label: Text(
                        reconnectRequired
                            ? 'agentReconnectResume'.tr()
                            : 'agentApproveRun'.tr(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: working ? null : onDecline,
                      child: Text('agentDecline'.tr()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentThinkingIndicator extends StatelessWidget {
  const _AgentThinkingIndicator();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'agentWorking'.tr(),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentCapabilitiesSheet extends ConsumerStatefulWidget {
  const _AgentCapabilitiesSheet();

  @override
  ConsumerState<_AgentCapabilitiesSheet> createState() =>
      _AgentCapabilitiesSheetState();
}

class _AgentCapabilitiesSheetState
    extends ConsumerState<_AgentCapabilitiesSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 2, vsync: this)..addListener(() {
        if (_tabController.index != _tabIndex) {
          setState(() => _tabIndex = _tabController.index);
        }
      });
  int _tabIndex = 0;

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _editMcpServer([McpServer? existing]) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        useRootNavigator: true,
        builder: (sheetContext) => _McpServerEditorSheet(
          existing: existing,
          onSave: (draft) async {
            try {
              final id = await ref
                  .read(mcpRepositoryProvider)
                  .save(draft, id: existing?.id);
              if (existing != null) {
                // Relaunch with the new configuration on next use.
                await ref.read(mcpClientManagerProvider).dispose(id);
              }
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            } catch (error) {
              showMaidKitErrorAlert(
                error,
                title: 'agentCouldNotSaveMcpServer'.tr(),
              );
            }
          },
        ),
      );

  Future<void> _deleteMcpServer(McpServer server) async {
    final confirmed = await showMaidKitConfirmAlert(
      'agentDeleteMcpServerConfirm'.tr(args: [server.name]),
      'agentDeleteMcpServer'.tr(),
      icon: Symbols.delete_outline,
      isDanger: true,
    );
    if (!confirmed) return;
    await ref.read(mcpClientManagerProvider).dispose(server.id);
    await ref.read(mcpRepositoryProvider).delete(server.id);
  }

  Future<void> _setMcpEnabled(McpServer server, bool enabled) async {
    await ref.read(mcpRepositoryProvider).setEnabled(server.id, enabled);
    if (!enabled) {
      await ref.read(mcpClientManagerProvider).dispose(server.id);
    }
  }

  Future<void> _importMcpConfig() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    builder: (_) => const _McpConfigImportSheet(),
  );

  Future<void> _browseSkillRegistry() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    builder: (_) => const _SkillRegistrySheet(),
  );

  Future<void> _editSkill([AgentSkill? existing]) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    builder: (sheetContext) => _SkillEditorSheet(
      existing: existing,
      onSave: (draft) async {
        try {
          await ref.read(skillRepositoryProvider).save(draft, id: existing?.id);
          if (sheetContext.mounted) Navigator.pop(sheetContext);
        } catch (error) {
          showMaidKitErrorAlert(error, title: 'agentCouldNotSaveSkill'.tr());
        }
      },
    ),
  );

  Future<void> _deleteSkill(AgentSkill skill) async {
    final confirmed = await showMaidKitConfirmAlert(
      'agentDeleteSkillConfirm'.tr(args: [skill.name]),
      'agentDeleteSkill'.tr(),
      icon: Symbols.delete_outline,
      isDanger: true,
    );
    if (!confirmed) return;
    await ref.read(skillRepositoryProvider).delete(skill.id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mcpServers =
        ref.watch(mcpServersProvider).asData?.value ?? const <McpServer>[];
    final skills =
        ref.watch(agentSkillsProvider).asData?.value ?? const <AgentSkill>[];
    return SheetScaffold(
      titleText: 'agentCapabilities'.tr(),
      heightFactor: 0.85,
      actions: [
        if (_tabIndex == 0) ...[
          IconButton(
            tooltip: 'agentImportMcpConfig'.tr(),
            onPressed: () => _importMcpConfig(),
            icon: const Icon(Symbols.content_paste),
          ),
          IconButton(
            tooltip: 'agentAddMcpServer'.tr(),
            onPressed: () => _editMcpServer(),
            icon: const Icon(Symbols.add),
          ),
        ] else ...[
          IconButton(
            tooltip: 'agentSkillRegistry'.tr(),
            onPressed: () => _browseSkillRegistry(),
            icon: const Icon(Symbols.travel_explore),
          ),
          IconButton(
            tooltip: 'agentAddSkill'.tr(),
            onPressed: () => _editSkill(),
            icon: const Icon(Symbols.add),
          ),
        ],
      ],
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: [
              Tab(text: 'agentMcpServers'.tr()),
              Tab(text: 'agentSkills'.tr()),
            ],
          ),
          Expanded(
            child: _tabIndex == 0
                ? _buildMcpServerList(scheme, mcpServers)
                : _buildSkillList(scheme, skills),
          ),
        ],
      ),
    );
  }

  Widget _buildMcpServerList(ColorScheme scheme, List<McpServer> servers) {
    if (servers.isEmpty) {
      return Center(
        child: Text(
          'agentNoMcpServers'.tr(),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: servers.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final server = servers[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 2,
          ),
          title: Text(
            server.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${server.command} ${decodeMcpArguments(server.arguments).join(' ')}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: MaidKitFonts.mono,
              fontSize: 11,
              color: scheme.onSurfaceVariant,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(
                value: server.enabled,
                onChanged: (value) => _setMcpEnabled(server, value),
              ),
              IconButton(
                tooltip: 'agentRestartMcpServer'.tr(),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Symbols.restart_alt, size: 18),
                onPressed: () =>
                    ref.read(mcpClientManagerProvider).dispose(server.id),
              ),
              IconButton(
                tooltip: 'agentEditMcpServer'.tr(),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Symbols.edit, size: 18),
                onPressed: () => _editMcpServer(server),
              ),
              IconButton(
                tooltip: 'agentDeleteMcpServer'.tr(),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Symbols.delete_outline, size: 18),
                onPressed: () => _deleteMcpServer(server),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSkillList(ColorScheme scheme, List<AgentSkill> skills) {
    if (skills.isEmpty) {
      return Center(
        child: Text(
          'agentNoSkills'.tr(),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: skills.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final skill = skills[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 2,
          ),
          title: Text(skill.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            skill.description.isEmpty
                ? 'agentNoSkillDescription'.tr()
                : skill.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(
                value: skill.enabled,
                onChanged: (value) => ref
                    .read(skillRepositoryProvider)
                    .setEnabled(skill.id, value),
              ),
              IconButton(
                tooltip: 'agentEditSkill'.tr(),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Symbols.edit, size: 18),
                onPressed: () => _editSkill(skill),
              ),
              IconButton(
                tooltip: 'agentDeleteSkill'.tr(),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Symbols.delete_outline, size: 18),
                onPressed: () => _deleteSkill(skill),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _McpServerEditorSheet extends StatefulWidget {
  const _McpServerEditorSheet({required this.existing, required this.onSave});

  final McpServer? existing;
  final Future<void> Function(McpServerDraft draft) onSave;

  @override
  State<_McpServerEditorSheet> createState() => _McpServerEditorSheetState();
}

class _McpServerEditorSheetState extends State<_McpServerEditorSheet> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _command = TextEditingController(
    text: widget.existing?.command ?? '',
  );
  late final _arguments = TextEditingController(
    text: widget.existing == null
        ? ''
        : decodeMcpArguments(widget.existing!.arguments).join('\n'),
  );
  late final _environment = TextEditingController(
    text: widget.existing == null
        ? ''
        : const JsonEncoder.withIndent(
            '  ',
          ).convert(decodeMcpEnvironment(widget.existing!.environment)),
  );
  late bool _enabled = widget.existing?.enabled ?? true;
  var _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _command.dispose();
    _arguments.dispose();
    _environment.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final environment = <String, String>{};
    final rawEnvironment = _environment.text.trim();
    if (rawEnvironment.isNotEmpty) {
      final Object? decoded;
      try {
        decoded = jsonDecode(rawEnvironment);
      } catch (_) {
        showMaidKitErrorAlert(
          FormatException('agentEnvironmentInvalidJson'.tr()),
          title: 'agentCouldNotSaveMcpServer'.tr(),
        );
        return;
      }
      if (decoded is! Map) {
        showMaidKitErrorAlert(
          FormatException('agentEnvironmentInvalidJson'.tr()),
          title: 'agentCouldNotSaveMcpServer'.tr(),
        );
        return;
      }
      for (final entry in decoded.entries) {
        if (entry.key is String) {
          environment[entry.key as String] = '${entry.value}';
        }
      }
    }
    setState(() => _saving = true);
    try {
      await widget.onSave(
        McpServerDraft(
          name: _name.text,
          command: _command.text,
          arguments: [
            for (final line in _arguments.text.split('\n'))
              if (line.trim().isNotEmpty) line.trim(),
          ],
          environment: environment,
          enabled: _enabled,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SheetScaffold(
    titleText: widget.existing == null
        ? 'agentAddMcpServer'.tr()
        : 'agentEditMcpServer'.tr(),
    heightFactor: 0.85,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text('agentMcpServerInfo'.tr()),
        const SizedBox(height: 20),
        TextField(
          controller: _name,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: 'agentMcpServerName'.tr()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _command,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'agentMcpServerCommand'.tr(),
            hintText: 'agentMcpServerCommandHint'.tr(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _arguments,
          minLines: 2,
          maxLines: 6,
          autocorrect: false,
          enableSuggestions: false,
          style: TextStyle(fontFamily: MaidKitFonts.mono, fontSize: 13),
          decoration: InputDecoration(
            labelText: 'agentMcpServerArguments'.tr(),
            hintText: 'agentMcpServerArgumentsHint'.tr(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _environment,
          minLines: 2,
          maxLines: 6,
          autocorrect: false,
          enableSuggestions: false,
          style: TextStyle(fontFamily: MaidKitFonts.mono, fontSize: 13),
          decoration: InputDecoration(
            labelText: 'agentMcpServerEnvironment'.tr(),
            hintText: 'agentMcpServerEnvironmentHint'.tr(),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('agentEnabled'.tr()),
          value: _enabled,
          onChanged: (value) => setState(() => _enabled = value),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Symbols.save),
            label: Text('agentSaveMcpServer'.tr()),
          ),
        ),
      ],
    ),
  );
}

class _McpConfigImportSheet extends ConsumerStatefulWidget {
  const _McpConfigImportSheet();

  @override
  ConsumerState<_McpConfigImportSheet> createState() =>
      _McpConfigImportSheetState();
}

class _McpConfigImportSheetState extends ConsumerState<_McpConfigImportSheet> {
  final _config = TextEditingController();
  var _busy = false;
  String? _summary;
  List<String>? _errors;

  @override
  void dispose() {
    _config.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    if (_busy) return;
    final result = parseMcpConfigJson(_config.text);
    if (result.servers.isEmpty) {
      setState(() {
        _summary = null;
        _errors = result.errors;
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final repository = ref.read(mcpRepositoryProvider);
      final existing = await repository.all();
      final byName = {for (final server in existing) server.name: server};
      var added = 0;
      var updated = 0;
      for (final draft in result.servers) {
        final current = byName[draft.name];
        if (current == null) {
          await repository.save(draft);
          added++;
        } else {
          await repository.save(draft, id: current.id);
          // Relaunch with the imported configuration on next use.
          await ref.read(mcpClientManagerProvider).dispose(current.id);
          updated++;
        }
      }
      final parts = <String>[
        if (added > 0) 'agentImportMcpAdded'.tr(args: ['$added']),
        if (updated > 0) 'agentImportMcpUpdated'.tr(args: ['$updated']),
      ];
      setState(() {
        _summary = parts.join(', ');
        _errors = result.hasErrors ? result.errors : null;
      });
    } catch (error) {
      setState(() {
        _summary = null;
        _errors = ['$error'];
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SheetScaffold(
      titleText: 'agentImportMcpConfig'.tr(),
      heightFactor: 0.8,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text('agentImportMcpConfigInfo'.tr()),
          const SizedBox(height: 16),
          TextField(
            controller: _config,
            minLines: 10,
            maxLines: 18,
            autocorrect: false,
            enableSuggestions: false,
            style: TextStyle(
              fontFamily: MaidKitFonts.mono,
              fontSize: 13,
              height: 1.4,
            ),
            decoration: InputDecoration(
              hintText: 'agentImportMcpConfigHint'.tr(),
            ),
          ),
          if (_summary != null) ...[
            const SizedBox(height: 16),
            Text(
              _summary!,
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (_errors != null && _errors!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _errors!.join('\n'),
              style: TextStyle(color: scheme.error, fontSize: 13, height: 1.4),
            ),
          ],
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _busy ? null : _import,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Symbols.upload),
              label: Text('agentImportMcpConfigParse'.tr()),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkillEditorSheet extends StatefulWidget {
  const _SkillEditorSheet({required this.existing, required this.onSave});

  final AgentSkill? existing;
  final Future<void> Function(AgentSkillDraft draft) onSave;

  @override
  State<_SkillEditorSheet> createState() => _SkillEditorSheetState();
}

class _SkillEditorSheetState extends State<_SkillEditorSheet> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _description = TextEditingController(
    text: widget.existing?.description ?? '',
  );
  late final _content = TextEditingController(
    text: widget.existing?.content ?? '',
  );
  late bool _enabled = widget.existing?.enabled ?? true;
  var _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(
        AgentSkillDraft(
          name: _name.text,
          description: _description.text,
          content: _content.text,
          enabled: _enabled,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SheetScaffold(
    titleText: widget.existing == null
        ? 'agentAddSkill'.tr()
        : 'agentEditSkill'.tr(),
    heightFactor: 0.8,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text('agentSkillInfo'.tr()),
        const SizedBox(height: 20),
        TextField(
          controller: _name,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: 'agentSkillName'.tr()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _description,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'agentSkillDescription'.tr(),
            hintText: 'agentSkillDescriptionHint'.tr(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _content,
          minLines: 8,
          maxLines: 16,
          autocorrect: false,
          enableSuggestions: false,
          style: TextStyle(
            fontFamily: MaidKitFonts.mono,
            fontSize: 13,
            height: 1.4,
          ),
          decoration: InputDecoration(
            labelText: 'agentSkillContent'.tr(),
            alignLabelWithHint: true,
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('agentEnabled'.tr()),
          value: _enabled,
          onChanged: (value) => setState(() => _enabled = value),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Symbols.save),
            label: Text('agentSaveSkill'.tr()),
          ),
        ),
      ],
    ),
  );
}

class _SkillRegistrySheet extends ConsumerStatefulWidget {
  const _SkillRegistrySheet();

  @override
  ConsumerState<_SkillRegistrySheet> createState() =>
      _SkillRegistrySheetState();
}

class _SkillRegistrySheetState extends ConsumerState<_SkillRegistrySheet> {
  late Future<List<RegistrySkill>> _catalogFuture = _load();
  Future<List<RegistrySkillHit>>? _searchFuture;
  final _query = TextEditingController();
  Timer? _debounce;
  String _activeQuery = '';
  final _added = <String>{};
  final _busy = <String>{};

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  /// Remote search, debounced the same way the CLI's interactive search is.
  /// Queries shorter than two characters fall back to the default catalog.
  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _activeQuery = '';
        _searchFuture = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() {
        _activeQuery = query;
        _searchFuture = ref
            .read(skillRegistryClientProvider)
            .searchSkills(query);
      });
    });
  }

  Future<List<RegistrySkill>> _load() async {
    final client = ref.read(skillRegistryClientProvider);
    final names = await client.listSkills();
    final skills = await Future.wait([
      for (final name in names) client.fetchSkill(name),
    ]);
    return skills;
  }

  void _retry() {
    if (_activeQuery.isNotEmpty) {
      setState(() {
        _searchFuture = ref
            .read(skillRegistryClientProvider)
            .searchSkills(_activeQuery);
      });
    } else {
      setState(() => _catalogFuture = _load());
    }
  }

  Future<void> _saveSkill(
    String name,
    String description,
    String content,
  ) async {
    final repository = ref.read(skillRepositoryProvider);
    final existing = await repository.all();
    final current = existing.where((saved) => saved.name == name).firstOrNull;
    await repository.save(
      AgentSkillDraft(name: name, description: description, content: content),
      id: current?.id,
    );
    setState(() => _added.add(name));
  }

  Future<void> _add(RegistrySkill skill) async {
    if (_busy.contains(skill.name)) return;
    setState(() => _busy.add(skill.name));
    try {
      await _saveSkill(skill.name, skill.description, skill.content);
    } catch (error) {
      showMaidKitErrorAlert(error, title: 'agentCouldNotAddSkill'.tr());
    } finally {
      if (mounted) setState(() => _busy.remove(skill.name));
    }
  }

  Future<void> _addHit(RegistrySkillHit hit) async {
    if (_busy.contains(hit.skillId)) return;
    setState(() => _busy.add(hit.skillId));
    try {
      final skill = await ref
          .read(skillRegistryClientProvider)
          .fetchSkillHit(hit);
      await _saveSkill(skill.name, skill.description, skill.content);
    } catch (error) {
      showMaidKitErrorAlert(error, title: 'agentCouldNotAddSkill'.tr());
    } finally {
      if (mounted) setState(() => _busy.remove(hit.skillId));
    }
  }

  static String _formatInstalls(int count) {
    if (count <= 0) return '';
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')}K';
    }
    return '$count';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SheetScaffold(
      titleText: 'agentSkillRegistry'.tr(),
      heightFactor: 0.85,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              'agentSkillRegistryInfo'.tr(),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              controller: _query,
              onChanged: _onQueryChanged,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                hintText: 'agentSkillRegistrySearch'.tr(),
                prefixIcon: const Icon(Symbols.search, size: 20),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'commonClearSearch'.tr(),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Symbols.close, size: 18),
                        onPressed: () {
                          _query.clear();
                          _onQueryChanged('');
                        },
                      ),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          Expanded(
            child: _activeQuery.isNotEmpty
                ? _buildSearchResults(scheme)
                : _buildCatalog(scheme),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(ColorScheme scheme) {
    return FutureBuilder<List<RegistrySkillHit>>(
      future: _searchFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (snapshot.hasError) {
          return _buildError(scheme, '${snapshot.error}');
        }
        final hits = snapshot.data ?? const <RegistrySkillHit>[];
        if (hits.isEmpty) {
          return _buildEmpty(scheme, 'agentSkillRegistryNoMatch'.tr());
        }
        final savedNames =
            ref
                .watch(agentSkillsProvider)
                .asData
                ?.value
                .map((skill) => skill.name)
                .toSet() ??
            <String>{};
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: hits.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, index) {
            final hit = hits[index];
            final exists = savedNames.contains(hit.skillId);
            final added = _added.contains(hit.skillId);
            final installs = _formatInstalls(hit.installs);
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 2,
              ),
              title: Text(
                hit.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                installs.isEmpty ? hit.source : '${hit.source} · $installs',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              trailing: added
                  ? Icon(Symbols.check_circle, size: 20, color: scheme.primary)
                  : FilledButton.tonal(
                      onPressed: _busy.contains(hit.skillId)
                          ? null
                          : () => _addHit(hit),
                      child: Text(
                        exists
                            ? 'agentSkillRegistryUpdate'.tr()
                            : 'agentSkillRegistryAdd'.tr(),
                      ),
                    ),
            );
          },
        );
      },
    );
  }

  Widget _buildCatalog(ColorScheme scheme) {
    return FutureBuilder<List<RegistrySkill>>(
      future: _catalogFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (snapshot.hasError) {
          return _buildError(scheme, '${snapshot.error}');
        }
        final skills = snapshot.data ?? const <RegistrySkill>[];
        if (skills.isEmpty) {
          return _buildEmpty(scheme, 'agentSkillRegistryEmpty'.tr());
        }
        final savedNames =
            ref
                .watch(agentSkillsProvider)
                .asData
                ?.value
                .map((skill) => skill.name)
                .toSet() ??
            <String>{};
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: skills.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, index) {
            final skill = skills[index];
            final exists = savedNames.contains(skill.name);
            final added = _added.contains(skill.name);
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 2,
              ),
              title: Text(
                skill.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                skill.description.isEmpty
                    ? 'agentNoSkillDescription'.tr()
                    : skill.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              trailing: added
                  ? Icon(Symbols.check_circle, size: 20, color: scheme.primary)
                  : FilledButton.tonal(
                      onPressed: _busy.contains(skill.name)
                          ? null
                          : () => _add(skill),
                      child: Text(
                        exists
                            ? 'agentSkillRegistryUpdate'.tr()
                            : 'agentSkillRegistryAdd'.tr(),
                      ),
                    ),
            );
          },
        );
      },
    );
  }

  Widget _buildError(ColorScheme scheme, String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.error, fontSize: 13),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _retry,
            icon: const Icon(Symbols.refresh),
            label: Text('agentRetry'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ColorScheme scheme, String message) {
    return Center(
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}
