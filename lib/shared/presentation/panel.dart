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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // The focused pane is the card, one step off the bar's paper — no further,
    // or a pane reads as a lit sheet instead of the same paper as the strip.
    // An unfocused pane sits back down on that paper, so a split shows exactly
    // one live card and the gutters alone divide the rest.
    final color = emphasized
        ? scheme.surfaceContainerLow
        : scheme.surfaceContainerLowest;
    // Inside a pane the sheet *is* the page paper: a tab body that paints its
    // own surface — a page scaffold, a pushed detail page, an editor — fills
    // the panel's tone instead of cutting a paper-coloured hole in the card.
    // Cards inside step one tone off the sheet, so the hierarchy in a pane
    // reads exactly as it does on the window paper.
    final cardColor = emphasized
        ? scheme.surfaceContainer
        : scheme.surfaceContainerLow;
    return Theme(
      data: theme.copyWith(
        scaffoldBackgroundColor: color,
        canvasColor: color,
        cardTheme: theme.cardTheme.copyWith(color: cardColor),
      ),
      child: Card(
        elevation: 0,
        margin: margin,
        color: color,
        shape: const RoundedRectangleBorder(
          borderRadius: MaidKitRadius.cardRadius,
        ),
        child: child,
      ),
    );
  }
}
