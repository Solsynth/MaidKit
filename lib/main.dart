import 'dart:async';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:drift/drift.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'servers/window_state_preferences.dart';
import 'servers/window_placement.dart';
import 'shared/presentation/app_scaffold.dart';
import 'servers/server_providers.dart';
import 'servers/app_theme_preferences.dart';
import 'servers/metrics_refresh_preferences.dart';
import 'servers/terminal_adapter_preferences.dart';
import 'servers/startup_connection_preferences.dart';
import 'servers/transfer_conflict_preferences.dart';
import 'servers/workspace_restore_preferences.dart';
import 'servers/terminal_tabs_provider.dart';
import 'servers/privacy_preferences.dart';
import 'firebase_options.dart';
import 'servers/maidcafe_preferences.dart';
import 'servers/maidcafe_push.dart';
import 'shared/services/analytics_service.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // The Solarpass sign-in flow opens an in-app WebView2 window
  // (flutter_web_auth_2 -> desktop_webview_window). On Windows that window's
  // title bar is rendered by a second in-process Flutter engine, which only
  // registers the webview plugin. That engine re-enters this entrypoint with
  // ['web_view_title_bar', <id>] and must run the title-bar app instead of the
  // full startup below; otherwise window_manager (and other plugins) are
  // missing and the app crashes with a MissingPluginException.
  if (runWebViewTitleBarWidget(args)) {
    return;
  }

  // Each selected vault uses its own SQLite file and executor. Drift's debug
  // warning is type-based, so it cannot distinguish these independent files.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  await EasyLocalization.ensureInitialized();
  EasyLocalization.logger.enableBuildModes = [];
  // Firebase for MaidCafe cloud notifications and analytics (Android/iOS/
  // macOS only; firebase_core has no Linux/Windows/web support here). The
  // background handler must be registered before any message can be received
  // in a terminated app.
  if (firebaseSupported()) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    MaidKitAnalytics.instance.initialize();
  }
  final preferences = await Future.wait([
    TerminalAdapterPreferences.load(),
    StartupConnectionPreferences.load(),
    MetricsRefreshPreferences.load(),
    AppThemePreferences.load(),
    PrivacyPreferences.load(),
    MaidCafePreferences.load(),
    TransferConflictPreferences.load(),
    WorkspaceRestorePreferences.load(),
  ]);
  final terminalAdapterPreferences =
      preferences[0] as TerminalAdapterPreferences;
  final startupConnectionPreferences =
      preferences[1] as StartupConnectionPreferences;
  final metricsRefreshPreferences = preferences[2] as MetricsRefreshPreferences;
  final appThemePreferences = preferences[3] as AppThemePreferences;
  final privacyPreferences = preferences[4] as PrivacyPreferences;
  final maidCafePreferences = preferences[5] as MaidCafePreferences;
  final transferConflictPreferences =
      preferences[6] as TransferConflictPreferences;
  final workspaceRestorePreferences =
      preferences[7] as WorkspaceRestorePreferences;

  // The legacy vault is an SQLite file in the documents directory, which a
  // browser does not have; there is nothing on disk to migrate there.
  if (!kIsWeb) {
    await migrateLegacyVault(defaultName: 'Primary Vault');
  }

  final container = ProviderContainer(
    overrides: [
      terminalAdapterPreferencesProvider.overrideWithValue(
        terminalAdapterPreferences,
      ),
      startupConnectionSettingsProvider.overrideWithValue(
        startupConnectionPreferences,
      ),
      metricsRefreshSettingsProvider.overrideWithValue(
        metricsRefreshPreferences,
      ),
      appThemeSettingsProvider.overrideWithValue(appThemePreferences),
      privacySettingsProvider.overrideWithValue(privacyPreferences),
      maidCafeSettingsProvider.overrideWithValue(maidCafePreferences),
      transferConflictSettingsProvider.overrideWithValue(
        transferConflictPreferences,
      ),
      workspaceRestoreSettingsProvider.overrideWithValue(
        workspaceRestorePreferences,
      ),
    ],
  );

  if (DesktopWindowFrame.isPlatformDesktop) {
    await windowManager.ensureInitialized();
    await windowManager.setOpacity(await loadMaidKitWindowOpacity());
    // Keep the desktop window resizable below the responsive breakpoint so
    // narrow-layout behavior can be exercised without a mobile device.
    const minimumSize = Size(390, 520);
    const defaultSize = Size(1180, 760);
    final savedWindowState = await loadMaidKitWindowState();
    // A crash or force-kill after a resize can leave the saved bounds pointing
    // at a display that is no longer attached (or at one arranged away from
    // the origin). Re-apply the saved frame — position included — but move the
    // window back onto an attached display, keeping its size, when it no
    // longer touches one.
    final restoreFrame = savedWindowState == null
        ? null
        : restoreFrameFor(
            saved: savedWindowState.bounds,
            displays: await loadDisplayWorkAreas(),
            minimumSize: minimumSize,
          );
    final windowOptions = WindowOptions(
      // Restore the user-adjusted window size. A maximized window is reported
      // as maximized rather than by its (unstable) frame size, so it is
      // re-maximized after the window is created at the saved frame size.
      size: restoreFrame?.size ?? savedWindowState?.bounds.size ?? defaultSize,
      minimumSize: minimumSize,
      // The saved position is re-applied below; only a fresh window is centered.
      center: savedWindowState == null,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: true,
    );
    // `waitUntilReadyToShow` does not await its callback, so wait for the
    // restore below to finish before the state listener snapshots the current
    // geometry. Otherwise that baseline write races the restored position and
    // immediately overwrites it with the platform's default one.
    final restored = Completer<void>();
    var restoreScheduled = false;
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      restoreScheduled = true;
      try {
        if (restoreFrame != null) {
          await windowManager.setBounds(restoreFrame);
        }
        if (savedWindowState?.maximized ?? false) {
          await windowManager.maximize();
        }
      } catch (_) {
        // Restoring the exact frame is best-effort; the window still shows.
      }
      try {
        await windowManager.show();
        await windowManager.focus();
      } finally {
        if (!restored.isCompleted) restored.complete();
      }
    });
    if (restoreScheduled) await restored.future;
    // Keep the persisted geometry fresh for the rest of the session, and make
    // a final best-effort write when the window is closed through the native
    // path (the in-app close button goes through `closeMaidKitWindow`, which
    // flushes the same state before quitting).
    final windowStateListener = MaidKitWindowStateListener(
      initial: savedWindowState,
    );
    await windowStateListener.start();
    MaidKitWindowStateListener.onAppClose(saveMaidKitWindowStateFromWindow);
    MaidKitWindowStateListener.onAppClose(
      () => container.read(terminalTabsProvider.notifier).saveSnapshotNow(),
    );
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: EasyLocalization(
        supportedLocales: const [
          Locale('en', 'US'),
          Locale('zh', 'CN'),
          Locale('zh', 'TW'),
        ],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        useFallbackTranslations: true,
        child: const MaidKitApp(),
      ),
    ),
  );
}
