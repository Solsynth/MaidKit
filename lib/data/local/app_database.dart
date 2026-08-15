import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class Servers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get host => text()();
  IntColumn get port => integer().withDefault(const Constant(22))();
  TextColumn get username => text()();
  DateTimeColumn get lastConnectedAt => dateTime().nullable()();
  TextColumn get syncId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get credentialType => text().nullable()();
  TextColumn get encryptedCredential => text().nullable()();
  TextColumn get credentialNonce => text().nullable()();
  IntColumn get credentialId => integer().nullable()();
  TextColumn get hostKeyAlgorithm => text().nullable()();
  TextColumn get hostKeyFingerprint => text().nullable()();
  BoolColumn get collectStats => boolean().withDefault(const Constant(true))();
  BoolColumn get collectSystemInfo =>
      boolean().withDefault(const Constant(true))();
  // Optional per-server HTTP CONNECT / SOCKS5 proxy. The password is
  // encrypted with the vault key, mirroring the SSH credential columns.
  TextColumn get proxyType => text().nullable()();
  TextColumn get proxyHost => text().nullable()();
  IntColumn get proxyPort => integer().nullable()();
  TextColumn get proxyUsername => text().nullable()();
  TextColumn get encryptedProxyPassword => text().nullable()();
  TextColumn get proxyPasswordNonce => text().nullable()();
  // Optional SSH jump host. The referenced server may itself have a jump
  // host, allowing chained routes.
  IntColumn get jumpHostServerId => integer().nullable()();
  // Per-server configuration, JSON-encoded. Environment is a map of variable
  // names to values, initialSnippets is a list of ScriptSnippets ids that run
  // on terminal open, and tags is a list of free-form labels.
  TextColumn get environment => text().nullable()();
  TextColumn get initialSnippets => text().nullable()();
  TextColumn get tags => text().nullable()();
  // Connection transport: `ssh` for a remote host, `serial` for a local
  // serial port. When the type is `serial`, [serialConfig] holds the JSON-
  // encoded SerialConfig.
  TextColumn get connectionType => text().withDefault(const Constant('ssh'))();
  TextColumn get serialConfig => text().nullable()();
  // MaidCafe daemon configuration. Secrets are encrypted with the vault key;
  // the endpoint is non-secret metadata.
  TextColumn get maidCafeDaemonUrl => text().nullable()();
  TextColumn get encryptedMaidCafeWebhookSecret => text().nullable()();
  TextColumn get maidCafeWebhookSecretNonce => text().nullable()();
  TextColumn get encryptedMaidCafeMetricsSecret => text().nullable()();
  TextColumn get maidCafeMetricsSecretNonce => text().nullable()();
  // User-controlled display order on the server dashboard. Rows without a
  // value (legacy rows and imports) sort after explicitly ordered ones.
  IntColumn get sortOrder => integer().nullable()();
}

/// An encrypted SSH credential that may be linked to by more than one server.
/// The encrypted payload remains protected by the user's vault key.
class SavedCredentials extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get credentialType => text()();
  TextColumn get encryptedCredential => text()();
  TextColumn get credentialNonce => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

class VaultMetadata extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get formatVersion => integer()();
  TextColumn get salt => text()();
  TextColumn get wrappedDataKey => text()();
  TextColumn get wrappedDataKeyNonce => text()();
  TextColumn get verifier => text()();
  TextColumn get verifierNonce => text()();
  TextColumn get syncPassphraseCiphertext => text().nullable()();
  TextColumn get syncPassphraseNonce => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

/// Locally remembered Compose folders. A link is intentionally metadata only:
/// its compose file and credentials remain on the managed server.
class ComposeProjectLinks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get serverId => integer()();
  TextColumn get name => text()();
  TextColumn get directory => text()();
  TextColumn get runtime => text()();
  TextColumn get scope => text()();
  DateTimeColumn get linkedAt => dateTime()();
}

/// Last successfully read container state. It is a UI cache, not an authority
/// for remote state, and contains no credentials or compose-file contents.
class ContainerCacheEntries extends Table {
  IntColumn get serverId => integer()();
  TextColumn get runtime => text()();
  TextColumn get scope => text()();
  TextColumn get containerId => text()();
  TextColumn get name => text()();
  TextColumn get image => text()();
  TextColumn get state => text()();
  TextColumn get status => text()();
  TextColumn get composeProject => text().nullable()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {serverId, runtime, scope, containerId};
}

/// A named deployment bundle. A project is deliberately not tied to one
/// deployment technology: its resources can be compose stacks, web servers,
/// standalone containers, or future integrations such as databases.
class DeploymentProjects extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

/// A deployable or supporting item belonging to a [DeploymentProjects] row.
/// Configuration is JSON so each resource kind can evolve without a schema
/// migration. It must only contain non-secret, portable deployment metadata.
class DeploymentResources extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get projectId => integer()();
  TextColumn get kind => text()();
  TextColumn get name => text()();
  IntColumn get serverId => integer().nullable()();
  TextColumn get configuration => text().withDefault(const Constant('{}'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

/// Reusable shell scripts. Snippets intentionally contain no credentials; they
/// execute through the selected server's existing SSH connection.
class ScriptSnippets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get script => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

/// Legacy single-provider configuration, retained only to migrate version 11
/// vaults into [AgentProviders].
class AgentSettings extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get encryptedApiKey => text()();
  TextColumn get apiKeyNonce => text()();
  TextColumn get model => text().withDefault(const Constant('gpt-4o-mini'))();
  DateTimeColumn get updatedAt => dateTime()();
}

/// Encrypted, OpenAI-compatible provider profiles. The vault database itself
/// is encrypted and syncable, so profiles travel with a user's vault.
class AgentProviders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get encryptedApiKey => text()();
  TextColumn get apiKeyNonce => text()();
  TextColumn get baseUrl => text().nullable()();
  TextColumn get model => text()();
  DateTimeColumn get updatedAt => dateTime()();
}

/// Model identifiers available through a particular AI provider endpoint.
class AgentProviderModels extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get providerId => integer()();
  TextColumn get model => text()();
  DateTimeColumn get createdAt => dateTime()();
}

/// A locally launched Model Context Protocol server the agent can call tools
/// on. The command is executed as a child process speaking JSON-RPC over
/// stdio; arguments and environment are JSON-encoded. Environment entries are
/// merged over the app's own environment.
class McpServers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get command => text()();
  TextColumn get arguments => text().withDefault(const Constant('[]'))();
  TextColumn get environment => text().withDefault(const Constant('{}'))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

/// Reusable expertise packs (skills) the agent can consult. Enabled skills
/// are listed in the system prompt; the agent reads full instructions through
/// the `get_skill` tool when a skill matches the task. Content is plain
/// markdown and contains no credentials.
class AgentSkills extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get content => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

/// A GitHub account the user signed in with. Only non-secret identity is kept
/// here; the access token lives in the OS keychain under a key derived from
/// [accountLogin] and never enters the vault database or cloud sync.
class GitHubConnections extends Table {
  @override
  String get tableName => 'github_connections';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get accountLogin => text().unique()();
  TextColumn get accountName => text().withDefault(const Constant(''))();
  TextColumn get avatarUrl => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
}

/// Repositories pinned to the GitHub tab. Metadata only, safe to sync.
class GitHubRepoPins extends Table {
  @override
  String get tableName => 'github_repo_pins';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get connectionId => integer().references(GitHubConnections, #id)();
  TextColumn get owner => text()();
  TextColumn get name => text()();
  DateTimeColumn get pinnedAt => dateTime()();
}

/// Links a deployment project to a GitHub workflow whose latest run is shown
/// on the project detail page.
@DriftDatabase(
  tables: [
    Servers,
    SavedCredentials,
    VaultMetadata,
    ComposeProjectLinks,
    ContainerCacheEntries,
    DeploymentProjects,
    DeploymentResources,
    ScriptSnippets,
    AgentSettings,
    AgentProviders,
    AgentProviderModels,
    McpServers,
    AgentSkills,
    GitHubConnections,
    GitHubRepoPins,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Opens the legacy app database when [filePath] is omitted, or a user
  /// selected vault database when it is provided.
  AppDatabase({String? filePath})
    : super(
        driftDatabase(
          name: filePath ?? 'maid_kit',
          native: filePath == null
              ? null
              : DriftNativeOptions(databasePath: () async => filePath),
        ),
      );

  @override
  int get schemaVersion => 26;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement(
        'CREATE UNIQUE INDEX servers_sync_id_unique ON servers (sync_id)',
      );
      await customStatement(
        'CREATE UNIQUE INDEX compose_project_links_location_unique '
        'ON compose_project_links (server_id, directory, scope)',
      );
      await customStatement(
        'CREATE UNIQUE INDEX github_repo_pins_unique '
        'ON github_repo_pins (connection_id, owner, name)',
      );
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(servers, servers.syncId);
        await m.addColumn(servers, servers.createdAt);
        await m.addColumn(servers, servers.updatedAt);
        await m.addColumn(servers, servers.deletedAt);
        await m.addColumn(servers, servers.credentialType);
        await m.addColumn(servers, servers.encryptedCredential);
        await m.addColumn(servers, servers.credentialNonce);
        await m.createTable(vaultMetadata);
        await customStatement(
          'CREATE UNIQUE INDEX servers_sync_id_unique ON servers (sync_id)',
        );
      }
      if (from < 3) {
        await m.addColumn(servers, servers.hostKeyAlgorithm);
        await m.addColumn(servers, servers.hostKeyFingerprint);
      }
      if (from < 4) {
        await m.addColumn(servers, servers.collectStats);
        await m.addColumn(servers, servers.collectSystemInfo);
      }
      if (from < 5) {
        await m.createTable(composeProjectLinks);
        await customStatement(
          'CREATE UNIQUE INDEX compose_project_links_location_unique '
          'ON compose_project_links (server_id, directory, scope)',
        );
      }
      if (from < 6) {
        await m.createTable(containerCacheEntries);
      }
      if (from < 7) {
        await m.createTable(deploymentProjects);
        await m.createTable(deploymentResources);
        // Preserve every existing Compose link as its own general project.
        // The link remains the live-operation authority while the new catalog
        // supplies a portable resource description around it.
        await customStatement('''
          INSERT INTO deployment_projects (name, description, created_at, updated_at)
          SELECT name, 'Migrated Compose link ' || id, linked_at, linked_at
          FROM compose_project_links
        ''');
        await customStatement('''
          INSERT INTO deployment_resources
            (project_id, kind, name, server_id, configuration, created_at, updated_at)
          SELECT deployment_projects.id, 'compose', compose_project_links.name,
            compose_project_links.server_id,
            '{"compose_link_id":' || compose_project_links.id || '}',
            compose_project_links.linked_at, compose_project_links.linked_at
          FROM compose_project_links
          INNER JOIN deployment_projects
            ON deployment_projects.description =
              'Migrated Compose link ' || compose_project_links.id
        ''');
      }
      if (from < 8) {
        await m.createTable(scriptSnippets);
      }
      if (from < 9) {
        await m.createTable(savedCredentials);
        await m.addColumn(servers, servers.credentialId);
        // Each pre-relationship server gets its own saved credential. Keeping
        // the original ciphertext means no vault unlock is required here.
        await customStatement('''
          INSERT INTO saved_credentials
            (name, credential_type, encrypted_credential, credential_nonce, created_at, updated_at)
          SELECT name, credential_type, encrypted_credential, credential_nonce,
            COALESCE(created_at, CURRENT_TIMESTAMP), COALESCE(updated_at, CURRENT_TIMESTAMP)
          FROM servers
          WHERE encrypted_credential IS NOT NULL
            AND credential_nonce IS NOT NULL
            AND credential_type IS NOT NULL
        ''');
        await customStatement('''
          UPDATE servers
          SET credential_id = (
            SELECT saved_credentials.id FROM saved_credentials
            WHERE saved_credentials.name = servers.name
              AND saved_credentials.encrypted_credential = servers.encrypted_credential
              AND saved_credentials.credential_nonce = servers.credential_nonce
            ORDER BY saved_credentials.id DESC LIMIT 1
          )
          WHERE encrypted_credential IS NOT NULL AND credential_nonce IS NOT NULL
        ''');
      }
      if (from < 10) {
        // Keep the encrypted sync passphrase with the vault instead of only in
        // the OS keychain, so biometric unlock (which recovers the data key)
        // can always decrypt it for cloud sync.
        await m.addColumn(
          vaultMetadata,
          vaultMetadata.syncPassphraseCiphertext,
        );
        await m.addColumn(vaultMetadata, vaultMetadata.syncPassphraseNonce);
      }
      if (from < 11) {
        await m.createTable(agentSettings);
      }
      if (from < 12) {
        await m.createTable(agentProviders);
        // Preserve the profile introduced in schema 11 as an OpenAI profile.
        await customStatement('''
          INSERT INTO agent_providers
            (name, encrypted_api_key, api_key_nonce, base_url, model, updated_at)
          SELECT 'OpenAI', encrypted_api_key, api_key_nonce,
            'https://api.openai.com/v1', model, updated_at
          FROM agent_settings
        ''');
      }
      if (from < 13) {
        await m.createTable(agentProviderModels);
        await customStatement('''
          INSERT INTO agent_provider_models (provider_id, model, created_at)
          SELECT id, model, updated_at FROM agent_providers
        ''');
      }
      if (from < 14) {
        // dart_openai appends its API version itself. Version 12 presets
        // included /v1, which resulted in requests such as /v1/v1/chat.
        await customStatement('''
          UPDATE agent_providers
          SET base_url = SUBSTR(base_url, 1, LENGTH(base_url) - 3)
          WHERE base_url LIKE '%/v1'
        ''');
      }
      if (from < 15) {
        // Table removed in schema 17; kept as raw SQL so upgrades from older
        // schemas still reproduce the historical layout.
        await customStatement('''
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
      }
      if (from < 16) {
        await m.createTable(mcpServers);
        await m.createTable(agentSkills);
      }
      if (from < 17) {
        // Conversation history moved out of the vault database into JSONL
        // files under the app's internal storage.
        await customStatement('DROP TABLE IF EXISTS agent_conversations');
      }
      if (from < 18) {
        await m.addColumn(servers, servers.proxyType);
        await m.addColumn(servers, servers.proxyHost);
        await m.addColumn(servers, servers.proxyPort);
        await m.addColumn(servers, servers.proxyUsername);
        await m.addColumn(servers, servers.encryptedProxyPassword);
        await m.addColumn(servers, servers.proxyPasswordNonce);
      }
      if (from < 19) {
        await m.createTable(gitHubConnections);
        await m.createTable(gitHubRepoPins);
        await customStatement(
          'CREATE UNIQUE INDEX github_repo_pins_unique '
          'ON github_repo_pins (connection_id, owner, name)',
        );
      }
      if (from < 20) {
        await m.addColumn(servers, servers.environment);
        await m.addColumn(servers, servers.initialSnippets);
        await m.addColumn(servers, servers.tags);
      }
      if (from < 21) {
        // Workflow links became a regular deployment resource (kind
        // `githubWorkflow`, configuration JSON) in schema 21.
        await customStatement(
          'DROP TABLE IF EXISTS github_project_workflow_links',
        );
      }
      if (from < 22) {
        await m.addColumn(servers, servers.connectionType);
        await m.addColumn(servers, servers.serialConfig);
      }
      if (from < 23) {
        // Some development builds wrote a servers table that already
        // contained sort_order while still reporting schema 22. Guard the
        // ALTER so those databases upgrade instead of crashing on a
        // duplicate column.
        final hasSortOrder = await customSelect(
          "SELECT 1 FROM pragma_table_info('servers') "
          "WHERE name = 'sort_order'",
        ).get();
        if (hasSortOrder.isEmpty) {
          await m.addColumn(servers, servers.sortOrder);
        }
        // Preserve the current (creation-id) dashboard order for existing
        // servers; new servers are appended after the largest sort order.
        await customStatement(
          'UPDATE servers SET sort_order = id WHERE sort_order IS NULL',
        );
      }
      if (from < 24) {
        final hasJumpHostServerId = await customSelect(
          "SELECT 1 FROM pragma_table_info('servers') "
          "WHERE name = 'jump_host_server_id'",
        ).get();
        if (hasJumpHostServerId.isEmpty) {
          await m.addColumn(servers, servers.jumpHostServerId);
        }
      }
      if (from < 25) {
        final maidCafeColumns = await customSelect(
          "SELECT name FROM pragma_table_info('servers') "
          "WHERE name IN ('maid_cafe_daemon_url', "
          "'encrypted_maid_cafe_webhook_secret', "
          "'maid_cafe_webhook_secret_nonce')",
        ).get();
        final existing = maidCafeColumns
            .map((row) => row.read<String>('name'))
            .toSet();
        if (!existing.contains('maid_cafe_daemon_url')) {
          await m.addColumn(servers, servers.maidCafeDaemonUrl);
        }
        if (!existing.contains('encrypted_maid_cafe_webhook_secret')) {
          await m.addColumn(servers, servers.encryptedMaidCafeWebhookSecret);
        }
        if (!existing.contains('maid_cafe_webhook_secret_nonce')) {
          await m.addColumn(servers, servers.maidCafeWebhookSecretNonce);
        }
      }
      if (from < 26) {
        await m.addColumn(servers, servers.encryptedMaidCafeMetricsSecret);
        await m.addColumn(servers, servers.maidCafeMetricsSecretNonce);
      }
    },
  );

  Stream<List<Server>> watchServers() =>
      (select(servers)
            ..where((table) => table.deletedAt.isNull())
            ..orderBy([
              (table) => OrderingTerm.asc(table.sortOrder.isNull()),
              (table) => OrderingTerm.asc(table.sortOrder),
              (table) => OrderingTerm.asc(table.id),
            ]))
          .watch();

  Stream<List<ComposeProjectLink>> watchComposeProjectLinks() =>
      select(composeProjectLinks).watch();

  Stream<List<ContainerCacheEntry>> watchContainerCacheEntries() =>
      select(containerCacheEntries).watch();

  Stream<List<DeploymentProject>> watchDeploymentProjects() =>
      select(deploymentProjects).watch();

  Stream<List<DeploymentResource>> watchDeploymentResources() =>
      select(deploymentResources).watch();

  Stream<List<ScriptSnippet>> watchScriptSnippets() => (select(
    scriptSnippets,
  )..orderBy([(table) => OrderingTerm.asc(table.name)])).watch();

  Stream<List<AgentSetting>> watchAgentSettings() =>
      select(agentSettings).watch();

  Stream<List<AgentProvider>> watchAgentProviders() => (select(
    agentProviders,
  )..orderBy([(table) => OrderingTerm.asc(table.name)])).watch();

  Stream<List<AgentProviderModel>> watchAgentProviderModels(int providerId) =>
      (select(agentProviderModels)
            ..where((table) => table.providerId.equals(providerId))
            ..orderBy([(table) => OrderingTerm.asc(table.model)]))
          .watch();

  Stream<List<McpServer>> watchMcpServers() => (select(
    mcpServers,
  )..orderBy([(table) => OrderingTerm.asc(table.name)])).watch();

  Stream<List<AgentSkill>> watchAgentSkills() => (select(
    agentSkills,
  )..orderBy([(table) => OrderingTerm.asc(table.name)])).watch();

  Stream<List<GitHubConnection>> watchGitHubConnections() => (select(
    gitHubConnections,
  )..orderBy([(table) => OrderingTerm.asc(table.accountLogin)])).watch();

  Stream<List<GitHubRepoPin>> watchGitHubRepoPins() =>
      select(gitHubRepoPins).watch();
}
