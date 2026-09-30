import 'package:drift/drift.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'package:maid_kit/servers/server_models.dart';
import 'package:maid_kit/servers/server_providers.dart';

final snippetRepositoryProvider = Provider<SnippetRepository>((ref) {
  return SnippetRepository(ref.watch(databaseProvider));
});

final scriptSnippetsProvider = StreamProvider<List<ScriptSnippet>>((ref) {
  return ref.watch(snippetRepositoryProvider).watchAll();
});

class SnippetRepository {
  SnippetRepository(this._database);

  final AppDatabase _database;

  Stream<List<ScriptSnippet>> watchAll() => _database.watchScriptSnippets();

  /// Every snippet, including the ones hidden from terminal autocomplete.
  /// Library, server, and agent surfaces use this list.
  Future<List<ScriptSnippet>> all() => (_database.select(
    _database.scriptSnippets,
  )..orderBy([(table) => OrderingTerm.asc(table.name)])).get();

  /// Snippets offered by the in-terminal snippet quick pick, which omits the
  /// ones the user excluded from terminal autocomplete.
  Future<List<ScriptSnippet>> autocomplete() =>
      (_database.select(_database.scriptSnippets)
            ..where((table) => table.excludedFromAutocomplete.equals(false))
            ..orderBy([(table) => OrderingTerm.asc(table.name)]))
          .get();

  Future<ScriptSnippet?> snippet(int id) => (_database.select(
    _database.scriptSnippets,
  )..where((table) => table.id.equals(id))).getSingleOrNull();

  Future<int> save({
    int? id,
    required String name,
    required String script,
    List<String> tags = const [],
    bool excludedFromAutocomplete = false,
    bool dangerous = false,
  }) {
    final now = DateTime.now().toUtc();
    final values = ScriptSnippetsCompanion(
      name: Value(name.trim()),
      script: Value(script),
      tags: Value(encodeStringList(_normalizeTags(tags))),
      excludedFromAutocomplete: Value(excludedFromAutocomplete),
      dangerous: Value(dangerous),
      createdAt: Value(now),
      updatedAt: Value(now),
    );
    if (id == null) {
      return _database.into(_database.scriptSnippets).insert(values);
    }
    return (_database.update(
      _database.scriptSnippets,
    )..where((table) => table.id.equals(id))).write(values).then((_) => id);
  }

  /// Records the servers the user checked the last time this snippet ran, so
  /// the next run dialog pre-selects them. Pass [serverIds] as null to forget
  /// the previous choice.
  Future<void> rememberServers(int id, List<int>? serverIds) {
    return (_database.update(
      _database.scriptSnippets,
    )..where((table) => table.id.equals(id))).write(
      ScriptSnippetsCompanion(
        lastServerIds: Value(encodeSnippetIdList(serverIds ?? const [])),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> delete(int id) => (_database.delete(
    _database.scriptSnippets,
  )..where((table) => table.id.equals(id))).go();

  List<String> _normalizeTags(List<String> tags) {
    final seen = <String>{};
    final normalized = <String>[];
    for (final tag in tags) {
      final trimmed = tag.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) continue;
      normalized.add(trimmed);
    }
    return normalized;
  }
}
