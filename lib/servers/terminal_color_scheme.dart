import 'package:material_ui/material_ui.dart';

/// A renderer-neutral terminal palette.
///
/// The ANSI order follows the conventional xterm layout: normal colors first,
/// then their bright counterparts.
class TerminalColorScheme {
  const TerminalColorScheme({
    required this.id,
    required this.label,
    required this.background,
    required this.foreground,
    required this.cursor,
    required this.selection,
    required this.ansiColors,
  });

  final String id;
  final String label;
  final Color background;
  final Color foreground;
  final Color cursor;
  final Color selection;
  final List<Color> ansiColors;

  TerminalColorScheme copyWith({
    String? id,
    String? label,
    Color? background,
    Color? foreground,
    Color? cursor,
    Color? selection,
    List<Color>? ansiColors,
  }) {
    return TerminalColorScheme(
      id: id ?? this.id,
      label: label ?? this.label,
      background: background ?? this.background,
      foreground: foreground ?? this.foreground,
      cursor: cursor ?? this.cursor,
      selection: selection ?? this.selection,
      ansiColors: ansiColors ?? this.ansiColors,
    );
  }
}

abstract final class TerminalColorSchemes {
  static const defaultScheme = TerminalColorScheme(
    id: 'default',
    label: 'Default',
    background: Color(0xFF1E1E1E),
    foreground: Color(0xFFCCCCCC),
    cursor: Color(0xFFAEAFAD),
    selection: Color(0xAAAEAFAD),
    ansiColors: [
      Color(0xFF000000),
      Color(0xFFCD3131),
      Color(0xFF0DBC79),
      Color(0xFFE5E510),
      Color(0xFF2472C8),
      Color(0xFFBC3FBC),
      Color(0xFF11A8CD),
      Color(0xFFE5E5E5),
      Color(0xFF666666),
      Color(0xFFF14C4C),
      Color(0xFF23D18B),
      Color(0xFFF5F543),
      Color(0xFF3B8EEA),
      Color(0xFFD670D6),
      Color(0xFF29B8DB),
      Color(0xFFFFFFFF),
    ],
  );

  static const defaultLightScheme = TerminalColorScheme(
    id: 'default-light',
    label: 'Default Light',
    background: Color(0xFFFAFAFA),
    foreground: Color(0xFF24292E),
    cursor: Color(0xFF0F766E),
    selection: Color(0xFFB7D8D5),
    ansiColors: [
      Color(0xFF24292E),
      Color(0xFFC62828),
      Color(0xFF2E7D32),
      Color(0xFFB8860B),
      Color(0xFF1565C0),
      Color(0xFF7B1FA2),
      Color(0xFF00838F),
      Color(0xFFB0BEC5),
      Color(0xFF90A4AE),
      Color(0xFFE53935),
      Color(0xFF43A047),
      Color(0xFFFBC02D),
      Color(0xFF1E88E5),
      Color(0xFF8E24AA),
      Color(0xFF00ACC1),
      Color(0xFFECEFF1),
    ],
  );

  static const catppuccinMocha = TerminalColorScheme(
    id: 'catppuccin-mocha',
    label: 'Catppuccin Mocha',
    background: Color(0xFF1E1E2E),
    foreground: Color(0xFFCDD6F4),
    cursor: Color(0xFFF5E0DC),
    selection: Color(0xFF585B70),
    ansiColors: [
      Color(0xFF45475A),
      Color(0xFFF38BA8),
      Color(0xFFA6E3A1),
      Color(0xFFF9E2AF),
      Color(0xFF89B4FA),
      Color(0xFFF5C2E7),
      Color(0xFF94E2D5),
      Color(0xFFBAC2DE),
      Color(0xFF585B70),
      Color(0xFFF38BA8),
      Color(0xFFA6E3A1),
      Color(0xFFF9E2AF),
      Color(0xFF89B4FA),
      Color(0xFFF5C2E7),
      Color(0xFF94E2D5),
      Color(0xFFA6ADC8),
    ],
  );

  static const catppuccinLatte = TerminalColorScheme(
    id: 'catppuccin-latte',
    label: 'Catppuccin Latte',
    background: Color(0xFFEFF1F5),
    foreground: Color(0xFF4C4F69),
    cursor: Color(0xFFDC8A78),
    selection: Color(0xFFBCC0CC),
    ansiColors: [
      Color(0xFF5C5F77),
      Color(0xFFD20F39),
      Color(0xFF40A02B),
      Color(0xFFDF8E1D),
      Color(0xFF1E66F5),
      Color(0xFFEA76CB),
      Color(0xFF179299),
      Color(0xFFACB0BE),
      Color(0xFF6C6F85),
      Color(0xFFD20F39),
      Color(0xFF40A02B),
      Color(0xFFDF8E1D),
      Color(0xFF1E66F5),
      Color(0xFFEA76CB),
      Color(0xFF179299),
      Color(0xFFBCC0CC),
    ],
  );

  static const dracula = TerminalColorScheme(
    id: 'dracula',
    label: 'Dracula',
    background: Color(0xFF282A36),
    foreground: Color(0xFFF8F8F2),
    cursor: Color(0xFFF8F8F2),
    selection: Color(0xFF44475A),
    ansiColors: [
      Color(0xFF21222C),
      Color(0xFFFF5555),
      Color(0xFF50FA7B),
      Color(0xFFF1FA8C),
      Color(0xFFBD93F9),
      Color(0xFFFF79C6),
      Color(0xFF8BE9FD),
      Color(0xFFF8F8F2),
      Color(0xFF6272A4),
      Color(0xFFFF6E6E),
      Color(0xFF69FF94),
      Color(0xFFFFFFA5),
      Color(0xFFD6ACFF),
      Color(0xFFFF92DF),
      Color(0xFFA4FFFF),
      Color(0xFFFFFFFF),
    ],
  );

  static const nord = TerminalColorScheme(
    id: 'nord',
    label: 'Nord',
    background: Color(0xFF2E3440),
    foreground: Color(0xFFD8DEE9),
    cursor: Color(0xFFD8DEE9),
    selection: Color(0xFF4C566A),
    ansiColors: [
      Color(0xFF3B4252),
      Color(0xFFBF616A),
      Color(0xFFA3BE8C),
      Color(0xFFEBCB8B),
      Color(0xFF81A1C1),
      Color(0xFFB48EAD),
      Color(0xFF88C0D0),
      Color(0xFFE5E9F0),
      Color(0xFF4C566A),
      Color(0xFFBF616A),
      Color(0xFFA3BE8C),
      Color(0xFFEBCB8B),
      Color(0xFF81A1C1),
      Color(0xFFB48EAD),
      Color(0xFF8FBCBB),
      Color(0xFFECEFF4),
    ],
  );

  static const all = [
    defaultScheme,
    catppuccinMocha,
    catppuccinLatte,
    dracula,
    nord,
  ];

  static TerminalColorScheme byId(String id) =>
      all.firstWhere((scheme) => scheme.id == id, orElse: () => defaultScheme);
}
