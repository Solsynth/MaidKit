import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/theme.dart';

import 'github_models.dart';

/// The tint a workflow conclusion is drawn in.
///
/// `success`, `timedOut` and `actionRequired` have no Material role to borrow —
/// a run's outcome is not the app's primary, error or secondary state — so they
/// keep GitHub's own conventional hue. The rest come from the scheme so they
/// still move with the user's accent.
Color githubConclusionTone(
  ColorScheme scheme,
  WorkflowRunConclusion? conclusion,
) => switch (conclusion) {
  WorkflowRunConclusion.success => const Color(0xFF2E7D32),
  WorkflowRunConclusion.failure => scheme.error,
  WorkflowRunConclusion.timedOut => const Color(0xFFE65100),
  WorkflowRunConclusion.actionRequired => const Color(0xFF6A1B9A),
  _ => scheme.onSurfaceVariant,
};

/// Status icon and color shared by the run tiles, run detail, and the
/// dashboard workflow card.
({IconData icon, Color color}) githubRunStatusVisual(
  BuildContext context,
  WorkflowRunStatus status,
  WorkflowRunConclusion? conclusion,
) {
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    WorkflowRunStatus.queued => (
      icon: Symbols.hourglass_top,
      color: scheme.onSurfaceVariant,
    ),
    WorkflowRunStatus.inProgress => (
      icon: Symbols.play_arrow,
      color: scheme.primary,
    ),
    WorkflowRunStatus.completed => (
      icon: switch (conclusion) {
        WorkflowRunConclusion.success => Symbols.check_circle,
        WorkflowRunConclusion.failure ||
        WorkflowRunConclusion.timedOut ||
        WorkflowRunConclusion.actionRequired => Symbols.error,
        WorkflowRunConclusion.cancelled => Symbols.cancel,
        _ => Symbols.remove_circle_outline,
      },
      color: githubConclusionTone(scheme, conclusion),
    ),
    WorkflowRunStatus.unknown => (
      icon: Symbols.help,
      color: scheme.onSurfaceVariant,
    ),
  };
}

/// A run or job conclusion as a tonal capsule.
///
/// One shape for the run list, the run's own page and the job cards: the fill
/// is a tint of the state's tone and the label carries the ink, so a list of
/// runs never turns into a row of saturated badges.
class GithubConclusionChip extends StatelessWidget {
  const GithubConclusionChip({super.key, required this.conclusion});

  final WorkflowRunConclusion conclusion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = githubConclusionTone(theme.colorScheme, conclusion);
    final label = switch (conclusion) {
      WorkflowRunConclusion.success => 'githubConclusionSuccess'.tr(),
      WorkflowRunConclusion.failure => 'githubConclusionFailure'.tr(),
      WorkflowRunConclusion.timedOut => 'githubConclusionTimedOut'.tr(),
      WorkflowRunConclusion.cancelled => 'githubConclusionCancelled'.tr(),
      WorkflowRunConclusion.actionRequired =>
        'githubConclusionActionRequired'.tr(),
      _ => 'githubConclusionUnknown'.tr(),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(MaidKitRadius.pill),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: tone,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Compact relative time label ("just now", "5m ago", …).
String githubTimeAgo(BuildContext context, DateTime? time) {
  if (time == null) return '';
  final difference = DateTime.now().difference(time);
  if (difference.inMinutes < 1) return 'agentJustNow'.tr();
  if (difference.inHours < 1) {
    return 'agentMinutesAgo'.tr(args: ['${difference.inMinutes}']);
  }
  if (difference.inDays < 1) {
    return 'agentHoursAgo'.tr(args: ['${difference.inHours}']);
  }
  return 'agentDaysAgo'.tr(args: ['${difference.inDays}']);
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Absolute timestamp for a run: "Aug 5 · 14:32" in the current year,
/// "Aug 5, 2026" otherwise. Shown alongside [githubTimeAgo].
String githubRunDateTime(BuildContext context, DateTime? time) {
  if (time == null) return '';
  final now = DateTime.now();
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  final date = '${_months[time.month - 1]} ${time.day}';
  return time.year == now.year
      ? '$date · $hour:$minute'
      : '$date, ${time.year}';
}
