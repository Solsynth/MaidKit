import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'terminal_color_scheme.dart';

class TerminalFontOption {
  const TerminalFontOption({required this.label, required this.family});

  /// Display name, without weight/style suffixes (e.g. `SFMono`).
  final String label;

  /// Font file name registered in the engine and used for rendering
  /// (e.g. `SFMono-Regular`).
  final String family;
}

abstract final class TerminalFonts {
  static const defaultFamily = 'IBM Plex Mono';

  static const _variantKeywords = <String>[
    // Longest-first so greedy decomposition splits compound variants
    // (e.g. `ExtraLightItalic` -> extra + light + italic).
    'extralightitalic',
    'extrabolditalic',
    'semibolditalic',
    'mediumitalic',
    'lightitalic',
    'blackitalic',
    'thinitalic',
    'bolditalic',
    'extralight',
    'extrabold',
    'semilight',
    'condensed',
    'semibold',
    'expanded',
    'regular',
    'oblique',
    'medium',
    'italic',
    'retina',
    'heavy',
    'black',
    'light',
    'ultra',
    'book',
    'bold',
    'demi',
    'thin',
    'text',
  ];

  static String sanitize(String family) {
    final trimmed = family.trim();
    return trimmed.isEmpty ? defaultFamily : trimmed;
  }

  static bool _isVariantSegment(String segment) {
    var rest = segment.toLowerCase();
    var matched = false;
    while (rest.isNotEmpty) {
      String? keyword;
      for (final candidate in _variantKeywords) {
        if (rest.startsWith(candidate)) {
          keyword = candidate;
          break;
        }
      }
      if (keyword == null) return false;
      matched = true;
      rest = rest.substring(keyword.length);
    }
    return matched;
  }

  static String _stripVariantSuffix(String name) {
    final dash = name.lastIndexOf('-');
    if (dash == -1) return name;
    final segment = name.substring(dash + 1);
    if (_isVariantSegment(segment)) {
      return name.substring(0, dash);
    }
    return name;
  }

  static String _pickRegular(List<String> names) {
    for (final name in names) {
      if (name.toLowerCase().endsWith('-regular')) return name;
    }
    final sorted = [...names]
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted.first;
  }

  /// Collapses font files of the same family into a single [TerminalFontOption],
  /// preferring the regular weight variant over bold/light/italic files.
  static List<TerminalFontOption> dedupe(List<String> families) {
    final byBase = <String, List<String>>{};
    for (final family in families) {
      byBase.putIfAbsent(_stripVariantSuffix(family), () => []).add(family);
    }
    final options = [
      for (final entry in byBase.entries)
        TerminalFontOption(label: entry.key, family: _pickRegular(entry.value)),
    ];
    options.sort(
      (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
    );
    return options;
  }
}

abstract interface class TerminalAdapterSettings {
  bool get cursorAnimationEnabled;
  bool get brandingEnvironmentEnabled;
  String get terminalFontFamily;
  TerminalColorScheme get lightTheme;
  TerminalColorScheme get darkTheme;

  /// Copy the current selection to the clipboard as soon as it is made.
  ///
  /// Default off: mirror Linux X11 select-to-copy behavior without affecting
  /// the existing copy shortcuts or context menu.
  bool get selectToCopyEnabled;

  /// Paste the clipboard (or current selection when [selectToCopyEnabled]) on
  /// Shift+Insert, matching traditional terminal paste.
  bool get shiftInsertPasteEnabled;

  /// Color keywords (errors, warnings, IPs, links) in terminal output,
  /// MobaXterm-style, without overriding server ANSI colors.
  bool get keywordHighlightEnabled;

  /// Auto-fill the saved SSH password into an active `sudo` password prompt
  /// when Enter is pressed at the prompt.
  ///
  /// Default on. Disable to require manual password entry for root
  /// operations and to guarantee the stored credential is never written to
  /// the shell.
  bool get sudoAutofillEnabled;

  Future<void> saveCursorAnimationEnabled(bool enabled);
  Future<void> saveBrandingEnvironmentEnabled(bool enabled);
  Future<void> saveTerminalFontFamily(String family);
  Future<void> saveLightTheme(TerminalColorScheme theme);
  Future<void> saveDarkTheme(TerminalColorScheme theme);
  Future<void> saveSelectToCopyEnabled(bool enabled);
  Future<void> saveShiftInsertPasteEnabled(bool enabled);
  Future<void> saveKeywordHighlightEnabled(bool enabled);
  Future<void> saveSudoAutofillEnabled(bool enabled);
}

class TerminalAdapterPreferences implements TerminalAdapterSettings {
  TerminalAdapterPreferences(
    this._preferences,
    this.cursorAnimationEnabled,
    this.brandingEnvironmentEnabled,
    this.terminalFontFamily,
    this.lightTheme,
    this.darkTheme,
    this.selectToCopyEnabled,
    this.shiftInsertPasteEnabled,
    this.keywordHighlightEnabled,
    this.sudoAutofillEnabled,
  );

  static const _cursorAnimationEnabledKey = 'cursor_animation_enabled';
  static const _brandingEnvironmentEnabledKey =
      'terminal_branding_environment_enabled';
  static const _terminalFontFamilyKey = 'terminal_font_family';
  static const _lightThemeKey = 'terminal_light_theme';
  static const _darkThemeKey = 'terminal_dark_theme';
  static const _selectToCopyEnabledKey = 'terminal_select_to_copy_enabled';
  static const _shiftInsertPasteEnabledKey =
      'terminal_shift_insert_paste_enabled';
  static const _keywordHighlightEnabledKey =
      'terminal_keyword_highlight_enabled';
  static const _sudoAutofillEnabledKey = 'terminal_sudo_autofill_enabled';

  final SharedPreferencesAsync _preferences;
  @override
  final bool cursorAnimationEnabled;
  @override
  final bool brandingEnvironmentEnabled;
  @override
  final String terminalFontFamily;
  @override
  final TerminalColorScheme lightTheme;
  @override
  final TerminalColorScheme darkTheme;
  @override
  final bool selectToCopyEnabled;
  @override
  final bool shiftInsertPasteEnabled;
  @override
  final bool keywordHighlightEnabled;
  @override
  final bool sudoAutofillEnabled;

  static Future<TerminalAdapterPreferences> load({
    SharedPreferencesAsync? preferences,
  }) async {
    final store = preferences ?? SharedPreferencesAsync();
    return TerminalAdapterPreferences(
      store,
      await store.getBool(_cursorAnimationEnabledKey) ?? true,
      await store.getBool(_brandingEnvironmentEnabledKey) ?? true,
      TerminalFonts.sanitize(
        await store.getString(_terminalFontFamilyKey) ??
            TerminalFonts.defaultFamily,
      ),
      _decodeTheme(await store.getString(_lightThemeKey)) ??
          TerminalColorSchemes.defaultLightScheme,
      _decodeTheme(await store.getString(_darkThemeKey)) ??
          TerminalColorSchemes.defaultScheme,
      await store.getBool(_selectToCopyEnabledKey) ?? false,
      await store.getBool(_shiftInsertPasteEnabledKey) ?? true,
      await store.getBool(_keywordHighlightEnabledKey) ?? true,
      await store.getBool(_sudoAutofillEnabledKey) ?? true,
    );
  }

  @override
  Future<void> saveCursorAnimationEnabled(bool enabled) =>
      _preferences.setBool(_cursorAnimationEnabledKey, enabled);

  @override
  Future<void> saveBrandingEnvironmentEnabled(bool enabled) =>
      _preferences.setBool(_brandingEnvironmentEnabledKey, enabled);

  @override
  Future<void> saveTerminalFontFamily(String family) =>
      _preferences.setString(_terminalFontFamilyKey, family);

  @override
  Future<void> saveLightTheme(TerminalColorScheme theme) =>
      _preferences.setString(_lightThemeKey, _encodeTheme(theme));

  @override
  Future<void> saveDarkTheme(TerminalColorScheme theme) =>
      _preferences.setString(_darkThemeKey, _encodeTheme(theme));

  @override
  Future<void> saveSelectToCopyEnabled(bool enabled) =>
      _preferences.setBool(_selectToCopyEnabledKey, enabled);

  @override
  Future<void> saveShiftInsertPasteEnabled(bool enabled) =>
      _preferences.setBool(_shiftInsertPasteEnabledKey, enabled);

  @override
  Future<void> saveKeywordHighlightEnabled(bool enabled) =>
      _preferences.setBool(_keywordHighlightEnabledKey, enabled);

  @override
  Future<void> saveSudoAutofillEnabled(bool enabled) =>
      _preferences.setBool(_sudoAutofillEnabledKey, enabled);

  static String _encodeTheme(TerminalColorScheme theme) => jsonEncode({
    'id': theme.id,
    'label': theme.label,
    'background': theme.background.toARGB32(),
    'foreground': theme.foreground.toARGB32(),
    'cursor': theme.cursor.toARGB32(),
    'selection': theme.selection.toARGB32(),
    'ansi': theme.ansiColors.map((color) => color.toARGB32()).toList(),
  });

  static TerminalColorScheme? _decodeTheme(String? encoded) {
    if (encoded == null) return null;
    try {
      final json = jsonDecode(encoded) as Map<String, dynamic>;
      final ansi = (json['ansi'] as List<dynamic>)
          .map((value) => Color(value as int))
          .toList();
      return TerminalColorScheme(
        id: json['id'] as String? ?? 'custom',
        label: json['label'] as String? ?? 'Custom',
        background: Color(json['background'] as int),
        foreground: Color(json['foreground'] as int),
        cursor: Color(json['cursor'] as int),
        selection: Color(json['selection'] as int),
        ansiColors: ansi,
      );
    } catch (_) {
      return null;
    }
  }
}

class InMemoryTerminalAdapterSettings implements TerminalAdapterSettings {
  InMemoryTerminalAdapterSettings({
    this.cursorAnimationEnabled = true,
    this.brandingEnvironmentEnabled = true,
    this.terminalFontFamily = TerminalFonts.defaultFamily,
    this.lightTheme = TerminalColorSchemes.defaultLightScheme,
    this.darkTheme = TerminalColorSchemes.defaultScheme,
    this.selectToCopyEnabled = false,
    this.shiftInsertPasteEnabled = true,
    this.keywordHighlightEnabled = true,
    this.sudoAutofillEnabled = true,
  });

  @override
  bool cursorAnimationEnabled;
  @override
  bool brandingEnvironmentEnabled;
  @override
  String terminalFontFamily;
  @override
  TerminalColorScheme lightTheme;
  @override
  TerminalColorScheme darkTheme;
  @override
  bool selectToCopyEnabled;
  @override
  bool shiftInsertPasteEnabled;
  @override
  bool keywordHighlightEnabled;
  @override
  bool sudoAutofillEnabled;

  @override
  Future<void> saveCursorAnimationEnabled(bool enabled) async {
    cursorAnimationEnabled = enabled;
  }

  @override
  Future<void> saveBrandingEnvironmentEnabled(bool enabled) async {
    brandingEnvironmentEnabled = enabled;
  }

  @override
  Future<void> saveTerminalFontFamily(String family) async {
    terminalFontFamily = family;
  }

  @override
  Future<void> saveLightTheme(TerminalColorScheme theme) async {
    lightTheme = theme;
  }

  @override
  Future<void> saveDarkTheme(TerminalColorScheme theme) async {
    darkTheme = theme;
  }

  @override
  Future<void> saveSelectToCopyEnabled(bool enabled) async {
    selectToCopyEnabled = enabled;
  }

  @override
  Future<void> saveShiftInsertPasteEnabled(bool enabled) async {
    shiftInsertPasteEnabled = enabled;
  }

  @override
  Future<void> saveKeywordHighlightEnabled(bool enabled) async {
    keywordHighlightEnabled = enabled;
  }

  @override
  Future<void> saveSudoAutofillEnabled(bool enabled) async {
    sudoAutofillEnabled = enabled;
  }
}
