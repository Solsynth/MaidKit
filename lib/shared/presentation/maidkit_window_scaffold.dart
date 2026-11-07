import 'dart:async';

import 'package:flutter/material.dart' as flutter;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    as flutter_localizations;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:maid_kit/servers/app_theme_preferences.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/terminal_command_palette.dart';
import 'package:maid_kit/servers/terminal_tabs_provider.dart';
import 'package:maid_kit/servers/workspace_shortcuts.dart';
import 'package:maid_kit/theme.dart';
import 'task_progress.dart';
import 'window_chrome.dart';

/// Scales the complete window subtree while keeping the native window bounds
/// unchanged. The subtree receives a correspondingly smaller logical viewport,
/// so responsive breakpoints and hit testing use the post-scale dimensions.
class MaidKitUiScale extends StatelessWidget {
  const MaidKitUiScale({super.key, required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final normalizedScale = scale
        .clamp(AppThemePreferences.minUiScale, AppThemePreferences.maxUiScale)
        .toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
          return child;
        }
        final mediaQuery = flutter.MediaQuery.of(context);
        final scaledMediaQuery = mediaQuery.copyWith(
          size: flutter.Size(
            constraints.maxWidth / normalizedScale,
            constraints.maxHeight / normalizedScale,
          ),
          padding: mediaQuery.padding / normalizedScale,
          viewPadding: mediaQuery.viewPadding / normalizedScale,
          viewInsets: mediaQuery.viewInsets / normalizedScale,
          systemGestureInsets: mediaQuery.systemGestureInsets / normalizedScale,
        );
        return flutter.FittedBox(
          alignment: Alignment.topLeft,
          fit: flutter.BoxFit.fill,
          child: flutter.MediaQuery(
            data: scaledMediaQuery,
            child: SizedBox(
              width: constraints.maxWidth / normalizedScale,
              height: constraints.maxHeight / normalizedScale,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// The app's window shell.
///
/// On desktop the window is borderless, so the shell draws the title bar band
/// above everything else: that band is what moves the window, and on macOS it
/// is the strip AppKit spends a pointer on before Flutter sees it. The
/// workspace's tabs sit below it rather than inside it, so dragging a tab along
/// the strip never competes with dragging the window.
class MaidKitWindowScaffold extends ConsumerWidget {
  const MaidKitWindowScaffold({super.key, required this.child, this.title});

  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = ref.watch(desktopWindowProvider);

    return FocusScope(
      // A scope, not a plain node: putting the soft keyboard away releases the
      // terminal's focus with the default `scope` disposition, which parks it
      // on the nearest enclosing scope. As a scope, this shell is where that
      // release lands, so the app-level shortcuts below still have a focus
      // chain after the keyboard is gone. `autofocus` claims it when nothing
      // inside the workspace has.
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        // Ctrl+Tab steps to the next workspace tab, Shift+Ctrl+Tab back —
        // the chord every editor and browser uses for the same move. It has to
        // be asked before the plain Shift+Tab palette chord below, because
        // Shift+Ctrl+Tab would otherwise read as that chord. Ctrl is required
        // rather than this platform's command modifier: on Apple platforms
        // Cmd+Tab belongs to the system and never reaches the app.
        if (tabCycleStep(event) case final step when step != 0) {
          ref.read(terminalTabsProvider.notifier).cycleSelectedTab(step);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.tab &&
            HardwareKeyboard.instance.isShiftPressed) {
          showTerminalCommandPalette(context, ref);
          return KeyEventResult.handled;
        }
        // Cmd/Ctrl+W closes the pane the workspace is showing. A split loses
        // only its live pane; the tab's last pane *is* the tab, so the close
        // falls through to closing the whole tab there. The window owns the
        // shortcut because focus can sit outside the workspace — or nowhere —
        // when it is pressed.
        if (event.logicalKey == LogicalKeyboardKey.keyW &&
            (HardwareKeyboard.instance.isMetaPressed ||
                HardwareKeyboard.instance.isControlPressed)) {
          final tab = ref.read(terminalTabsProvider).selectedTab;
          if (tab == null) return KeyEventResult.ignored;
          // Closing may have to ask about work in progress, so it is async.
          unawaited(
            ref
                .read(terminalTabsProvider.notifier)
                .closePaneInTab(tab.id, tab.focusedPaneId),
          );
          return KeyEventResult.handled;
        }
        // Cmd/Ctrl+T opens an empty workspace tab — the same launcher pane a
        // split leaves behind — so the new tab starts from a choice instead of
        // a copy of the current one. It sits before the split branch so a
        // terminal that keeps the chord never reaches the remote shell.
        if (isNewTabShortcut(event)) {
          ref.read(terminalTabsProvider.notifier).openEmptyTab();
          return KeyEventResult.handled;
        }
        // Cmd/Ctrl+D splits the focused pane to the right, Shift below. The
        // terminal asks the same helper before its renderer claims the chord,
        // so this branch covers every other focused surface.
        if (splitShortcutAxis(event) case final axis?) {
          ref.read(terminalTabsProvider.notifier).splitSelectedTab(axis);
          return KeyEventResult.handled;
        }
        // Cmd/Ctrl+1…9 selects the tab at that position in the bar. Positions
        // past the last tab do nothing.
        if (tabPositionShortcut(event) case final position?) {
          ref.read(terminalTabsProvider.notifier).selectTabAt(position);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: flutter.Theme(
        data: _createWindowFrameTheme(
          Theme.of(context),
          fontFamily: ref.watch(appUiFontFamilyProvider),
        ),
        child: flutter.Localizations.override(
          context: context,
          delegates: const [
            // Both packages define distinct MaterialLocalizations types.
            ...GlobalMaterialLocalizations.delegates,
            flutter_localizations.GlobalCupertinoLocalizations.delegate,
            flutter_localizations.GlobalMaterialLocalizations.delegate,
            flutter_localizations.GlobalWidgetsLocalizations.delegate,
          ],
          child: flutter.Material(
            // Keep the frame's existing surface painting while providing the
            // Flutter SDK Material ancestor required by legacy controls.
            type: flutter.MaterialType.transparency,
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              child: Column(
                children: [
                  // The band owns the window drag; the workspace's tabs live
                  // below it so a tab drag never moves the window.
                  if (isDesktop)
                    MaidKitTitleBar(title: Text(title ?? 'MaidKit')),
                  Expanded(child: child),
                  const TaskProgressBar(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Supplies the Flutter Material theme consumed by the window chrome.
///
/// `material_ui` and Flutter's Material library expose separate Theme
/// inherited widgets, so the chrome otherwise falls back to Flutter defaults.
flutter.ThemeData _createWindowFrameTheme(
  ThemeData theme, {
  String? fontFamily,
}) {
  final colors = theme.colorScheme;
  // Copy the whole scheme across rather than regenerating it from the seed:
  // the app's paper ramp (`_seedPaper`) is not what `fromSeed` produces, so a
  // regenerated scheme would give the chrome different neutrals than the pages
  // inside it. Only the two packages' distinct ColorScheme types force the
  // mapping.
  final colorScheme = flutter.ColorScheme(
    brightness: colors.brightness,
    primary: colors.primary,
    onPrimary: colors.onPrimary,
    primaryContainer: colors.primaryContainer,
    onPrimaryContainer: colors.onPrimaryContainer,
    primaryFixed: colors.primaryFixed,
    primaryFixedDim: colors.primaryFixedDim,
    onPrimaryFixed: colors.onPrimaryFixed,
    onPrimaryFixedVariant: colors.onPrimaryFixedVariant,
    secondary: colors.secondary,
    onSecondary: colors.onSecondary,
    secondaryContainer: colors.secondaryContainer,
    onSecondaryContainer: colors.onSecondaryContainer,
    secondaryFixed: colors.secondaryFixed,
    secondaryFixedDim: colors.secondaryFixedDim,
    onSecondaryFixed: colors.onSecondaryFixed,
    onSecondaryFixedVariant: colors.onSecondaryFixedVariant,
    tertiary: colors.tertiary,
    onTertiary: colors.onTertiary,
    tertiaryContainer: colors.tertiaryContainer,
    onTertiaryContainer: colors.onTertiaryContainer,
    tertiaryFixed: colors.tertiaryFixed,
    tertiaryFixedDim: colors.tertiaryFixedDim,
    onTertiaryFixed: colors.onTertiaryFixed,
    onTertiaryFixedVariant: colors.onTertiaryFixedVariant,
    error: colors.error,
    onError: colors.onError,
    errorContainer: colors.errorContainer,
    onErrorContainer: colors.onErrorContainer,
    surface: colors.surface,
    onSurface: colors.onSurface,
    surfaceDim: colors.surfaceDim,
    surfaceBright: colors.surfaceBright,
    surfaceContainerLowest: colors.surfaceContainerLowest,
    surfaceContainerLow: colors.surfaceContainerLow,
    surfaceContainer: colors.surfaceContainer,
    surfaceContainerHigh: colors.surfaceContainerHigh,
    surfaceContainerHighest: colors.surfaceContainerHighest,
    onSurfaceVariant: colors.onSurfaceVariant,
    outline: colors.outline,
    outlineVariant: colors.outlineVariant,
    shadow: colors.shadow,
    scrim: colors.scrim,
    inverseSurface: colors.inverseSurface,
    onInverseSurface: colors.onInverseSurface,
    inversePrimary: colors.inversePrimary,
  );

  return flutter.ThemeData(
    brightness: colors.brightness,
    useMaterial3: true,
    fontFamily: fontFamily ?? MaidKitFonts.sans,
    colorScheme: colorScheme,
    inputDecorationTheme: flutter.InputDecorationTheme(
      border: flutter.OutlineInputBorder(
        borderRadius: BorderRadius.circular(MaidKitRadius.md),
      ),
    ),
    iconTheme: flutter.IconThemeData(
      color: theme.iconTheme.color ?? colors.onSurface,
    ),
  );
}
