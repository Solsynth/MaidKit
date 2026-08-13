import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/routing/app_router.gr.dart';

import 'github_models.dart';
import 'github_providers.dart';
import 'github_ui.dart';

/// Pinned-repo workflow status card for the Servers dashboard: a header plus
/// a grid of tiles, one per pinned repo (its newest run), styled like the
/// server cards. Tapping a tile opens the run detail. Hidden until a GitHub
/// account is connected and repos are pinned.
class GithubWorkflowStatusStrip extends ConsumerWidget {
  const GithubWorkflowStatusStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final snapshot = ref.watch(githubRunsProvider).asData?.value;
    if (snapshot == null || snapshot.repos.isEmpty) {
      return const SizedBox.shrink();
    }
    // One tile per pinned repo: its newest run. Older runs of other workflows
    // still count toward the failure badge in the header.
    final latestByRepo =
        <String, ({String owner, String name, WorkflowRun run})>{};
    for (final repo in snapshot.repos) {
      for (final run in repo.runs) {
        final key = '${repo.owner}/${repo.name}';
        final existing = latestByRepo[key];
        if (existing == null || run.id > existing.run.id) {
          latestByRepo[key] = (owner: repo.owner, name: repo.name, run: run);
        }
      }
    }
    final entries = latestByRepo.values.toList()
      ..sort((a, b) => b.run.id.compareTo(a.run.id));
    if (entries.isEmpty) return const SizedBox.shrink();
    final failing = snapshot.failingRuns.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
              child: Row(
                children: [
                  Icon(Symbols.rocket_launch, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'githubRuns'.tr(),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (failing > 0)
                    Text(
                      'githubStatusFailing'.tr(args: ['$failing']),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 340,
                  mainAxisExtent: 112,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                children: [
                  for (final entry in entries)
                    _WorkflowStatusTile(
                      owner: entry.owner,
                      name: entry.name,
                      run: entry.run,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkflowStatusTile extends StatelessWidget {
  const _WorkflowStatusTile({
    required this.owner,
    required this.name,
    required this.run,
  });

  final String owner;
  final String name;
  final WorkflowRun run;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (:icon, :color) = githubRunStatusVisual(
      context,
      run.status,
      run.conclusion,
    );
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => context.router.push(
          GitHubRunDetailRoute(
            owner: owner,
            name: name,
            runId: run.id,
            run: run,
          ),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      run.name.isEmpty ? '$owner/$name' : run.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (run.runNumber > 0)
                    Text(
                      '#${run.runNumber}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                [
                  '$owner/$name',
                  if (run.headBranch.isNotEmpty) run.headBranch,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  run.displayTitle.isEmpty
                      ? 'githubNoRuns'.tr()
                      : run.displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      githubRunDateTime(
                        context,
                        run.updatedAt ?? run.createdAt,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    githubTimeAgo(context, run.updatedAt ?? run.createdAt),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.outline,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
