import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maid_kit/agent/conversation_store.dart';
import 'package:maid_kit/data/local/app_database.dart';

/// drift_flutter resolves its native database directory through
/// path_provider; point it at the system temp directory in tests.
void _mockPathProvider() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        return Directory.systemTemp.path;
      });
}

void main() {
  _mockPathProvider();

  group('AppDatabase migrations', () {
    test(
      'schema 22 database that already has sort_order migrates to 34',
      () async {
        final directory = Directory.systemTemp.createTempSync('migration_test');
        final path = '${directory.path}/stale.sqlite';

        // Reproduce the state left behind by pre-release builds: a servers
        // table that already contains sort_order while user_version still
        // reports 22.
        final seeded = AppDatabase(filePath: path);
        await seeded
            .into(seeded.servers)
            .insert(
              ServersCompanion.insert(
                name: 'legacy',
                host: '10.0.0.1',
                username: 'root',
              ),
            );
        await seeded.customStatement('PRAGMA user_version = 22');
        await seeded.close();

        // Opening the database again runs the 22 -> 33 migrations, which
        // must not fail with a duplicate column error.
        final database = AppDatabase(filePath: path);
        final version = await database
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(version.read<int>('user_version'), 34);

        // The order backfill still ran, so the legacy row keeps its
        // creation-id position.
        final row = await database
            .customSelect(
              'SELECT sort_order FROM servers WHERE name = ?',
              variables: [Variable('legacy')],
            )
            .getSingle();
        expect(row.read<int>('sort_order'), 1);

        // The GitHub token table is created for vault-backed token storage.
        final tokenTable = await database
            .customSelect(
              "SELECT name FROM sqlite_master "
              "WHERE type = 'table' AND name = 'github_tokens'",
            )
            .get();
        expect(tokenTable, isNotEmpty);

        // Saved port-forwarding presets are created in schema 28.
        final presetTable = await database
            .customSelect(
              "SELECT name FROM sqlite_master "
              "WHERE type = 'table' AND name = 'port_forward_configs'",
            )
            .get();
        expect(presetTable, isNotEmpty);

        // Per-runtime watch toggles are created in schema 29.
        final runtimeTable = await database
            .customSelect(
              "SELECT name FROM sqlite_master "
              "WHERE type = 'table' AND name = 'runtime_watch_configs'",
            )
            .get();
        expect(runtimeTable, isNotEmpty);

        // The pinned column for dashboard pins is added in schema 30.
        final pinnedColumn = await database
            .customSelect(
              "SELECT name FROM pragma_table_info('runtime_watch_configs') "
              "WHERE name = 'pinned'",
            )
            .get();
        expect(pinnedColumn, isNotEmpty);

        // Vault-synced app preferences are created in schema 31.
        final settingsTable = await database
            .customSelect(
              "SELECT name FROM sqlite_master "
              "WHERE type = 'table' AND name = 'app_settings'",
            )
            .get();
        expect(settingsTable, isNotEmpty);

        // The workspace snapshot table is created in schema 34.
        final snapshotTable = await database
            .customSelect(
              "SELECT name FROM sqlite_master "
              "WHERE type = 'table' AND name = 'workspace_snapshots'",
            )
            .get();
        expect(snapshotTable, isNotEmpty);

        final authKeyColumns = await database
            .customSelect(
              "SELECT name FROM pragma_table_info('vault_metadata') "
              "WHERE name IN ('encrypted_tailscale_auth_key', "
              "'tailscale_auth_key_nonce')",
            )
            .get();
        expect(authKeyColumns, hasLength(2));
        await database.close();
      },
    );
    test(
      'schema 22 without sort_order adds the column and file preferences',
      () async {
        final directory = Directory.systemTemp.createTempSync('migration_test');
        final path = '${directory.path}/clean.sqlite';

        final seeded = AppDatabase(filePath: path);
        await seeded.customStatement(
          'ALTER TABLE servers DROP COLUMN sort_order',
        );
        await seeded.customStatement('PRAGMA user_version = 22');
        await seeded.close();

        final database = AppDatabase(filePath: path);
        final version = await database
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(version.read<int>('user_version'), 34);

        final column = await database
            .customSelect(
              "SELECT name FROM pragma_table_info('servers') "
              "WHERE name = 'sort_order'",
            )
            .get();
        expect(column, isNotEmpty);
        final preferenceColumns = await database
            .customSelect(
              "SELECT name FROM pragma_table_info('servers') "
              "WHERE name IN ('file_management_initial_path', "
              "'file_management_favorites')",
            )
            .get();
        expect(preferenceColumns, hasLength(2));
        await database.close();
      },
    );
    test(
      'schema 16 conversations are exported to JSONL before the table drops',
      () async {
        final directory = Directory.systemTemp.createTempSync('migration_test');
        final path = '${directory.path}/legacy.sqlite';
        final conversationsDirectory = Directory(
          '${Directory.systemTemp.path}/agent_conversations',
        );
        if (await conversationsDirectory.exists()) {
          await conversationsDirectory.delete(recursive: true);
        }
        addTearDown(() async {
          if (await conversationsDirectory.exists()) {
            await conversationsDirectory.delete(recursive: true);
          }
        });

        // Roll the fresh schema-33 database back to the schema-16 layout:
        // drop every servers column the 18/20/22 migrations re-add (they are
        // unguarded), and create the agent_conversations table that held
        // chat history until 2.0.0, with saved conversations.
        final seeded = AppDatabase(filePath: path);
        for (final column in const [
          'proxy_type',
          'proxy_host',
          'proxy_port',
          'proxy_username',
          'encrypted_proxy_password',
          'proxy_password_nonce',
          'environment',
          'initial_snippets',
          'tags',
          'connection_type',
          'serial_config',
        ]) {
          await seeded.customStatement(
            'ALTER TABLE servers DROP COLUMN $column',
          );
        }
        // Schema 19 recreates these (including the unguarded unique index);
        // drop the fresh-schema versions so the migration reproduces a real
        // upgrade.
        await seeded.customStatement('DROP TABLE IF EXISTS github_repo_pins');
        await seeded.customStatement('DROP TABLE IF EXISTS github_connections');
        await seeded.customStatement('''
          CREATE TABLE agent_conversations (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            provider_id INTEGER,
            model_id INTEGER,
            messages TEXT NOT NULL,
            created_at DATETIME NOT NULL,
            updated_at DATETIME NOT NULL
          )
        ''');
        await seeded.customStatement('''
          INSERT INTO agent_conversations
            (id, title, provider_id, model_id, messages, created_at, updated_at)
          VALUES
            (1, 'first chat', 3, 5,
             '[{"role":"user","text":"hello\\nworld"},{"role":"assistant","text":"hi"}]',
             '2026-01-01T10:00:00.000Z', '2026-01-02T11:30:00.000Z'),
            (2, 'empty chat', NULL, NULL, '[]',
             '2026-01-03T08:00:00.000Z', '2026-01-03T08:00:00.000Z')
        ''');
        await seeded.customStatement('PRAGMA user_version = 16');
        await seeded.close();

        // Opening the database again runs the 16 -> 34 migrations, which
        // must export the legacy rows as JSONL before dropping the table.
        final database = AppDatabase(filePath: path);
        final version = await database
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(version.read<int>('user_version'), 34);

        final table = await database
            .customSelect(
              "SELECT name FROM pragma_table_info('agent_conversations')",
            )
            .get();
        expect(table, isEmpty);

        final first = File('${conversationsDirectory.path}/1.jsonl');
        final second = File('${conversationsDirectory.path}/2.jsonl');
        expect(await first.exists(), isTrue);
        expect(await second.exists(), isTrue);

        final firstLines = await first.readAsLines();
        final header = jsonDecode(firstLines.first) as Map<String, dynamic>;
        expect(header['id'], 1);
        expect(header['title'], 'first chat');
        expect(header['providerId'], 3);
        expect(header['modelId'], 5);
        expect(header['createdAt'], '2026-01-01T10:00:00.000Z');
        expect(header['updatedAt'], '2026-01-02T11:30:00.000Z');
        final messages = firstLines.skip(1).map(jsonDecode).toList();
        expect(messages, [
          {'role': 'user', 'text': 'hello\nworld'},
          {'role': 'assistant', 'text': 'hi'},
        ]);

        final secondLines = await second.readAsLines();
        final secondHeader =
            jsonDecode(secondLines.first) as Map<String, dynamic>;
        expect(secondHeader['id'], 2);
        expect(secondHeader['providerId'], null);
        expect(secondHeader['modelId'], null);
        expect(secondLines, hasLength(1));

        // The exported files load through the store exactly like fresh saves.
        final store = AgentConversationStore(directory: conversationsDirectory);
        final conversation = await store.conversation(1);
        expect(conversation, isA<AgentConversation>());
        expect(conversation!.title, 'first chat');
        expect(conversation.providerId, 3);
        expect(conversation.messages, hasLength(2));
        expect(conversation.messages.first.text, 'hello\nworld');
        expect(await store.list(), hasLength(2));
        await database.close();
      },
    );
  });
}
