import 'package:flutter/material.dart' as flutter;
import 'package:maid_kit/theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';

import 'package:maid_kit/servers/terminal_command_palette.dart';
import 'task_progress.dart';

final desktopWindowProvider = Provider<bool>(
  (ref) => DesktopWindowFrame.isPlatformDesktop,
);

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
        // material_ui 和 Flutter 原生 Material 各有一套 RenderInkFeatures,
        // 原生 Ink/InkWell 在 material_ui 的树里找不到祖先,release 下就是
        // "Null check operator used on a null value"(Material.of 里的 result!)。
        // 以下依赖仍用原生 material,且在 pub cache 里改不了,故在此统一兜底:
        //   flutter_code_editor      搜索框 / 补全弹窗的 InkWell
        //   markdown_widget          链接、图片的 InkWell,目录的 ListTile
        //   solar_network_foundation InputChip
        //   update_settings_section  SwitchListTile / DropdownButtonFormField / ListTile
        // 透明 Material 只补这个祖先,不绘制任何背景。
        child: flutter.Material(
          type: flutter.MaterialType.transparency,
          child: DesktopWindowFrame(
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
    fontFamily: MaidKitFonts.sans,
    colorScheme: colorScheme,
    iconTheme: flutter.IconThemeData(
      color: theme.iconTheme.color ?? colors.onSurface,
    ),
  );
}
