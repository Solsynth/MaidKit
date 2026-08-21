enum AtlasEntryLane { text, emoji, sprite, decoration }

/// Position and metadata of a rendered glyph in an atlas texture.
///
/// Coordinates are in physical pixels (logical pixels * device pixel ratio).
/// The source rectangle ([srcLeft], [srcTop], [srcRight], [srcBottom]) maps
/// directly to the [Canvas.drawRawAtlas] source rect parameter.
final class AtlasEntry {
  /// Left edge of the glyph region in the atlas, in physical pixels.
  final double srcLeft;

  /// Top edge of the glyph region in the atlas, in physical pixels.
  final double srcTop;

  /// Right edge of the glyph region in the atlas, in physical pixels.
  final double srcRight;

  /// Bottom edge of the glyph region in the atlas, in physical pixels.
  final double srcBottom;

  /// Vertical offset associated with the glyph's source pixels.
  ///
  /// Text and sprite glyphs use this as a draw offset when their source rect
  /// includes pixels outside the cell.
  final double bearingY;

  /// Horizontal offset associated with the glyph's source pixels.
  ///
  /// Text and sprite glyphs use this as a draw offset when their source rect
  /// includes pixels outside the cell.
  final double bearingX;

  /// Atlas lane that owns this entry's source pixels.
  final AtlasEntryLane lane;

  const AtlasEntry({
    required this.srcLeft,
    required this.srcTop,
    required this.srcRight,
    required this.srcBottom,
    required this.bearingY,
    this.bearingX = 0.0,
    this.lane = .text,
  });
}
