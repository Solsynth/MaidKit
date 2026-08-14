import 'package:drift/drift.dart';
import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/vault_service.dart';

import 'personality_service.dart';

class AgentConfiguration {
  const AgentConfiguration({
    required this.providerId,
    required this.providerName,
    required this.apiKey,
    required this.baseUrl,
    required this.model,
  });
  final int providerId;
  final String providerName;
  final String apiKey;
  final String? baseUrl;
  final String model;
}

class AgentProviderDraft {
  const AgentProviderDraft({
    required this.name,
    required this.apiKey,
    required this.baseUrl,
    required this.model,
    this.models = const [],
  });
  final String name;

  /// Leave empty when editing to retain the stored key.
  final String apiKey;
  final String? baseUrl;
  final String model;
  final List<String> models;
}

class AgentRepository {
  AgentRepository(this._database, this._vault);
  final AppDatabase _database;
  final VaultService _vault;

  Stream<List<AgentProvider>> watchProviders() =>
      _database.watchAgentProviders();

  Stream<List<AgentProviderModel>> watchModels(int providerId) =>
      _database.watchAgentProviderModels(providerId);

  Future<void> save(AgentProviderDraft draft, {int? id}) async {
    final name = draft.name.trim();
    final model = draft.model.trim();
    final baseUrl = _normalizeBaseUrl(draft.baseUrl);
    if (baseUrl == PersonalityService.productionBaseUrl) {
      throw ArgumentError(
        'Solar Network Personality is managed automatically by Solarpass.',
      );
    }
    if (name.isEmpty || model.isEmpty) {
      throw ArgumentError('Provider name and model are required.');
    }
    final existing = id == null
        ? null
        : await (_database.select(
            _database.agentProviders,
          )..where((table) => table.id.equals(id))).getSingle();
    final rawKey = draft.apiKey.trim();
    if (existing == null && rawKey.isEmpty) {
      throw ArgumentError('An API key is required for a new provider.');
    }
    final encrypted = rawKey.isEmpty
        ? null
        : await _vault.encrypt(rawKey, context: 'agent-provider-api-key');
    final values = AgentProvidersCompanion(
      name: Value(name),
      encryptedApiKey: encrypted == null
          ? const Value.absent()
          : Value(encrypted.bytes),
      apiKeyNonce: encrypted == null
          ? const Value.absent()
          : Value(encrypted.nonce),
      baseUrl: Value(baseUrl),
      model: Value(model),
      updatedAt: Value(DateTime.now().toUtc()),
    );
    if (existing == null) {
      final providerId = await _database
          .into(_database.agentProviders)
          .insert(
            AgentProvidersCompanion.insert(
              name: name,
              encryptedApiKey: encrypted!.bytes,
              apiKeyNonce: encrypted.nonce,
              baseUrl: Value(baseUrl),
              model: model,
              updatedAt: DateTime.now().toUtc(),
            ),
          );
      for (final discoveredModel in {model, ...draft.models}) {
        await addModel(providerId, discoveredModel);
      }
    } else {
      await (_database.update(
        _database.agentProviders,
      )..where((table) => table.id.equals(existing.id))).write(values);
      await addModel(existing.id, model);
      for (final discoveredModel in draft.models) {
        await addModel(existing.id, discoveredModel);
      }
    }
  }

  Future<void> addModel(int providerId, String value) async {
    final model = value.trim();
    if (model.isEmpty) throw ArgumentError.value(value, 'model', 'is empty');
    final existing =
        await (_database.select(_database.agentProviderModels)..where(
              (table) =>
                  table.providerId.equals(providerId) &
                  table.model.equals(model),
            ))
            .get();
    if (existing.isNotEmpty) return;
    await _database
        .into(_database.agentProviderModels)
        .insert(
          AgentProviderModelsCompanion.insert(
            providerId: providerId,
            model: model,
            createdAt: DateTime.now().toUtc(),
          ),
        );
  }

  Future<void> deleteModel(int id) => (_database.delete(
    _database.agentProviderModels,
  )..where((table) => table.id.equals(id))).go();

  Future<void> delete(int id) => (_database.delete(
    _database.agentProviders,
  )..where((table) => table.id.equals(id))).go();

  /// Keeps the first-party provider available for the active Solarpass user.
  /// Its access token is encrypted with the vault key like other provider
  /// credentials, while the active request still uses a refreshed token.
  Future<void> ensurePersonalityProvider(
    String accessToken, {
    Iterable<String> models = const ['agent'],
  }) async {
    final encrypted = await _vault.encrypt(
      accessToken,
      context: 'agent-provider-api-key',
    );
    final existing =
        await (_database.select(_database.agentProviders)
              ..where(
                (table) =>
                    table.baseUrl.equals(PersonalityService.productionBaseUrl),
              )
              ..limit(1))
            .getSingleOrNull();
    final now = DateTime.now().toUtc();
    if (existing == null) {
      final providerId = await _database
          .into(_database.agentProviders)
          .insert(
            AgentProvidersCompanion.insert(
              name: 'Solar Network Personality',
              encryptedApiKey: encrypted.bytes,
              apiKeyNonce: encrypted.nonce,
              baseUrl: const Value(PersonalityService.productionBaseUrl),
              model: 'agent',
              updatedAt: now,
            ),
          );
      for (final model in models) {
        await addModel(providerId, model);
      }
      return;
    }
    await (_database.update(
      _database.agentProviders,
    )..where((table) => table.id.equals(existing.id))).write(
      AgentProvidersCompanion(
        encryptedApiKey: Value(encrypted.bytes),
        apiKeyNonce: Value(encrypted.nonce),
        updatedAt: Value(now),
      ),
    );
    for (final model in models) {
      await addModel(existing.id, model);
    }
  }

  Future<AgentConfiguration?> configuration([
    int? providerId,
    int? modelId,
  ]) async {
    final query = _database.select(_database.agentProviders)
      ..orderBy([(table) => OrderingTerm.asc(table.name)]);
    if (providerId != null) query.where((table) => table.id.equals(providerId));
    final rows = await query.get();
    if (rows.isEmpty) return null;
    final provider = rows.first;
    final modelsQuery = _database.select(_database.agentProviderModels)
      ..where((table) => table.providerId.equals(provider.id))
      ..orderBy([(table) => OrderingTerm.asc(table.model)]);
    if (modelId != null) modelsQuery.where((table) => table.id.equals(modelId));
    final models = await modelsQuery.get();
    final model = models.isEmpty ? provider.model : models.first.model;
    return AgentConfiguration(
      providerId: provider.id,
      providerName: provider.name,
      apiKey: await _vault.decrypt(
        EncryptedValue(
          bytes: provider.encryptedApiKey,
          nonce: provider.apiKeyNonce,
        ),
        context: 'agent-provider-api-key',
      ),
      baseUrl: provider.baseUrl,
      model: model,
    );
  }

  String? _normalizeBaseUrl(String? value) {
    final url = value?.trim();
    if (url == null || url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw ArgumentError.value(value, 'baseUrl', 'must be an absolute URL');
    }
    return url.replaceFirst(RegExp(r'/+$'), '');
  }
}
