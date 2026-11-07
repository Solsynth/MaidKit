import 'package:flutter/foundation.dart';

/// What a resource named with `@` in a prompt is: a server the agent may act
/// on, a saved snippet it may run, or a skill it may consult.
enum AgentMentionKind { server, snippet, skill }

/// One resource the composer can offer after an `@`, and one the reader picked.
///
/// A mention is not just decoration in the prompt: it rides with the turn the
/// way an attachment does, so the request names the exact row — `server #3`,
/// `snippet #12`, `skill #4` — instead of leaving the model to guess which of
/// the listed resources the sentence meant. Picked mentions are saved with the
/// conversation, so reopening it rebuilds the request it was sent with.
@immutable
class AgentMention {
  const AgentMention({
    required this.kind,
    required this.id,
    required this.name,
    this.detail = '',
  });

  final AgentMentionKind kind;
  final int id;
  final String name;

  /// The second line the menu and the request carry: the account and host of a
  /// server, a skill's one-line summary. Empty when the name says it all.
  final String detail;

  /// What the reader types: the picker writes the name, not the id, so the
  /// sentence stays readable. A name with spaces is written with underscores —
  /// a token has to be one word for the menu to find its end — which keeps
  /// `@Build_host` readable while the chip still shows the real name.
  String get token => '@${name.trim().replaceAll(RegExp(r'\s+'), '_')}';

  /// The line the turn carries for this resource, in the vocabulary of the
  /// system prompt's own lists.
  String get referenceLine {
    final base = '${kind.name} #$id: $name';
    return detail.isEmpty ? base : '$base ($detail)';
  }

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'id': id,
    'name': name,
    if (detail.isNotEmpty) 'detail': detail,
  };

  factory AgentMention.fromJson(Map<String, dynamic> json) => AgentMention(
    kind:
        AgentMentionKind.values.asNameMap()[json['kind'] as String? ?? ''] ??
        AgentMentionKind.server,
    id: json['id'] as int? ?? 0,
    name: json['name'] as String? ?? '',
    detail: json['detail'] as String? ?? '',
  );

  @override
  bool operator ==(Object other) =>
      other is AgentMention && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

/// Whether [mention]'s token still stands in [text] as a whole name, so a
/// mention the reader deleted stops riding the turn and one they retyped
/// starts again.
bool agentMentionPresent(String text, AgentMention mention) {
  final token = mention.token;
  var index = text.indexOf(token);
  while (index >= 0) {
    final end = index + token.length;
    if (end == text.length || !_isNameCharacter(text[end])) return true;
    index = text.indexOf(token, index + 1);
  }
  return false;
}

bool _isNameCharacter(String character) =>
    RegExp(r'[A-Za-z0-9_]').hasMatch(character);

/// The block [agentUserContent] appends to a turn that named resources, so the
/// model knows which row each `@name` meant. Empty when no mention rides it.
String agentMentionReferenceBlock(List<AgentMention> mentions) {
  if (mentions.isEmpty) return '';
  return [
    '--- Referenced resources (named by the user with @) ---',
    for (final mention in mentions) '- ${mention.referenceLine}',
    '--- End of referenced resources ---',
  ].join('\n');
}
