import 'package:material_ui/material_ui.dart';

/// A [Tab] rendered as a horizontal `[icon] label` row instead of the
/// built-in vertically stacked icon/text composition.
///
/// The TabBar's [_TabStyle]-provided label color and icon theme still apply
/// to the row's [Text] and [Icon], so selection highlighting works as usual.
class IconLabelTab extends StatelessWidget {
  const IconLabelTab({super.key, required this.icon, required this.label});

  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [icon, const SizedBox(width: 8), Text(label)],
        ),
      ),
    );
  }
}
