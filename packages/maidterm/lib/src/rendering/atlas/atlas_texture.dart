import 'dart:math';
import 'dart:ui';

import 'atlas_entry.dart';

/// Thrown when a glyph or sprite cannot fit inside the configured atlas limit.
class AtlasFullException implements Exception {
  final double requestedWidth;
  final double requestedHeight;
  final int atlasWidth;
  final int atlasHeight;
  final int maxSize;

  const AtlasFullException({
    required this.requestedWidth,
    required this.requestedHeight,
    required this.atlasWidth,
    required this.atlasHeight,
    required this.maxSize,
  });

  @override
  String toString() =>
      'AtlasFullException: requested '
      '${requestedWidth.toStringAsFixed(1)}x'
      '${requestedHeight.toStringAsFixed(1)} in ${atlasWidth}x$atlasHeight '
      'atlas with max size $maxSize';
}

/// Owns atlas storage, slot allocation, and image replacement.
class AtlasTexture {
  static const defaultInitialSize = 256;
  static const defaultMaxSize = 4096;

  // Gap between atlas cells prevents sub-pixel bleed between sprites.
  static const padding = 1.0;

  final _compositePaint = Paint();
  final int _initialSize;
  final int _maxSize;

  late int _width;
  late int _height;
  var _packX = 0.0;
  var _packY = 0.0;
  var _rowHeight = 0.0;
  Image? _image;

  AtlasTexture({
    int initialSize = defaultInitialSize,
    int maxSize = defaultMaxSize,
  }) : assert(initialSize > 0, 'initialSize must be positive'),
       assert(maxSize >= initialSize, 'maxSize must be >= initialSize'),
       _initialSize = initialSize,
       _maxSize = maxSize {
    _width = initialSize;
    _height = initialSize;
  }

  Image? get image => _image;

  AtlasEntry allocate({
    required double width,
    required double height,
    required double bearingY,
    double bearingX = 0.0,
    AtlasEntryLane lane = .text,
  }) {
    _pack(width, height);

    final entry = AtlasEntry(
      srcLeft: _packX,
      srcTop: _packY,
      srcRight: _packX + width,
      srcBottom: _packY + height,
      bearingY: bearingY,
      bearingX: bearingX,
      lane: lane,
    );

    _packX += width + padding;
    _rowHeight = max(_rowHeight, height);
    return entry;
  }

  void clear() {
    _image?.dispose();
    _image = null;
    _packX = 0;
    _packY = 0;
    _rowHeight = 0;
    _width = _initialSize;
    _height = _initialSize;
  }

  void dispose() {
    _image?.dispose();
    _image = null;
  }

  void replaceImage(void Function(Canvas canvas) paintPending) {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final image = _image;
    if (image != null) canvas.drawImage(image, Offset.zero, _compositePaint);

    paintPending(canvas);

    final picture = recorder.endRecording();
    _image?.dispose();
    _image = picture.toImageSync(_width, _height);
    picture.dispose();
  }

  /// Doubles one atlas dimension so the texture stays roughly square as it
  /// grows toward [_maxSize]. Returns false when both dimensions are maxed.
  bool _grow() {
    if ((_width <= _height && _width < _maxSize) ||
        (_height >= _maxSize && _width < _maxSize)) {
      _width = min(_width * 2, _maxSize);
      return true;
    } else if (_height < _maxSize) {
      _height = min(_height * 2, _maxSize);
      return true;
    }
    return false;
  }

  /// Row-based bin packing: fills left-to-right within the current row,
  /// wraps to the next row when the glyph won't fit, and grows the
  /// atlas if vertical space is exhausted.
  void _pack(double width, double height) {
    if (width + padding > _maxSize || height + padding > _maxSize) {
      throw AtlasFullException(
        requestedWidth: width,
        requestedHeight: height,
        atlasWidth: _width,
        atlasHeight: _height,
        maxSize: _maxSize,
      );
    }

    while (width + padding > _width || height + padding > _height) {
      if (!_grow()) {
        throw AtlasFullException(
          requestedWidth: width,
          requestedHeight: height,
          atlasWidth: _width,
          atlasHeight: _height,
          maxSize: _maxSize,
        );
      }
    }

    if (_packX + width + padding > _width) {
      _packX = 0;
      _packY += _rowHeight + padding;
      _rowHeight = 0;
    }

    while (_packY + height + padding > _height) {
      if (!_grow()) {
        throw AtlasFullException(
          requestedWidth: width,
          requestedHeight: height,
          atlasWidth: _width,
          atlasHeight: _height,
          maxSize: _maxSize,
        );
      }
    }
  }
}
