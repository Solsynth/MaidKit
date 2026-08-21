import 'dart:ui';

import 'package:libghostty/libghostty.dart';

import 'atlas/atlas.dart';
import 'atlas/sprite_buffer.dart';
import 'kitty_image_cache.dart';
import 'paint_state.dart';
import 'painters/background_painter.dart';
import 'painters/cursor_painter.dart';
import 'painters/decoration_painter.dart';
import 'painters/emoji_painter.dart';
import 'painters/kitty_graphics_painter.dart';
import 'painters/shaped_run_painter.dart';
import 'painters/sprite_painter.dart';
import 'painters/terminal_text_painter.dart';
import 'painters/underline_painter.dart';

/// Owns paint helpers, paint order, and paint-only terminal resources.
final class TerminalPainterStack {
  final SpriteBuffer _sprites;
  final TerminalPaintState _state;
  final _liveKittyImageIds = <int>{};
  final KittyImageCache _kittyImageCache;
  final ShapedRunPainter _shapedRunPainter;
  final List<KittyPlacementSnapshot> _kittyBelowBg = [];
  final List<KittyPlacementSnapshot> _kittyBelowText = [];
  final List<KittyPlacementSnapshot> _kittyAboveText = [];

  final BackgroundPainter _backgroundPainter;
  final DecorationPainter _decorationPainter;
  late final KittyGraphicsPainter _kittyBelowBgPainter;
  late final KittyGraphicsPainter _kittyBelowTextPainter;
  late final KittyGraphicsPainter _kittyAboveTextPainter;

  late EmojiPainter _emojiPainter;
  late SpritePainter _spritePainter;
  late CursorPainter _cursorPainter;
  late TerminalTextPainter _textPainter;
  late UnderlinePainter _underlinePainter;

  TerminalPainterStack({
    required Atlas atlas,
    required this._sprites,
    required this._state,
    required void Function() onImageReady,
  }) : _kittyImageCache = KittyImageCache(onImageReady: onImageReady),
       _shapedRunPainter = ShapedRunPainter(_sprites.shaped),
       _backgroundPainter = BackgroundPainter(_state, _sprites),
       _decorationPainter = DecorationPainter(_sprites) {
    _kittyBelowBgPainter = KittyGraphicsPainter(
      state: _state,
      cache: _kittyImageCache,
      snapshots: _kittyBelowBg,
    );
    _kittyBelowTextPainter = KittyGraphicsPainter(
      state: _state,
      cache: _kittyImageCache,
      snapshots: _kittyBelowText,
    );
    _kittyAboveTextPainter = KittyGraphicsPainter(
      state: _state,
      cache: _kittyImageCache,
      snapshots: _kittyAboveText,
    );
    bindAtlas(atlas);
  }

  void bindAtlas(Atlas atlas) {
    _textPainter = TerminalTextPainter(atlas, _sprites.wide, _sprites.regular);
    _spritePainter = SpritePainter(atlas, _sprites);
    _cursorPainter = CursorPainter(_state, atlas);
    _emojiPainter = EmojiPainter(atlas, _sprites);
    _underlinePainter = UnderlinePainter(atlas, _sprites);
  }

  void dispose() {
    _kittyImageCache.dispose();
  }

  void paint(Canvas canvas) {
    _kittyBelowBgPainter.paint(canvas);
    _backgroundPainter.paint(canvas);
    _kittyBelowTextPainter.paint(canvas);
    _underlinePainter.paint(canvas);
    _textPainter.paint(canvas);
    _shapedRunPainter.paint(canvas);
    _spritePainter.paint(canvas);
    _cursorPainter.paint(canvas);
    _emojiPainter.paint(canvas);
    _decorationPainter.paint(canvas);
    _kittyAboveTextPainter.paint(canvas);
  }

  void sync(Terminal terminal) {
    _kittyBelowBg.clear();
    _kittyBelowText.clear();
    _kittyAboveText.clear();
    _liveKittyImageIds.clear();

    final graphics = KittyGraphics.of(terminal);
    if (graphics == null) {
      _kittyImageCache.evict(_liveKittyImageIds);
      return;
    }

    final cellWidth = _state.metrics.cellWidth;
    final cellHeight = _state.metrics.cellHeight;
    final dpr = _state.devicePixelRatio;

    for (final placement in graphics.placements()) {
      final info = placement.renderInfo;
      if (!info.viewportVisible) continue;
      if (info.pixelWidth == 0 || info.pixelHeight == 0) continue;

      final image = graphics.image(placement.imageId);
      if (image == null) continue;

      _liveKittyImageIds.add(placement.imageId);
      _kittyImageCache.lookup(image);

      _placementsFor(placement.z).add(
        KittyPlacementSnapshot(
          imageId: placement.imageId,
          dst: Rect.fromLTWH(
            info.viewportCol * cellWidth + placement.xOffset / dpr,
            info.viewportRow * cellHeight + placement.yOffset / dpr,
            info.pixelWidth / dpr,
            info.pixelHeight / dpr,
          ),
          src: Rect.fromLTWH(
            info.sourceX.toDouble(),
            info.sourceY.toDouble(),
            info.sourceWidth.toDouble(),
            info.sourceHeight.toDouble(),
          ),
          z: placement.z,
        ),
      );
    }

    _sort(_kittyBelowBg);
    _sort(_kittyBelowText);
    _sort(_kittyAboveText);
    _kittyImageCache.evict(_liveKittyImageIds);
  }

  List<KittyPlacementSnapshot> _placementsFor(int z) {
    switch (KittyPaintLayer.forZ(z)) {
      case .belowBg:
        return _kittyBelowBg;
      case .belowText:
        return _kittyBelowText;
      case .aboveText:
        return _kittyAboveText;
    }
  }

  void _sort(List<KittyPlacementSnapshot> snapshots) {
    if (snapshots.length < 2) return;
    snapshots.sort((a, b) => a.z.compareTo(b.z));
  }
}
