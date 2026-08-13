import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';

import 'agent/local_mcp_server.dart';
import 'routing/app_router.dart';
import 'shared/presentation/maidkit_window_scaffold.dart';
import 'shared/services/update_service.dart';
import 'servers/server_providers.dart';
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
    });
  }

  /// Runs the update check once the app navigator is ready to host the
  /// update sheet, mirroring Island's startup update flow.
  Future<void> checkForUpdatesWhenReady([int retry = 0]) async {
    final ctx = maidKitNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      await UpdateService().checkForUpdates(ctx);
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
    ref.watch(serverMetricsRefreshSchedulerProvider);
    // Starts the local MCP server when the user enabled it, so other agents
    // can connect right after the app launches.
    ref.watch(localMcpServerProvider);
    IslandUIFoundation.configureOverlay(maidKitOverlayKey);
    IslandUIFoundation.configureNavigator(maidKitNavigatorKey);
    return MaterialApp.router(
      title: 'title'.tr(),
      debugShowCheckedModeBanner: false,
      theme: createMaidKitTheme(Brightness.light, seedColor: appSeedColor),
      darkTheme: createMaidKitTheme(Brightness.dark, seedColor: appSeedColor),
      themeMode: themeMode,
      locale: context.locale,
      supportedLocales: context.supportedLocales,
      localizationsDelegates: [
        ...context.localizationDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: appRouter.config(),
      builder: (context, child) => Overlay(
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
    );
  }
}
