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
import 'package:maid_kit/servers/sessions_page.dart';
import 'package:maid_kit/servers/ssh_connection_manager.dart';
import 'package:maid_kit/servers/terminal_tabs_provider.dart';
import 'package:maid_kit/shared/presentation/maidkit_window_scaffold.dart';
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

/// Cmd/Ctrl+W closes the tab the workspace is showing, and asks first when
/// closing it would abandon work that is still going.
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

  /// Pumps the window shell around the workspace, which is where the shortcut
  /// is handled, and installs the overlay the app-level prompts render into.
  Future<ProviderContainer> pumpWindow(WidgetTester tester) async {
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
            // The desktop frame is what holds focus in the app; here the
            // workspace keeps it instead so key events reach the window.
            desktopWindowProvider.overrideWithValue(false),
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
                    child: Focus(
                      autofocus: true,
                      child: const Scaffold(body: SessionsWorkspace()),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(SessionsWorkspace)),
    );
  }

  /// Pumps fixed frames instead of settling: a tab with work going shows a
  /// spinner, and a spinner never settles.
  Future<void> pumpFrames(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> pressCloseShortcut(
    WidgetTester tester, {
    bool control = false,
  }) async {
    final modifier = control
        ? LogicalKeyboardKey.control
        : LogicalKeyboardKey.meta;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(modifier);
    await pumpFrames(tester);
  }

  testWidgets('Cmd/Ctrl+W closes the focused tab', (tester) async {
    final container = await pumpWindow(tester);
    final notifier = container.read(terminalTabsProvider.notifier);

    notifier.openAssets();
    await tester.pumpAndSettle();
    expect(find.text('tabAssets'.tr()), findsOneWidget);

    await pressCloseShortcut(tester);
    expect(find.text('tabAssets'.tr()), findsNothing);
    expect(find.text('tabDashboard'.tr()), findsOneWidget);

    // Ctrl+W is the same shortcut on Windows and Linux.
    notifier.openAssets(section: AssetsSection.github);
    await tester.pumpAndSettle();
    expect(find.text('tabAssets'.tr()), findsOneWidget);

    await pressCloseShortcut(tester, control: true);
    expect(find.text('tabAssets'.tr()), findsNothing);
    expect(find.text('tabDashboard'.tr()), findsOneWidget);
  });

  testWidgets('a close shortcut asks before cutting a chat short', (
    tester,
  ) async {
    final container = await pumpWindow(tester);
    final notifier = container.read(terminalTabsProvider.notifier);

    final chat = notifier.openAgentChat();
    await tester.pumpAndSettle();
    notifier.setAgentChatWorking(chat.id, true);
    await pumpFrames(tester);

    await pressCloseShortcut(tester, control: true);
    expect(find.text('sessionsCloseWorkingTabTitle'.tr()), findsOneWidget);

    // Backing out keeps the chat running.
    await tester.tap(find.text('Cancel'));
    await pumpFrames(tester);
    expect(find.text('agentNewConversation'.tr()), findsOneWidget);

    // Confirming closes it.
    await pressCloseShortcut(tester, control: true);
    await tester.tap(find.text('OK'));
    await pumpFrames(tester);
    expect(find.text('agentNewConversation'.tr()), findsNothing);
  });

  testWidgets('a close shortcut leaves the dashboard tab alone', (
    tester,
  ) async {
    final container = await pumpWindow(tester);
    expect(container.read(terminalTabsProvider).isEmpty, isFalse);

    await pressCloseShortcut(tester);
    expect(find.text('tabDashboard'.tr()), findsOneWidget);
  });
}
