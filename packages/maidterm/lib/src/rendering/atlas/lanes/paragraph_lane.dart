import 'dart:math';
import 'dart:ui';

import 'package:meta/meta.dart';

import '../atlas_config.dart';
import '../atlas_entry.dart';
import 'atlas_lane.dart';

typedef _PendingParagraph = ({
  Paragraph paragraph,
  AtlasEntry entry,
  double widthScale,
  Offset paintOffset,
});

/// Shared paragraph setup for font-backed atlas lanes.
abstract class ParagraphLane extends AtlasLane {
  final List<_PendingParagraph> _pending = [];

  var _fontFamily = '';
  var _fontWeight = FontWeight.normal;
  var _fontFamilyFallback = const <String>[];
  var _pxCellWidth = 0.0;
  var _pxCellHeight = 0.0;
  var _pxFontSize = 0.0;
  var _pxBaseline = 0.0;
  var _pxItalicOverhang = 0.0;

  ParagraphLane({required super.entryLane, super.initialSize, super.maxSize});

  @override
  bool get hasPending => _pending.isNotEmpty;

  double get pxBaseline => _pxBaseline;

  double get pxCellHeight => _pxCellHeight;

  double get pxCellWidth => _pxCellWidth;

  double get pxFontSize => _pxFontSize;

  double get pxItalicOverhang => _pxItalicOverhang;

  void addPendingParagraph(
    Paragraph paragraph,
    AtlasEntry entry, {
    double widthScale = 1.0,
    Offset paintOffset = Offset.zero,
  }) {
    _pending.add((
      paragraph: paragraph,
      entry: entry,
      widthScale: widthScale,
      paintOffset: paintOffset,
    ));
  }

  Paragraph buildParagraph(
    String text, {
    required bool bold,
    required bool italic,
    required double size,
    required double width,
    double? height,
    String? fontFamily,
    List<String>? fontFamilyFallback,
  }) {
    final resolvedFontFamily = fontFamily ?? _fontFamily;
    final resolvedFontFamilyFallback =
        fontFamilyFallback ?? _fontFamilyFallback;

    // All glyphs use textAlign: .start. Centering is handled by the
    // individual lanes so CJK text and emoji do not double-center.
    return (ParagraphBuilder(
            ParagraphStyle(
              fontSize: size,
              fontFamily: resolvedFontFamily,
              height: height,
              textAlign: .start,
            ),
          )
          ..pushStyle(
            TextStyle(
              color: const Color(0xFFFFFFFF),
              fontSize: size,
              fontFamily: resolvedFontFamily,
              height: height,
              decoration: TextDecoration.none,
              fontWeight: bold ? .bold : _fontWeight,
              fontStyle: italic ? .italic : .normal,
              fontFamilyFallback: resolvedFontFamilyFallback,
            ),
          )
          ..addText(text)
          ..pop())
        .build()
      ..layout(ParagraphConstraints(width: width));
  }

  @override
  void clearPending() {
    for (final pending in _pending) {
      pending.paragraph.dispose();
    }
    _pending.clear();
  }

  @override
  void configure(AtlasConfig config) {
    _fontFamily = config.fontFamily;
    _fontWeight = config.fontWeight;
    _fontFamilyFallback = config.fontFamilyFallback;
    _pxCellWidth = config.metrics.cellWidth * config.devicePixelRatio;
    _pxCellHeight = config.metrics.cellHeight * config.devicePixelRatio;
    _pxBaseline = config.metrics.baseline * config.devicePixelRatio;
    _pxFontSize = config.fontSize * config.devicePixelRatio;
    _pxItalicOverhang = max(1.0, (_pxFontSize * 0.15).ceilToDouble());
  }

  @override
  void paintPending(Canvas canvas) {
    for (final pending in _pending) {
      final entry = pending.entry;
      canvas.save();
      canvas.clipRect(
        Rect.fromLTRB(
          entry.srcLeft,
          entry.srcTop,
          entry.srcRight,
          entry.srcBottom,
        ),
      );
      paintPendingParagraph(
        canvas,
        pending.paragraph,
        entry,
        pending.widthScale,
        pending.paintOffset,
      );
      canvas.restore();
      pending.paragraph.dispose();
    }
    _pending.clear();
  }

  @protected
  void paintPendingParagraph(
    Canvas canvas,
    Paragraph paragraph,
    AtlasEntry entry,
    double widthScale,
    Offset paintOffset,
  );
}
