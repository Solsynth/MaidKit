import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:maid_kit/shared/presentation/app_scaffold.dart';

import 'github_models.dart';
import 'github_providers.dart';
import 'github_ui.dart';

/// Detail view of one workflow run: header, actions, and per-job step
/// results.
@RoutePage()
class GitHubRunDetailPage extends ConsumerWidget {
  const GitHubRunDetailPage({
    super.key,
    required this.owner,
    required this.name,
    required this.runId,
    required this.run,
  });

  final String owner;
  final String name;
  final int runId;
  final WorkflowRun run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final jobs =
        ref
            .watch(
              githubRunJobsProvider((owner: owner, name: name, runId: runId)),
            )
            .asData
            ?.value ??
        const <RunJob>[];
    final loading =
        ref
            .watch(
              githubRunJobsProvider((owner: owner, name: name, runId: runId)),
            )
            .isLoading &&
        jobs.isEmpty;

    return MaidKitAppScaffold(
      appBar: AppBar(
        title: Text(
          '${run.displayTitle.isEmpty ? run.name : run.displayTitle} #${run.runNumber}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (run.htmlUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: () => launchUrl(Uri.parse(run.htmlUrl)),
                icon: const Icon(Symbols.open_in_new, size: 18),
                label: Text('githubRunOpen'.tr()),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _RunStatusIcon(
                      status: run.status,
                      conclusion: run.conclusion,
                    ),
                    const SizedBox(width: 8),
                    if (run.conclusion != null)
                      _ConclusionChip(conclusion: run.conclusion!),
                    const Spacer(),
                    Text(
                      run.status.name,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(run.displayTitle, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  [
                    '$owner/$name',
                    if (run.headBranch.isNotEmpty) run.headBranch,
                    if (run.actorLogin.isNotEmpty)
                      'githubActor'.tr(args: [run.actorLogin]),
                    if (run.event.isNotEmpty) run.event,
                    githubTimeAgo(context, run.updatedAt ?? run.createdAt),
                  ].join(' · '),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    _Meta(icon: Symbols.tag, text: '#${run.runNumber}'),
                    if (run.headSha.isNotEmpty)
                      _Meta(
                        icon: Symbols.commit,
                        text: run.headSha.substring(
                          0,
                          run.headSha.length > 7 ? 7 : run.headSha.length,
                        ),
                      ),
                    if (run.createdAt != null)
                      _Meta(
                        icon: Symbols.schedule,
                        text: githubTimeAgo(context, run.createdAt),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(Symbols.rocket_launch, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text('githubJobs'.tr(), style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          if (loading)
            const LinearProgressIndicator()
          else if (jobs.isEmpty)
            Text(
              'githubNoRuns'.tr(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            for (final job in jobs) ...[
              _JobCard(job: job),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontFamily: 'IBM Plex Mono'),
        ),
      ],
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job});

  final RunJob job;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RunStatusIcon(status: job.status, conclusion: job.conclusion),
              const SizedBox(width: 8),
              Expanded(
                child: Text(job.name, style: theme.textTheme.titleSmall),
              ),
              if (job.conclusion != null)
                _ConclusionChip(conclusion: job.conclusion!),
            ],
          ),
          const SizedBox(height: 8),
          for (final step in job.steps) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Row(
                children: [
                  Icon(
                    switch (step.status) {
                      WorkflowRunStatus.completed =>
                        step.conclusion == WorkflowRunConclusion.success
                            ? Symbols.check_circle
                            : Symbols.error,
                      WorkflowRunStatus.inProgress => Symbols.play_arrow,
                      WorkflowRunStatus.queued => Symbols.hourglass_top,
                      WorkflowRunStatus.unknown => Symbols.help,
                    },
                    size: 15,
                    color: switch (step.status) {
                      WorkflowRunStatus.completed =>
                        step.conclusion == WorkflowRunConclusion.success
                            ? const Color(0xFF2E7D32)
                            : scheme.error,
                      WorkflowRunStatus.inProgress => scheme.primary,
                      _ => scheme.onSurfaceVariant,
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${step.number}. ${step.name}',
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

class _RunStatusIcon extends StatelessWidget {
  const _RunStatusIcon({required this.status, this.conclusion});

  final WorkflowRunStatus status;
  final WorkflowRunConclusion? conclusion;

  @override
  Widget build(BuildContext context) {
    final (:icon, :color) = githubRunStatusVisual(context, status, conclusion);
    return Icon(icon, size: 20, color: color);
  }
}

class _ConclusionChip extends StatelessWidget {
  const _ConclusionChip({required this.conclusion});

  final WorkflowRunConclusion conclusion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (background, foreground, label) = switch (conclusion) {
      WorkflowRunConclusion.success => (
        const Color(0xFF2E7D32),
        Colors.white,
        'githubConclusionSuccess',
      ),
      WorkflowRunConclusion.failure => (
        theme.colorScheme.error,
        theme.colorScheme.onError,
        'githubConclusionFailure',
      ),
      WorkflowRunConclusion.timedOut => (
        const Color(0xFFE65100),
        Colors.white,
        'githubConclusionTimedOut',
      ),
      WorkflowRunConclusion.cancelled => (
        theme.colorScheme.surfaceContainerHighest,
        theme.colorScheme.onSurfaceVariant,
        'githubConclusionCancelled',
      ),
      WorkflowRunConclusion.actionRequired => (
        const Color(0xFF6A1B9A),
        Colors.white,
        'githubConclusionActionRequired',
      ),
      _ => (
        theme.colorScheme.surfaceContainerHighest,
        theme.colorScheme.onSurfaceVariant,
        'githubConclusionUnknown',
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.tr(),
        style: theme.textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}
