import 'package:easy_localization/easy_localization.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// The dashboard's bottom action bar: arrange mode and the search toggle.
///
/// The controls are a [Wrap], so a narrow pane reflows them onto extra runs
/// instead of overflowing the way the previous fixed [Row] did — the servers
/// dashboard lives in a pane that can be arbitrarily narrow.
///
/// Card density is not here: it is a lasting preference, so it lives in
/// Settings > Appearance next to the other layout controls.
class DashboardActionsBar extends StatelessWidget {
  const DashboardActionsBar({
    super.key,
    required this.isArranging,
    required this.canArrange,
    required this.onToggleArrange,
    required this.isSearching,
    required this.onToggleSearch,
  });

  /// Whether the catalog is in arrange mode.
  final bool isArranging;

  /// Arranging needs at least two servers to reorder.
  final bool canArrange;

  final VoidCallback onToggleArrange;

  /// Whether the header search field is revealed.
  final bool isSearching;

  final VoidCallback onToggleSearch;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _ActionsToggleButton(
          engaged: isArranging,
          onPressed: canArrange ? onToggleArrange : null,
          icon: isArranging ? Symbols.check : Symbols.drag_indicator,
          label: isArranging
              ? 'serversDoneArranging'.tr()
              : 'serversArrange'.tr(),
        ),
        _ActionsToggleButton(
          engaged: isSearching,
          onPressed: onToggleSearch,
          icon: Symbols.search,
          label: isSearching ? 'serversHideSearch'.tr() : 'serversSearch'.tr(),
        ),
      ],
    );
  }
}

/// One labelled toggle in [DashboardActionsBar].
///
/// An engaged toggle takes a tonal fill, which reads as "on" without competing
/// with the page's single primary action, the add-server FAB.
class _ActionsToggleButton extends StatelessWidget {
  const _ActionsToggleButton({
    required this.engaged,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final bool engaged;
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, size: 18);
    final labelWidget = Text(label);
    if (engaged) {
      return FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: iconWidget,
        label: labelWidget,
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: iconWidget,
      label: labelWidget,
    );
  }
}
