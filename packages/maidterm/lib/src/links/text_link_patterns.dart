// Raw strings keep the regular expression fragments readable.
// ignore_for_file: unnecessary_raw_strings

import 'package:flutter/foundation.dart' show internal;

/// Built-in URL, URI, and file path patterns used by [TextLinkDetector].
///
/// We keep these patterns close to Ghostty's URL and path matching behavior
/// where that behavior maps cleanly to Dart regular expressions.
@internal
abstract final class TextLinkPatterns {
  /// Maximum logical-line length scanned by built-in and custom regex rules.
  static const maxLineLength = 8192;

  /// Maximum matches accepted from one logical line for each detector pass.
  static const maxMatchesPerLine = 256;

  /// Pattern for URLs, URIs, POSIX paths, Windows paths, and `.` or `..`.
  static final link = RegExp(_source);

  static const _urlSchemes =
      r'https?://|mailto:|ftp://|file:|ssh:|git://|ssh://|tel:|magnet:|ipfs://|ipns://|gemini://|gopher://|news:';
  static const _ipv6Url = r'\[[0-9a-fA-F:]+\](?::[0-9]+)?';
  static const _urlChars = r'[\w\-.~:/?#@!$&*+,;=%\[\]\(\)]';
  static const _pathChars = r'[\w\-.~:/$?#@!&*+;=%]';
  static const _posixRootedPrefix =
      r'(?:\.\./|\.\/|(?<!\w)~/|(?:[\w][\w\-.]*/)*(?<!\w)\$[A-Za-z_]\w*/|\.[\w][\w\-.]*/|(?<![\w~/])/(?!/))';
  static final _posixDottedPath = [
    r'(?=[\w\-.~:/$?#@!&*+;=%]*\.)',
    _pathChars,
    r'+(?:(?<!:) (?!\w+://)(?!\.{0,2}/)(?!~/)[\w\-.~:/$?#@!&*+;=%]*[/.])*(?<!:)',
  ].join();
  static final _posixUndottedPath = [
    r'(?![\w\-.~:/$?#@!&*+;=%]*\.)',
    _pathChars,
    r'+(?:(?<!:) (?!\w+://)(?!\.{0,2}/)(?!~/)[\w\-.~:/$?#@!&*+;=%]+)*(?<!:)',
  ].join();
  static const _posixBarePath =
      r'(?<![\w$~])[\w][\w\-.]*/[\w\-.~:/$?#@!&*+;=%]*\.[\w\-.~:/$?#@!&*+;=%]+';
  static final _windowsRootedPath = [
    r'(?:[A-Za-z]:[\\/]|\\\\[^\\/ ]+[\\/][^\\/ ]+[\\/]|\.{1,2}\\)',
    r'[\w\-.~:\\/$?#@!&*+;=%\\]+',
  ].join();
  static const _windowsBarePath =
      r'(?<![\w$~])[\w][\w\-.]*\\[\w\-.~:\\/$?#@!&*+;=%\\]*\.[\w\-.~:\\/$?#@!&*+;=%\\]+';
  static const _currentDirectoryPath = r'(?<![\w./$~-])\.{1,2}(?![\w./])';
  static final _source = [
    r'(?:',
    r'(?:',
    _urlSchemes,
    r')(?:',
    _ipv6Url,
    r'|',
    _urlChars,
    r'+)+',
    r'|',
    _posixRootedPrefix,
    r'(?:',
    _posixDottedPath,
    r'|',
    _posixUndottedPath,
    r')',
    r'|',
    _posixBarePath,
    r'|',
    _windowsRootedPath,
    r'|',
    _windowsBarePath,
    r'|',
    _currentDirectoryPath,
    r')',
  ].join();
}
