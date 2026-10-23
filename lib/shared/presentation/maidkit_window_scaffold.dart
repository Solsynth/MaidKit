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
import 'package:maid_kit/servers/vault_gate.dart';
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
/// On desktop the window is borderless and the top pane tab strip *is* the
/// title bar: the strip already draws the app's identity and its tabs, so a
/// second bar above it only costs a row. While no strip is on screen — the
/// locked vault, an empty workspace — the shell draws a plain title bar so the
/// window stays draggable and closable.
class MaidKitWindowScaffold extends ConsumerWidget {
  const MaidKitWindowScaffold({super.key, required this.child, this.title});

  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = ref.watch(desktopWindowProvider);
    // The workspace renders a pane tab strip on the top edge as soon as it has
    // a pane, and that strip *is* the title bar. Until then (locked vault, no
    // panes) the shell owns the bar.
    final titleBarClaimed =
        ref.watch(vaultUnlockedProvider) &&
        ref.watch(terminalTabsProvider).isNotEmpty;

    return Focus(
      // The shell holds the app-level shortcuts, so it keeps focus whenever
      // nothing inside the workspace has claimed it.
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.tab &&
            HardwareKeyboard.instance.isShiftPressed) {
          showTerminalCommandPalette(context, ref);
          return KeyEventResult.handled;
        }
        // Cmd/Ctrl+W closes the tab the workspace is showing. The window owns
        // the shortcut because focus can sit outside the workspace — or
        // nowhere — when it is pressed.
        if (event.logicalKey == LogicalKeyboardKey.keyW &&
            (HardwareKeyboard.instance.isMetaPressed ||
                HardwareKeyboard.instance.isControlPressed)) {
          final tabId = ref.read(terminalTabsProvider).selectedId;
          if (tabId == null) return KeyEventResult.ignored;
          // Closing may have to ask about work in progress, so it is async.
          unawaited(ref.read(terminalTabsProvider.notifier).close(tabId));
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
              color: Theme.of(context).colorScheme.surface,
              child: Column(
                children: [
                  if (isDesktop && !titleBarClaimed)
                    MaidKitTitleBar(title: Text(title ?? 'MaidKit')),
                  Expanded(
                    // Routes own their safe areas. Consuming mobile insets here
                    // prevents page scaffolds from participating correctly in
                    // gesture-back.
                    child: Column(
                      children: [
                        Expanded(child: child),
                        const TaskProgressBar(),
                      ],
                    ),
                  ),
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
  final colorScheme =
      flutter.ColorScheme.fromSeed(
        seedColor: colors.primary,
        brightness: colors.brightness,
      ).copyWith(
        primary: colors.primary,
        onPrimary: colors.onPrimary,
        surface: colors.surface,
        onSurface: colors.onSurface,
        surfaceContainer: colors.surfaceContainer,
        onSurfaceVariant: colors.onSurfaceVariant,
        outline: colors.outline,
      );

  return flutter.ThemeData(
    brightness: colors.brightness,
    useMaterial3: true,
    fontFamily: fontFamily ?? MaidKitFonts.sans,
    colorScheme: colorScheme,
    inputDecorationTheme: flutter.InputDecorationTheme(
      border: flutter.OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    iconTheme: flutter.IconThemeData(
      color: theme.iconTheme.color ?? colors.onSurface,
    ),
  );
}
