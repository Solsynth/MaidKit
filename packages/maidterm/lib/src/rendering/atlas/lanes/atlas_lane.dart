import 'dart:ui' show Canvas, Image;

import '../atlas_config.dart';
import '../atlas_entry.dart';
import '../atlas_texture.dart';

/// Shared lifecycle for one physical atlas texture.
abstract class AtlasLane {
  final AtlasTexture _texture;
  final AtlasEntryLane entryLane;

  AtlasLane({
    required this.entryLane,
    int initialSize = AtlasTexture.defaultInitialSize,
    int maxSize = AtlasTexture.defaultMaxSize,
  }) : _texture = AtlasTexture(initialSize: initialSize, maxSize: maxSize);

  bool get hasPending;

  Image? get image => _texture.image;

  AtlasEntry allocate({
    required double width,
    required double height,
    required double bearingY,
    double bearingX = 0.0,
  }) {
    return _texture.allocate(
      width: width,
      height: height,
      bearingY: bearingY,
      bearingX: bearingX,
      lane: entryLane,
    );
  }

  void clear() {
    clearPending();
    _texture.clear();
  }

  void clearPending();

  void configure(AtlasConfig config);

  void dispose() {
    clearPending();
    _texture.dispose();
  }

  void ensureImage() {
    if (hasPending) _texture.replaceImage(paintPending);
  }

  void paintPending(Canvas canvas);
}
