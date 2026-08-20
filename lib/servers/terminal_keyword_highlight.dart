import 'package:flutter/material.dart';

/// Keyword categories highlighted in terminal output, MobaXterm-style.
enum TerminalKeywordCategory {
  /// Hard failures: error, fail, denied, refused, corrupt, ...
  error,

  /// Recoverable problems: warn, warning, cannot, timeout, not found, ...
  warning,

  /// Positive outcomes: success, ok, accepted, connected, enabled, ...
  success,

  /// http/https network links.
  url,

  /// IPv4 and IPv6 addresses.
  ip,
}

/// A single keyword-highlight rule.
///
/// [pattern] is matched against each terminal line (case-insensitive). [color]
/// is the background tint applied by renderers that support per-span overlays
/// (xterm). Renderers without per-color overlays (Ghostty) reuse [pattern] as a
/// link rule and apply their own single underline style.
class TerminalKeywordHighlightRule {
  const TerminalKeywordHighlightRule({
    required this.category,
    required this.pattern,
    required this.color,
  });

  final TerminalKeywordCategory category;
  final RegExp pattern;

  /// Semi-transparent background tint so the original ANSI foreground color of
  /// the matched cell stays readable (never overrides server colors).
  final Color color;
}

/// MobaXterm-style keyword rules.
///
/// Patterns are word-anchored and case-insensitive. The colors are background
/// tints (alpha ~0x44) used by the xterm renderer; the Ghostty renderer applies
/// these same patterns as underline link rules.
final List<TerminalKeywordHighlightRule> terminalKeywordRules = [
  TerminalKeywordHighlightRule(
    category: TerminalKeywordCategory.error,
    pattern: RegExp(
      r'\b(error|failed?|failure|denied|refused|invalid|corrupt|permission '
      r'denied|segment fault|does not exist|bad|wrong)\b',
      caseSensitive: false,
    ),
    color: Color(0x44FF5252),
  ),
  TerminalKeywordHighlightRule(
    category: TerminalKeywordCategory.warning,
    pattern: RegExp(
      r'\b(warn|warning|cannot|unexpected|timeout|out of memory|low disk|'
      r'discarded|not found)\b',
      caseSensitive: false,
    ),
    color: Color(0x44FFD740),
  ),
  TerminalKeywordHighlightRule(
    category: TerminalKeywordCategory.success,
    pattern: RegExp(
      r'\b(success|succeeded|ok|pass|accepted|connected|enabled)\b',
      caseSensitive: false,
    ),
    color: Color(0x4425C26E),
  ),
  TerminalKeywordHighlightRule(
    category: TerminalKeywordCategory.url,
    pattern: RegExp(
      r'\bhttps?://[^\s<>)\]}]+',
      caseSensitive: false,
    ),
    color: Color(0x444DFFFF),
  ),
  TerminalKeywordHighlightRule(
    category: TerminalKeywordCategory.ip,
    pattern: RegExp(
      r'(?<![A-Za-z0-9.])(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}'
      r'(?:25[0-5]|2[0-4]\d|1?\d?\d)(?![A-Za-z0-9.])'
      r'|(?<![A-Za-z0-9:])(?:[A-Fa-f0-9]{1,4}:){2,7}[A-Fa-f0-9]{1,4}'
      r'(?![A-Za-z0-9:])',
      caseSensitive: false,
    ),
    color: Color(0x44E040FB),
  ),
];
