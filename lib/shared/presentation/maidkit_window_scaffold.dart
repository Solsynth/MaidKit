import 'package:window_manager/window_manager.dart';

import 'package:flutter/material.dart' as flutter;
import 'package:maid_kit/theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    as flutter_localizations;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';

import 'package:maid_kit/servers/app_theme_preferences.dart';
import 'package:maid_kit/servers/terminal_command_palette.dart';
import 'task_progress.dart';

/// Closes the desktop window without a visible teardown stall.
///
/// On Windows, `windowManager.destroy()` only posts WM_QUIT; the window stays
/// on screen while the engines (Flutter, plus WebView2's title-bar engine)
/// shut down and stop pumping messages, which reads as a freeze. Hide first,
/// then quit. On macOS/Linux `destroy()` tears down immediately either way.
Future<void> closeMaidKitWindow() async {
  await windowManager.hide();
  await windowManager.destroy();
}

final desktopWindowProvider = Provider<bool>(
  (ref) => DesktopWindowFrame.isPlatformDesktop,
);

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

class MaidKitWindowScaffold extends ConsumerWidget {
  const MaidKitWindowScaffold({super.key, required this.child, this.title});

  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = ref.watch(desktopWindowProvider);

    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.tab &&
            HardwareKeyboard.instance.isShiftPressed) {
          showTerminalCommandPalette(context, ref);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      // Island's frame still reads Flutter's Material theme while MaidKit
      // uses the modular material_ui package.
      child: flutter.Theme(
        data: _createWindowFrameTheme(Theme.of(context)),
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
            child: DesktopWindowFrame(
              // Closing the custom title bar must terminate the native window.
              // Hiding it leaves the Dart isolate (and local MCP server) alive,
              // so every relaunch creates another background MaidKit process.
              onClose: isDesktop ? closeMaidKitWindow : null,
              isDesktopPlatform: isDesktop,
              title: Text(
                title ?? 'MaidKit',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              // Routes own their safe areas. Consuming mobile insets here prevents
              // page scaffolds from participating correctly in gesture-back.
              child: Column(
                children: [
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

/// Supplies the Flutter Material theme consumed by Island's window frame.
///
/// `material_ui` and Flutter's Material library expose separate Theme
/// inherited widgets, so the frame otherwise falls back to Flutter defaults.
flutter.ThemeData _createWindowFrameTheme(ThemeData theme) {
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
    fontFamily: MaidKitFonts.sans,
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
