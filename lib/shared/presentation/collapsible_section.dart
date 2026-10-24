import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/theme.dart';

/// A tonal, compact disclosure section used across the workspace.
class MaidKitCollapsibleSection extends StatefulWidget {
  const MaidKitCollapsibleSection({
    super.key,
    required this.title,
    required this.children,
    this.icon,
    this.subtitle,
    this.initiallyExpanded = true,
    this.tilePadding = const EdgeInsets.symmetric(horizontal: 16),
    this.childrenPadding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
  });

  final Widget title;
  final List<Widget> children;
  final IconData? icon;
  final Widget? subtitle;
  final bool initiallyExpanded;
  final EdgeInsetsGeometry tilePadding;
  final EdgeInsetsGeometry childrenPadding;

  @override
  State<MaidKitCollapsibleSection> createState() =>
      _MaidKitCollapsibleSectionState();
}

class _MaidKitCollapsibleSectionState extends State<MaidKitCollapsibleSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(MaidKitRadius.lg),
    );
    // Separation comes from tone, not an outline: the section is a slightly
    // deeper sheet of the page's paper, matching `CardThemeData`.
    return Material(
      color: scheme.surfaceContainer,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: _expanded,
        onExpansionChanged: (expanded) => setState(() => _expanded = expanded),
        tilePadding: widget.tilePadding,
        childrenPadding: widget.childrenPadding,
        leading: widget.icon == null
            ? null
            : Icon(widget.icon, color: scheme.onSurfaceVariant),
        title: widget.title,
        subtitle: widget.subtitle,
        trailing: Icon(
          _expanded ? Symbols.keyboard_arrow_up : Symbols.keyboard_arrow_down,
          color: scheme.onSurfaceVariant,
        ),
        shape: shape,
        collapsedShape: shape,
        children: widget.children,
      ),
    );
  }
}
