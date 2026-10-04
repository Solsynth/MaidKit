import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';

import 'sessions_page.dart';

/// The app's home route: the pane tab workspace.
///
/// Every destination lives in this one tab strip — the servers dashboard,
/// terminals, file management, agent chats, saved assets, deployment projects,
/// the MaidCafe cloud console and settings. Detail pages pushed from a tab stay
/// inside that tab, and panes can still be split, dragged and rearranged.
@RoutePage()
class ServerWorkspacePage extends StatelessWidget {
  const ServerWorkspacePage({super.key});

  @override
  Widget build(BuildContext context) => const SessionsWorkspace();
}
