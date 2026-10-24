import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart' as ez;
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart' as ez_tr;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/agent/agent_selection.dart';
import 'package:maid_kit/agent/conversation_store.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/tabs_screen.dart';
import 'package:maid_kit/servers/ssh_connection_manager.dart';
import 'package:maid_kit/servers/vault_gate.dart';
import 'package:maid_kit/shared/presentation/maidkit_window_scaffold.dart';
import 'package:maid_kit/shared/presentation/window_chrome.dart';
import 'package:maid_kit/snippets/snippet_repository.dart';
import 'package:maid_kit/theme.dart';

class _RecordingConnectionManager extends SshConnectionManager {
  _RecordingConnectionManager() : super(() => throw UnimplementedError());
}

class _StubSelectionNotifier extends AgentSelectionNotifier {
  @override
  Future<AgentSelectionSettings> build() async =>
      InMemoryAgentSelectionSettings();
}

class _UnlockedVault extends VaultUnlocked {
  @override
  bool build() => true;
}

/// The window title bar and the workspace's tab strip are one bar on desktop.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return Directory.systemTemp.path;
        });
    final enMap =
        jsonDecode(File('assets/translations/en-US.json').readAsStringSync())
            as Map<String, dynamic>;
    ez.Localization.load(
      const Locale('en', 'US'),
      translations: ez_tr.Translations(enMap),
      ignorePluralRules: false,
    );
  });

  Future<void> pumpWindow(WidgetTester tester, {required bool desktop}) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final overlayKey = GlobalKey<OverlayState>();
    IslandUIFoundation.configureOverlay(overlayKey);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: ProviderScope(
          overrides: [
            desktopWindowProvider.overrideWithValue(desktop),
            vaultUnlockedProvider.overrideWith(_UnlockedVault.new),
            serversProvider.overrideWith((ref) => Stream.value(<Server>[])),
            savedCredentialsProvider.overrideWith(
              (ref) => Stream.value(<SavedCredential>[]),
            ),
            scriptSnippetsProvider.overrideWith(
              (ref) => Stream.value(<ScriptSnippet>[]),
            ),
            biometricUnlockEnabledProvider.overrideWith(
              (ref) => Future.value(false),
            ),
            connectionManagerProvider.overrideWithValue(
              _RecordingConnectionManager(),
            ),
            cloudUserProvider.overrideWith((ref) async => null),
            mcpServersProvider.overrideWith(
              (ref) => Stream.value(const <McpServer>[]),
            ),
            agentProvidersProvider.overrideWith(
              (ref) => Stream.value(const <AgentProvider>[]),
            ),
            agentProviderModelsProvider.overrideWith(
              (ref, providerId) => Stream.value(const <AgentProviderModel>[]),
            ),
            agentConversationsProvider.overrideWith(
              (ref) => Stream.value(const <AgentConversation>[]),
            ),
            agentSelectionProvider.overrideWith(() => _StubSelectionNotifier()),
          ],
          child: MaterialApp(
            theme: createMaidKitTheme(Brightness.light),
            home: Overlay(
              key: overlayKey,
              initialEntries: [
                OverlayEntry(
                  builder: (context) => MaidKitWindowScaffold(
                    child: const Scaffold(body: SessionsWorkspace()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the workspace strip is the only bar on desktop', (tester) async {
    await pumpWindow(tester, desktop: true);

    // The shell hands the title bar to the workspace: no second bar above it.
    expect(find.byType(MaidKitTitleBar), findsNothing);

    // The tab strip occupies the title bar slot, at title bar height, and is
    // the surface that drags the window.
    final strip = find.ancestor(
      of: find.text('tabDashboard'.tr()),
      matching: find.byType(Material),
    );
    expect(strip, findsWidgets);
    expect(
      tester.getSize(strip.first).height,
      kMaidKitTitleBarHeight,
      reason: 'the strip and the title bar are one row',
    );
    expect(find.byType(MaidKitWindowDragArea), findsWidgets);
  });

  testWidgets('reports the scaled title bar height to the native window', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('maidkit/window'), (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('maidkit/window'),
        null,
      ),
    );

    Widget shell(double scale) => ProviderScope(
      key: ValueKey(scale),
      overrides: [
        desktopWindowProvider.overrideWithValue(true),
        vaultUnlockedProvider.overrideWith(() => _UnlockedVault()),
      ],
      child: MaterialApp(
        theme: createMaidKitTheme(Brightness.light),
        home: MaidKitTitleBarHeightReporter(
          uiScale: scale,
          child: const MaidKitWindowScaffold(child: SizedBox()),
        ),
      ),
    );

    await tester.pumpWidget(shell(1.5));
    await tester.pumpAndSettle();
    // The macOS traffic lights sit on the strip's center line, so the native
    // window needs the strip's height in window points — the UI scale shrinks
    // the logical viewport, not the window.
    expect(
      calls
          .where((call) => call.method == 'setTitleBarHeight')
          .map((call) => call.arguments),
      contains(closeTo(kMaidKitTitleBarHeight * 1.5, 0.001)),
    );

    calls.clear();
    await tester.pumpWidget(shell(2.0));
    await tester.pumpAndSettle();
    expect(
      calls
          .where((call) => call.method == 'setTitleBarHeight')
          .map((call) => call.arguments),
      contains(closeTo(kMaidKitTitleBarHeight * 2.0, 0.001)),
      reason: 'a scale change re-centers the traffic lights',
    );
  });

  testWidgets('non-desktop keeps no window chrome', (tester) async {
    await pumpWindow(tester, desktop: false);

    // Nothing merges on mobile/web, and no native window bar is drawn either.
    expect(find.byType(MaidKitTitleBar), findsNothing);
    expect(find.byType(MaidKitWindowDragArea), findsNothing);
  });
}
