import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'deployment_project_models.dart';

/// Compact overview of the portable deployment catalog. The Compose workspace
/// below remains available for live container operations.
class DeploymentCatalogStrip extends StatelessWidget {
  const DeploymentCatalogStrip({
    super.key,
    required this.projects,
    required this.resources,
  });

  final List<DeploymentProject> projects;
  final List<DeploymentResource> resources;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxHeight: 112),
      padding: const EdgeInsets.fromLTRB(24, 10, 16, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: projects.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final project = projects[index];
          final items = resources
              .where((resource) => resource.projectId == project.id)
              .toList();
          final kinds = <DeploymentResourceKind>{
            for (final item in items) deploymentResourceKindFromId(item.kind),
          };
          return Container(
            width: 240,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Symbols.deployed_code, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        items.isEmpty
                            ? 'No resources yet'
                            : '${items.length} resource${items.length == 1 ? '' : 's'} · ${kinds.map((kind) => kind.name).join(', ')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
