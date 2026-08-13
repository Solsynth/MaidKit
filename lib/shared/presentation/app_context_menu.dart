import 'package:material_ui/material_ui.dart';
import 'package:super_context_menu/super_context_menu.dart';

/// Wraps [child] so right-click / control-click presents [menuBuilder].
///
/// Use this for list rows and cards. Visible overflow buttons should keep a
/// Flutter [PopupMenuButton] instead of opening a context menu on primary click.
class AppContextMenuRegion extends StatelessWidget {
  const AppContextMenuRegion({
    super.key,
    required this.menuBuilder,
    required this.child,
    this.enabled = true,
  });

  final Menu Function() menuBuilder;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return ContextMenuWidget(menuProvider: (_) => menuBuilder(), child: child);
  }
}
