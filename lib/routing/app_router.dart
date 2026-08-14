// Shell route consts follow the generated-route naming style.
// ignore_for_file: constant_identifier_names
import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'app_router.gr.dart';

final maidKitNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<AppRouter>(
  (ref) => AppRouter(navigatorKey: maidKitNavigatorKey),
);

/// Tab shells that host nested detail routes. Each renders an [AutoRouter]
/// outlet, so pushed detail pages (project, compose, container, server, GitHub
/// run) stay inside their tab's stack and the tab chrome (rail / bottom
/// navigation) remains switchable while inspecting them.
const ServersTab = EmptyShellRoute('ServersTab');
const AssetsTab = EmptyShellRoute('AssetsTab');
const ProjectsTab = EmptyShellRoute('ProjectsTab');

/// Detail pages opened from within a tab. Declared under every shell tab so
/// cross-links (e.g. opening a server detail from a project detail) resolve
/// against the tab the user is currently inspecting.
List<AutoRoute> _detailRoutes() => [
  AutoRoute(page: ProjectDetailRoute.page, path: 'project-detail'),
  AutoRoute(page: ComposeDetailRoute.page, path: 'compose-detail'),
  AutoRoute(page: ContainerDetailRoute.page, path: 'container-detail'),
  AutoRoute(page: GitHubRunDetailRoute.page, path: 'github-run-detail'),
  AutoRoute(page: ServerDetailRoute.page, path: 'server-detail'),
];

@AutoRouterConfig(replaceInRouteName: 'Page,Route')
class AppRouter extends RootStackRouter {
  AppRouter({super.navigatorKey});

  @override
  List<AutoRoute> get routes => [
    AutoRoute(
      page: ServerWorkspaceRoute.page,
      initial: true,
      children: [
        AutoRoute(
          page: ServersTab.page,
          path: '',
          initial: true,
          children: [
            AutoRoute(page: ServersRoute.page, path: '', initial: true),
            ..._detailRoutes(),
          ],
        ),
        AutoRoute(
          page: AssetsTab.page,
          path: 'assets',
          children: [
            AutoRoute(page: AssetsRoute.page, path: '', initial: true),
            ..._detailRoutes(),
          ],
        ),
        AutoRoute(
          page: ProjectsTab.page,
          path: 'projects',
          children: [
            AutoRoute(page: ProjectsRoute.page, path: '', initial: true),
            ..._detailRoutes(),
          ],
        ),
        AutoRoute(page: AgentRoute.page, path: 'agent'),
        AutoRoute(page: MaidCafeRoute.page, path: 'maidcafe'),
        AutoRoute(page: SettingsRoute.page, path: 'settings'),
      ],
    ),
    AutoRoute(page: AboutRoute.page, path: '/about'),
  ];
}
