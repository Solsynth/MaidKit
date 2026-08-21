import 'dart:ui';

import '../atlas_entry.dart';
import 'paragraph_lane.dart';

/// Rasterizes font-backed text glyphs into the text atlas.
class TextLane extends ParagraphLane {
  TextLane({super.initialSize, super.maxSize}) : super(entryLane: .text);

  @override
  void paintPendingParagraph(
    Canvas canvas,
    Paragraph paragraph,
    AtlasEntry entry,
    double widthScale,
    Offset paintOffset,
  ) {
    final offset = Offset(
      entry.srcLeft + paintOffset.dx,
      entry.srcTop + paintOffset.dy,
    );
    if (widthScale == 1.0) {
      canvas.drawParagraph(paragraph, offset);
    } else {
      canvas.translate(offset.dx, offset.dy);
      canvas.scale(widthScale, 1.0);
      canvas.drawParagraph(paragraph, Offset.zero);
    }
  }

  /// Builds a paragraph for [text], packs it into the atlas, and returns
  /// an [AtlasEntry] with its source coordinates.
  ///
  /// The glyph is not composited into the atlas image until [ensureImage]
  /// is called. [span] controls how many cell widths the glyph occupies
  /// (2 for wide/CJK characters).
  AtlasEntry rasterizeText(
    String text, {
    required bool bold,
    required bool italic,
    int span = 1,
    double sourcePadding = 0.0,
  }) {
    final pxCellWidth = (this.pxCellWidth * span).ceil().toDouble();
    final pxHeight = pxCellHeight.ceil().toDouble();

    // The sprite is positioned at the cell origin; the overhang width
    // overlaps into the adjacent cell's space without shifting the glyph.
    final overhang = italic ? pxItalicOverhang : 0.0;
    final pxWidth = pxCellWidth + overhang;

    final paragraph = buildParagraph(
      text,
      bold: bold,
      italic: italic,
      size: pxFontSize,
      width: double.infinity,
    );

    final textWidth = paragraph.maxIntrinsicWidth;
    final widthScale = span > 1 && textWidth > pxCellWidth
        ? pxCellWidth / textWidth
        : 1.0;
    final bearingX = span > 1 && textWidth > 0.0 && textWidth < pxCellWidth
        ? (pxCellWidth - textWidth) / 2
        : 0.0;
    final bearingY = pxBaseline - paragraph.alphabeticBaseline;
    final paintOffset = Offset(
      sourcePadding + bearingX,
      sourcePadding + bearingY,
    );
    late final AtlasEntry entry;
    try {
      entry = allocate(
        width: pxWidth + sourcePadding * 2,
        height: pxHeight + sourcePadding * 2,
        bearingX: -sourcePadding,
        bearingY: -sourcePadding,
      );
    } catch (_) {
      paragraph.dispose();
      rethrow;
    }

    addPendingParagraph(
      paragraph,
      entry,
      widthScale: widthScale,
      paintOffset: paintOffset,
    );
    return entry;
  }
}
