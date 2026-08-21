import 'dart:math';
import 'dart:ui';

import '../atlas_config.dart';
import '../atlas_entry.dart';
import 'paragraph_lane.dart';

/// Rasterizes full-color emoji glyphs into the emoji atlas.
class EmojiLane extends ParagraphLane {
  static const _emojiLayoutWidthMultiplier = 8;
  static const _emojiFontFamilies = {
    'Apple Color Emoji',
    'Noto Color Emoji',
    'Segoe UI Emoji',
    'Noto Emoji',
  };

  String? _emojiFontFamily;
  List<String>? _emojiFontFamilyFallback;

  EmojiLane({super.initialSize, super.maxSize}) : super(entryLane: .emoji);

  @override
  void configure(AtlasConfig config) {
    super.configure(config);

    final emojiFontFamily = _emojiFontFamilyFor(config);
    _emojiFontFamily = emojiFontFamily;
    _emojiFontFamilyFallback = emojiFontFamily == null
        ? null
        : _emojiFallbackFor(config, emojiFontFamily);
  }

  /// Scales and centers an emoji paragraph within its atlas cell span.
  ///
  /// The emoji is uniformly scaled by whichever axis is tighter, then centered
  /// on both axes. The allocated span is the terminal contract; font metrics
  /// only decide how the glyph is fitted inside that span.
  @override
  void paintPendingParagraph(
    Canvas canvas,
    Paragraph paragraph,
    AtlasEntry entry,
    double _,
    Offset _,
  ) {
    final cellWidth = entry.srcRight - entry.srcLeft;
    final cellHeight = entry.srcBottom - entry.srcTop;
    final emojiWidth = max(paragraph.maxIntrinsicWidth, 1.0);
    final emojiHeight = max(paragraph.height, 1.0);
    final scale = min(
      1.0,
      min(cellWidth / emojiWidth, cellHeight / emojiHeight),
    );

    final dx = (cellWidth - emojiWidth * scale) / 2;
    final dy = (cellHeight - emojiHeight * scale) / 2;
    canvas.translate(entry.srcLeft + dx, entry.srcTop + dy);
    canvas.scale(scale);
    canvas.drawParagraph(paragraph, Offset.zero);
  }

  /// Builds a full-color emoji paragraph for [text], packs it into the
  /// atlas, and returns an [AtlasEntry] with its source coordinates.
  ///
  /// Emoji are rasterized in color and composited with uniform scaling to fit
  /// within the cell span; tinting is not applied at draw time.
  AtlasEntry rasterizeEmoji(
    String text, {
    required bool bold,
    required bool italic,
    int span = 1,
  }) {
    final pxSpanWidth = (pxCellWidth * span).ceilToDouble();
    final pxSpanHeight = pxCellHeight.ceilToDouble();
    final size = min(pxCellHeight, pxCellWidth * span) * 0.95;

    // Keep the paragraph wider than the atlas span so emoji sequences do not
    // wrap before this lane applies its own fitting.
    final layoutWidthMultiplier = max(_emojiLayoutWidthMultiplier, text.length);
    final layoutWidth = max(pxSpanWidth, size * layoutWidthMultiplier);

    final paragraph = buildParagraph(
      text,
      bold: bold,
      italic: italic,
      size: size,
      width: layoutWidth,
      fontFamily: _emojiFontFamily,
      fontFamilyFallback: _emojiFontFamilyFallback,
    );

    late final AtlasEntry entry;
    try {
      entry = allocate(
        width: pxSpanWidth,
        height: pxSpanHeight,
        bearingY: max(0.0, (pxCellHeight - paragraph.height) / 2),
      );
    } catch (_) {
      paragraph.dispose();
      rethrow;
    }

    addPendingParagraph(paragraph, entry);
    return entry;
  }

  static List<String> _emojiFallbackFor(AtlasConfig config, String primary) {
    final seen = {primary};
    final fallback = <String>[];

    void add(String family) {
      if (seen.add(family)) fallback.add(family);
    }

    for (final family in config.fontFamilyFallback) {
      add(family);
    }
    add(config.fontFamily);
    return fallback;
  }

  static String? _emojiFontFamilyFor(AtlasConfig config) {
    if (_emojiFontFamilies.contains(config.fontFamily)) {
      return config.fontFamily;
    }

    for (final family in config.fontFamilyFallback) {
      if (_emojiFontFamilies.contains(family)) return family;
    }
    return null;
  }
}
