import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:maid_kit/agent/agent_reasoning.dart';
import 'package:maid_kit/agent/agent_selection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Route SharedPreferencesAsync to an in-memory store so the selection can
    // be round-tripped without touching the host platform.
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('a chosen reasoning level survives a reload', () async {
    final settings = await AgentSelectionPreferences.load();
    expect(settings.reasoning, AgentReasoning.modelDefault);

    await settings.saveReasoning(AgentReasoning.high);

    final reloaded = await AgentSelectionPreferences.load();
    expect(reloaded.reasoning, AgentReasoning.high);
    expect(reloaded.providerId, isNull);
    expect(reloaded.modelId, isNull);
  });

  test('the model default is stored as the absence of a choice', () async {
    final settings = await AgentSelectionPreferences.load();
    await settings.saveReasoning(AgentReasoning.low);
    expect(await SharedPreferencesAsync().getString('agent_reasoning'), 'low');

    await settings.saveReasoning(AgentReasoning.modelDefault);

    expect(await SharedPreferencesAsync().getString('agent_reasoning'), isNull);
  });

  test('an unknown stored level reads back as the model default', () async {
    await SharedPreferencesAsync().setString('agent_reasoning', 'xhigh');

    final settings = await AgentSelectionPreferences.load();

    expect(settings.reasoning, AgentReasoning.modelDefault);
  });

  test('saving the provider and model keeps the reasoning level', () async {
    final settings = await AgentSelectionPreferences.load();
    await settings.saveReasoning(AgentReasoning.medium);
    await settings.saveSelection(providerId: 7, modelId: 8);

    final reloaded = await AgentSelectionPreferences.load();
    expect(reloaded.providerId, 7);
    expect(reloaded.modelId, 8);
    expect(reloaded.reasoning, AgentReasoning.medium);
  });
}
