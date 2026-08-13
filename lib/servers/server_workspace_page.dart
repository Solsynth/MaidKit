import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:maid_kit/agent/agent_input_focus.dart';
import 'package:maid_kit/github/github_providers.dart';
import 'package:maid_kit/routing/app_router.dart';
import 'package:maid_kit/routing/app_router.gr.dart';
import 'package:maid_kit/shared/presentation/deploy_terminal.dart';
import 'package:maid_kit/shared/presentation/app_scaffold.dart';
import 'package:styled_widget/styled_widget.dart';
import 'port_forwarding_models.dart';
import 'server_providers.dart';
import 'terminal_tabs_provider.dart';

@RoutePage()
class ServerWorkspacePage extends StatelessWidget {
  const ServerWorkspacePage({super.key});

  @override
  Widget build(BuildContext context) {
    return AutoTabsRouter(
      routes: [
        ServersTab(),
        AssetsTab(),
        ProjectsTab(),
        SnippetsRoute(),
        AgentRoute(),
        MaidCafeRoute(),
        SettingsRoute(),
      ],
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      transitionBuilder: (context, child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      builder: (context, child) => _ServerTabsShell(child: child),
    );
  }
}

class _ServerTabsShell extends ConsumerWidget {
  const _ServerTabsShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabsRouter = AutoTabsRouter.of(context);
    final isDashboardFocused =
        tabsRouter.activeIndex != 0 ||
        ref.watch(
          terminalTabsProvider.select(
            (tabs) => tabs.selectedTab is DashboardTab,
          ),
        );
    final isAgentInputFocused = ref.watch(agentInputFocusedProvider);
    final githubHasFailures = ref.watch(githubHasFailuresProvider);
    final mobileSelectedIndex = tabsRouter.activeIndex == 6
        ? 5
        : tabsRouter.activeIndex == 5
        ? null
        : tabsRouter.activeIndex;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 768;

        return MaidKitAppScaffold(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
          showBackgroundImage: false,
          // Each tab page is its own page scaffold; let it manage the top
          // safe area so its surface paints edge-to-edge behind the status bar.
          topSafeArea: false,
          body: isWide
              ? Row(
                  children: [
                    NavigationRail(
                      backgroundColor: Colors.transparent,
                      selectedIndex: tabsRouter.activeIndex < 6
                          ? tabsRouter.activeIndex
                          : null,
                      onDestinationSelected: tabsRouter.setActiveIndex,
                      trailingAtBottom: true,
                      trailing: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _PortForwardRailIndicator(),
                            const SizedBox(height: 8),
                            const DeploySessionsRailButton(),
                            const SizedBox(height: 8),
                            _CloudAccountRailButton(
                              onPressed: () => tabsRouter.setActiveIndex(6),
                            ),
                            IconButton(
                              tooltip: 'tabSettings'.tr(),
                              onPressed: () => tabsRouter.setActiveIndex(6),
                              icon: const Icon(Symbols.settings),
                            ),
                          ],
                        ),
                      ),
                      destinations: [
                        NavigationRailDestination(
                          icon: const Icon(Symbols.dns),
                          selectedIcon: const Icon(Symbols.dns, fill: 1),
                          label: Text('tabServers').tr(),
                        ),
                        NavigationRailDestination(
                          icon: Badge(
                            isLabelVisible: githubHasFailures,
                            child: const Icon(Symbols.inventory_2),
                          ),
                          selectedIcon: Badge(
                            isLabelVisible: githubHasFailures,
                            child: const Icon(Symbols.inventory_2, fill: 1),
                          ),
                          label: Text('tabAssets').tr(),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Symbols.deployed_code),
                          selectedIcon: const Icon(
                            Symbols.deployed_code,
                            fill: 1,
                          ),
                          label: Text('tabProjects').tr(),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Symbols.code),
                          selectedIcon: const Icon(Symbols.code, fill: 1),
                          label: Text('tabSnippets').tr(),
                        ),
                        const NavigationRailDestination(
                          icon: Icon(Symbols.smart_toy),
                          selectedIcon: Icon(Symbols.smart_toy, fill: 1),
                          label: Text('Agent'),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Symbols.cloud),
                          selectedIcon: const Icon(Symbols.cloud, fill: 1),
                          label: Text('maidCafeTitle').tr(),
                        ),
                      ],
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                        ),
                        child: ColoredBox(
                          color: Theme.of(context).colorScheme.surface,
                          child: child,
                        ),
                      ),
                    ),
                  ],
                )
              : child,
          bottomNavigationBar:
              isWide ||
                  !isDashboardFocused ||
                  isAgentInputFocused ||
                  mobileSelectedIndex == null
              ? null
              : Material(
                  elevation: 0,
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  child: NavigationBar(
                    backgroundColor: Colors.transparent,
                    height: 56,
                    labelBehavior:
                        NavigationDestinationLabelBehavior.alwaysHide,
                    selectedIndex: mobileSelectedIndex,
                    onDestinationSelected: tabsRouter.setActiveIndex,
                    destinations: [
                      NavigationDestination(
                        icon: const Icon(Symbols.dns),
                        selectedIcon: const Icon(Symbols.dns, fill: 1),
                        label: 'tabServers'.tr(),
                      ),
                      NavigationDestination(
                        icon: Badge(
                          isLabelVisible: githubHasFailures,
                          child: const Icon(Symbols.inventory_2),
                        ),
                        selectedIcon: Badge(
                          isLabelVisible: githubHasFailures,
                          child: const Icon(Symbols.inventory_2, fill: 1),
                        ),
                        label: 'tabAssets'.tr(),
                      ),
                      NavigationDestination(
                        icon: const Icon(Symbols.deployed_code),
                        selectedIcon: const Icon(
                          Symbols.deployed_code,
                          fill: 1,
                        ),
                        label: 'tabProjects'.tr(),
                      ),
                      NavigationDestination(
                        icon: const Icon(Symbols.code),
                        selectedIcon: const Icon(Symbols.code, fill: 1),
                        label: 'tabSnippets'.tr(),
                      ),
                      const NavigationDestination(
                        icon: Icon(Symbols.smart_toy),
                        selectedIcon: Icon(Symbols.smart_toy, fill: 1),
                        label: 'Agent',
                      ),
                      NavigationDestination(
                        icon: const Icon(Symbols.settings, fill: 1),
                        selectedIcon: const Icon(Symbols.settings),
                        label: 'tabSettings'.tr(),
                      ),
                    ],
                  ).padding(horizontal: 16),
                ),
        );
      },
    );
  }
}

class _CloudAccountRailButton extends ConsumerWidget {
  const _CloudAccountRailButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(cloudUserProvider).asData?.value;
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: 'settingsAccount'.tr(),
      onPressed: onPressed,
      icon: CircleAvatar(
        radius: 14,
        backgroundColor: scheme.surfaceContainerHighest,
        foregroundImage: user?.avatarUrl == null
            ? null
            : NetworkImage(user!.avatarUrl!),
        child: user == null
            ? const Icon(Symbols.person, size: 18)
            : Text(
                user.initials,
                style: Theme.of(context).textTheme.labelSmall,
              ),
      ),
    );
  }
}

class _PortForwardRailIndicator extends ConsumerWidget {
  const _PortForwardRailIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forwards = ref.watch(portForwardsProvider).asData?.value ?? const [];
    if (forwards.isEmpty) return const SizedBox.shrink();
    return Badge(
      label: Text('portForwardCount').tr(args: ['${forwards.length}']),
      child: PopupMenuButton<ActivePortForward>(
        tooltip: 'activePortForwards'.plural(forwards.length),
        icon: const Icon(Symbols.swap_horiz),
        onSelected: (forward) =>
            ref.read(connectionManagerProvider).stopPortForward(forward.id),
        itemBuilder: (context) => [
          for (final forward in forwards)
            PopupMenuItem(
              value: forward,
              child: SizedBox(
                width: 260,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Symbols.swap_horiz),
                  title: Text(forward.serverName),
                  subtitle: Text(forward.summary),
                  trailing: const Icon(Symbols.stop_circle),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
