import 'dart:io';

import 'package:flutter/foundation.dart';

/// IO implementation of system font resolution.
///
/// Uses `dart:io` [File], [Directory], and [Platform] to scan
/// platform-specific system font directories.
Uint8List? trySystemFonts(
  String fontFamily,
  List<String> Function(String) candidates,
  Set<String> excludedWeights,
) {
  if (kIsWeb) return null;

  final dirs = _systemFontDirs();
  if (dirs.isEmpty) return null;

  final normalizedLower = fontFamily.replaceAll(' ', '').toLowerCase();

  for (final dir in dirs) {
    for (final candidate in candidates(fontFamily)) {
      final file = File('${dir.path}/$candidate');
      if (file.existsSync()) return file.readAsBytesSync();
    }

    // Fonts are often in family-named subfolders
    // (e.g., /usr/share/fonts/truetype/jetbrains-mono/).
    try {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last.toLowerCase();
        if (!name.endsWith('.ttf') && !name.endsWith('.otf')) continue;
        final nameNoExt = name.substring(0, name.length - 4);
        if (nameNoExt.contains(normalizedLower) &&
            !excludedWeights.any(nameNoExt.contains)) {
          return entity.readAsBytesSync();
        }
      }
    } on FileSystemException {
      // Directory not readable.
    }
  }
  return null;
}

/// Returns platform-specific system font directories.
List<Directory> _systemFontDirs() {
  switch (Platform.operatingSystem) {
    case 'macos':
      return [
        Directory('/Library/Fonts'),
        Directory('${Platform.environment['HOME']}/Library/Fonts'),
        Directory('/System/Library/Fonts'),
        Directory('/System/Library/Fonts/Supplemental'),
      ].where((d) => d.existsSync()).toList();

    case 'linux':
      final home = Platform.environment['HOME'] ?? '';
      return [
        Directory('$home/.local/share/fonts'),
        Directory('$home/.fonts'),
        Directory('/usr/share/fonts'),
        Directory('/usr/local/share/fonts'),
      ].where((d) => d.existsSync()).toList();

    case 'windows':
      final winDir = Platform.environment['WINDIR'] ?? r'C:\Windows';
      final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
      return [
        Directory('$winDir\\Fonts'),
        if (localAppData.isNotEmpty)
          Directory('$localAppData\\Microsoft\\Windows\\Fonts'),
      ].where((d) => d.existsSync()).toList();

    default:
      return const [];
  }
}
