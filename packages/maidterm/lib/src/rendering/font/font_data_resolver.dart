import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'font_data_resolver_io.dart'
    if (dart.library.js_interop) 'font_data_resolver_web.dart';

/// Resolves raw TTF/OTF font file bytes for a given font family name.
///
/// Used internally by `TerminalView` to automatically find font data for
/// exact metric extraction without requiring callers to manually load and
/// pass font bytes.
///
/// Resolution order (first match wins):
/// 1. Flutter asset bundle: tries common asset path conventions.
/// 2. System font directories: scans platform-specific font folders
///    (macOS, Linux, Windows; skipped on mobile and web).
///
/// Results are cached globally so repeated lookups are free.
///
/// ```dart
/// final bytes = await FontDataResolver.resolve('JetBrains Mono');
/// if (bytes != null) {
///   final metrics = parseFontTableMetrics(bytes);
/// }
/// ```
class FontDataResolver {
  static final _cache = <String, Uint8List?>{};

  /// Weight-style suffixes excluded during filesystem font scanning.
  ///
  /// Only the regular weight is useful for baseline metric extraction;
  /// bold/italic variants share the same `post` and `OS/2` values.
  static const _excludedWeights = {
    'bold',
    'italic',
    'oblique',
    'light',
    'thin',
    'medium',
    'semibold',
    'extrabold',
    'black',
  };

  FontDataResolver._();

  /// Clears the resolution cache.
  @visibleForTesting
  static void clearCache() => _cache.clear();

  /// Resolves font file bytes for [fontFamily].
  ///
  /// Returns cached results on subsequent calls. Returns `null` if the
  /// font cannot be found in any source.
  static Future<Uint8List?> resolve(String fontFamily) async {
    if (_cache.containsKey(fontFamily)) return _cache[fontFamily];

    final assetBytes = await _tryAssetBundle(fontFamily);
    if (assetBytes != null) {
      _cache[fontFamily] = assetBytes;
      return assetBytes;
    }

    final systemBytes = trySystemFonts(
      fontFamily,
      _candidates,
      _excludedWeights,
    );
    _cache[fontFamily] = systemBytes;
    return systemBytes;
  }

  /// Candidate filenames for a font family (regular weight only).
  static List<String> _candidates(String fontFamily) {
    final normalized = fontFamily.replaceAll(' ', '');
    return [
      '$normalized-Regular.ttf',
      '$normalized-Regular.otf',
      '$normalized.ttf',
      '$normalized.otf',
      '$fontFamily-Regular.ttf',
      '$fontFamily.ttf',
    ];
  }

  /// Tries common Flutter asset bundle paths for a font file.
  static Future<Uint8List?> _tryAssetBundle(String fontFamily) async {
    const prefixes = ['assets/fonts/', 'fonts/', 'assets/', ''];

    for (final prefix in prefixes) {
      for (final candidate in _candidates(fontFamily)) {
        try {
          final data = await rootBundle.load('$prefix$candidate');
          // Uint8List.sublistView respects ByteData's offsetInBytes,
          // unlike data.buffer.asUint8List() which can include padding.
          return Uint8List.sublistView(data);
        } on Object {
          // Asset not found at this path.
        }
      }
    }
    return null;
  }
}
