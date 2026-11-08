import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/theme.dart';

/// The fixed slot at the end of a search field.
///
/// A clear button that appears only once something is typed changes the row's
/// cross-axis extent, so the field's band jumps taller the moment the query
/// starts. This slot is always laid out at one size: it shows the clear button
/// when there is a query, the Escape keycap instead when a [keyHint] is given,
/// and otherwise nothing — but it never resizes.
class SearchFieldSuffix extends StatelessWidget {
  const SearchFieldSuffix({
    super.key,
    required this.visible,
    required this.onClear,
    this.keyHint,
  });

  /// Whether there is a query to clear.
  final bool visible;

  final VoidCallback onClear;

  /// A chord printed in the slot while there is nothing to clear.
  final String? keyHint;

  /// One height for the clear button and the keycap alike, so the field's band
  /// never depends on which of them is showing.
  static const double height = 26;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hint = keyHint;
    return SizedBox(
      height: height,
      child: Center(
        widthFactor: 1,
        child: visible
            ? IconButton(
                tooltip: 'commonClearSearch'.tr(),
                icon: const Icon(Symbols.close, size: 18),
                padding: EdgeInsets.zero,
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 40,
                  height: height,
                ),
                onPressed: onClear,
              )
            : hint == null
            ? const SizedBox(width: 0)
            : Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: MaidKitSpace.sm,
                  vertical: MaidKitSpace.xxs,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(MaidKitRadius.xs),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Text(
                  hint,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
      ),
    );
  }
}
