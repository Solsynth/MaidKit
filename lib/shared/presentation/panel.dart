import 'package:material_ui/material_ui.dart';
import 'package:maid_kit/theme.dart';

/// A pane's sheet: the surface one tab's content sits on.
///
/// The workspace paper is the bar's tone; a panel steps up from it so every
/// pane reads as a distinct card without a rule or a shadow between panes.
/// [emphasized] marks the focused pane, which steps one tone further so the
/// live pane is obvious at a glance in a split.
class MaidKitPanel extends StatelessWidget {
  final Widget? child;

  /// Gutter between the panel and its slot.
  ///
  /// The pane area and the split own the gutters between panes, so a pane's
  /// panel is normally flush; a panel used on its own keeps this margin.
  final EdgeInsetsGeometry margin;

  /// Whether this is the focused pane. Only tone changes: a panel never grows
  /// a shadow or a border for emphasis.
  final bool emphasized;

  const MaidKitPanel({
    super.key,
    this.child,
    this.margin = const EdgeInsets.fromLTRB(
      MaidKitSpace.sm,
      MaidKitSpace.xs,
      MaidKitSpace.sm,
      MaidKitSpace.sm,
    ),
    this.emphasized = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The focused pane is the card; an unfocused one steps one tone toward the
    // paper so it recedes without changing size or losing its content.
    final color = emphasized
        ? scheme.surfaceContainerHigh
        : scheme.surfaceContainer;
    return Card(
      elevation: 0,
      margin: margin,
      color: color,
      shape: const RoundedRectangleBorder(
        borderRadius: MaidKitRadius.cardRadius,
      ),
      child: child,
    );
  }
}
