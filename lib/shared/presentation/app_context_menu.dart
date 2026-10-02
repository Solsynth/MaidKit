import 'package:material_ui/material_ui.dart';
import 'package:super_context_menu/super_context_menu.dart';
// The desktop menu extension points are public, but the argument types they
// use are only declared in the package's internal widget builder library.
// ignore: implementation_imports
import 'package:super_context_menu/src/default_builder/group_intrinsic_width.dart';
// ignore: implementation_imports
import 'package:super_context_menu/src/scaffold/desktop/menu_widget_builder.dart';

/// Desktop menu builder used by every context menu in the app.
///
/// [DefaultDesktopMenuWidgetBuilder] wraps each item's shortcut/activator in a
/// `GroupIntrinsicWidth`, and shares a single `GroupIntrinsicWidthContainer`
/// per menu so every shortcut column ends up with the same width. That
/// container calls `markNeedsLayout()` on its remaining group children from
/// `attach`/`detach`, so tearing the menu down while Flutter is running a
/// `LayoutBuilder` callback — the callback synchronously builds the dirty
/// overlay entry — aborts with:
///
///     A _RenderGroupIntrinsicWidth was mutated in _RenderLayoutBuilder.performLayout.
///     The RenderObject was mutated when none of its ancestors is actively performing layout.
///
/// Flutter renders context menus itself on web and Android (other platforms use
/// the system menu), which is why the crash only shows up there.
///
/// Wrapping each item in its own [GroupIntrinsicWidthContainer] keeps the
/// package's item rendering but leaves every group with a single child, so
/// nothing is ever marked from attach/detach and the menu can be torn down at
/// any point of the frame. Shortcut columns are then sized per item instead of
/// being width-matched across the menu; each shortcut is still right aligned
/// because the title takes the remaining space.
class MaidKitDesktopMenuWidgetBuilder extends DefaultDesktopMenuWidgetBuilder {
  MaidKitDesktopMenuWidgetBuilder({super.maxWidth});

  @override
  Widget buildMenuItem(
    BuildContext context,
    DesktopMenuInfo menuInfo,
    Key innerKey,
    DesktopMenuButtonState state,
    MenuElement element,
  ) {
    return GroupIntrinsicWidthContainer(
      child: super.buildMenuItem(context, menuInfo, innerKey, state, element),
    );
  }
}

/// Shared instance of [MaidKitDesktopMenuWidgetBuilder]; it holds no state.
final MaidKitDesktopMenuWidgetBuilder maidKitDesktopMenuWidgetBuilder =
    MaidKitDesktopMenuWidgetBuilder();

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
    return ContextMenuWidget(
      menuProvider: (_) => menuBuilder(),
      desktopMenuWidgetBuilder: maidKitDesktopMenuWidgetBuilder,
      child: child,
    );
  }
}
