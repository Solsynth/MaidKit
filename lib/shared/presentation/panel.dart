import 'package:material_ui/material_ui.dart';
import 'package:maid_kit/theme.dart';

/// A pane's sheet: the surface one tab's content sits on.
///
/// The workspace paper is the bar's tone; a panel steps up from it so every
/// pane reads as a distinct card without a rule or a shadow between panes.
/// [emphasized] marks the focused pane: it draws one hairline in the accent
/// tone, while an idle pane has its content dimmed so a split shows exactly one
/// live viewport.
class MaidKitPanel extends StatelessWidget {
  final Widget? child;

  /// Gutter between the panel and its slot.
  ///
  /// The pane area and the split own the gutters between panes, so a pane's
  /// panel is normally flush; a panel used on its own keeps this margin.
  final EdgeInsetsGeometry margin;

  /// Whether this is the focused pane.
  ///
  /// Emphasis is a hairline, never a shadow: the live pane keeps full contrast
  /// and the idle ones recede, the same way an unfocused window does.
  final bool emphasized;

  /// Whether a dragged pane is hovering this slot.
  ///
  /// A drop target answers in the accent tone at full strength, because the
  /// gesture is momentary and the pane it will swap with has to be
  /// unambiguous.
  final bool highlighted;

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
    this.highlighted = false,
  });

  /// Brightness an idle panel's content keeps, as a fraction of its own.
  ///
  /// Emphasis subtracts light, it does not paint over the pane: the content is
  /// scaled toward black, so text, accents and a terminal's own dark backdrop
  /// all dim by the same amount and nothing is tinted a second colour.
  static const _idleBrightness = 0.85;

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
    final body = child ?? const SizedBox.shrink();
    return Theme(
      data: theme.copyWith(
        // The sheet is the page paper for everything inside the pane. Pages
        // read the paper from the scheme (`MaidKitAppScaffold` asks for
        // `surfaceContainerLowest`), so the tone has to be republished there
        // rather than only on the scaffold/canvas defaults; cards inside then
        // step one tone off the sheet, as they do on the window paper.
        colorScheme: scheme.copyWith(surfaceContainerLowest: color),
        scaffoldBackgroundColor: color,
        canvasColor: color,
        cardTheme: theme.cardTheme.copyWith(color: cardColor),
      ),
      child: Card(
        elevation: 0,
        margin: margin,
        color: color,
        // The sheet clips its own content, so a terminal's dark backdrop and a
        // dimmed pane's filter both end on the card's corner.
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: MaidKitRadius.cardRadius,
          // One hairline around the live pane: enough to name it at a glance,
          // quiet enough to stay a sheet rather than a boxed control. A drag
          // hovering this slot takes the same hairline at full strength.
          side: switch ((highlighted, emphasized)) {
            (true, _) => BorderSide(color: scheme.primary),
            (_, true) => BorderSide(
              color: scheme.primary.withValues(alpha: 0.45),
            ),
            _ => BorderSide.none,
          },
        ),
        // Dimming is a paint-time filter, not a block above the content: an
        // idle pane keeps its own Material ancestors, its pointer events, its
        // scrolling and its ink. Only the light it gives off changes.
        child: emphasized
            ? body
            : ColorFiltered(
                colorFilter: const ColorFilter.matrix(<double>[
                  _idleBrightness, 0, 0, 0, 0, //
                  0, _idleBrightness, 0, 0, 0, //
                  0, 0, _idleBrightness, 0, 0, //
                  0, 0, 0, 1, 0, //
                ]),
                child: body,
              ),
      ),
    );
  }
}
