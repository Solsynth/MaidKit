import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'deployment_project_models.dart';

final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  return ProjectRepository(ref.watch(databaseProvider));
});

final deploymentProjectsProvider = StreamProvider<List<DeploymentProject>>(
  (ref) => ref.watch(projectRepositoryProvider).watchProjects(),
);

final deploymentResourcesProvider = StreamProvider<List<DeploymentResource>>(
  (ref) => ref.watch(projectRepositoryProvider).watchResources(),
);

class ProjectRepository {
  ProjectRepository(this._database);

  final AppDatabase _database;

  Stream<List<DeploymentProject>> watchProjects() =>
      _database.watchDeploymentProjects();

  Stream<List<DeploymentResource>> watchResources() =>
      _database.watchDeploymentResources();

  Future<int> createProject({required String name, String? description}) {
    final now = DateTime.now().toUtc();
    final normalizedDescription = description?.trim();
    return _database
        .into(_database.deploymentProjects)
        .insert(
          DeploymentProjectsCompanion.insert(
            name: name.trim(),
            description: Value(
              normalizedDescription == null || normalizedDescription.isEmpty
                  ? null
                  : normalizedDescription,
            ),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<void> updateProject({
    required int projectId,
    required String name,
    String? description,
  }) async {
    final normalizedDescription = description?.trim();
    await (_database.update(
      _database.deploymentProjects,
    )..where((table) => table.id.equals(projectId))).write(
      DeploymentProjectsCompanion(
        name: Value(name.trim()),
        description: Value(
          normalizedDescription == null || normalizedDescription.isEmpty
              ? null
              : normalizedDescription,
        ),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> addResource({
    required int projectId,
    required String kind,
    required String name,
    int? serverId,
    Map<String, Object?> configuration = const {},
  }) async {
    final now = DateTime.now().toUtc();
    await _database
        .into(_database.deploymentResources)
        .insert(
          DeploymentResourcesCompanion.insert(
            projectId: projectId,
            kind: kind,
            name: name.trim(),
            serverId: Value(serverId),
            configuration: Value(jsonEncode(configuration)),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await (_database.update(_database.deploymentProjects)
          ..where((table) => table.id.equals(projectId)))
        .write(DeploymentProjectsCompanion(updatedAt: Value(now)));
  }

  Future<void> updateResource({
    required int resourceId,
    required String kind,
    required String name,
    required int? serverId,
    required Map<String, Object?> configuration,
  }) async {
    final resource = await (_database.select(
      _database.deploymentResources,
    )..where((table) => table.id.equals(resourceId))).getSingleOrNull();
    if (resource == null) return;

    final now = DateTime.now().toUtc();
    await _database.transaction(() async {
      await (_database.update(
        _database.deploymentResources,
      )..where((table) => table.id.equals(resourceId))).write(
        DeploymentResourcesCompanion(
          kind: Value(kind),
          name: Value(name.trim()),
          serverId: Value(serverId),
          configuration: Value(jsonEncode(configuration)),
          updatedAt: Value(now),
        ),
      );
      await (_database.update(_database.deploymentProjects)
            ..where((table) => table.id.equals(resource.projectId)))
          .write(DeploymentProjectsCompanion(updatedAt: Value(now)));
    });
  }

  Future<void> deleteProject(int projectId) async {
    await _database.transaction(() async {
      await (_database.delete(
        _database.deploymentResources,
      )..where((table) => table.projectId.equals(projectId))).go();
      await (_database.delete(
        _database.deploymentProjects,
      )..where((table) => table.id.equals(projectId))).go();
    });
  }

  Future<void> deleteResource(int resourceId) async {
    final resource = await (_database.select(
      _database.deploymentResources,
    )..where((table) => table.id.equals(resourceId))).getSingleOrNull();
    await (_database.delete(
      _database.deploymentResources,
    )..where((table) => table.id.equals(resourceId))).go();
    if (resource == null) return;
    await (_database.update(
      _database.deploymentProjects,
    )..where((table) => table.id.equals(resource.projectId))).write(
      DeploymentProjectsCompanion(updatedAt: Value(DateTime.now().toUtc())),
    );
  }

  Future<String> exportToml() async {
    final projects = await _database.select(_database.deploymentProjects).get();
    final resources = await _database
        .select(_database.deploymentResources)
        .get();
    final buffer = StringBuffer(
      '# MaidKit deployment catalog\nformat_version = 1\n',
    );
    for (final project in projects) {
      buffer
        ..write('\n[[projects]]\nname = ${_tomlString(project.name)}\n')
        ..write('description = ${_tomlString(project.description ?? '')}\n');
      for (final resource in resources.where(
        (item) => item.projectId == project.id,
      )) {
        buffer
          ..write('[[projects.resources]]\n')
          ..write('kind = ${_tomlString(resource.kind)}\n')
          ..write('name = ${_tomlString(resource.name)}\n');
        if (resource.serverId != null) {
          buffer.write('server_id = ${resource.serverId}\n');
        }
        buffer.write(
          'configuration_json = ${_tomlString(resource.configuration)}\n',
        );
      }
    }
    return buffer.toString();
  }

  /// Imports the intentionally small TOML dialect produced by [exportToml].
  /// Existing catalog data is retained; importing the same file creates a new
  /// portable bundle so it can be edited before deployment.
  Future<int> importToml(String source) async {
    final parsed = _parseToml(source);
    var imported = 0;
    await _database.transaction(() async {
      for (final bundle in parsed) {
        final projectId = await createProject(
          name: bundle.name,
          description: bundle.description,
        );
        for (final resource in bundle.resources) {
          await addResource(
            projectId: projectId,
            kind: resource.kind,
            name: resource.name,
            serverId: resource.serverId,
            configuration: resource.configuration,
          );
        }
        imported++;
      }
    });
    return imported;
  }
}

String _tomlString(String value) => jsonEncode(value);

List<DeploymentProjectBundle> _parseToml(String source) {
  final projects = <DeploymentProjectBundle>[];
  String? name;
  String? description;
  final resources = <DeploymentResourceBundle>[];
  String? resourceKind;
  String? resourceName;
  int? resourceServerId;
  Map<String, Object?> resourceConfiguration = const {};

  void commitResource() {
    if (resourceKind == null || resourceName == null) return;
    resources.add(
      DeploymentResourceBundle(
        kind: resourceKind!,
        name: resourceName!,
        serverId: resourceServerId,
        configuration: resourceConfiguration,
      ),
    );
    resourceKind = null;
    resourceName = null;
    resourceServerId = null;
    resourceConfiguration = const {};
  }

  void commitProject() {
    commitResource();
    if (name == null || name!.trim().isEmpty) return;
    projects.add(
      DeploymentProjectBundle(
        name: name!,
        description: description?.isEmpty ?? true ? null : description,
        resources: List.of(resources),
      ),
    );
    resources.clear();
    name = null;
    description = null;
  }

  for (final raw in const LineSplitter().convert(source)) {
    final line = raw.trim();
    if (line.isEmpty ||
        line.startsWith('#') ||
        line.startsWith('format_version')) {
      continue;
    }
    if (line == '[[projects]]') {
      commitProject();
      continue;
    }
    if (line == '[[projects.resources]]') {
      commitResource();
      continue;
    }
    final split = line.indexOf('=');
    if (split < 1) continue;
    final key = line.substring(0, split).trim();
    final value = line.substring(split + 1).trim();
    final decoded = value.startsWith('"') ? jsonDecode(value) : value;
    switch (key) {
      case 'name':
        if (resourceKind == null) {
          name = '$decoded';
        } else {
          resourceName = '$decoded';
        }
      case 'description':
        description = '$decoded';
      case 'kind':
        resourceKind = '$decoded';
      case 'server_id':
        resourceServerId = int.tryParse('$decoded');
      case 'configuration_json':
        final config = jsonDecode('$decoded');
        if (config is Map) {
          resourceConfiguration = config.map(
            (key, value) => MapEntry('$key', value),
          );
        }
    }
  }
  commitProject();
  if (projects.isEmpty) {
    throw const FormatException('No MaidKit projects found in TOML.');
  }
  return projects;
}
