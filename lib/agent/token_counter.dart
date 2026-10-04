import 'dart:convert';

import 'package:material_ui/material_ui.dart';

/// Token accounting for the agent chat.
///
/// Nothing here tokenizes. The providers this app talks to hand back usage only
/// after a turn, and none of them ship a tokenizer to run on the client, so the
/// meter counts the text a request will carry with a character-based estimate
/// and lets a provider's own numbers replace it whenever a turn reports them.
/// The formatting and the window rules follow Persynth's context meter: counts
/// short enough for one line (`12.4k`), a share that stays precise while it is
/// small, and an unknown model ceiling left out rather than guessed.
///
/// The estimate is deliberately simple: characters that tokenize roughly one
/// apiece (CJK and friends) count one each, everything else counts one per
/// [_latinCharsPerToken]. BPE tokenizers land near that for prose and code, so
/// the meter is close enough to warn before a window fills — which is all a
/// client-side count can honestly claim.
abstract final class AgentTokenCounter {
  /// Latin-script characters that share a token. English prose runs about four
  /// to a token and source code a little tighter; four keeps the number from
  /// overstating the window.
  static const int latinCharsPerToken = 4;

  /// What one chat message costs beyond its text: the role and the delimiters
  /// the API wraps around it.
  static const int messageOverhead = 4;

  /// What one tool schema costs beyond its JSON: the envelope around it.
  static const int toolOverhead = 8;

  /// Estimated tokens in [text], or `0` for nothing.
  static int estimate(String? text) {
    if (text == null || text.isEmpty) return 0;
    var dense = 0;
    var latin = 0;
    for (final rune in text.runes) {
      if (_isDenseScript(rune)) {
        dense++;
      } else {
        latin++;
      }
    }
    return dense + (latin + latinCharsPerToken - 1) ~/ latinCharsPerToken;
  }

  /// Estimated tokens in one OpenAI-style chat message, its text, its tool
  /// calls and its overhead.
  static int estimateMessage(Map<String, dynamic> message) {
    var tokens = messageOverhead;
    final content = message['content'];
    if (content is String) {
      tokens += estimate(content);
    } else if (content is List) {
      // Multimodal content: the parts this app sends are text. Image parts are
      // billed by pixels, which no character count can see.
      for (final part in content) {
        if (part is Map) {
          final text = part['text'];
          if (text is String) tokens += estimate(text);
        }
      }
    }
    final name = message['name'];
    if (name is String) tokens += estimate(name);
    final calls = message['tool_calls'];
    if (calls is List) {
      for (final call in calls) {
        if (call is Map) tokens += estimate(jsonEncode(call));
      }
    }
    return tokens;
  }

  /// Estimated tokens in a whole message list.
  static int estimateMessages(Iterable<Map<String, dynamic>> messages) {
    var tokens = 0;
    for (final message in messages) {
      tokens += estimateMessage(message);
    }
    return tokens;
  }

  /// Estimated tokens in the tool schemas a request advertises.
  static int estimateTools(Iterable<Map<String, dynamic>> tools) {
    var tokens = 0;
    for (final tool in tools) {
      tokens += toolOverhead + estimate(jsonEncode(tool));
    }
    return tokens;
  }

  /// A count short enough for a one-line footer: `512`, `12.4k`, `57.5k`,
  /// `128k`, `1.2M`. A tenth is kept while it still says something.
  static String format(int value) {
    if (value < 1000) return '$value';
    final thousands = value / 1000;
    if (thousands < 1000) return _scaled(thousands, 'k');
    return _scaled(value / 1000000, 'M');
  }

  /// A share of the context window: precise while it is small, coarse once it
  /// is not.
  static String formatPercent(double ratio) {
    final percent = ratio * 100;
    if (percent < 1) return '${percent.toStringAsFixed(2)}%';
    if (percent < 10) return '${percent.toStringAsFixed(1)}%';
    return '${percent.toStringAsFixed(0)}%';
  }

  /// `12.43` with `k` is `12.4k`; `1.0` is just `1k`.
  static String _scaled(double value, String suffix) {
    final text = value.toStringAsFixed(value < 100 ? 1 : 0);
    final trimmed = text.endsWith('.0')
        ? text.substring(0, text.length - 2)
        : text;
    return '$trimmed$suffix';
  }

  /// The context window of [model], or null when it is not known.
  ///
  /// Only models whose ceiling is a matter of record are listed, and the
  /// longest name wins so `gpt-4o-mini` is not answered by `gpt-4o`. An
  /// unrecognised model, a local build, or a name invented by a provider gets
  /// null: the meter then shows what the request costs without inventing a
  /// ceiling to divide it by.
  static int? contextWindow(String? model) {
    if (model == null) return null;
    // `openai/gpt-4o` (OpenRouter) and `llama3.2:latest` (Ollama) name the same
    // model as the bare id.
    final leaf = model
        .toLowerCase()
        .trim()
        .split('/')
        .last
        .split(':')
        .first
        .trim();
    if (leaf.isEmpty) return null;
    int? window;
    var matched = 0;
    _contextWindows.forEach((key, tokens) {
      if (key.length > matched && leaf.startsWith(key)) {
        window = tokens;
        matched = key.length;
      }
    });
    return window;
  }

  /// Ceilings in tokens, keyed by the substring that identifies the model.
  static const Map<String, int> _contextWindows = {
    // OpenAI
    'gpt-4.1-mini': 1047576,
    'gpt-4.1-nano': 1047576,
    'gpt-4.1': 1047576,
    'gpt-4o-mini': 128000,
    'gpt-4o': 128000,
    'gpt-4-turbo': 128000,
    'gpt-4-32k': 32768,
    'gpt-4': 8192,
    'gpt-3.5-turbo': 16385,
    'o4-mini': 200000,
    'o3-mini': 200000,
    'o3': 200000,
    'o1-mini': 128000,
    'o1': 200000,
    // Anthropic
    'claude-3-5': 200000,
    'claude-3-7': 200000,
    'claude-sonnet-4': 200000,
    'claude-opus-4': 200000,
    'claude-haiku-4': 200000,
    // DeepSeek
    'deepseek-reasoner': 65536,
    'deepseek-chat': 65536,
    'deepseek-r1': 65536,
    // Local builds
    'llama3.2': 131072,
    'llama3.1': 131072,
    'qwen2.5-coder': 32768,
    'qwen2.5': 32768,
    'mistral': 32768,
    'gemma2': 8192,
  };

  /// Whether [rune] belongs to a script that tokenizes at roughly one token per
  /// character: CJK ideographs, kana, hangul, and their punctuation.
  static bool _isDenseScript(int rune) =>
      (rune >= 0x3000 && rune <= 0x303F) || // CJK punctuation
      (rune >= 0x3040 && rune <= 0x30FF) || // kana
      (rune >= 0x3400 && rune <= 0x4DBF) || // CJK extension A
      (rune >= 0x4E00 && rune <= 0x9FFF) || // CJK unified ideographs
      (rune >= 0xAC00 && rune <= 0xD7AF) || // hangul syllables
      (rune >= 0xF900 && rune <= 0xFAFF) || // CJK compatibility ideographs
      (rune >= 0xFF00 && rune <= 0xFFEF) || // fullwidth forms
      (rune >= 0x20000 && rune <= 0x2FA1F); // CJK extensions B onwards
}

/// What one model call reported about itself, when it reported anything.
@immutable
class AgentTurnUsage {
  const AgentTurnUsage({
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
  });

  /// The prompt the call sent: the size the model's context was actually
  /// filled with.
  final int inputTokens;
  final int outputTokens;
  final int totalTokens;

  /// Reads a response's `usage` bag, or returns null when there is none: a
  /// provider that reports nothing must not be read as a call that spent zero.
  static AgentTurnUsage? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final input = _count(raw['prompt_tokens'] ?? raw['input_tokens']);
    final output = _count(raw['completion_tokens'] ?? raw['output_tokens']);
    final total = _count(raw['total_tokens']);
    if (input == 0 && output == 0 && total == 0) return null;
    return AgentTurnUsage(
      inputTokens: input,
      outputTokens: output,
      totalTokens: total == 0 ? input + output : total,
    );
  }

  static int _count(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }
}

/// The numbers behind the context meter: how full the next request is, the
/// fullest one this conversation has sent, and what the conversation has spent
/// in total.
@immutable
class AgentContextMeter {
  const AgentContextMeter({
    this.tokens = 0,
    this.peakTokens = 0,
    this.totalTokens = 0,
    this.runs = 0,
    this.estimatedTotals = false,
  });

  /// Tokens the next request will carry. Counted from the request itself while
  /// the draft is being written, and replaced by the provider's own count once
  /// a turn reports one.
  final int tokens;

  /// The fullest single request this conversation has sent.
  final int peakTokens;

  /// Every token the conversation has spent, prompts and answers together.
  final int totalTokens;

  /// Model calls made. A turn that calls tools makes one per round.
  final int runs;

  /// Whether any of the calls behind [peakTokens] and [totalTokens] was counted
  /// instead of reported, which makes those totals an estimate too. [tokens] is
  /// always the counter's number for the next request, so the meter marks it as
  /// an estimate unconditionally.
  final bool estimatedTotals;

  /// Whether there is anything worth showing: an untouched chat counts the
  /// draft's own message overhead and nothing else.
  bool get isEmpty =>
      peakTokens == 0 &&
      totalTokens == 0 &&
      tokens <= AgentTokenCounter.messageOverhead;

  AgentContextMeter copyWith({
    int? tokens,
    int? peakTokens,
    int? totalTokens,
    int? runs,
    bool? estimatedTotals,
  }) => AgentContextMeter(
    tokens: tokens ?? this.tokens,
    peakTokens: peakTokens ?? this.peakTokens,
    totalTokens: totalTokens ?? this.totalTokens,
    runs: runs ?? this.runs,
    estimatedTotals: estimatedTotals ?? this.estimatedTotals,
  );

  /// Folds one finished call into the running totals. [reported] is the
  /// provider's own accounting: when it is there it replaces the estimate of
  /// the same call, and the call stops counting as estimated.
  AgentContextMeter record(AgentTurnUsage? reported, int estimateOfCall) {
    final prompt = reported?.inputTokens ?? estimateOfCall;
    final spent = reported?.totalTokens ?? estimateOfCall;
    return copyWith(
      tokens: prompt,
      peakTokens: prompt > peakTokens ? prompt : peakTokens,
      totalTokens: totalTokens + spent,
      runs: runs + 1,
      estimatedTotals: estimatedTotals || reported == null,
    );
  }
}
