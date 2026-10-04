import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:maid_kit/agent/agent_selection.dart';
import 'package:maid_kit/agent/conversation_store.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/server_providers.dart';
import 'package:maid_kit/servers/sessions_page.dart';
import 'package:maid_kit/servers/terminal_tabs_provider.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
  });

  /// Pumps the workspace — agent chats are pane tabs in it, not a page of
  /// their own.
  Future<ProviderContainer> pumpWorkspace(WidgetTester tester) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        useFallbackTranslations: true,
        child: ProviderScope(
          overrides: [
            cloudUserProvider.overrideWith((ref) async => null),
            serversProvider.overrideWith(
              (ref) => Stream.value(const <Server>[]),
            ),
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
          child: const MaterialApp(home: SessionsWorkspace()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  }

  // Every pane tab stays mounted; non-selected ones are transparent rather
  // than offstage, so prompt finders must not skip them.
  Finder prompts() => find.byType(TextField, skipOffstage: false);

  testWidgets('opening a chat adds a pane tab with its own prompt', (
    tester,
  ) async {
    final container = await pumpWorkspace(tester);
    expect(prompts(), findsNothing);

    container.read(terminalTabsProvider.notifier).openAgentChat();
    await tester.pumpAndSettle();

    expect(find.text('agentNewConversation'.tr()), findsOneWidget);
    expect(prompts(), findsOneWidget);
  });

  testWidgets('a second chat keeps both chats alive', (tester) async {
    final container = await pumpWorkspace(tester);
    final notifier = container.read(terminalTabsProvider.notifier);

    notifier.openAgentChat();
    await tester.pumpAndSettle();
    notifier.openAgentChat();
    await tester.pumpAndSettle();

    expect(find.text('agentNewConversation'.tr()), findsNWidgets(2));
    expect(prompts(), findsNWidgets(2));
  });

  testWidgets('prompt drafts stay with their own chat tab', (tester) async {
    final container = await pumpWorkspace(tester);
    final notifier = container.read(terminalTabsProvider.notifier);

    final first = notifier.openAgentChat();
    await tester.pumpAndSettle();
    final second = notifier.openAgentChat();
    await tester.pumpAndSettle();

    final fields = prompts();
    tester.widget<TextField>(fields.at(0)).controller!.text = 'draft one';
    tester.widget<TextField>(fields.at(1)).controller!.text = 'draft two';
    await tester.pump();

    // Both chats stay real tabs while the other one is selected, and each
    // keeps its own draft.
    notifier.select(first.id);
    await tester.pumpAndSettle();
    notifier.select(second.id);
    await tester.pumpAndSettle();

    final drafts = [
      for (final element in prompts().evaluate())
        (element.widget as TextField).controller!.text,
    ];
    expect(drafts.where((text) => text == 'draft one'), hasLength(1));
    expect(drafts.where((text) => text == 'draft two'), hasLength(1));
  });

  testWidgets('closing a chat tab takes its chat with it', (tester) async {
    final container = await pumpWorkspace(tester);
    final notifier = container.read(terminalTabsProvider.notifier);

    notifier.openAgentChat();
    await tester.pumpAndSettle();
    final second = notifier.openAgentChat();
    await tester.pumpAndSettle();
    expect(prompts(), findsNWidgets(2));

    await notifier.close(second.id);
    await tester.pumpAndSettle();

    expect(prompts(), findsOneWidget);
    expect(find.text('agentNewConversation'.tr()), findsOneWidget);
  });
}

class _StubSelectionNotifier extends AgentSelectionNotifier {
  @override
  Future<AgentSelectionSettings> build() async =>
      InMemoryAgentSelectionSettings();
}
