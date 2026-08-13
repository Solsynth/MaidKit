import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:drift/drift.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'shared/presentation/app_scaffold.dart';
import 'servers/server_providers.dart';
import 'servers/app_theme_preferences.dart';
import 'servers/metrics_refresh_preferences.dart';
import 'servers/terminal_adapter_preferences.dart';
import 'servers/startup_connection_preferences.dart';
import 'servers/privacy_preferences.dart';
import 'servers/local_machine_preferences.dart';
import 'servers/maidcafe_preferences.dart';

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
  final preferences = await Future.wait([
    TerminalAdapterPreferences.load(),
    StartupConnectionPreferences.load(),
    MetricsRefreshPreferences.load(),
    AppThemePreferences.load(),
    PrivacyPreferences.load(),
    LocalMachinePreferences.load(),
    MaidCafePreferences.load(),
  ]);
  final terminalAdapterPreferences =
      preferences[0] as TerminalAdapterPreferences;
  final startupConnectionPreferences =
      preferences[1] as StartupConnectionPreferences;
  final metricsRefreshPreferences = preferences[2] as MetricsRefreshPreferences;
  final appThemePreferences = preferences[3] as AppThemePreferences;
  final privacyPreferences = preferences[4] as PrivacyPreferences;
  final localMachinePreferences = preferences[5] as LocalMachinePreferences;
  final maidCafePreferences = preferences[6] as MaidCafePreferences;

  await migrateLegacyVault(defaultName: 'Primary Vault');

  if (DesktopWindowFrame.isPlatformDesktop) {
    await windowManager.ensureInitialized();
    await windowManager.setOpacity(await loadMaidKitWindowOpacity());
    const windowOptions = WindowOptions(
      size: Size(1180, 760),
      minimumSize: Size(720, 520),
      center: true,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: true,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(
    ProviderScope(
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
        localMachineSettingsProvider.overrideWithValue(localMachinePreferences),
        maidCafeSettingsProvider.overrideWithValue(maidCafePreferences),
      ],
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
