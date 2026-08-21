import 'package:libghostty/libghostty.dart' show UnderlineStyle;

import '../sprite/sprite_face.dart';
import 'atlas_entry.dart';
import 'lanes/decoration_lane.dart';
import 'lanes/emoji_lane.dart';
import 'lanes/sprite_lane.dart';
import 'lanes/text_lane.dart';

/// Lookup key for a cached text glyph. Two glyphs with the same text, bold,
/// and italic state share the same atlas entry.
typedef TextAtlasKey = ({String text, bool bold, bool italic});
typedef _CodepointKey = ({int codepoint, bool bold, bool italic, int span});
typedef _TextKey = ({
  String text,
  bool bold,
  bool italic,
  int span,
  double sourcePadding,
});
typedef _SpriteKey = ({int codepoint, int span});

/// Caches atlas entries and delegates rasterization on cache miss.
class AtlasCache {
  // Printable ASCII excluding space; space does not rasterize.
  static const _printableAsciiStart = 0x21; // !
  static const _printableAsciiEnd = 0x7E; // ~
  static const _printableAsciiCount =
      _printableAsciiEnd - _printableAsciiStart + 1;

  // Built-in sprites start at U+2500; lower glyphs skip registry lookup.
  static const _builtinSpriteStart = 0x2500;
  static const _singleCellTextSourcePadding = 2.0;

  final SpriteFace _spriteFace;
  final TextLane _textLane;
  final EmojiLane _emojiLane;
  final SpriteLane _spriteLane;
  final DecorationLane _decorationLane;

  final Map<_TextKey, AtlasEntry> _text = {};
  final Map<_TextKey, AtlasEntry> _emoji = {};
  final Map<_SpriteKey, AtlasEntry> _sprites = {};
  final Map<_CodepointKey, AtlasEntry> _codepoints = {};
  final Map<UnderlineStyle, AtlasEntry> _decorations = {};
  final List<AtlasEntry?> _regularAscii = List.filled(
    _printableAsciiCount,
    null,
  );

  AtlasCache({
    required this._textLane,
    required this._emojiLane,
    required this._spriteLane,
    required this._decorationLane,
    SpriteFace? spriteFace,
  }) : _spriteFace = spriteFace ?? SpriteFace();

  int get size {
    return _text.length + _emoji.length + _sprites.length + _decorations.length;
  }

  /// Returns or creates a text or emoji glyph for [key].
  AtlasEntry add(TextAtlasKey key, {int span = 1, bool emoji = false}) {
    return emoji ? _addEmoji(key, span: span) : _addText(key, span: span);
  }

  /// Returns or creates a glyph for a single [codepoint].
  ///
  /// Built-in sprite codepoints bypass font rasterization entirely and
  /// render from geometry. Non-sprite codepoints route through the text
  /// lane so single-codepoint and text-keyed callers share entries.
  AtlasEntry addCodepoint(
    int codepoint, {
    required bool bold,
    required bool italic,
    int span = 1,
  }) {
    if (span == 1 &&
        !bold &&
        !italic &&
        codepoint >= _printableAsciiStart &&
        codepoint <= _printableAsciiEnd) {
      final index = codepoint - _printableAsciiStart;
      return _regularAscii[index] ??= _addText((
        text: String.fromCharCode(codepoint),
        bold: false,
        italic: false,
      ));
    }

    if (codepoint >= _builtinSpriteStart) {
      final sprite = _addSpriteCodepoint(codepoint, span: span);
      if (sprite != null) return sprite;
    }

    final key = (codepoint: codepoint, bold: bold, italic: italic, span: span);
    final existing = _codepoints[key];
    if (existing != null) return existing;

    final entry = _addText((
      text: String.fromCharCode(codepoint),
      bold: bold,
      italic: italic,
    ), span: span);
    _codepoints[key] = entry;
    return entry;
  }

  /// Returns or creates a decoration sprite for the given underline [style].
  AtlasEntry addDecoration(UnderlineStyle style) {
    return _decorations[style] ??= _decorationLane.rasterizeDecoration(style);
  }

  void clear() {
    _text.clear();
    _emoji.clear();
    _codepoints.clear();
    _sprites.clear();
    _decorations.clear();
    _regularAscii.fillRange(0, _regularAscii.length);
  }

  bool hasSprite(int codepoint) => _spriteFace.hasCodepoint(codepoint);

  /// Pre-seeds glyphs that are expected to appear in nearly every terminal.
  ///
  /// Normal printable ASCII is seeded because it appears in nearly every frame.
  /// Bold and italic variants stay lazy so every atlas does not pay the memory
  /// cost for style combinations that may never render. Built-in sprites stay
  /// lazy so they do not consume memory until a terminal actually renders them.
  /// Decorations are seeded because they are few and avoid mid-frame atlas
  /// composites.
  void preseedCommonEntries() {
    _preseedAscii();
    _preseedDecorations();
  }

  AtlasEntry _addEmoji(TextAtlasKey key, {int span = 1}) {
    final cacheKey = (
      text: key.text,
      bold: key.bold,
      italic: key.italic,
      span: span,
      sourcePadding: 0.0,
    );
    return _emoji[cacheKey] ??= _emojiLane.rasterizeEmoji(
      key.text,
      bold: key.bold,
      italic: key.italic,
      span: span,
    );
  }

  AtlasEntry? _addSpriteCodepoint(int codepoint, {int span = 1}) {
    final glyph = _spriteFace.glyphFor(codepoint);
    if (glyph == null) return null;

    final key = (codepoint: codepoint, span: span);
    return _sprites[key] ??= _spriteLane.rasterizeSprite(glyph, span: span);
  }

  AtlasEntry _addText(TextAtlasKey key, {int span = 1}) {
    final sourcePadding = _textSourcePadding(key.text, span: span);
    final cacheKey = (
      text: key.text,
      bold: key.bold,
      italic: key.italic,
      span: span,
      sourcePadding: sourcePadding,
    );
    return _text[cacheKey] ??= _textLane.rasterizeText(
      key.text,
      bold: key.bold,
      italic: key.italic,
      span: span,
      sourcePadding: sourcePadding,
    );
  }

  double _textSourcePadding(String text, {required int span}) {
    if (span != 1) return 0.0;

    final runes = text.runes.iterator;
    if (!runes.moveNext()) return 0.0;
    final codepoint = runes.current;
    if (runes.moveNext()) return 0.0;

    return codepoint >= 0x80 ? _singleCellTextSourcePadding : 0.0;
  }

  void _preseedAscii() {
    for (
      var codepoint = _printableAsciiStart;
      codepoint <= _printableAsciiEnd;
      codepoint++
    ) {
      addCodepoint(codepoint, bold: false, italic: false);
    }
  }

  void _preseedDecorations() {
    for (final style in UnderlineStyle.values) {
      if (style != .none) addDecoration(style);
    }
  }
}
