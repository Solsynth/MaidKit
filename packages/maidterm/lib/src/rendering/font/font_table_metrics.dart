import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Parses font table metrics from raw TrueType/OpenType font file bytes.
///
/// Reads the `head`, `hhea`, `post`, and `OS/2` tables to extract exact
/// decoration metrics. Returns `null` if the data is malformed or missing
/// required tables (`head` and `hhea`).
///
/// Zero-valued thickness fields (underline or strikethrough) are treated
/// as broken and returned as `null`, since they signal a degenerate font
/// table that should fall back to heuristic estimation.
///
/// ```dart
/// final metrics = parseFontTableMetrics(fontBytes);
/// if (metrics != null) {
///   final ppu = fontSize / metrics.unitsPerEm;
///   final thickness = metrics.underlineThickness! * ppu;
/// }
/// ```
FontTableMetrics? parseFontTableMetrics(Uint8List data) {
  if (data.length < 12) return null;

  final byteData = ByteData.sublistView(data);

  final numTables = byteData.getUint16(4);
  if (data.length < 12 + numTables * 16) return null;

  int? headOffset;
  int? hheaOffset;
  int? postOffset;
  int? os2Offset;
  int? headLength;
  int? hheaLength;
  int? postLength;
  int? os2Length;

  for (var i = 0; i < numTables; i++) {
    final entryOffset = 12 + i * 16;
    final tag = String.fromCharCodes(data, entryOffset, entryOffset + 4);
    final offset = byteData.getUint32(entryOffset + 8);
    final length = byteData.getUint32(entryOffset + 12);

    switch (tag) {
      case 'head':
        headOffset = offset;
        headLength = length;
      case 'hhea':
        hheaOffset = offset;
        hheaLength = length;
      case 'post':
        postOffset = offset;
        postLength = length;
      case 'OS/2':
        os2Offset = offset;
        os2Length = length;
    }
  }

  if (headOffset == null || hheaOffset == null) return null;
  if (headLength! < 20 || hheaLength! < 10) return null;

  // head: unitsPerEm (uint16 @ +18).
  final unitsPerEm = byteData.getUint16(headOffset + 18);
  if (unitsPerEm == 0) return null;

  // hhea: ascent (int16 @ +4), descent (int16 @ +6), lineGap (int16 @ +8).
  final ascent = byteData.getInt16(hheaOffset + 4);
  final descent = byteData.getInt16(hheaOffset + 6);
  final lineGap = byteData.getInt16(hheaOffset + 8);

  // post: underlinePosition (int16 @ +8), underlineThickness (int16 @ +10).
  int? underlinePosition;
  int? underlineThickness;
  if (postOffset != null && postLength! >= 12) {
    final rawPos = byteData.getInt16(postOffset + 8);
    final rawThick = byteData.getInt16(postOffset + 10);

    // Thickness of 0 is treated as broken; position is still used if
    // the thickness is broken but the position is non-zero.
    if (rawThick != 0 || rawPos != 0) underlinePosition = rawPos;
    if (rawThick != 0) underlineThickness = rawThick;
  }

  // OS/2: yStrikeoutSize (int16 @ +26), yStrikeoutPosition (int16 @ +28).
  int? strikethroughPosition;
  int? strikethroughThickness;
  int? capHeight;
  int? exHeight;
  if (os2Offset != null && os2Length! >= 30) {
    final os2Version = byteData.getUint16(os2Offset);
    final rawStSize = byteData.getInt16(os2Offset + 26);
    final rawStPos = byteData.getInt16(os2Offset + 28);

    if (rawStSize != 0 || rawStPos != 0) strikethroughPosition = rawStPos;
    if (rawStSize != 0) strikethroughThickness = rawStSize;

    // sxHeight (int16 @ +86) and sCapHeight (int16 @ +88) require
    // OS/2 version ≥ 2.
    if (os2Version >= 2 && os2Length >= 90) {
      final rawExHeight = byteData.getInt16(os2Offset + 86);
      final rawCapHeight = byteData.getInt16(os2Offset + 88);
      if (rawExHeight > 0) exHeight = rawExHeight;
      if (rawCapHeight > 0) capHeight = rawCapHeight;
    }
  }

  return FontTableMetrics(
    unitsPerEm: unitsPerEm,
    ascent: ascent,
    descent: descent,
    lineGap: lineGap,
    underlinePosition: underlinePosition,
    underlineThickness: underlineThickness,
    strikethroughPosition: strikethroughPosition,
    strikethroughThickness: strikethroughThickness,
    capHeight: capHeight,
    exHeight: exHeight,
  );
}

/// Metrics extracted from a TrueType/OpenType font's binary tables.
///
/// Parsed from the `head`, `hhea`, `post`, and `OS/2` tables. All values
/// are in font design units; convert to pixels with
/// `value * fontSize / unitsPerEm`.
///
/// See also:
/// - [parseFontTableMetrics], which creates this from raw font bytes.
@immutable
final class FontTableMetrics {
  /// Font design units per em square.
  final int unitsPerEm;

  /// Typographic ascent in font units (positive, above baseline).
  final int ascent;

  /// Typographic descent in font units (negative, below baseline).
  final int descent;

  /// Line gap in font units.
  final int lineGap;

  /// Underline position in font units (negative = below baseline).
  /// Null if the font's `post` table has a degenerate value.
  final int? underlinePosition;

  /// Underline thickness in font units.
  /// Null if the font's `post` table has a degenerate value.
  final int? underlineThickness;

  /// Strikethrough position in font units (positive = above baseline).
  /// Null if the font's `OS/2` table has a degenerate value.
  final int? strikethroughPosition;

  /// Strikethrough thickness in font units.
  /// Null if the font's `OS/2` table has a degenerate value.
  final int? strikethroughThickness;

  /// Cap height in font units. Null if not available (OS/2 version < 2).
  final int? capHeight;

  /// x-height in font units. Null if not available (OS/2 version < 2).
  final int? exHeight;

  const FontTableMetrics({
    required this.unitsPerEm,
    required this.ascent,
    required this.descent,
    required this.lineGap,
    this.underlinePosition,
    this.underlineThickness,
    this.strikethroughPosition,
    this.strikethroughThickness,
    this.capHeight,
    this.exHeight,
  });
}
