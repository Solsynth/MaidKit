import 'package:material_ui/material_ui.dart';

class MaidKitPanel extends StatelessWidget {
  final Widget? child;
  const MaidKitPanel({super.key, this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      // The panel fills its slot edge to edge: separation between panes comes
      // from the gap the split leaves, not from a floating margin that would
      // shrink the content by four pixels on every side.
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: child,
    );
  }
}
