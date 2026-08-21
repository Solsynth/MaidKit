import 'package:flutter/foundation.dart' show internal;

import 'link_settings.dart';

/// Parses path-like link text without touching the filesystem.
///
/// Resolution is string-based. Absolute paths are normalized, and relative
/// paths are joined with the current working directory when one is available.
@internal
abstract final class LinkPathResolver {
  static final _lineColumnPattern = RegExp(r'^(.*?):([0-9]+)(?::([0-9]+))?$');
  static final _windowsDrivePathPattern = RegExp(r'^[A-Za-z]:[\\/]');
  static final _windowsFileUriPathPattern = RegExp('^/[A-Za-z]:/');

  static bool isWindowsDrivePath(String path) {
    return _windowsDrivePathPattern.hasMatch(path);
  }

  static bool looksLikePath(String text) {
    return text == '.' ||
        text == '..' ||
        isWindowsDrivePath(text) ||
        _isWindowsUncPath(text) ||
        text.startsWith('/') ||
        text.startsWith('./') ||
        text.startsWith('../') ||
        text.startsWith(r'.\') ||
        text.startsWith(r'..\') ||
        text.startsWith('~/') ||
        text.startsWith(r'$') ||
        text.contains('/') ||
        text.contains(r'\');
  }

  /// Returns parsed file data when [text] looks like a file path.
  static LinkedFile? parseFile(String text, String? cwd) {
    var path = text;
    int? line;
    int? column;
    final suffix = _lineColumnPattern.firstMatch(text);
    if (suffix != null && !text.contains('://')) {
      path = suffix.group(1)!;
      line = int.tryParse(suffix.group(2)!);
      column = int.tryParse(suffix.group(3) ?? '');
    }

    if (_parseUri(text) != null &&
        !text.startsWith('file:') &&
        !isWindowsDrivePath(path)) {
      return null;
    }

    if (!looksLikePath(path)) return null;
    return LinkedFile(
      path: path,
      line: line,
      column: column,
      cwd: cwd,
      resolvedPath: resolvePath(path, cwd),
    );
  }

  /// Returns a URI for URI-like text that is not a Windows drive path.
  static Uri? parseTextUri(String text) {
    final suffix = _lineColumnPattern.firstMatch(text);
    final path = suffix != null ? suffix.group(1)! : text;
    if (isWindowsDrivePath(path)) return null;
    return _parseUri(text);
  }

  /// Resolves [path] against [cwd] using POSIX or Windows separators inferred
  /// from the input strings.
  static String? resolvePath(String path, String? cwd) {
    final filePath = _fileUriPath(path);
    if (filePath != null) return _normalizePath(filePath);
    if (_isAbsolutePath(path)) return _normalizePath(path);
    if (_isShellExpandedPath(path)) return null;

    final base = _cwdPath(cwd);
    if (base == null) return null;
    return _normalizePath(_joinPath(base, path));
  }

  static String trimTextLink(String text) {
    if (parseTextUri(text) != null) return _trimTrailingPunctuation(text);
    return _trimTrailingPathProse(text);
  }

  static String? _fileUriPath(String text) {
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme != 'file') return null;
    final path = uri.path;
    if (_windowsFileUriPathPattern.hasMatch(path)) {
      return path.substring(1).replaceAll('/', r'\');
    }
    return path;
  }

  static bool _isAbsolutePath(String path) {
    return path.startsWith('/') ||
        isWindowsDrivePath(path) ||
        _isWindowsUncPath(path);
  }

  static bool _isFileLikePathSegment(String segment) {
    return segment.contains('/') ||
        segment.contains(r'\') ||
        segment.contains('.');
  }

  static bool _isShellExpandedPath(String path) {
    return path.startsWith('~/') || path.startsWith(r'$');
  }

  static bool _isWindowsPath(String path) {
    return isWindowsDrivePath(path) ||
        _isWindowsUncPath(path) ||
        path.contains(r'\');
  }

  static bool _isWindowsUncPath(String path) => path.startsWith(r'\\');

  static String _joinPath(String base, String path) {
    final separator = _isWindowsPath(base) || _isWindowsPath(path) ? r'\' : '/';
    final cleanBase = base.endsWith(separator)
        ? base.substring(0, base.length - 1)
        : base;
    return '$cleanBase$separator$path';
  }

  static String _normalizePath(String path) {
    if (_isWindowsPath(path)) return _normalizeWindowsPath(path);
    return _normalizePosixPath(path);
  }

  static String _normalizePosixPath(String path) {
    final segments = <String>[];
    for (final segment in path.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (segments.isNotEmpty) segments.removeLast();
        continue;
      }
      segments.add(segment);
    }

    if (path.startsWith('/')) {
      return segments.isEmpty ? '/' : '/${segments.join('/')}';
    }
    return segments.join('/');
  }

  static String _normalizeWindowsPath(String path) {
    const separator = r'\';
    final value = path.replaceAll('/', separator);
    var prefix = '';
    var rest = value;

    if (isWindowsDrivePath(value)) {
      prefix = value.substring(0, 2);
      rest = value.substring(2);
    } else if (_isWindowsUncPath(value)) {
      final parts = value.substring(2).split(separator);
      if (parts.length >= 2) {
        prefix = '$separator$separator${parts[0]}$separator${parts[1]}';
        rest = parts.skip(2).join(separator);
      }
    }

    final segments = <String>[];
    for (final segment in rest.split(separator)) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (segments.isNotEmpty) segments.removeLast();
        continue;
      }
      segments.add(segment);
    }

    if (prefix.isEmpty) return segments.join(separator);
    if (segments.isEmpty) return '$prefix$separator';
    return '$prefix$separator${segments.join(separator)}';
  }

  static Uri? _parseUri(String text) {
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme.isEmpty) return null;
    return uri;
  }

  static String _trimTrailingPathProse(String text) {
    if (!text.contains(' ')) return text;

    final segments = text.split(' ');
    final keep = <String>[segments.first];
    var foundFileLikeSpacedSegment = false;

    for (final segment in segments.skip(1)) {
      if (segment.isEmpty) break;
      if (foundFileLikeSpacedSegment && !_isFileLikePathSegment(segment)) {
        break;
      }
      keep.add(segment);
      foundFileLikeSpacedSegment |= _isFileLikePathSegment(segment);
    }

    return keep.join(' ');
  }

  static String _trimTrailingPunctuation(String text) {
    if (text == '.' || text == '..') return text;
    var end = text.length;
    while (end > 0) {
      final code = text.codeUnitAt(end - 1);
      if (code != 0x2E && code != 0x2C) break;
      end--;
    }
    if (end > 0 && text.codeUnitAt(end - 1) == 0x29) {
      final opens = '('.allMatches(text.substring(0, end)).length;
      final closes = ')'.allMatches(text.substring(0, end)).length;
      if (closes > opens) end--;
    }
    return text.substring(0, end);
  }

  static String? _cwdPath(String? cwd) {
    if (cwd == null || cwd.isEmpty) return null;
    final filePath = _fileUriPath(cwd);
    if (filePath != null) return filePath;
    return cwd.startsWith('/') ? cwd : null;
  }
}
