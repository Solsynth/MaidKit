import 'package:shared_preferences/shared_preferences.dart';

import 'agent_reasoning.dart';

/// The standing agent choices the composer shows: the provider and model the
/// user last selected, and how much the model should think. Saved so they
/// survive restarts without being tied to a conversation.
abstract interface class AgentSelectionSettings {
  int? get providerId;
  int? get modelId;
  AgentReasoning get reasoning;

  Future<void> saveSelection({int? providerId, int? modelId});

  Future<void> saveReasoning(AgentReasoning reasoning);
}

class AgentSelectionPreferences implements AgentSelectionSettings {
  AgentSelectionPreferences(
    this._preferences,
    this.providerId,
    this.modelId,
    this.reasoning,
  );

  static const _providerIdKey = 'agent_selected_provider_id';
  static const _modelIdKey = 'agent_selected_model_id';
  static const _reasoningKey = 'agent_reasoning';
  final SharedPreferencesAsync _preferences;

  @override
  int? providerId;
  @override
  int? modelId;
  @override
  AgentReasoning reasoning;

  static Future<AgentSelectionPreferences> load({
    SharedPreferencesAsync? preferences,
  }) async {
    final store = preferences ?? SharedPreferencesAsync();
    return AgentSelectionPreferences(
      store,
      await store.getInt(_providerIdKey),
      await store.getInt(_modelIdKey),
      AgentReasoning.fromName(await store.getString(_reasoningKey)),
    );
  }

  @override
  Future<void> saveSelection({int? providerId, int? modelId}) async {
    this.providerId = providerId;
    this.modelId = modelId;
    if (providerId == null) {
      await _preferences.remove(_providerIdKey);
    } else {
      await _preferences.setInt(_providerIdKey, providerId);
    }
    if (modelId == null) {
      await _preferences.remove(_modelIdKey);
    } else {
      await _preferences.setInt(_modelIdKey, modelId);
    }
  }

  @override
  Future<void> saveReasoning(AgentReasoning reasoning) async {
    this.reasoning = reasoning;
    // The default is the absence of a choice, so it is stored as one.
    if (reasoning == AgentReasoning.modelDefault) {
      await _preferences.remove(_reasoningKey);
    } else {
      await _preferences.setString(_reasoningKey, reasoning.name);
    }
  }
}

class InMemoryAgentSelectionSettings implements AgentSelectionSettings {
  InMemoryAgentSelectionSettings({
    this.providerId,
    this.modelId,
    this.reasoning = AgentReasoning.modelDefault,
  });

  @override
  int? providerId;
  @override
  int? modelId;
  @override
  AgentReasoning reasoning;

  @override
  Future<void> saveSelection({int? providerId, int? modelId}) async {
    this.providerId = providerId;
    this.modelId = modelId;
  }

  @override
  Future<void> saveReasoning(AgentReasoning reasoning) async =>
      this.reasoning = reasoning;
}
