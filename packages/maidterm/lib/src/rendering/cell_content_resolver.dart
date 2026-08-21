import 'package:libghostty/libghostty.dart';

import 'atlas/atlas.dart';
import 'codepoint_classification.dart';

/// Resolves terminal cell content to the atlas entry that should paint it.
///
/// This owns the text/emoji/built-in-sprite routing rules shared by normal
/// row rendering and block cursor glyph rendering. It does not decide where
/// or how the entry is painted; row and cursor builders own the output lane.
final class CellContentResolver {
  final Atlas _atlas;
  var _lastCodepoint = -1;
  var _lastSpan = 0;
  var _lastBold = false;
  var _lastItalic = false;
  late AtlasEntry _lastEntry;

  CellContentResolver(this._atlas);

  AtlasEntry? resolveCell(
    CellIterator cell, {
    required Style style,
    required int span,
  }) {
    final graphemeLength = cell.graphemeLength;
    if (graphemeLength == 0) return null;

    final codepoint = cell.codepoint;
    if (graphemeLength == 1) {
      if (codepoint == 0x20) return null;
      if (_usesCodepointEntry(
        codepoint: codepoint,
        graphemeLength: graphemeLength,
        span: span,
      )) {
        return resolveCodepoint(codepoint, style: style, span: span);
      }
    }

    final content = cell.content;
    if (content.isEmpty || content == ' ') return null;

    return resolve(
      content: content,
      codepoint: codepoint,
      graphemeLength: graphemeLength,
      style: style,
      span: span,
    );
  }

  AtlasEntry? resolve({
    required String content,
    required int codepoint,
    required int graphemeLength,
    required Style style,
    required int span,
  }) {
    if (content.isEmpty) return null;

    if (_usesCodepointEntry(
      codepoint: codepoint,
      graphemeLength: graphemeLength,
      span: span,
    )) {
      return resolveCodepoint(codepoint, style: style, span: span);
    }

    return _atlas.add(
      (text: content, bold: style.bold, italic: style.italic),
      span: span,
      emoji: _paintsAsEmoji(content, codepoint, span: span),
    );
  }

  AtlasEntry resolveCodepoint(
    int codepoint, {
    required Style style,
    int span = 1,
  }) {
    if (codepoint == _lastCodepoint &&
        span == _lastSpan &&
        style.bold == _lastBold &&
        style.italic == _lastItalic) {
      return _lastEntry;
    }

    final entry = _atlas.addCodepoint(
      codepoint,
      bold: style.bold,
      italic: style.italic,
      span: span,
    );
    _lastCodepoint = codepoint;
    _lastSpan = span;
    _lastBold = style.bold;
    _lastItalic = style.italic;
    _lastEntry = entry;
    return entry;
  }

  bool _paintsAsEmoji(String content, int codepoint, {required int span}) {
    return content.contains('\uFE0F') ||
        (span == 2 && !isCjkCodepoint(codepoint));
  }

  bool _usesCodepointEntry({
    required int codepoint,
    required int graphemeLength,
    required int span,
  }) {
    if (graphemeLength != 1) return false;
    if (span == 1) return codepoint < 0x100000;
    return _atlas.hasSprite(codepoint) || isCjkCodepoint(codepoint);
  }
}
