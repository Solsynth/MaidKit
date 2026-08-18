import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart' hide GlobalMaterialLocalizations;
import 'package:material_ui/material_ui.dart'
    as material_ui
    show GlobalMaterialLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';

import 'agent/local_mcp_server.dart';
import 'routing/app_router.dart';
import 'shared/presentation/maidkit_window_scaffold.dart';
import 'package:solsynth_express/solsynth_express.dart';
import 'servers/server_providers.dart';
import 'shared/services/analytics_service.dart';
import 'shared/services/update_preferences.dart';
import 'servers/startup_connection_bootstrap.dart';
import 'servers/tailscale_auto_connect.dart';
import 'servers/vault_gate.dart';
import 'theme.dart';

final maidKitOverlayKey = GlobalKey<OverlayState>();

class MaidKitApp extends ConsumerStatefulWidget {
  const MaidKitApp({super.key});

  @override
  ConsumerState<MaidKitApp> createState() => _MaidKitAppState();
}

class _MaidKitAppState extends ConsumerState<MaidKitApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    // MCP servers run as child processes. Riverpod's onDispose never fires on
    // a non-autoDispose provider, so kill them when the app actually exits;
    // otherwise npx/uvx children outlive MaidKit.
    _lifecycleListener = AppLifecycleListener(
      onDetach: () => ref.read(mcpClientManagerProvider).disposeAll(),
    );
    // The router navigator only builds once the vault gate is unlocked, so
    // retry until a context is available (up to ~60s).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(checkForUpdatesWhenReady());
      MaidKitAnalytics.instance.logAppOpen();
    });
  }

  /// Runs the update check once the app navigator is ready to host the
  Future<void> checkForUpdatesWhenReady([int retry = 0]) async {
    final ctx = maidKitNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      final updateChecksEnabled = await ref.read(
        maidKitUpdateChecksEnabledProvider.future,
      );
      final updateChannel = await ref.read(maidKitUpdateChannelProvider.future);
      if (!mounted || !ctx.mounted) return;
      await UpdateService(
        apiBaseUrl: kMaidKitDistributionApiBaseUrl,
        channel: updateChannel,
        productId: kMaidKitDistributionProductId,
        enabled: updateChecksEnabled,
      ).checkForUpdates(ctx);
      return;
    }
    if (retry >= 120) return;
    await Future.delayed(const Duration(milliseconds: 500));
    await checkForUpdatesWhenReady(retry + 1);
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appRouter = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    final appSeedColor = ref.watch(appSeedColorProvider);
    final appUiScale = ref.watch(appUiScaleProvider);
    ref.watch(serverMetricsRefreshSchedulerProvider);
    // Starts the local MCP server when the user enabled it, so other agents
    // can connect right after the app launches.
    ref.watch(localMcpServerProvider);
    // Keeps the MaidCafe FCM push subscription alive (and subscribing on
    // sign-in) for the whole app session.
    ref.watch(maidCafePushProvider);
    IslandUIFoundation.configureOverlay(maidKitOverlayKey);
    IslandUIFoundation.configureNavigator(maidKitNavigatorKey);
    return MaterialApp.router(
      title: 'title'.tr(),
      debugShowCheckedModeBanner: true,
      theme: createMaidKitTheme(Brightness.light, seedColor: appSeedColor),
      darkTheme: createMaidKitTheme(Brightness.dark, seedColor: appSeedColor),
      themeMode: themeMode,
      localizationsDelegates: [
        ...context.localizationDelegates,
        ...material_ui.GlobalMaterialLocalizations.delegates,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: appRouter.config(),
      // This bridge is required while legacy Flutter widgets remain in the
      // app and in third-party dependencies.
      builder: (context, child) => MaidKitUiScale(
        scale: appUiScale,
        // ignore: deprecated_member_use
        child: MaterialUiCompatibilityBridge(
          child: Overlay(
            key: maidKitOverlayKey,
            initialEntries: [
              OverlayEntry(
                builder: (context) => MaidKitWindowScaffold(
                  title: 'title'.tr(),
                  // The gate needs a Navigator for standard Material controls
                  // such as a dropdown. The app router remains below it and is
                  // only exposed once the vault unlocks.
                  child: Navigator(
                    onGenerateRoute: (settings) => MaterialPageRoute<void>(
                      settings: settings,
                      builder: (context) => VaultGate(
                        child: StartupConnectionBootstrap(
                          child: TailscaleAutoConnect(
                            child: child ?? const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
