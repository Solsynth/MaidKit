import 'package:flutter/foundation.dart';

import '../foundation/cell_range.dart';
import 'activation_modifier.dart';

/// Data reported when a terminal link is activated.
@immutable
final class ActivatedLink {
  /// Source category that produced the link.
  final LinkType type;

  /// Stable identifier for custom links.
  ///
  /// Built-in link types leave this null. Custom regex rules use
  /// [LinkRule.id] so activation callbacks can route matches without
  /// inspecting the matched text.
  final String? id;

  /// Text covered by the activated link.
  final String text;

  /// Parsed URI for OSC 8 and URI-like text links.
  final Uri? uri;

  /// Parsed file data for path-like text links.
  final LinkedFile? file;

  /// Terminal cells covered by the link.
  final CellRange range;

  /// Capture groups for a custom regex rule.
  ///
  /// Entries are nullable because Dart reports an unmatched optional capture
  /// group as `null`.
  final List<String?> captureGroups;

  const ActivatedLink({
    required this.type,
    required this.text,
    required this.range,
    this.id,
    this.uri,
    this.file,
    this.captureGroups = const [],
  });

  @override
  int get hashCode => Object.hash(
    type,
    id,
    text,
    uri,
    file,
    range,
    Object.hashAll(captureGroups),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivatedLink &&
          type == other.type &&
          id == other.id &&
          text == other.text &&
          uri == other.uri &&
          file == other.file &&
          range == other.range &&
          listEquals(captureGroups, other.captureGroups);
}

/// Parsed file path data from a detected link.
@immutable
final class LinkedFile {
  /// Path text without a trailing line or column suffix.
  final String path;

  /// Optional 1-based line number parsed from the match.
  final int? line;

  /// Optional 1-based column number parsed from the match.
  final int? column;

  /// Current working directory used to resolve [path], when one was reported.
  final String? cwd;

  /// Absolute path resolved from [cwd] for relative paths.
  final String? resolvedPath;

  const LinkedFile({
    required this.path,
    this.line,
    this.column,
    this.cwd,
    this.resolvedPath,
  });

  @override
  int get hashCode => Object.hash(path, line, column, cwd, resolvedPath);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkedFile &&
          path == other.path &&
          line == other.line &&
          column == other.column &&
          cwd == other.cwd &&
          resolvedPath == other.resolvedPath;
}

/// Determines when a link rule contributes visible link styling.
enum LinkHighlightMode {
  /// Highlights matching text whenever it is visible.
  ///
  /// This participates in idle link snapshots. Avoid it for high-throughput
  /// terminal output unless the content is mostly static. Use [hover] for the
  /// best throughput.
  always,

  /// Highlights matching text only when it is under the pointer and the
  /// activation modifier is satisfied.
  hover,
}

/// A custom regex rule that turns matching terminal text into a link.
@immutable
final class LinkRule {
  /// Stable identifier reported through [ActivatedLink.id].
  final String id;

  /// Pattern matched against visible logical terminal lines.
  ///
  /// Capture groups are reported through
  /// [ActivatedLink.captureGroups].
  final RegExp pattern;

  /// Higher values win when this rule overlaps another detected link.
  final int priority;

  /// When matching ranges should be visibly styled.
  ///
  /// See [LinkHighlightMode.always] for the performance tradeoff of visible
  /// idle styling.
  final LinkHighlightMode highlightMode;

  const factory LinkRule.regex({
    required String id,
    required RegExp pattern,
    int priority,
    LinkHighlightMode highlightMode,
  }) = LinkRule._regex;

  const LinkRule._regex({
    required this.id,
    required this.pattern,
    this.priority = 0,
    this.highlightMode = .hover,
  });

  @override
  int get hashCode => Object.hash(
    id,
    pattern.pattern,
    pattern.isCaseSensitive,
    pattern.isMultiLine,
    pattern.isUnicode,
    pattern.isDotAll,
    priority,
    highlightMode,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkRule &&
          id == other.id &&
          pattern.pattern == other.pattern.pattern &&
          pattern.isCaseSensitive == other.pattern.isCaseSensitive &&
          pattern.isMultiLine == other.pattern.isMultiLine &&
          pattern.isUnicode == other.pattern.isUnicode &&
          pattern.isDotAll == other.pattern.isDotAll &&
          priority == other.priority &&
          highlightMode == other.highlightMode;
}

/// Link detection, styling, and pointer handling configuration.
@immutable
final class LinkSettings {
  /// Link categories that can be detected, styled, and activated.
  ///
  /// All link categories are enabled by default. Use an empty set to disable
  /// link detection.
  ///
  /// ```dart
  /// const links = LinkSettings(types: {.osc8, .text});
  /// ```
  final Set<LinkType> types;

  /// Modifier required for pointer activation.
  final ActivationModifier modifier;

  /// Custom regex rules applied to visible terminal text.
  ///
  /// Rules that use [LinkHighlightMode.always] can be expensive with
  /// high-throughput output because visible lines must be scanned after
  /// content changes.
  final List<LinkRule> rules;

  /// Called when the user activates a detected link.
  final ValueChanged<ActivatedLink>? onActivate;

  const LinkSettings({
    this.types = const {.osc8, .text, .custom},
    this.modifier = .primary,
    this.rules = const [],
    this.onActivate,
  });

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(types),
    modifier,
    Object.hashAll(rules),
    onActivate,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkSettings &&
          setEquals(types, other.types) &&
          modifier == other.modifier &&
          listEquals(rules, other.rules) &&
          onActivate == other.onActivate;
}

/// Source category for detected links.
enum LinkType {
  /// Explicit OSC 8 hyperlink metadata attached to terminal cells.
  osc8,

  /// Built-in URL, URI, and file path detection from visible terminal text.
  text,

  /// Application-defined [LinkRule] matches.
  custom,
}
