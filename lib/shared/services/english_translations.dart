import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// The English text behind every translation key, whatever locale is active.
///
/// A searchable list is searched by what a thing is called, and an English name
/// stays the name a user knows from a document, a ticket or a screenshot even
/// after the app is switched to another language. The bundle is the same asset
/// the app ships for en-US, read once into memory.
///
/// Reading it is asynchronous but consulting it is not: surfaces look the labels
/// up while they build, and [load] runs at startup so the map is already there.
/// A surface opened before the read finishes simply has no aliases until its
/// next build, which is why the map is never awaited on a UI path.
abstract final class EnglishLabels {
  static Map<String, String> _labels = const {};
  static Future<void>? _loading;

  /// The English strings, keyed the way `tr()` keys them.
  static Map<String, String> get labels {
    // A hot restart or a test that skipped startup still gets the aliases, just
    // one frame later; the read is shared, so asking twice costs nothing.
    if (_labels.isEmpty) {
      _loading ??= _read();
    }
    return _labels;
  }

  /// Reads the bundle. Called from startup; safe to call again.
  static Future<void> load() => _loading ??= _read();

  static Future<void> _read() async {
    try {
      final raw = await rootBundle.loadString('assets/translations/en-US.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _labels = {
        for (final entry in data.entries)
          if (entry.value is String) entry.key: entry.value as String,
      };
    } on Object {
      // A missing bundle costs the English alias, not the search: the active
      // locale's labels still match.
      _labels = const {};
    }
  }
}

/// [key]'s English text with [args] filled into its `{}` slots in order.
///
/// Null when the bundle has no string for [key]; plural maps are maps, not
/// strings, so they have no alias here either.
String? englishText(
  Map<String, String> labels,
  String key, {
  List<String> args = const [],
}) {
  final template = labels[key];
  if (template == null) return null;
  var value = template;
  for (final arg in args) {
    value = value.replaceFirst('{}', arg);
  }
  return value;
}
