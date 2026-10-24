import 'package:material_ui/material_ui.dart';

import 'package:maid_kit/theme.dart';

/// The app's placeholder: what a surface shows when it has nothing to show.
///
/// One shape everywhere — a dimmed icon, a bold line, a quiet explanation and
/// an optional way out — so "nothing here" reads the same in a search tab, a
/// sheet or a settings page. This is the `EmptyState` shape from Island's
/// `lib/shared/widgets/empty_state.dart`, on MaidKit's token scale.
class MaidKitEmptyState extends StatelessWidget {
  const MaidKitEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.action,
    this.iconColor,
    this.compact = false,
  });

  final IconData icon;
  final String title;

  /// The line that tells the reader what to do next. Omitted when the title
  /// already says everything.
  final String? description;
  final Widget? action;

  /// Overrides the dimmed icon ink — an error placeholder keeps its own tint.
  final Color? iconColor;

  /// Sizes the whole block down for a panel, sheet or toolbar strip rather
  /// than a full page.
  final bool compact;

  /// Long explanations wrap here rather than running the width of a desktop
  /// window.
  static const double maxTextWidth = 420;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final description = this.description;

    // A pane can be shorter than the placeholder. The block scrolls rather
    // than overflowing, and it stays centered while it fits.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? MaidKitSpace.xxl : MaidKitSpace.xxxl,
              vertical: compact ? MaidKitSpace.lg : MaidKitSpace.xxl,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: maxTextWidth),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: compact ? 28 : 44,
                      color: iconColor ?? muted.withValues(alpha: 0.35),
                    ),
                    SizedBox(height: compact ? 10 : 14),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style:
                          (compact
                                  ? theme.textTheme.titleSmall
                                  : theme.textTheme.titleMedium)
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurface,
                              ),
                    ),
                    if (description != null) ...[
                      SizedBox(height: compact ? MaidKitSpace.xs : 6),
                      Text(
                        description,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                          height: compact ? 1.35 : 1.4,
                        ),
                      ),
                    ],
                    if (action != null) ...[
                      SizedBox(
                        height: compact ? MaidKitSpace.md : MaidKitSpace.lg,
                      ),
                      action!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
