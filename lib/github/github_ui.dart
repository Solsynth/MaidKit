import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'github_models.dart';

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
    WorkflowRunStatus.completed => switch (conclusion) {
      WorkflowRunConclusion.success => (
        icon: Symbols.check_circle,
        color: const Color(0xFF2E7D32),
      ),
      WorkflowRunConclusion.failure => (
        icon: Symbols.error,
        color: scheme.error,
      ),
      WorkflowRunConclusion.timedOut => (
        icon: Symbols.error,
        color: const Color(0xFFE65100),
      ),
      WorkflowRunConclusion.actionRequired => (
        icon: Symbols.error,
        color: const Color(0xFF6A1B9A),
      ),
      WorkflowRunConclusion.cancelled => (
        icon: Symbols.cancel,
        color: scheme.onSurfaceVariant,
      ),
      _ => (
        icon: Symbols.remove_circle_outline,
        color: scheme.onSurfaceVariant,
      ),
    },
    WorkflowRunStatus.unknown => (
      icon: Symbols.help,
      color: scheme.onSurfaceVariant,
    ),
  };
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
