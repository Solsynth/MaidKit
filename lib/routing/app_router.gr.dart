// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:auto_route/auto_route.dart' as _i15;
import 'package:maid_kit/agent/agent_page.dart' as _i2;
import 'package:maid_kit/containers/compose_detail_page.dart' as _i4;
import 'package:maid_kit/containers/container_detail_page.dart' as _i5;
import 'package:maid_kit/containers/container_models.dart' as _i18;
import 'package:maid_kit/containers/project_detail_page.dart' as _i9;
import 'package:maid_kit/containers/projects_page.dart' as _i10;
import 'package:maid_kit/data/local/app_database.dart' as _i17;
import 'package:maid_kit/github/github_models.dart' as _i19;
import 'package:maid_kit/github/github_run_detail_page.dart' as _i6;
import 'package:maid_kit/servers/about_page.dart' as _i1;
import 'package:maid_kit/servers/assets_page.dart' as _i3;
import 'package:maid_kit/servers/maidcafe_cloud_page.dart' as _i7;
import 'package:maid_kit/servers/maidcafe_daemon_detail_page.dart' as _i8;
import 'package:maid_kit/servers/maidcafe_service.dart' as _i20;
import 'package:maid_kit/servers/server_detail_page.dart' as _i11;
import 'package:maid_kit/servers/server_workspace_page.dart' as _i12;
import 'package:maid_kit/servers/servers_page.dart' as _i13;
import 'package:maid_kit/servers/settings_page.dart' as _i14;
import 'package:material_ui/material_ui.dart' as _i16;

/// generated route for
/// [_i1.AboutPage]
class AboutRoute extends _i15.PageRouteInfo<void> {
  const AboutRoute({List<_i15.PageRouteInfo>? children})
    : super(AboutRoute.name, initialChildren: children);

  static const String name = 'AboutRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      return const _i1.AboutPage();
    },
  );
}

/// generated route for
/// [_i2.AgentPage]
class AgentRoute extends _i15.PageRouteInfo<void> {
  const AgentRoute({List<_i15.PageRouteInfo>? children})
    : super(AgentRoute.name, initialChildren: children);

  static const String name = 'AgentRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      return const _i2.AgentPage();
    },
  );
}

/// generated route for
/// [_i3.AssetsPage]
class AssetsRoute extends _i15.PageRouteInfo<void> {
  const AssetsRoute({List<_i15.PageRouteInfo>? children})
    : super(AssetsRoute.name, initialChildren: children);

  static const String name = 'AssetsRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      return const _i3.AssetsPage();
    },
  );
}

/// generated route for
/// [_i4.ComposeDetailPage]
class ComposeDetailRoute extends _i15.PageRouteInfo<ComposeDetailRouteArgs> {
  ComposeDetailRoute({
    _i16.Key? key,
    required _i17.Server server,
    required _i18.ContainerRuntime runtime,
    required _i18.ContainerScope scope,
    required String projectName,
    required String directory,
    List<_i15.PageRouteInfo>? children,
  }) : super(
         ComposeDetailRoute.name,
         args: ComposeDetailRouteArgs(
           key: key,
           server: server,
           runtime: runtime,
           scope: scope,
           projectName: projectName,
           directory: directory,
         ),
         initialChildren: children,
       );

  static const String name = 'ComposeDetailRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<ComposeDetailRouteArgs>();
      return _i4.ComposeDetailPage(
        key: args.key,
        server: args.server,
        runtime: args.runtime,
        scope: args.scope,
        projectName: args.projectName,
        directory: args.directory,
      );
    },
  );
}

class ComposeDetailRouteArgs {
  const ComposeDetailRouteArgs({
    this.key,
    required this.server,
    required this.runtime,
    required this.scope,
    required this.projectName,
    required this.directory,
  });

  final _i16.Key? key;

  final _i17.Server server;

  final _i18.ContainerRuntime runtime;

  final _i18.ContainerScope scope;

  final String projectName;

  final String directory;

  @override
  String toString() {
    return 'ComposeDetailRouteArgs{key: $key, server: $server, runtime: $runtime, scope: $scope, projectName: $projectName, directory: $directory}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ComposeDetailRouteArgs) return false;
    return key == other.key &&
        server == other.server &&
        runtime == other.runtime &&
        scope == other.scope &&
        projectName == other.projectName &&
        directory == other.directory;
  }

  @override
  int get hashCode =>
      key.hashCode ^
      server.hashCode ^
      runtime.hashCode ^
      scope.hashCode ^
      projectName.hashCode ^
      directory.hashCode;
}

/// generated route for
/// [_i5.ContainerDetailPage]
class ContainerDetailRoute
    extends _i15.PageRouteInfo<ContainerDetailRouteArgs> {
  ContainerDetailRoute({
    _i16.Key? key,
    required _i17.Server server,
    required _i18.ContainerRuntime runtime,
    required _i18.ContainerScope scope,
    required String containerId,
    required String containerName,
    List<_i15.PageRouteInfo>? children,
  }) : super(
         ContainerDetailRoute.name,
         args: ContainerDetailRouteArgs(
           key: key,
           server: server,
           runtime: runtime,
           scope: scope,
           containerId: containerId,
           containerName: containerName,
         ),
         initialChildren: children,
       );

  static const String name = 'ContainerDetailRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<ContainerDetailRouteArgs>();
      return _i5.ContainerDetailPage(
        key: args.key,
        server: args.server,
        runtime: args.runtime,
        scope: args.scope,
        containerId: args.containerId,
        containerName: args.containerName,
      );
    },
  );
}

class ContainerDetailRouteArgs {
  const ContainerDetailRouteArgs({
    this.key,
    required this.server,
    required this.runtime,
    required this.scope,
    required this.containerId,
    required this.containerName,
  });

  final _i16.Key? key;

  final _i17.Server server;

  final _i18.ContainerRuntime runtime;

  final _i18.ContainerScope scope;

  final String containerId;

  final String containerName;

  @override
  String toString() {
    return 'ContainerDetailRouteArgs{key: $key, server: $server, runtime: $runtime, scope: $scope, containerId: $containerId, containerName: $containerName}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ContainerDetailRouteArgs) return false;
    return key == other.key &&
        server == other.server &&
        runtime == other.runtime &&
        scope == other.scope &&
        containerId == other.containerId &&
        containerName == other.containerName;
  }

  @override
  int get hashCode =>
      key.hashCode ^
      server.hashCode ^
      runtime.hashCode ^
      scope.hashCode ^
      containerId.hashCode ^
      containerName.hashCode;
}

/// generated route for
/// [_i6.GitHubRunDetailPage]
class GitHubRunDetailRoute
    extends _i15.PageRouteInfo<GitHubRunDetailRouteArgs> {
  GitHubRunDetailRoute({
    _i16.Key? key,
    required String owner,
    required String name,
    required int runId,
    required _i19.WorkflowRun run,
    List<_i15.PageRouteInfo>? children,
  }) : super(
         GitHubRunDetailRoute.name,
         args: GitHubRunDetailRouteArgs(
           key: key,
           owner: owner,
           name: name,
           runId: runId,
           run: run,
         ),
         initialChildren: children,
       );

  static const String name = 'GitHubRunDetailRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<GitHubRunDetailRouteArgs>();
      return _i6.GitHubRunDetailPage(
        key: args.key,
        owner: args.owner,
        name: args.name,
        runId: args.runId,
        run: args.run,
      );
    },
  );
}

class GitHubRunDetailRouteArgs {
  const GitHubRunDetailRouteArgs({
    this.key,
    required this.owner,
    required this.name,
    required this.runId,
    required this.run,
  });

  final _i16.Key? key;

  final String owner;

  final String name;

  final int runId;

  final _i19.WorkflowRun run;

  @override
  String toString() {
    return 'GitHubRunDetailRouteArgs{key: $key, owner: $owner, name: $name, runId: $runId, run: $run}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! GitHubRunDetailRouteArgs) return false;
    return key == other.key &&
        owner == other.owner &&
        name == other.name &&
        runId == other.runId &&
        run == other.run;
  }

  @override
  int get hashCode =>
      key.hashCode ^
      owner.hashCode ^
      name.hashCode ^
      runId.hashCode ^
      run.hashCode;
}

/// generated route for
/// [_i7.MaidCafeCloudPage]
class MaidCafeCloudRoute extends _i15.PageRouteInfo<void> {
  const MaidCafeCloudRoute({List<_i15.PageRouteInfo>? children})
    : super(MaidCafeCloudRoute.name, initialChildren: children);

  static const String name = 'MaidCafeCloudRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      return const _i7.MaidCafeCloudPage();
    },
  );
}

/// generated route for
/// [_i8.MaidCafeDaemonDetailPage]
class MaidCafeDaemonDetailRoute
    extends _i15.PageRouteInfo<MaidCafeDaemonDetailRouteArgs> {
  MaidCafeDaemonDetailRoute({
    _i16.Key? key,
    required _i20.MaidCafeDaemon daemon,
    List<_i15.PageRouteInfo>? children,
  }) : super(
         MaidCafeDaemonDetailRoute.name,
         args: MaidCafeDaemonDetailRouteArgs(key: key, daemon: daemon),
         initialChildren: children,
       );

  static const String name = 'MaidCafeDaemonDetailRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<MaidCafeDaemonDetailRouteArgs>();
      return _i8.MaidCafeDaemonDetailPage(key: args.key, daemon: args.daemon);
    },
  );
}

class MaidCafeDaemonDetailRouteArgs {
  const MaidCafeDaemonDetailRouteArgs({this.key, required this.daemon});

  final _i16.Key? key;

  final _i20.MaidCafeDaemon daemon;

  @override
  String toString() {
    return 'MaidCafeDaemonDetailRouteArgs{key: $key, daemon: $daemon}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! MaidCafeDaemonDetailRouteArgs) return false;
    return key == other.key && daemon == other.daemon;
  }

  @override
  int get hashCode => key.hashCode ^ daemon.hashCode;
}

/// generated route for
/// [_i9.ProjectDetailPage]
class ProjectDetailRoute extends _i15.PageRouteInfo<ProjectDetailRouteArgs> {
  ProjectDetailRoute({
    _i16.Key? key,
    int? projectId,
    int? linkId,
    List<_i15.PageRouteInfo>? children,
  }) : super(
         ProjectDetailRoute.name,
         args: ProjectDetailRouteArgs(
           key: key,
           projectId: projectId,
           linkId: linkId,
         ),
         initialChildren: children,
       );

  static const String name = 'ProjectDetailRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<ProjectDetailRouteArgs>(
        orElse: () => const ProjectDetailRouteArgs(),
      );
      return _i9.ProjectDetailPage(
        key: args.key,
        projectId: args.projectId,
        linkId: args.linkId,
      );
    },
  );
}

class ProjectDetailRouteArgs {
  const ProjectDetailRouteArgs({this.key, this.projectId, this.linkId});

  final _i16.Key? key;

  final int? projectId;

  final int? linkId;

  @override
  String toString() {
    return 'ProjectDetailRouteArgs{key: $key, projectId: $projectId, linkId: $linkId}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ProjectDetailRouteArgs) return false;
    return key == other.key &&
        projectId == other.projectId &&
        linkId == other.linkId;
  }

  @override
  int get hashCode => key.hashCode ^ projectId.hashCode ^ linkId.hashCode;
}

/// generated route for
/// [_i10.ProjectsPage]
class ProjectsRoute extends _i15.PageRouteInfo<void> {
  const ProjectsRoute({List<_i15.PageRouteInfo>? children})
    : super(ProjectsRoute.name, initialChildren: children);

  static const String name = 'ProjectsRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      return const _i10.ProjectsPage();
    },
  );
}

/// generated route for
/// [_i11.ServerDetailPage]
class ServerDetailRoute extends _i15.PageRouteInfo<ServerDetailRouteArgs> {
  ServerDetailRoute({
    _i16.Key? key,
    required _i17.Server server,
    int initialTab = 0,
    String? initialComposeProject,
    bool embedded = false,
    List<_i15.PageRouteInfo>? children,
  }) : super(
         ServerDetailRoute.name,
         args: ServerDetailRouteArgs(
           key: key,
           server: server,
           initialTab: initialTab,
           initialComposeProject: initialComposeProject,
           embedded: embedded,
         ),
         initialChildren: children,
       );

  static const String name = 'ServerDetailRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<ServerDetailRouteArgs>();
      return _i11.ServerDetailPage(
        key: args.key,
        server: args.server,
        initialTab: args.initialTab,
        initialComposeProject: args.initialComposeProject,
        embedded: args.embedded,
      );
    },
  );
}

class ServerDetailRouteArgs {
  const ServerDetailRouteArgs({
    this.key,
    required this.server,
    this.initialTab = 0,
    this.initialComposeProject,
    this.embedded = false,
  });

  final _i16.Key? key;

  final _i17.Server server;

  final int initialTab;

  final String? initialComposeProject;

  final bool embedded;

  @override
  String toString() {
    return 'ServerDetailRouteArgs{key: $key, server: $server, initialTab: $initialTab, initialComposeProject: $initialComposeProject, embedded: $embedded}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ServerDetailRouteArgs) return false;
    return key == other.key &&
        server == other.server &&
        initialTab == other.initialTab &&
        initialComposeProject == other.initialComposeProject &&
        embedded == other.embedded;
  }

  @override
  int get hashCode =>
      key.hashCode ^
      server.hashCode ^
      initialTab.hashCode ^
      initialComposeProject.hashCode ^
      embedded.hashCode;
}

/// generated route for
/// [_i12.ServerWorkspacePage]
class ServerWorkspaceRoute extends _i15.PageRouteInfo<void> {
  const ServerWorkspaceRoute({List<_i15.PageRouteInfo>? children})
    : super(ServerWorkspaceRoute.name, initialChildren: children);

  static const String name = 'ServerWorkspaceRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      return const _i12.ServerWorkspacePage();
    },
  );
}

/// generated route for
/// [_i13.ServersPage]
class ServersRoute extends _i15.PageRouteInfo<void> {
  const ServersRoute({List<_i15.PageRouteInfo>? children})
    : super(ServersRoute.name, initialChildren: children);

  static const String name = 'ServersRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      return const _i13.ServersPage();
    },
  );
}

/// generated route for
/// [_i14.SettingsPage]
class SettingsRoute extends _i15.PageRouteInfo<void> {
  const SettingsRoute({List<_i15.PageRouteInfo>? children})
    : super(SettingsRoute.name, initialChildren: children);

  static const String name = 'SettingsRoute';

  static _i15.PageInfo page = _i15.PageInfo(
    name,
    builder: (data) {
      return const _i14.SettingsPage();
    },
  );
}
