import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'app_router.gr.dart';

final maidKitNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<AppRouter>(
  (ref) => AppRouter(navigatorKey: maidKitNavigatorKey),
);

/// The app has a single route: the pane tab workspace.
///
/// Destinations are tabs inside that workspace rather than separate routes, so
/// there is no tab router and no per-destination route stack. A detail page
/// opened from a tab is pushed onto that tab's own stack (see
/// `shared/presentation/tab_navigator.dart`), which keeps it inside the tab it
/// was opened from.
@AutoRouterConfig(replaceInRouteName: 'Page,Route')
class AppRouter extends RootStackRouter {
  AppRouter({super.navigatorKey});

  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: ServerWorkspaceRoute.page, initial: true),
  ];
}
