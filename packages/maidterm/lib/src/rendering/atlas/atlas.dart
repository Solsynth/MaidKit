import 'dart:ui' show Image;

import 'package:libghostty/libghostty.dart';

import 'atlas_cache.dart';
import 'atlas_config.dart';
import 'atlas_entry.dart';
import 'lanes/decoration_lane.dart';
import 'lanes/emoji_lane.dart';
import 'lanes/sprite_lane.dart';
import 'lanes/text_lane.dart';

export 'atlas_cache.dart' show TextAtlasKey;
export 'atlas_config.dart';
export 'atlas_entry.dart';
export 'atlas_texture.dart' show AtlasFullException;

/// Cache backed by lane-specific atlas textures.
///
/// Caches rasterized text, emoji, sprite, and decoration glyphs. On first use
/// with new cell dimensions, pre-seeds the common normal-style text glyphs so
/// steady-state rendering avoids the most common cache misses without eagerly
/// rasterizing rarely used style variants.
///
/// Lifecycle: construct with an [AtlasConfig],
/// [add]/[addCodepoint] per frame, [ensureImage] to composite pending glyphs,
/// [dispose] when detached.
class Atlas {
  final AtlasConfig _config;
  final _textLane = TextLane();
  final _emojiLane = EmojiLane();
  final _spriteLane = SpriteLane();
  final _decorationLane = DecorationLane();
  late final _cache = AtlasCache(
    textLane: _textLane,
    emojiLane: _emojiLane,
    spriteLane: _spriteLane,
    decorationLane: _decorationLane,
  );

  Atlas(this._config) {
    _configureLanes();
    if (_config.metrics.cellWidth > 0 && _config.metrics.cellHeight > 0) {
      _preseed();
    }
  }

  int get cacheSize => _cache.size;

  Image? get decorationImage => _decorationLane.image;

  double get devicePixelRatio => _config.devicePixelRatio;

  Image? get emojiImage => _emojiLane.image;

  Image? get spriteImage => _spriteLane.image;

  Image? get textImage => _textLane.image;

  Image? imageFor(AtlasEntry entry) => switch (entry.lane) {
    .text => textImage,
    .emoji => emojiImage,
    .sprite => spriteImage,
    .decoration => decorationImage,
  };

  /// Returns or creates a glyph for [key].
  ///
  /// Convenience for call sites that classify text vs. emoji at runtime
  /// (e.g. wide-cell dispatch) and want to defer the branch to the atlas.
  AtlasEntry add(TextAtlasKey key, {int span = 1, bool emoji = false}) =>
      _cache.add(key, span: span, emoji: emoji);

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
  }) => _cache.addCodepoint(codepoint, bold: bold, italic: italic, span: span);

  /// Returns or creates a decoration sprite for the given underline [style].
  AtlasEntry addDecoration(UnderlineStyle style) => _cache.addDecoration(style);

  void dispose() {
    _cache.clear();
    _textLane.dispose();
    _emojiLane.dispose();
    _spriteLane.dispose();
    _decorationLane.dispose();
  }

  /// Composites pending glyphs into the atlas texture.
  void ensureImage() {
    _textLane.ensureImage();
    _emojiLane.ensureImage();
    _spriteLane.ensureImage();
    _decorationLane.ensureImage();
  }

  /// Whether [codepoint] has a built-in sprite glyph.
  ///
  /// Sprite codepoints render from geometry regardless of how libghostty
  /// classifies the cell (wide, emoji, etc.). Callers route through
  /// [addCodepoint] to retrieve the entry; this predicate lets callers
  /// pick the right output channel before calling.
  bool hasSprite(int codepoint) => _cache.hasSprite(codepoint);

  /// Pre-seeds the atlas with glyphs that will almost certainly be needed.
  ///
  /// Rasterizing normal printable ASCII up front avoids per-frame cache misses
  /// for the most common characters while keeping bold/italic variants lazy.
  /// Built-in sprite glyphs are rasterized lazily into their own atlas
  /// texture, so first use no longer shifts text/emoji atlas positions.
  /// All underline styles are pre-seeded so decoration rendering never
  /// triggers a mid-frame atlas composite.
  void _preseed() {
    _cache.preseedCommonEntries();
    ensureImage();
  }

  void _configureLanes() {
    _textLane.configure(_config);
    _emojiLane.configure(_config);
    _spriteLane.configure(_config);
    _decorationLane.configure(_config);
  }
}
