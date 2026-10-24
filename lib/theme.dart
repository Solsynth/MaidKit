import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';

/// Registered font families from `assets/fonts`.
abstract final class MaidKitFonts {
  static const sans = 'IBM Plex Sans';
  static const mono = 'IBM Plex Mono';
}

// ---------------------------------------------------------------------------
// Design tokens
//
// Ported from Island's `lib/core/theme.dart`. One small scale for the whole
// app: if a spacing or radius is not on this list it is a one-off, not a
// system decision.
//
// Visual direction: Island's "sun-warmed paper". Neutrals are tinted toward
// the seed's own hue instead of blue-gray, contrast comes from tone and space
// rather than outlines, and inputs are tonal first (a soft filled shape) with
// an outline only for the focused and error states. Radii stay on MaidKit's
// 4/8/12/16/24 scale rather than Island's phone-sized 20/28: this is a dense
// desktop app, and AGENTS.md keeps corners modest here.
// ---------------------------------------------------------------------------

/// Spacing scale, in logical pixels.
abstract final class MaidKitSpace {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// Horizontal gutter for a page body.
  static const double page = xxl;

  /// Gap between major sections of a page.
  static const double section = xxl;

  /// Inset inside cards and other primary content surfaces.
  static const double card = lg;

  /// Height of a comfortable primary control.
  ///
  /// Island uses 48 for touch. The workspace runs on pointer input, so the
  /// same control is a step tighter here; icon-only controls keep 40 too.
  static const double control = 40;
}

/// Corner-radius scale, in logical pixels.
///
/// Buttons, inputs and menus share [md] so the interactive language reads as
/// one family; cards step up to [lg]; sheets and dialogs to [xl]. Chips stay
/// at [sm] so dense filter rows do not turn into a wall of pills.
abstract final class MaidKitRadius {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 999;

  static const double control = md;
  static const double card = lg;
  static const double input = md;
  static const double chip = sm;
  static const double menu = md;
  static const double sheet = xl;
  static const double dialog = xl;

  static const BorderRadius controlRadius = BorderRadius.all(
    Radius.circular(control),
  );
  static const BorderRadius cardRadius = BorderRadius.all(
    Radius.circular(card),
  );
  static const BorderRadius inputRadius = BorderRadius.all(
    Radius.circular(input),
  );
  static const BorderRadius menuRadius = BorderRadius.all(
    Radius.circular(menu),
  );
  static const BorderRadius sheetRadius = BorderRadius.vertical(
    top: Radius.circular(sheet),
  );
  static const BorderRadius dialogRadius = BorderRadius.all(
    Radius.circular(dialog),
  );

  /// Fully rounded capsule: any height collapses to a pill, never a squircle.
  static const BorderRadius pillRadius = BorderRadius.all(
    Radius.circular(pill),
  );
}

/// Reusable insets built from [MaidKitSpace].
abstract final class MaidKitInsets {
  static const page = EdgeInsets.symmetric(horizontal: MaidKitSpace.page);
  static const card = EdgeInsets.all(MaidKitSpace.card);
  static const control = EdgeInsets.symmetric(
    horizontal: MaidKitSpace.xl,
    vertical: MaidKitSpace.md,
  );
  static const input = EdgeInsets.symmetric(
    horizontal: MaidKitSpace.lg,
    vertical: MaidKitSpace.lg,
  );
}

const _menuShape = RoundedRectangleBorder(
  borderRadius: MaidKitRadius.menuRadius,
);
const _cardShape = RoundedRectangleBorder(
  borderRadius: MaidKitRadius.cardRadius,
);
const _buttonShape = RoundedRectangleBorder(
  borderRadius: MaidKitRadius.controlRadius,
);

/// The application-wide Material theme. Keep feature widgets dependent on this
/// shared foundation instead of creating local colour schemes or chrome.
ThemeData createMaidKitTheme(
  Brightness brightness, {
  Color? seedColor,
  String? fontFamily,
}) {
  final seed = seedColor ?? const Color(0xFF0F766E);
  final colorScheme = _seedPaper(
    ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
    seed,
    brightness,
  );

  final baseTheme = ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    brightness: brightness,
    fontFamily: fontFamily ?? MaidKitFonts.sans,
    // One paper for the app: the pane tab strip's tone is also the page paper,
    // so the locked vault, a sheet and the workspace never sit on two slightly
    // different off-whites. A pane republishes its own sheet tone inside its
    // content (see `MaidKitPanel`).
    scaffoldBackgroundColor: colorScheme.surfaceContainerLow,
    canvasColor: colorScheme.surfaceContainerLow,
    // Symbol glyphs read as one weight everywhere: no filled/optical jitter
    // between a rail, a list row and a toolbar.
    iconTheme: IconThemeData(
      fill: 0,
      weight: 400,
      opticalSize: 20,
      color: colorScheme.onSurface,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colorScheme.primary,
      selectionColor: colorScheme.primary.withValues(alpha: 0.24),
      selectionHandleColor: colorScheme.primary,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );

  final textTheme = _buildTextTheme(baseTheme.textTheme);
  final onSurface = colorScheme.onSurface;
  final onSurfaceVariant = colorScheme.onSurfaceVariant;

  // Inputs are tonal first: the soft fill defines the field, and only the
  // focused/error states draw an edge.
  final inputBorder = OutlineInputBorder(
    borderRadius: MaidKitRadius.inputRadius,
    borderSide: BorderSide.none,
  );
  final focusedInputBorder = OutlineInputBorder(
    borderRadius: MaidKitRadius.inputRadius,
    borderSide: BorderSide(color: colorScheme.primary.withValues(alpha: 0.65)),
  );
  final errorInputBorder = OutlineInputBorder(
    borderRadius: MaidKitRadius.inputRadius,
    borderSide: BorderSide(color: colorScheme.error),
  );

  return baseTheme.copyWith(
    textTheme: textTheme,
    appBarTheme: AppBarThemeData(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      // Bars are transparent; a page that needs a backdrop paints its own.
      backgroundColor: Colors.transparent,
      foregroundColor: onSurface,
      iconTheme: IconThemeData(color: onSurface),
      actionsIconTheme: IconThemeData(color: onSurface),
      toolbarHeight: 56,
      titleSpacing: MaidKitSpace.md,
      actionsPadding: const EdgeInsets.only(right: MaidKitSpace.sm),
      titleTextStyle: textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      // A card is a slightly deeper sheet of the same paper. Separation comes
      // from tone, not from a shadow.
      color: colorScheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.all(MaidKitSpace.xs),
      shape: _cardShape,
      clipBehavior: Clip.antiAlias,
    ),
    // No `selectedTileColor`: a tile paints its own background on the nearest
    // `Material`, so a global opaque fill makes Flutter's debug assertion fire
    // for every tile that sits inside a colored `DecoratedBox` (container and
    // daemon cards do). A selected row tints itself at the call site.
    listTileTheme: ListTileThemeData(
      minLeadingWidth: 40,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MaidKitRadius.sm),
      ),
      iconColor: onSurfaceVariant,
      textColor: onSurface,
      titleTextStyle: textTheme.bodyLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: onSurface,
      ),
      subtitleTextStyle: textTheme.bodySmall?.copyWith(
        color: onSurfaceVariant,
        height: 1.4,
      ),
      leadingAndTrailingTextStyle: textTheme.labelMedium?.copyWith(
        color: onSurfaceVariant,
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: colorScheme.surfaceContainerHigh.withValues(alpha: 0.7),
      contentPadding: MaidKitInsets.input,
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: focusedInputBorder,
      errorBorder: errorInputBorder,
      focusedErrorBorder: errorInputBorder,
      disabledBorder: inputBorder,
      hintStyle: textTheme.bodyMedium?.copyWith(
        color: onSurfaceVariant.withValues(alpha: 0.72),
      ),
      labelStyle: textTheme.bodyMedium?.copyWith(color: onSurfaceVariant),
      floatingLabelStyle: textTheme.bodyMedium?.copyWith(
        color: colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
      helperStyle: textTheme.bodySmall?.copyWith(color: onSurfaceVariant),
      errorStyle: textTheme.bodySmall?.copyWith(color: colorScheme.error),
      iconColor: onSurfaceVariant,
      prefixIconColor: onSurfaceVariant,
      suffixIconColor: onSurfaceVariant,
      prefixStyle: textTheme.bodyMedium?.copyWith(color: onSurface),
      suffixStyle: textTheme.bodyMedium?.copyWith(color: onSurfaceVariant),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: MaidKitInsets.control,
        minimumSize: const Size(64, MaidKitSpace.control),
        shape: _buttonShape,
        animationDuration: const Duration(milliseconds: 180),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        padding: MaidKitInsets.control,
        minimumSize: const Size(64, MaidKitSpace.control),
        shape: _buttonShape,
        animationDuration: const Duration(milliseconds: 180),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: MaidKitInsets.control,
        minimumSize: const Size(64, MaidKitSpace.control),
        shape: _buttonShape,
        side: BorderSide(color: colorScheme.outlineVariant),
        animationDuration: const Duration(milliseconds: 180),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: MaidKitSpace.lg,
          vertical: MaidKitSpace.sm,
        ),
        minimumSize: const Size(48, 36),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MaidKitRadius.md),
        ),
        animationDuration: const Duration(milliseconds: 180),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(
            horizontal: MaidKitSpace.lg,
            vertical: MaidKitSpace.sm,
          ),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(64, 36)),
        textStyle: WidgetStatePropertyAll(
          textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: _buttonShape,
      elevation: 0,
      focusElevation: 1,
      hoverElevation: 2,
      highlightElevation: 1,
      extendedPadding: const EdgeInsets.symmetric(
        horizontal: MaidKitSpace.xxl,
        vertical: MaidKitSpace.md,
      ),
      extendedIconLabelSpacing: MaidKitSpace.sm,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.18),
      elevation: 3,
      shape: const RoundedRectangleBorder(
        borderRadius: MaidKitRadius.dialogRadius,
      ),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: MaidKitSpace.xxl,
        vertical: MaidKitSpace.xxl,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        MaidKitSpace.xl,
        0,
        MaidKitSpace.xl,
        MaidKitSpace.lg,
      ),
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: onSurface,
      ),
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: onSurfaceVariant,
        height: 1.5,
      ),
      iconColor: colorScheme.primary,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colorScheme.surfaceContainerLow,
      modalBackgroundColor: colorScheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: MaidKitRadius.sheetRadius,
      ),
      dragHandleColor: onSurfaceVariant.withValues(alpha: 0.4),
      clipBehavior: Clip.antiAlias,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colorScheme.inverseSurface,
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: colorScheme.onInverseSurface,
      ),
      actionTextColor: colorScheme.inversePrimary,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MaidKitRadius.md),
      ),
      insetPadding: const EdgeInsets.fromLTRB(
        MaidKitSpace.xl,
        0,
        MaidKitSpace.xl,
        MaidKitSpace.lg,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colorScheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.18),
      elevation: 3,
      shape: _menuShape,
      menuPadding: const EdgeInsets.symmetric(vertical: MaidKitSpace.sm),
      textStyle: textTheme.bodyMedium?.copyWith(color: onSurface),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(
          colorScheme.surfaceContainerLow,
        ),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(3),
        shape: const WidgetStatePropertyAll<OutlinedBorder>(_menuShape),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: MaidKitSpace.sm),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colorScheme.surfaceContainerHigh,
      selectedColor: colorScheme.secondaryContainer,
      secondarySelectedColor: colorScheme.secondaryContainer,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MaidKitRadius.chip),
      ),
      labelPadding: const EdgeInsets.symmetric(horizontal: MaidKitSpace.sm),
      labelStyle: textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w500,
        color: onSurface,
      ),
      secondaryLabelStyle: textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w500,
        color: colorScheme.onSecondaryContainer,
      ),
      iconTheme: IconThemeData(size: 18, color: onSurfaceVariant),
      checkmarkColor: colorScheme.onSecondaryContainer,
    ),
    expansionTileTheme: ExpansionTileThemeData(
      tilePadding: const EdgeInsets.symmetric(
        horizontal: MaidKitSpace.lg,
        vertical: MaidKitSpace.xs,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MaidKitRadius.sm),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MaidKitRadius.sm),
      ),
      iconColor: onSurfaceVariant,
      collapsedIconColor: onSurfaceVariant,
      textColor: onSurface,
      collapsedTextColor: onSurface,
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: colorScheme.outlineVariant.withValues(alpha: 0.5),
      splashBorderRadius: BorderRadius.circular(MaidKitRadius.sm),
      labelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      unselectedLabelStyle: textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w500,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: colorScheme.secondaryContainer,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MaidKitRadius.md),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return textTheme.labelMedium?.copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? onSurface : onSurfaceVariant,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 24,
          color: selected ? colorScheme.onSecondaryContainer : onSurfaceVariant,
        );
      }),
    ),
    navigationRailTheme: NavigationRailThemeData(
      groupAlignment: -1,
      labelType: NavigationRailLabelType.all,
      indicatorColor: colorScheme.secondaryContainer,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MaidKitRadius.md),
      ),
      selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: onSurface,
      ),
      unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w500,
        color: onSurfaceVariant,
      ),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: colorScheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(
          right: Radius.circular(MaidKitRadius.xl),
        ),
      ),
      endShape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(MaidKitRadius.xl),
        ),
      ),
    ),
    searchBarTheme: SearchBarThemeData(
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      backgroundColor: WidgetStatePropertyAll(colorScheme.surfaceContainerHigh),
      side: const WidgetStatePropertyAll(BorderSide.none),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: MaidKitRadius.inputRadius),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: MaidKitSpace.lg),
      ),
      textStyle: WidgetStatePropertyAll(
        textTheme.bodyMedium?.copyWith(color: onSurface),
      ),
      hintStyle: WidgetStatePropertyAll(
        textTheme.bodyMedium?.copyWith(color: onSurfaceVariant),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colorScheme.inverseSurface,
        borderRadius: BorderRadius.circular(MaidKitRadius.sm),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: MaidKitSpace.sm,
        vertical: MaidKitSpace.xs,
      ),
      textStyle: textTheme.labelSmall?.copyWith(
        color: colorScheme.onInverseSurface,
      ),
      waitDuration: const Duration(milliseconds: 400),
      exitDuration: const Duration(milliseconds: 100),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant.withValues(alpha: 0.7),
      thickness: 1,
      space: MaidKitSpace.lg,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered) ? 8 : 4,
      ),
      radius: const Radius.circular(MaidKitRadius.pill),
      thumbColor: WidgetStatePropertyAll(
        onSurfaceVariant.withValues(alpha: 0.35),
      ),
      trackColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    // The 2024 progress and slider shapes are what the rest of the chrome
    // assumes. The flag itself is deprecated only because it will become the
    // default, so it stays explicit until then.
    progressIndicatorTheme: ProgressIndicatorThemeData(
      // ignore: deprecated_member_use
      year2023: false,
      color: colorScheme.primary,
      linearTrackColor: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(MaidKitRadius.pill),
      // The 2024 circular shape is drawn for one standalone 40 px ring: it
      // insets itself by 4, draws a track ring behind an indeterminate arc,
      // notches 4 px out of the track and caps a determinate bar with a dot.
      // Here a spinner is a 14–20 px glyph inside a button, a tab chip or a
      // status row, so that inset halved every one of them and the track
      // turned a plain arc into a grey doughnut. The widget that places a
      // spinner owns its size; the ring fills the box it is given, and an
      // indicator that wants a track or a stop dot asks for one.
      circularTrackPadding: EdgeInsets.zero,
      trackGap: 0,
      stopIndicatorRadius: 0,
    ),
    sliderTheme: SliderThemeData(
      // ignore: deprecated_member_use
      year2023: false,
      activeTrackColor: colorScheme.primary,
      inactiveTrackColor: colorScheme.surfaceContainerHighest,
      thumbColor: colorScheme.primary,
      overlayColor: colorScheme.primary.withValues(alpha: 0.12),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MaidKitRadius.xs),
      ),
      side: BorderSide(color: colorScheme.outline, width: 1.2),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.transparent;
        return colorScheme.outline;
      }),
    ),
  );
}

/// Builds the neutral ramp for the app's paper look from the seed.
///
/// Only the *ground* is rebuilt here: accent roles (primary, secondary,
/// tertiary, error) are left exactly as the seed produced them. Tones are
/// fixed to a soft, paper-like ramp while the hue and a trace of the seed's
/// chroma are kept, so a teal seed reads as cool paper and a clay seed as warm
/// paper. A near-gray seed stays neutral instead of picking up an invented hue.
ColorScheme _seedPaper(
  ColorScheme scheme,
  Color seedColor,
  Brightness brightness,
) {
  final seed = Hct.fromInt(seedColor.toARGB32());
  final hasHue = seed.chroma >= 5;
  final hue = hasHue ? seed.hue : 0.0;
  // Cap the tint so vivid seeds stay paper, not pastel; muted seeds get less.
  final tint = hasHue ? (seed.chroma / 16).clamp(1.5, 4.0) : 0.0;

  Color shade(double tone, [double tintScale = 1]) =>
      Color(Hct.from(hue, tint * tintScale, tone).toInt());

  final isDark = brightness == Brightness.dark;
  return scheme.copyWith(
    surface: shade(isDark ? 7.5 : 97.5, 0.7),
    surfaceDim: shade(isDark ? 5 : 87),
    surfaceBright: shade(isDark ? 25 : 99, 0.5),
    surfaceContainerLowest: shade(isDark ? 4 : 100, 0.3),
    surfaceContainerLow: shade(isDark ? 11 : 96),
    surfaceContainer: shade(isDark ? 14 : 93),
    surfaceContainerHigh: shade(isDark ? 19 : 90),
    surfaceContainerHighest: shade(isDark ? 24 : 87),
    onSurface: shade(isDark ? 93 : 12, 1.1),
    onSurfaceVariant: shade(isDark ? 80 : 32, 1.25),
    outline: shade(isDark ? 62 : 52, 1.4),
    outlineVariant: shade(isDark ? 32 : 84, 1.2),
    inverseSurface: shade(isDark ? 92 : 22),
    onInverseSurface: shade(isDark ? 18 : 96, 0.8),
    shadow: shade(isDark ? 2 : 14, 1.5),
    scrim: shade(isDark ? 2 : 8, 1.5),
  );
}

/// Softens the generated type ramp without changing its sizes.
///
/// IBM Plex Sans already carries a technical voice; the extra tracking on
/// headings and the taller body leading keep dense server pages scannable.
TextTheme _buildTextTheme(TextTheme base) {
  return base.copyWith(
    displayLarge: base.displayLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -1,
    ),
    displayMedium: base.displayMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.8,
    ),
    displaySmall: base.displaySmall?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.6,
    ),
    headlineLarge: base.headlineLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
    ),
    headlineMedium: base.headlineMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
    ),
    headlineSmall: base.headlineSmall?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
    ),
    titleLarge: base.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.25,
      height: 1.25,
    ),
    titleMedium: base.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      height: 1.3,
    ),
    titleSmall: base.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    bodyLarge: base.bodyLarge?.copyWith(height: 1.5),
    bodyMedium: base.bodyMedium?.copyWith(height: 1.45),
    bodySmall: base.bodySmall?.copyWith(height: 1.4),
    labelLarge: base.labelLarge?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    ),
    labelMedium: base.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    ),
  );
}
