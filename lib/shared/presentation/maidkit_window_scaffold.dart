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
    );
  }
}
