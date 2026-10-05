import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dart_openai/dart_openai.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:markdown_widget/markdown_widget.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/shared/presentation/ansi_log_view.dart';
import 'package:maid_kit/shared/presentation/app_scaffold.dart';
import 'package:maid_kit/theme.dart';
import 'package:maid_kit/shared/presentation/maidkit_alert.dart';
import 'package:maid_kit/servers/server_connection_actions.dart';
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/terminal_session_adapter.dart'
    show SudoPromptAutofill;
import 'package:maid_kit/snippets/snippet_repository.dart';
import 'package:maid_kit/agent/mcp_client.dart';
import 'package:maid_kit/agent/mcp_config_parser.dart';
import 'package:maid_kit/agent/mcp_repository.dart';
import 'package:maid_kit/agent/skill_repository.dart';
import 'package:maid_kit/agent/skill_registry.dart';
import 'agent_attachment.dart';
import 'agent_composer.dart';
import 'agent_reasoning.dart';
import 'agent_repository.dart';
import 'agent_run_policy.dart';
import 'conversation_store.dart';
import 'personality_service.dart';
import 'token_counter.dart';
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

/// One agent chat, hosted as a pane tab: provider/model selectors, conversation
/// history sidebar, message list, and prompt.
///
/// The pane tab stack keeps the chat mounted while another tab is selected, so
/// streaming and queued work survive tab switches.
class AgentChatView extends ConsumerStatefulWidget {
  const AgentChatView({
    super.key,
    required this.tabId,
    required this.autofocus,
    required this.onTitleChanged,
    required this.onWorkingChanged,
  });

  final String tabId;

  /// Whether this chat is the selected tab, so its prompt can take focus.
  final bool autofocus;

  final ValueChanged<String> onTitleChanged;
  final ValueChanged<bool> onWorkingChanged;

  @override
  ConsumerState<AgentChatView> createState() => _AgentChatViewState();
}

class _AgentChatViewState extends ConsumerState<AgentChatView> {
  final _prompt = TextEditingController();
  final _promptFocus = FocusNode();
  final _showSidebar = ValueNotifier<bool>(false);
  final _messages = <_AgentMessage>[];
  // Files queued for the next prompt. They belong to the page rather than the
  // composer because a turn, a queued prompt and a saved conversation all have
  // to carry them.
  final _attachments = <AgentAttachment>[];
  bool _draggingFiles = false;
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
  bool _scrollVisibilityUpdateScheduled = false;
  String? _pendingPrompt;
  int? _activeProviderId;
  int? _activeModelId;
  AgentReasoning _reasoning = AgentReasoning.modelDefault;
  int? _conversationId;
  bool _ghost = false;
  bool _working = false;
  bool _personalityProviderProvisioned = false;
  AgentCancelToken? _activeToken;
  // The command an approved action is running, and the chat card streaming its
  // output. The session answers typed input and stops the process on its own,
  // so a stuck or prompting command never has to cancel the whole turn.
  AgentExecutionSession? _activeCommand;
  // Index of the tool card currently streaming, or -1 when none is.
  int _liveToolIndex = -1;
  bool _commandAcceptsInput = false;
  bool _commandPrompting = false;
  String? _commandPassword;
  // Reused from the terminal: the same watcher decides whether the remote is
  // showing a sudo password prompt, so the card can offer the saved secret
  // without a second, drifting matcher.
  SudoPromptAutofill? _commandAutofill;
  // MCP tools and skills gathered when a turn starts. Reused for the
  // continuation after an approved action so the model always sees the same
  // tool set across the request/execute/continue cycle.
  List<AgentMcpToolTarget> _activeMcpTools = const [];
  List<AgentSkillTarget> _activeSkills = const [];
  String? _activeMcpUnavailable;
  // Token accounting for this chat. It lives on a notifier so typing re-counts
  // the meter without rebuilding the message list, and the numbers are what the
  // next request will carry rather than what the model has already answered.
  final _meter = ValueNotifier<AgentContextMeter>(const AgentContextMeter());
  // Tokens in the system prompt and the tool schemas of the current turn. They
  // do not move while the prompt is written, so they are counted once per turn.
  int _staticTokens = 0;
  // Tokens in the history the next request will replay, counted whenever the
  // conversation context changes.
  int _historyTokens = 0;

  @override
  void initState() {
    super.initState();
    _restoreSelection();
    _messagesScroll.addListener(_updateScrollToBottomVisibility);
    _prompt.addListener(_publishMeter);
    if (widget.autofocus) _focusPromptAfterFrame();
  }

  @override
  void didUpdateWidget(AgentChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autofocus && !oldWidget.autofocus) _focusPromptAfterFrame();
  }

  /// Opens the picker and queues what it returns. Each file is read on its
  /// own, so one that turns out not to be text shows its problem on the strip
  /// instead of failing the whole pick.
  Future<void> _attachFromPicker() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      // A browser has no filesystem path to read back, so ask the picker for
      // the bytes; native keeps reading the file from disk.
      withData: kIsWeb,
    );
    final files = result?.files ?? const <PlatformFile>[];
    if (files.isEmpty) return;
    await _addAttachments([
      for (final file in files)
        readAgentAttachment(
          name: file.name,
          path: file.path,
          bytes: file.bytes,
        ),
    ]);
  }

  /// Queues files dropped on the chat: the same path a picked file takes, with
  /// the macOS sandbox access a drag out of Finder needs.
  Future<void> _attachDropped(List<DropItem> items) async {
    if (_proposal != null) return;
    final queued = <AgentAttachment>[];
    for (final item in items.whereType<DropItemFile>()) {
      final bookmark = item.extraAppleBookmark;
      final scoped =
          bookmark != null &&
          await DesktopDrop.instance.startAccessingSecurityScopedResource(
            bookmark: bookmark,
          );
      try {
        queued.add(
          await readAgentAttachment(
            name: item.name,
            // A browser drop carries the file's bytes and a blob URL rather
            // than a path; a desktop drop is the other way round.
            path: kIsWeb ? null : item.path,
            bytes: kIsWeb ? await item.readAsBytes() : null,
          ),
        );
      } finally {
        if (scoped) {
          await DesktopDrop.instance.stopAccessingSecurityScopedResource(
            bookmark: bookmark,
          );
        }
      }
    }
    if (queued.isEmpty || !mounted) return;
    setState(() => _attachments.addAll(queued));
    _publishMeter();
  }

  Future<void> _addAttachments(List<Future<AgentAttachment>> pending) async {
    final resolved = await Future.wait(pending);
    if (!mounted || resolved.isEmpty) return;
    setState(() => _attachments.addAll(resolved));
    _publishMeter();
  }

  /// A block pasted into the field becomes a text attachment instead: the
  /// composer keeps the message, the document keeps the document, and the
  /// block stays editable until it is sent.
  void _attachText(String text) {
    setState(() {
      _attachments.add(
        AgentAttachment.text(text, name: 'agentPastedText'.tr()),
      );
    });
    _publishMeter();
  }

  Future<void> _editAttachment(int index) async {
    if (index < 0 || index >= _attachments.length) return;
    final attachment = _attachments[index];
    if (attachment.isImage) return;
    final edited = await showTextAttachmentEditor(
      context,
      name: attachment.name,
      text: attachment.content ?? '',
    );
    if (edited == null || !mounted) return;
    setState(() {
      _attachments[index] = attachment.copyWith(content: edited);
    });
    _publishMeter();
  }

  void _removeAttachment(int index) {
    if (index < 0 || index >= _attachments.length) return;
    setState(() => _attachments.removeAt(index));
    _publishMeter();
  }

  Future<void> _restoreSelection() async {
    final selection = await ref.read(agentSelectionProvider.future);
    if (!mounted) return;
    setState(() {
      _reasoning = selection.reasoning;
      if (selection.providerId != null) {
        _activeProviderId = selection.providerId;
        _activeModelId = selection.modelId;
      }
    });
  }

  void _persistSelection() {
    ref
        .read(agentSelectionProvider.notifier)
        .select(providerId: _activeProviderId, modelId: _activeModelId);
  }

  /// Remembers how hard the model should think. Like the provider and model,
  /// it is a standing choice rather than a property of one message, so it is
  /// saved and carried by every request of this chat.
  void _selectReasoning(AgentReasoning reasoning) {
    setState(() => _reasoning = reasoning);
    ref.read(agentSelectionProvider.notifier).selectReasoning(reasoning);
  }

  @override
  void dispose() {
    _showSidebar.dispose();
    _meter.dispose();
    _prompt.removeListener(_publishMeter);
    _messagesScroll.removeListener(_updateScrollToBottomVisibility);
    _messagesScroll.dispose();
    _promptFocus.dispose();
    _prompt.dispose();
    super.dispose();
  }

  void _interrupt() => _activeToken?.cancel();

  /// Focuses the prompt once the tab that owns this chat is on screen, so
  /// typing can start immediately after the tab is opened or selected.
  void _focusPromptAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _promptFocus.requestFocus();
    });
  }

  /// Keeps the tab chip label in sync with the conversation title.
  void _reportTitle() => widget.onTitleChanged(_conversationTitle(_messages));

  void _updateScrollToBottomVisibility() {
    if (!_messagesScroll.hasClients) return;
    _setScrollToBottomVisibility(_messagesScroll.position);
  }

  // Scroll notifications can be delivered during layout, so defer the
  // visibility rebuild until the frame has completed.
  void _setScrollToBottomVisibility(ScrollMetrics position) {
    if (!position.hasContentDimensions || !mounted) return;
    final visible = position.pixels < position.maxScrollExtent - 64;
    if (visible == _showScrollToBottom || _scrollVisibilityUpdateScheduled) {
      return;
    }
    _scrollVisibilityUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollVisibilityUpdateScheduled = false;
      if (!mounted || !_messagesScroll.hasClients) return;
      final currentPosition = _messagesScroll.position;
      if (!currentPosition.hasContentDimensions) return;
      final currentVisible =
          currentPosition.pixels < currentPosition.maxScrollExtent - 64;
      if (currentVisible == _showScrollToBottom) return;
      setState(() => _showScrollToBottom = currentVisible);
    });
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
    final attachments = List<AgentAttachment>.of(_attachments);
    final servers = ref.read(serversProvider).asData?.value ?? const <Server>[];
    if ((text.isEmpty && attachments.isEmpty) ||
        servers.isEmpty ||
        _proposal != null) {
      return;
    }
    setState(() {
      _queuedPrompts.add(_QueuedPrompt(text, attachments));
      _prompt.clear();
      _attachments.clear();
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
    await _runPrompt(queued.text, queued.attachments);
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
    await _runPrompt(queued.text, queued.attachments);
  }

  Future<void> _send() async {
    final text = _prompt.text.trim();
    final attachments = List<AgentAttachment>.of(_attachments);
    final servers = ref.read(serversProvider).asData?.value ?? const <Server>[];
    if ((text.isEmpty && attachments.isEmpty) ||
        servers.isEmpty ||
        _working ||
        _proposal != null) {
      return;
    }
    await _runPrompt(text, attachments);
  }

  Future<void> _runPrompt(
    String text,
    List<AgentAttachment> attachments,
  ) async {
    final servers = ref.read(serversProvider).asData?.value ?? const <Server>[];
    if ((text.isEmpty && attachments.isEmpty) ||
        servers.isEmpty ||
        _working ||
        _proposal != null) {
      return;
    }
    final targets = _serverTargets(servers);
    final snippets = await ref.read(snippetRepositoryProvider).all();
    if (!mounted) return;
    final promptContent = agentUserContent(text, attachments);
    final userMessage = {'role': 'user', 'content': promptContent};
    final conversationContext = List<Map<String, dynamic>>.from(_agentContext);
    setState(() {
      _working = true;
      _pendingPrompt = text;
      _pendingContext = [...conversationContext, userMessage];
      _messages.add(_AgentMessage.user(text, attachments: attachments));
      _prompt.clear();
      _attachments.clear();
    });
    widget.onWorkingChanged(true);
    _reportTitle();
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
      final agent = SshAgentService(
        config,
        personality: personality,
        uiLanguage: context.locale.toLanguageTag(),
        hideServerAddresses: ref.read(hideServerAddressesProvider),
        reasoningEffort: _reasoning.effort,
      );
      _measureLiveContext(
        agent: agent,
        servers: targets,
        snippets: _snippetTargets(snippets),
        mcpTools: mcpTools,
        skills: skillTargets,
        mcpUnavailable: mcpUnavailable,
        history: conversationContext,
      );
      final turn = await agent.request(
        servers: targets,
        snippets: _snippetTargets(snippets),
        mcpTools: mcpTools,
        skills: skillTargets,
        mcpUnavailable: mcpUnavailable,
        prompt: promptContent,
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
      _recordCall(turn);
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
        widget.onWorkingChanged(false);
        await _persistConversation();
        _refreshHistoryTokens();
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
    widget.onWorkingChanged(true);
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
      Server? targetServer;
      final serverId = approvedProposal.serverId;
      if (serverId != null) {
        final server = servers
            .where((server) => server.id == serverId)
            .firstOrNull;
        if (server == null) {
          throw StateError('agentServerGone'.tr());
        }
        targetServer = server;
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
        reasoningEffort: _reasoning.effort,
      );
      final cancelToken = AgentCancelToken();
      _activeToken = cancelToken;
      final toolIndex = await _beginToolCard(
        approvedProposal,
        autoApproved: autoApproved,
        server: targetServer,
      );
      if (!mounted) return;
      final String result;
      try {
        result = await _executeProposal(
          agent,
          client,
          approvedProposal,
          cancelToken,
          sink: _commandSink(toolIndex),
        );
      } catch (_) {
        // The card has to stop streaming even when the action never produced a
        // result, or it would keep the stop control and the input field alive
        // for a run that is over. What the process printed stays on screen.
        if (mounted && toolIndex < _messages.length) {
          setState(() {
            _messages[toolIndex] = _messages[toolIndex].copyWith(live: false);
            _endToolCard();
          });
        }
        rethrow;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _messages[toolIndex] = _AgentMessage.tool(
          '${approvedProposal.title}:\n$result',
          autoApproved: autoApproved,
        );
        _endToolCard();
        _proposal = null;
        _reconnectRequired = false;
      });
      _scrollToBottom();
      final targets = _serverTargets(servers);
      final snippets = _snippetTargets(
        await ref.read(snippetRepositoryProvider).all(),
      );
      _measureLiveContext(
        agent: agent,
        servers: targets,
        snippets: snippets,
        mcpTools: _activeMcpTools,
        skills: _activeSkills,
        mcpUnavailable: _activeMcpUnavailable,
        history: _pendingContext,
      );
      var streamedMessageIndex = -1;
      final turn = await agent.continueAfterExecution(
        servers: targets,
        snippets: snippets,
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
      _recordCall(turn);
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
        widget.onWorkingChanged(false);
        await _persistConversation();
        _refreshHistoryTokens();
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
    // The browser cannot spawn MCP server processes; skip them entirely so a
    // configured server does not surface a launch failure on every turn.
    final servers = kIsWeb
        ? const <McpServer>[]
        : ref.read(mcpServersProvider).asData?.value ?? const <McpServer>[];
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

  /// Adds the tool card for an action that is about to run and returns its
  /// index. The card streams the command's output in place until the finished
  /// result replaces it, so a long command is visible while it runs instead of
  /// appearing all at once when it ends.
  Future<int> _beginToolCard(
    AgentProposal proposal, {
    required bool autoApproved,
    required Server? server,
  }) async {
    final password = server == null ? null : await _storedSudoPassword(server);
    if (!mounted) return _liveToolIndex;
    final index = _messages.length;
    setState(() {
      _messages.add(
        _AgentMessage.tool(
          '${proposal.title}:\n',
          autoApproved: autoApproved,
          live: true,
        ),
      );
      _liveToolIndex = index;
      // A command may prompt for anything; a snippet's stdin already carries
      // its script, so it cannot take typed input on top.
      _commandAcceptsInput = proposal.kind == AgentActionKind.command;
      _commandPrompting = false;
      _commandPassword = password;
      _commandAutofill = password == null ? null : SudoPromptAutofill(password);
    });
    _scrollToBottom();
    return index;
  }

  /// Forgets the streaming card. Safe to call when none is live.
  void _endToolCard() {
    _liveToolIndex = -1;
    _activeCommand = null;
    _commandAcceptsInput = false;
    _commandPrompting = false;
    _commandPassword = null;
    _commandAutofill = null;
  }

  AgentExecutionSink _commandSink(int index) => AgentExecutionSink(
    interactive: true,
    onOutput: (chunk) => _appendCommandOutput(index, chunk),
    onSession: (session) => _activeCommand = session,
  );

  /// Appends one chunk of command output to the live card, watching it for a
  /// sudo prompt so the card can offer the server's saved password.
  void _appendCommandOutput(int index, String chunk) {
    if (!mounted || index < 0 || index >= _messages.length) return;
    final message = _messages[index];
    if (!message.live) return;
    _commandAutofill?.inspect(Uint8List.fromList(utf8.encode(chunk)));
    final prompting = _commandAutofill?.prompting ?? false;
    setState(() {
      _messages[index] = message.copyWith(text: message.text + chunk);
      _commandPrompting = prompting;
    });
    _scrollToBottom();
  }

  /// Answers a prompt on the running command with a line of typed input.
  void _sendCommandInput(String line) {
    if (line.isEmpty) return;
    _activeCommand?.sendLine(line);
    if (mounted) setState(() => _commandPrompting = false);
  }

  /// Answers a sudo prompt with the target server's saved password.
  ///
  /// Only ever sent on this explicit request: the command came from the model,
  /// so filling the secret in automatically would leak it to any prompt the
  /// model's command chooses to print.
  void _sendSavedPassword() {
    final password = _commandPassword;
    if (password == null) return;
    _activeCommand?.sendLine(password);
    if (mounted) setState(() => _commandPrompting = false);
  }

  /// Stops the running command, keeping the turn: the model receives the
  /// output so far and a note that the command was stopped.
  void _stopActiveCommand() => _activeCommand?.stop();

  Future<String?> _storedSudoPassword(Server server) async {
    final credential = await ref
        .read(serverRepositoryProvider)
        .credentialFor(server);
    return credential.type == CredentialType.password
        ? credential.password
        : null;
  }

  Future<String> _executeProposal(
    SshAgentService agent,
    SSHClient? client,
    AgentProposal proposal,
    AgentCancelToken cancelToken, {
    AgentExecutionSink? sink,
  }) async {
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
          sink: sink,
        );
      case AgentActionKind.command:
      case AgentActionKind.readFile:
      case AgentActionKind.writeFile:
      case AgentActionKind.deleteFile:
        return agent.execute(
          _requireClient(client),
          proposal,
          cancelToken: cancelToken,
          sink: sink,
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
          AgentMcpToolTarget.bareName(proposal.toolCall.function?.name ?? ''),
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
    _refreshHistoryTokens();
    await _persistConversation();
    await _drainQueuedPrompts();
  }

  Future<void> _persistConversation() async {
    _reportTitle();
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
                  attachments: message.attachments,
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
      _attachments.clear();
      _agentContext.clear();
      _pendingContext = const [];
      _conversationId = null;
      _proposal = null;
      _reconnectRequired = false;
      _pendingPrompt = null;
    });
    _resetUsage();
    _reportTitle();
    _showSidebar.value = false;
    _promptFocus.requestFocus();
  }

  /// Fills the composer from a suggested prompt on the empty state. The text
  /// is only offered, never sent, so it stays editable before it goes out.
  void _useExample(String text) {
    _prompt
      ..text = text
      ..selection = TextSelection.collapsed(offset: text.length);
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
      _attachments.clear();
      _messages
        ..clear()
        ..addAll([
          for (final message in conversation.messages)
            _AgentMessage(
              message.text,
              _roleKind(message.role),
              autoApproved: false,
              attachments: message.attachments,
            ),
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
    _resetUsage();
    _refreshHistoryTokens();
    _persistSelection();
    _reportTitle();
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
        _attachments.clear();
        _agentContext.clear();
        _pendingContext = const [];
        _conversationId = null;
        _proposal = null;
        _reconnectRequired = false;
        _pendingPrompt = null;
      });
      _resetUsage();
      _reportTitle();
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
        onFetchModels: (apiKey, baseUrl) => ref
            .read(agentModelCatalogProvider)
            .fetchModels(baseUrl: baseUrl, apiKey: apiKey),
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
    final windowTokens = AgentTokenCounter.contextWindow(
      selectedModelId == null
          ? null
          : models
                .where((model) => model.id == selectedModelId)
                .firstOrNull
                ?.model,
    );
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
          body: ResponsiveSidebar(
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
            mainContent: _buildChat(
              servers: servers,
              mcpServers: mcpServers,
              scheme: scheme,
              compact: compact,
              windowTokens: windowTokens,
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

  /// The chat body: the log centred in the pane, the composer docked across
  /// the pane's full width.
  ///
  /// Files dropped anywhere on the chat attach to the next message; the picker
  /// behind the composer's attach button is the other way in.
  Widget _buildChat({
    required List<Server> servers,
    required List<McpServer> mcpServers,
    required ColorScheme scheme,
    required bool compact,
    required int? windowTokens,
  }) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _draggingFiles = true),
      onDragExited: (_) => setState(() => _draggingFiles = false),
      onDragDone: (details) async {
        setState(() => _draggingFiles = false);
        await _attachDropped(details.files);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: _buildMessageArea(
                      servers: servers,
                      mcpServers: mcpServers,
                      scheme: scheme,
                      compact: compact,
                    ),
                  ),
                ),
              ),
              _buildComposerDock(
                compact: compact,
                scheme: scheme,
                windowTokens: windowTokens,
              ),
            ],
          ),
          if (_draggingFiles)
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.08),
                  border: Border.all(color: scheme.primary, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Symbols.attach_file,
                        size: 32,
                        color: scheme.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'agentDropFilesToAttach'.tr(),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The log itself, held to the same insets as the composer's contents so the
  /// two columns of text line up.
  Widget _buildMessageArea({
    required List<Server> servers,
    required List<McpServer> mcpServers,
    required ColorScheme scheme,
    required bool compact,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 16 : 24, 0, compact ? 16 : 24, 0),
      child: Stack(
        children: [
          Positioned.fill(
            child: _buildMessageList(
              servers: servers,
              mcpServers: mcpServers,
              scheme: scheme,
            ),
          ),
          // Scroll-to-bottom affordance fades and scales in, as
          // Solian's back-to-bottom button does, instead of popping.
          Positioned(
            right: 12,
            bottom: 12,
            child: IgnorePointer(
              ignoring: !_showScrollToBottom,
              child: AnimatedOpacity(
                opacity: _showScrollToBottom ? 1 : 0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: AnimatedScale(
                  scale: _showScrollToBottom ? 1 : 0.8,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: FloatingActionButton.small(
                    heroTag: 'agent-scroll-to-bottom-${widget.tabId}',
                    tooltip: 'agentScrollToLatest'.tr(),
                    onPressed: _scrollToLatest,
                    child: const Icon(Symbols.arrow_downward),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The input end of the chat: the queued prompts and the composer, on the
  /// bar that closes the pane.
  ///
  /// The bar reaches both pane edges rather than floating as a card inside
  /// them, and keeps the log's own insets inside it, so the prompt sits where
  /// the messages above it do.
  ///
  /// The bar rests a step off the pane's own surface; once the list is
  /// scrolled back it takes the heavier fill and lifts off the messages, which
  /// is what tells a reader the composer is not part of the log. Solian's chat
  /// input does the same, and the 300ms ease keeps the change from reading as
  /// a blink.
  Widget _buildComposerDock({
    required bool compact,
    required ColorScheme scheme,
    required int? windowTokens,
  }) {
    final readingHistory = _showScrollToBottom;
    final gutter = compact ? 16.0 : 24.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: readingHistory
            ? scheme.surfaceContainerHighest
            : scheme.surfaceContainer,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
        boxShadow: [
          if (readingHistory)
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.2),
              blurRadius: 12,
              spreadRadius: 2,
              offset: const Offset(0, -4),
            ),
        ],
      ),
      // Ink has to land on the bar's surface rather than on the pane behind
      // it.
      child: Material(
        type: MaterialType.transparency,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                gutter,
                8,
                gutter,
                compact ? 16 : 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The panel keeps its slot while empty so its height animates
                  // in and out instead of the composer jumping.
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
                    child: _queuedPrompts.isEmpty
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildQueuedPrompts(scheme),
                          ),
                  ),
                  AgentComposer(
                    controller: _prompt,
                    focusNode: _promptFocus,
                    attachments: _attachments,
                    working: _working,
                    // A pending proposal owns the turn: its answer has to be run or
                    // declined before anything else can be sent.
                    enabled: _proposal == null,
                    onAttach: _attachFromPicker,
                    onAttachText: _attachText,
                    onEditAttachment: _editAttachment,
                    onRemoveAttachment: _removeAttachment,
                    onSubmit: _submitPrompt,
                    onStop: _interrupt,
                    status: _AgentContextStatus(
                      meter: _meter,
                      windowTokens: windowTokens,
                    ),
                    reasoning: _reasoning,
                    onReasoningChanged: _selectReasoning,
                  ),
                ],
              ),
            ),
          ),
        ),
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
            final attached = queued.attachments.length;
            return _QueuedPromptTile(
              text: queued.text.isEmpty
                  ? queued.attachments.firstOrNull?.name ??
                        'agentPastedText'.tr()
                  : queued.text,
              detail: attached == 0
                  ? 'agentQueuedMessage'.tr()
                  : '${'agentQueuedMessage'.tr()} · '
                        '${attached == 1 ? 'agentAttachmentOne'.tr() : 'agentAttachmentCount'.tr(args: ['$attached'])}',
              onSteer: () => _steerQueuedPrompt(index),
              onRemove: () => _removeQueuedPrompt(index),
            );
          },
        ),
      ),
    );
  }

  /// Re-counts what the prompt adds to the next request.
  ///
  /// Only the draft moves while typing, so the system prompt, the tool schemas
  /// and the history are counted once per turn and reused here; the meter is
  /// published on a notifier so the message list is never rebuilt for a count.
  void _publishMeter() {
    if (!mounted) return;
    final tokens =
        _staticTokens +
        _historyTokens +
        AgentTokenCounter.estimateMessage({
          'role': 'user',
          'content': agentUserContent(_prompt.text, _attachments),
        });
    if (tokens == _meter.value.tokens) return;
    _meter.value = _meter.value.copyWith(tokens: tokens);
  }

  /// Forgets the counts that the conversation context made stale.
  void _refreshHistoryTokens() {
    _historyTokens = AgentTokenCounter.estimateMessages(_agentContext);
    _publishMeter();
  }

  /// Counts the parts of a request that do not move while the prompt is
  /// written: the system prompt and tool schemas the call will send, and the
  /// history it will replay.
  void _measureLiveContext({
    required SshAgentService agent,
    required List<AgentServerTarget> servers,
    required List<AgentSnippetTarget> snippets,
    required List<AgentMcpToolTarget> mcpTools,
    required List<AgentSkillTarget> skills,
    required String? mcpUnavailable,
    required List<Map<String, dynamic>> history,
  }) {
    _staticTokens = agent.estimateStaticTokens(
      servers: servers,
      snippets: snippets,
      mcpTools: mcpTools,
      skills: skills,
      mcpUnavailable: mcpUnavailable,
    );
    _historyTokens = AgentTokenCounter.estimateMessages(history);
    _publishMeter();
  }

  /// Folds a finished call into the chat's totals. A provider's own numbers
  /// replace the estimate of the same call, so the meter goes back to being
  /// exact whenever one is reported.
  void _recordCall(AgentTurn turn) {
    _meter.value = _meter.value.record(turn.usage, turn.estimatedPromptTokens);
  }

  /// Drops the accounting with the conversation it described.
  void _resetUsage() {
    _staticTokens = 0;
    _historyTokens = 0;
    _meter.value = const AgentContextMeter();
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
      return _AgentEmptyState(
        ghost: _ghost,
        title: _ghost ? 'agentGhostTitle'.tr() : 'agentEmptyTitle'.tr(),
        hint: _ghost ? 'agentGhostHint'.tr() : 'agentEmptyHint'.tr(),
        // With nothing saved to run on, the opening prompt has to say what is
        // missing instead of letting the composer swallow the first message.
        notice: !_ghost && servers.isEmpty ? 'agentEmptyNoServers'.tr() : null,
        examples: _ghost
            ? const []
            : [
                'agentExampleDiagnose'.tr(),
                'agentExampleDisk'.tr(),
                'agentExampleSummarize'.tr(),
                'agentExampleFiles'.tr(),
              ],
        onExample: _useExample,
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        _setScrollToBottomVisibility(notification.metrics);
        return false;
      },
      child: ListView.separated(
        padding: const EdgeInsets.only(top: 16, bottom: 16),
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
          return _MessageCard(
            message: _messages[index],
            liveTool: index == _liveToolIndex
                ? _LiveToolControl(
                    interactive: _commandAcceptsInput,
                    prompting: _commandPrompting,
                    hasSavedPassword: _commandPassword != null,
                    onInput: _sendCommandInput,
                    onSendSavedPassword: _sendSavedPassword,
                    onStop: _stopActiveCommand,
                  )
                : null,
          );
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

  /// The user message as a request and the saved history carry it: the typed
  /// text plus whatever was attached to it, in the same shape the turn was
  /// sent with.
  static Map<String, dynamic> _userContextMessage(
    String text,
    List<AgentAttachment> attachments,
  ) => {'role': 'user', 'content': agentUserContent(text, attachments)};

  static List<Map<String, dynamic>> _contextFromMessages(
    List<_AgentMessage> messages,
  ) => [
    for (final message in messages)
      if (message.kind == _MessageKind.user)
        _userContextMessage(message.text, message.attachments)
      else
        _rawContextMessage(
          'assistant',
          message.kind == _MessageKind.tool
              ? 'Tool result from an earlier action:\n${message.text}'
              : message.text,
        ),
  ];

  static String _conversationTitle(List<_AgentMessage> messages) {
    final firstUser = messages
        .where((message) => message.kind == _MessageKind.user)
        .firstOrNull;
    final typed = firstUser?.text ?? '';
    // A turn that was nothing but an attachment is titled by the file it sent,
    // which is the only thing about it worth reading in a list.
    final text =
        (typed.trim().isEmpty
                ? firstUser?.attachments.firstOrNull?.name ??
                      'agentDefaultConversationTitle'.tr()
                : typed)
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    return text.length <= 48 ? text : '${text.substring(0, 48)}…';
  }
}

class _AgentMessage {
  const _AgentMessage(
    this.text,
    this.kind, {
    required this.autoApproved,
    this.attachments = const [],
    this.live = false,
  });
  const _AgentMessage.user(
    String text, {
    List<AgentAttachment> attachments = const [],
  }) : this(
         text,
         _MessageKind.user,
         autoApproved: false,
         attachments: attachments,
       );
  const _AgentMessage.assistant(String text)
    : this(text, _MessageKind.assistant, autoApproved: false);
  const _AgentMessage.tool(
    String text, {
    bool autoApproved = false,
    bool live = false,
  }) : this(text, _MessageKind.tool, autoApproved: autoApproved, live: live);
  final String text;
  final _MessageKind kind;
  final bool autoApproved;

  /// Whether this tool call is still running and appending to [text], which
  /// makes its card show the live output with the stop and input controls.
  final bool live;

  /// What the turn was sent with. Only a user turn has any.
  final List<AgentAttachment> attachments;

  _AgentMessage copyWith({String? text, bool? live}) => _AgentMessage(
    text ?? this.text,
    kind,
    autoApproved: autoApproved,
    attachments: attachments,
    live: live ?? this.live,
  );
}

class _QueuedPrompt {
  const _QueuedPrompt(this.text, this.attachments);

  final String text;
  final List<AgentAttachment> attachments;
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
    required this.onFetchModels,
    required this.onSave,
  });
  final AgentProvider? existing;
  final Future<List<String>> Function(String apiKey, String baseUrl)
  onFetchModels;
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
  var _models = <String>[];
  var _fetchingModels = false;
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
      if (_key.text.trim().isNotEmpty && _models.isEmpty) {
        await _fetchModels(showError: false);
      }
      await widget.onSave(
        AgentProviderDraft(
          name: _name.text,
          apiKey: _key.text,
          baseUrl: _endpoint.text,
          model: _model.text,
          models: _models,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _fetchModels({bool showError = true}) async {
    if (_fetchingModels) return;
    setState(() => _fetchingModels = true);
    try {
      final models = await widget.onFetchModels(_key.text, _endpoint.text);
      if (!mounted) return;
      setState(() {
        _models = models;
        if (!models.contains(_model.text)) _model.text = models.first;
      });
    } catch (error) {
      if (showError) {
        showMaidKitErrorAlert(error, title: 'agentCouldNotFetchModels'.tr());
      }
    } finally {
      if (mounted) setState(() => _fetchingModels = false);
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
              _models = [];
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
        OutlinedButton.icon(
          onPressed: _fetchingModels ? null : _fetchModels,
          icon: _fetchingModels
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Symbols.refresh),
          label: Text('agentFetchModels'.tr()),
        ),
        if (_models.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _models.contains(_model.text) ? _model.text : null,
            decoration: InputDecoration(
              labelText: 'agentDiscoveredModels'.tr(),
            ),
            items: [
              for (final model in _models)
                DropdownMenuItem(value: model, child: Text(model)),
            ],
            onChanged: (model) {
              if (model != null) _model.text = model;
            },
          ),
        ],
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
  const _MessageCard({required this.message, this.liveTool});
  final _AgentMessage message;

  /// Controls for a tool card that is still running. Non-null only for the
  /// message of the action currently executing.
  final _LiveToolControl? liveTool;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (message.kind == _MessageKind.tool) {
      final live = liveTool;
      return Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: message.live && live != null
              ? _LiveToolCard(
                  text: message.text,
                  autoApproved: message.autoApproved,
                  control: live,
                )
              : _ToolCallCard(
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
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.attachments.isNotEmpty) ...[
                    AgentAttachmentChips(attachments: message.attachments),
                    if (message.text.isNotEmpty) const SizedBox(height: 6),
                  ],
                  if (message.text.isNotEmpty) SelectableText(message.text),
                ],
              ),
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

/// What the live tool card needs from the chat that owns the running command.
class _LiveToolControl {
  const _LiveToolControl({
    required this.interactive,
    required this.prompting,
    required this.hasSavedPassword,
    required this.onInput,
    required this.onSendSavedPassword,
    required this.onStop,
  });

  /// Whether the running action can take typed input at all. A snippet reads
  /// its script from stdin, so it never can.
  final bool interactive;

  /// Whether the remote currently shows a prompt worth answering.
  final bool prompting;

  /// Whether the target server has a saved password worth offering.
  final bool hasSavedPassword;

  final ValueChanged<String> onInput;
  final VoidCallback onSendSavedPassword;
  final VoidCallback onStop;
}

/// The card of a tool call that is still running: output streams in as the
/// process writes it, and the running command can be answered or stopped
/// without cancelling the turn that asked for it.
class _LiveToolCard extends StatefulWidget {
  const _LiveToolCard({
    required this.text,
    required this.autoApproved,
    required this.control,
  });

  final String text;
  final bool autoApproved;
  final _LiveToolControl control;

  @override
  State<_LiveToolCard> createState() => _LiveToolCardState();
}

class _LiveToolCardState extends State<_LiveToolCard> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    widget.control.onInput(text);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final separator = widget.text.indexOf('\n');
    final title = separator < 0
        ? widget.text
        : widget.text
              .substring(0, separator)
              .replaceFirst(RegExp(r':\s*$'), '');
    final content = separator < 0 ? '' : widget.text.substring(separator + 1);
    final control = widget.control;
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
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            child: Row(
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
                if (widget.autoApproved) ...[
                  const SizedBox(width: 8),
                  const _AutoApprovedBadge(),
                ],
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'agentStopCommand'.tr(),
                  onPressed: control.onStop,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Symbols.stop, size: 18),
                ),
              ],
            ),
          ),
          if (content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              // MaidTerm renders what a PTY actually emitted: progress lines
              // rewrite in place and colors survive, instead of the raw
              // carriage returns landing in a text block.
              child: SizedBox(
                height: 180,
                child: AnsiLogView(
                  text: content,
                  streaming: true,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          if (control.interactive)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (control.prompting) ...[
                    Row(
                      children: [
                        Icon(
                          Symbols.password,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'agentCommandWaitingInput'.tr(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (control.hasSavedPassword)
                          TextButton.icon(
                            onPressed: control.onSendSavedPassword,
                            icon: const Icon(Symbols.key, size: 16),
                            label: Text('agentSendSavedPassword'.tr()),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          focusNode: _inputFocus,
                          onSubmitted: (_) => _submit(),
                          style: TextStyle(
                            fontFamily: MaidKitFonts.mono,
                            fontSize: 12,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            border: const OutlineInputBorder(),
                            hintText: 'agentCommandInputHint'.tr(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: 'agentSendCommandInput'.tr(),
                        onPressed: _submit,
                        icon: const Icon(Symbols.send, size: 18),
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

class _AutoApprovedBadge extends StatelessWidget {
  const _AutoApprovedBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
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
            const _AutoApprovedBadge(),
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

/// What a chat shows before its first message: what the agent can do, and
/// prompts that are close enough to a real task to edit rather than replace.
class _AgentEmptyState extends StatelessWidget {
  const _AgentEmptyState({
    required this.ghost,
    required this.title,
    required this.hint,
    required this.examples,
    required this.onExample,
    this.notice,
  });

  /// Ghost chats are never saved, so they cannot offer the same examples.
  final bool ghost;
  final String title;
  final String hint;

  /// A blocking prerequisite (no servers yet) rendered below the hint.
  final String? notice;

  final List<String> examples;
  final ValueChanged<String> onExample;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                ghost ? Symbols.visibility_off : Symbols.smart_toy,
                size: 40,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (notice case final notice?) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Symbols.info, size: 16, color: scheme.tertiary),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          notice,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (examples.isNotEmpty) ...[
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final example in examples)
                      ActionChip(
                        label: Text(example),
                        onPressed: () => onExample(example),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One queued prompt. It fades and rises into place as it is queued; taking it
/// out again is left to the panel's own size animation, which closes the gap.
class _QueuedPromptTile extends StatefulWidget {
  const _QueuedPromptTile({
    required this.text,
    required this.detail,
    required this.onSteer,
    required this.onRemove,
  });

  final String text;

  /// The line under the prompt: that it is queued, and what rides with it.
  final String detail;

  final VoidCallback onSteer;
  final VoidCallback onRemove;

  @override
  State<_QueuedPromptTile> createState() => _QueuedPromptTileState();
}

class _QueuedPromptTileState extends State<_QueuedPromptTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  late final Animation<double> _entrance = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _entrance,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.12),
          end: Offset.zero,
        ).animate(_entrance),
        child: ListTile(
          dense: true,
          leading: const Icon(Symbols.schedule, size: 20),
          title: Text(
            widget.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(widget.detail),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'agentSteerMessage'.tr(),
                onPressed: widget.onSteer,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Symbols.arrow_upward, size: 18),
              ),
              IconButton(
                tooltip: 'agentRemoveQueuedMessage'.tr(),
                onPressed: widget.onRemove,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Symbols.close, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The chat's memory gauge, after Persynth's: a ring for the share of the
/// model's window the next request fills, then the numbers behind it. Quiet at
/// rest; the ring warms to the accent as the window fills and to the error tone
/// at its end. An unknown ceiling leaves the ring out rather than inventing a
/// window to divide by, and the count wears a `~` because no provider hands the
/// chat an exact count before a turn runs.
class _AgentContextStatus extends StatelessWidget {
  const _AgentContextStatus({required this.meter, required this.windowTokens});

  final ValueListenable<AgentContextMeter> meter;

  /// The selected model's ceiling in tokens, or null when it is not known.
  final int? windowTokens;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return ValueListenableBuilder<AgentContextMeter>(
      valueListenable: meter,
      builder: (context, usage, _) {
        if (usage.isEmpty) return const SizedBox.shrink();
        final window = windowTokens ?? 0;
        return Tooltip(
          message: _tooltip(usage, window),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (window > 0) ...[
                _ContextRing(ratio: usage.tokens / window),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  _label(usage, window),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// `~12.4k / 128k · 34.2k tok · 5 runs`.
  String _label(AgentContextMeter usage, int window) {
    final count = _count(usage.tokens);
    final parts = <String>[
      if (window > 0)
        '$count / ${AgentTokenCounter.format(window)}'
      else
        'agentContextShort'.tr(args: [count]),
      if (usage.totalTokens > 0)
        'agentTokensShort'.tr(
          args: [AgentTokenCounter.format(usage.totalTokens)],
        ),
      if (usage.runs > 0) _runs(usage.runs),
    ];
    return parts.join(' · ');
  }

  /// The full sentence behind the meter, for the pointer that hovers it.
  String _tooltip(AgentContextMeter usage, int window) {
    final count = _count(usage.tokens);
    final parts = <String>[
      if (window > 0)
        'agentContextTooltipWindow'.tr(
          args: [
            count,
            AgentTokenCounter.format(window),
            AgentTokenCounter.formatPercent(usage.tokens / window),
          ],
        )
      else
        'agentContextTooltipUsed'.tr(args: [count]),
      if (usage.totalTokens > 0)
        'agentContextTooltipTotal'.tr(
          args: [AgentTokenCounter.format(usage.totalTokens)],
        ),
      if (usage.peakTokens > usage.tokens)
        'agentContextTooltipPeak'.tr(
          args: [AgentTokenCounter.format(usage.peakTokens)],
        ),
      if (usage.runs > 0) _runs(usage.runs),
      'agentContextTooltipCounted'.tr(),
      if (usage.estimatedTotals) 'agentContextTooltipEstimatedTotals'.tr(),
    ];
    return parts.join('\n');
  }

  String _count(int tokens) => '~${AgentTokenCounter.format(tokens)}';

  String _runs(int runs) => runs == 1
      ? 'agentRunsShortOne'.tr()
      : 'agentRunsShort'.tr(args: ['$runs']);
}

/// The meter's ring: a full track with the filled share swept from the top
/// clockwise, so a nearly empty window still reads as a ring rather than a dot.
class _ContextRing extends StatelessWidget {
  const _ContextRing({required this.ratio});

  final double ratio;

  /// Big enough to read a share off, small enough to sit on a one-line footer.
  static const _diameter = 20.0;
  static const _stroke = 2.4;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = switch (ratio.clamp(0.0, 1.0)) {
      >= 0.95 => scheme.error,
      >= 0.8 => scheme.primary,
      _ => scheme.onSurfaceVariant,
    };
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SizedBox.square(
      dimension: _diameter,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: ratio.clamp(0.0, 1.0)),
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) => CustomPaint(
          painter: _ContextRingPainter(
            value: value,
            // The composer's surface is a hairline tone away from
            // `outlineVariant`, so the track is the fill's colour thinned until
            // it reads as a ring rather than a hole.
            track: scheme.onSurfaceVariant.withValues(alpha: 0.28),
            fill: fill,
            stroke: _stroke,
          ),
        ),
      ),
    );
  }
}

class _ContextRingPainter extends CustomPainter {
  const _ContextRingPainter({
    required this.value,
    required this.track,
    required this.fill,
    required this.stroke,
  });

  /// The share of the window to sweep, 0…1.
  final double value;
  final Color track;
  final Color fill;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    if (value <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = fill,
    );
  }

  @override
  bool shouldRepaint(_ContextRingPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.track != track ||
      oldDelegate.fill != fill ||
      oldDelegate.stroke != stroke;
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
      TabController(length: kIsWeb ? 1 : 2, vsync: this)..addListener(() {
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
        // MCP server management needs child-process spawning, unavailable in a
        // browser, so the MCP tab is hidden there.
        if (!kIsWeb && _tabIndex == 0) ...[
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
              if (!kIsWeb) Tab(text: 'agentMcpServers'.tr()),
              Tab(text: 'agentSkills'.tr()),
            ],
          ),
          Expanded(
            child: !kIsWeb && _tabIndex == 0
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
