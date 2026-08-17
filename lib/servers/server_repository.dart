import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:maid_kit/data/local/app_database.dart';
import 'port_forwarding_models.dart';
import 'server_models.dart';
import 'maidcafe_service.dart';
import 'vault_service.dart';

class ServerRepository {
  ServerRepository(this._database, this._vault);

  final AppDatabase _database;
  final VaultService _vault;
  final Uuid _uuid = const Uuid();

  Stream<List<Server>> watchAll() => _database.watchServers();

  Future<List<Server>> all() =>
      (_database.select(_database.servers)
            ..where((table) => table.deletedAt.isNull())
            ..orderBy([
              (table) => OrderingTerm.asc(table.sortOrder.isNull()),
              (table) => OrderingTerm.asc(table.sortOrder),
              (table) => OrderingTerm.asc(table.id),
            ]))
          .get();

  Future<Server> create(ServerDraft draft) async {
    final now = DateTime.now().toUtc();
    final credentialId = await _credentialIdForDraft(draft, now);
    final proxyPassword =
        draft.proxy?.password == null || draft.proxy!.password!.isEmpty
        ? null
        : await _vault.encrypt(
            draft.proxy!.password!,
            context: 'server-proxy-password',
          );
    final id = await _database.transaction(() async {
      final maxOrder =
          await (_database.selectOnly(_database.servers)
                ..addColumns([_database.servers.sortOrder.max()])
                ..where(_database.servers.deletedAt.isNull()))
              .getSingle();
      final nextOrder =
          (maxOrder.read(_database.servers.sortOrder.max()) ?? -1) + 1;
      return _database
          .into(_database.servers)
          .insert(
            ServersCompanion.insert(
              name: draft.name.trim(),
              host: draft.host.trim(),
              port: Value(draft.port),
              username: draft.username.trim(),
              syncId: Value(_uuid.v4()),
              createdAt: Value(now),
              updatedAt: Value(now),
              credentialId: Value(credentialId),
              collectStats: Value(draft.collectStats),
              proxyType: Value(draft.proxy?.type.name),
              proxyHost: Value(draft.proxy?.host),
              proxyPort: Value(draft.proxy?.port),
              proxyUsername: Value(draft.proxy?.username),
              encryptedProxyPassword: Value(proxyPassword?.bytes),
              proxyPasswordNonce: Value(proxyPassword?.nonce),
              jumpHostServerId: Value(draft.jumpHostServerId),
              environment: Value(encodeEnvironmentMap(draft.environment)),
              initialSnippets: Value(
                encodeSnippetIdList(draft.initialSnippets),
              ),
              tags: Value(encodeStringList(draft.tags)),
              connectionType: Value(draft.connectionType.name),
              serialConfig: Value(encodeSerialConfig(draft.serialConfig)),
              sortOrder: Value(nextOrder),
            ),
          );
    });
    return (_database.select(
      _database.servers,
    )..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> update(Server server, ServerDraft draft) async {
    final credentialId = await _credentialIdForDraft(
      draft,
      DateTime.now().toUtc(),
    );
    final proxy = draft.proxy;
    // A new password replaces the stored one. Leaving the field blank keeps
    // the existing encrypted password, and removing the proxy clears it.
    final proxyPassword = proxy?.password == null
        ? null
        : proxy!.password!.isEmpty
        ? null
        : await _vault.encrypt(
            proxy.password!,
            context: 'server-proxy-password',
          );
    await (_database.update(
      _database.servers,
    )..where((table) => table.id.equals(server.id))).write(
      ServersCompanion(
        name: Value(draft.name.trim()),
        host: Value(draft.host.trim()),
        port: Value(draft.port),
        username: Value(draft.username.trim()),
        credentialId: Value(credentialId),
        collectStats: Value(draft.collectStats),
        collectSystemInfo: Value(draft.collectSystemInfo),
        proxyType: Value(proxy?.type.name),
        proxyHost: Value(proxy?.host),
        proxyPort: Value(proxy?.port),
        proxyUsername: Value(proxy?.username),
        encryptedProxyPassword: proxy == null
            ? const Value(null)
            : proxyPassword == null
            ? const Value.absent()
            : Value(proxyPassword.bytes),
        proxyPasswordNonce: proxy == null
            ? const Value(null)
            : proxyPassword == null
            ? const Value.absent()
            : Value(proxyPassword.nonce),
        jumpHostServerId: Value(draft.jumpHostServerId),
        environment: Value(encodeEnvironmentMap(draft.environment)),
        initialSnippets: Value(encodeSnippetIdList(draft.initialSnippets)),
        tags: Value(encodeStringList(draft.tags)),
        connectionType: Value(draft.connectionType.name),
        serialConfig: Value(encodeSerialConfig(draft.serialConfig)),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> setJumpHostServerId(int serverId, int? jumpHostServerId) =>
      (_database.update(
        _database.servers,
      )..where((table) => table.id.equals(serverId))).write(
        ServersCompanion(
          jumpHostServerId: Value(jumpHostServerId),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

  Future<ServerCredential> credentialFor(Server server) async {
    final credential = await credentialRecordFor(server);
    final value = await _vault.decrypt(
      EncryptedValue(
        bytes: credential.encryptedCredential,
        nonce: credential.credentialNonce,
      ),
      context: 'server-credential',
    );
    return ServerCredential.decode(value);
  }

  /// Returns the server's configured proxy with its password decrypted, or
  /// null when the server does not use a proxy.
  Future<ServerProxy?> proxyFor(Server server) async {
    final type = server.proxyType;
    final host = server.proxyHost;
    if (type == null ||
        type == ServerProxyType.none.name ||
        host == null ||
        host.isEmpty) {
      return null;
    }
    String? password;
    if (server.encryptedProxyPassword != null &&
        server.proxyPasswordNonce != null) {
      password = await _vault.decrypt(
        EncryptedValue(
          bytes: server.encryptedProxyPassword!,
          nonce: server.proxyPasswordNonce!,
        ),
        context: 'server-proxy-password',
      );
    }
    return ServerProxy(
      type: ServerProxyType.values.byName(type),
      host: host,
      port: server.proxyPort ?? 1080,
      username: server.proxyUsername,
      password: password,
    );
  }

  Future<void> updateMaidCafeConfig(
    Server server, {
    required String daemonUrl,
    String? webhookSecret,
    bool clearWebhookSecret = false,
    String? metricsSecret,
    bool clearMetricsSecret = false,
  }) async {
    final normalizedUrl = normalizeMaidCafeLocalDaemonUrl(daemonUrl);
    final encryptedSecret =
        webhookSecret == null || webhookSecret.trim().isEmpty
        ? null
        : await _vault.encrypt(
            webhookSecret.trim(),
            context: 'maidcafe-webhook-secret',
          );
    final encryptedMetricsSecret =
        metricsSecret == null || metricsSecret.trim().isEmpty
        ? null
        : await _vault.encrypt(
            metricsSecret.trim(),
            context: 'maidcafe-metrics-secret',
          );
    await (_database.update(
      _database.servers,
    )..where((table) => table.id.equals(server.id))).write(
      ServersCompanion(
        maidCafeDaemonUrl: Value(normalizedUrl),
        encryptedMaidCafeWebhookSecret: clearWebhookSecret
            ? const Value(null)
            : encryptedSecret == null
            ? const Value.absent()
            : Value(encryptedSecret.bytes),
        maidCafeWebhookSecretNonce: clearWebhookSecret
            ? const Value(null)
            : encryptedSecret == null
            ? const Value.absent()
            : Value(encryptedSecret.nonce),
        encryptedMaidCafeMetricsSecret: clearMetricsSecret
            ? const Value(null)
            : encryptedMetricsSecret == null
            ? const Value.absent()
            : Value(encryptedMetricsSecret.bytes),
        maidCafeMetricsSecretNonce: clearMetricsSecret
            ? const Value(null)
            : encryptedMetricsSecret == null
            ? const Value.absent()
            : Value(encryptedMetricsSecret.nonce),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> clearMaidCafeConfig(Server server) async {
    await (_database.update(
      _database.servers,
    )..where((table) => table.id.equals(server.id))).write(
      ServersCompanion(
        maidCafeDaemonUrl: const Value(null),
        encryptedMaidCafeWebhookSecret: const Value(null),
        maidCafeWebhookSecretNonce: const Value(null),
        encryptedMaidCafeMetricsSecret: const Value(null),
        maidCafeMetricsSecretNonce: const Value(null),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<String?> maidCafeWebhookSecretFor(Server server) async {
    final bytes = server.encryptedMaidCafeWebhookSecret;
    final nonce = server.maidCafeWebhookSecretNonce;
    if (bytes == null || nonce == null) return null;
    return _vault.decrypt(
      EncryptedValue(bytes: bytes, nonce: nonce),
      context: 'maidcafe-webhook-secret',
    );
  }

  Future<String?> maidCafeMetricsSecretFor(Server server) async {
    final bytes = server.encryptedMaidCafeMetricsSecret;
    final nonce = server.maidCafeMetricsSecretNonce;
    if (bytes == null || nonce == null) return null;
    return _vault.decrypt(
      EncryptedValue(bytes: bytes, nonce: nonce),
      context: 'maidcafe-metrics-secret',
    );
  }

  Stream<List<SavedCredential>> watchCredentials() => (_database.select(
    _database.savedCredentials,
  )..orderBy([(table) => OrderingTerm.asc(table.name)])).watch();

  Stream<List<PortForwardConfig>> watchPortForwardConfigs(int serverId) =>
      _database.watchPortForwardConfigs(serverId);

  Stream<List<RuntimeWatchConfig>> watchRuntimeWatchConfigs(int serverId) =>
      _database.watchRuntimeWatchConfigs(serverId);

  Stream<List<RuntimeWatchConfig>> watchPinnedRuntimeConfigs() =>
      _database.watchPinnedRuntimeConfigs();

  Stream<String?> watchAppSetting(String key) => _database.watchAppSetting(key);

  Future<String?> getAppSetting(String key) => _database.getAppSetting(key);

  Future<void> setAppSetting(String key, String value) =>
      _database.setAppSetting(key, value);

  /// Persists the enable/disable toggle for one runtime on a server. Absent
  /// rows default to enabled, so toggling back on inserts a row.
  Future<void> setRuntimeEnabled(
    int serverId,
    RuntimeKind kind,
    bool enabled,
  ) async {
    await _database
        .into(_database.runtimeWatchConfigs)
        .insertOnConflictUpdate(
          RuntimeWatchConfigsCompanion.insert(
            serverId: serverId,
            runtime: kind.name,
            enabled: Value(enabled),
          ),
        );
  }

  /// Pins or unpins a runtime/watched-process card on the server detail page
  /// for the dashboard. [runtime] is the wire runtime name or watched-process
  /// name; absent rows are created with the enabled default.
  Future<void> setRuntimePinned(
    int serverId,
    String runtime,
    bool pinned,
  ) async {
    await _database
        .into(_database.runtimeWatchConfigs)
        .insertOnConflictUpdate(
          RuntimeWatchConfigsCompanion.insert(
            serverId: serverId,
            runtime: runtime,
            pinned: Value(pinned),
          ),
        );
  }

  Future<List<PortForwardConfig>> portForwardConfigsForServer(int serverId) =>
      _database.portForwardConfigsForServer(serverId);

  /// Persists a port-forwarding preset. Saving the same forward (same server,
  /// direction, kind and endpoints) again updates the existing preset instead
  /// of creating a duplicate; [autoStart] can only turn auto-start on.
  Future<void> savePortForwardConfig({
    required int serverId,
    required PortForwardDirection direction,
    required PortForwardKind kind,
    required String bindHost,
    required int bindPort,
    required String targetHost,
    required int targetPort,
    bool autoStart = false,
  }) async {
    final now = DateTime.now().toUtc();
    final existing =
        await (_database.select(_database.portForwardConfigs)..where(
              (table) =>
                  table.serverId.equals(serverId) &
                  table.direction.equals(direction.name) &
                  table.kind.equals(kind.name) &
                  table.bindHost.equals(bindHost) &
                  table.bindPort.equals(bindPort) &
                  table.targetHost.equals(targetHost) &
                  table.targetPort.equals(targetPort),
            ))
            .getSingleOrNull();
    if (existing == null) {
      await _database
          .into(_database.portForwardConfigs)
          .insert(
            PortForwardConfigsCompanion.insert(
              serverId: serverId,
              direction: direction.name,
              kind: kind.name,
              bindHost: bindHost,
              bindPort: bindPort,
              targetHost: targetHost,
              targetPort: targetPort,
              autoStart: Value(autoStart),
              createdAt: now,
              updatedAt: now,
            ),
          );
    } else {
      await (_database.update(
        _database.portForwardConfigs,
      )..where((table) => table.id.equals(existing.id))).write(
        PortForwardConfigsCompanion(
          autoStart: Value(existing.autoStart || autoStart),
          updatedAt: Value(now),
        ),
      );
    }
  }

  Future<void> setPortForwardConfigAutoStart(int id, bool autoStart) =>
      (_database.update(
        _database.portForwardConfigs,
      )..where((table) => table.id.equals(id))).write(
        PortForwardConfigsCompanion(
          autoStart: Value(autoStart),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

  Future<void> deletePortForwardConfig(int id) => (_database.delete(
    _database.portForwardConfigs,
  )..where((table) => table.id.equals(id))).go();

  Future<List<SavedCredential>> credentials() => (_database.select(
    _database.savedCredentials,
  )..orderBy([(table) => OrderingTerm.asc(table.name)])).get();

  Future<SavedCredential> credentialRecordFor(Server server) async {
    final id = server.credentialId;
    if (id == null) {
      throw StateError('This server has no saved credential.');
    }
    return (_database.select(
      _database.savedCredentials,
    )..where((table) => table.id.equals(id))).getSingle();
  }

  Future<ServerCredential> decryptCredential(SavedCredential credential) async {
    final value = await _vault.decrypt(
      EncryptedValue(
        bytes: credential.encryptedCredential,
        nonce: credential.credentialNonce,
      ),
      context: 'server-credential',
    );
    return ServerCredential.decode(value);
  }

  Future<void> createCredential(SavedCredentialDraft draft) async {
    final now = DateTime.now().toUtc();
    await _insertCredential(draft, now);
  }

  Future<void> updateCredential(
    SavedCredential existing,
    SavedCredentialDraft draft,
  ) async {
    final encrypted = await _vault.encrypt(
      draft.credential.encode(),
      context: 'server-credential',
    );
    await (_database.update(
      _database.savedCredentials,
    )..where((table) => table.id.equals(existing.id))).write(
      SavedCredentialsCompanion(
        name: Value(draft.name.trim()),
        credentialType: Value(draft.credential.type.name),
        encryptedCredential: Value(encrypted.bytes),
        credentialNonce: Value(encrypted.nonce),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<int> serversUsingCredential(int credentialId) =>
      (_database.select(_database.servers)
            ..where((table) => table.credentialId.equals(credentialId))
            ..where((table) => table.deletedAt.isNull()))
          .get()
          .then((servers) => servers.length);

  Future<void> deleteCredential(SavedCredential credential) =>
      _database.transaction(() async {
        await (_database.update(_database.servers)
              ..where((table) => table.credentialId.equals(credential.id)))
            .write(const ServersCompanion(credentialId: Value(null)));
        await (_database.delete(
          _database.savedCredentials,
        )..where((table) => table.id.equals(credential.id))).go();
      });

  Future<int?> _credentialIdForDraft(ServerDraft draft, DateTime now) async {
    if (draft.credentialId case final id?) return id;
    final credential = draft.credential;
    // Credential-less servers are allowed (e.g. imported redacted connection
    // lists); the user assigns a credential later in the edit form.
    if (credential == null) return null;
    final encrypted = await _vault.encrypt(
      credential.encode(),
      context: 'server-credential',
    );
    return _database
        .into(_database.savedCredentials)
        .insert(
          SavedCredentialsCompanion.insert(
            name: draft.credentialName?.trim().isNotEmpty == true
                ? draft.credentialName!.trim()
                : draft.name.trim(),
            credentialType: credential.type.name,
            encryptedCredential: encrypted.bytes,
            credentialNonce: encrypted.nonce,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<int> _insertCredential(
    SavedCredentialDraft draft,
    DateTime now,
  ) async {
    final encrypted = await _vault.encrypt(
      draft.credential.encode(),
      context: 'server-credential',
    );
    return _database
        .into(_database.savedCredentials)
        .insert(
          SavedCredentialsCompanion.insert(
            name: draft.name.trim(),
            credentialType: draft.credential.type.name,
            encryptedCredential: encrypted.bytes,
            credentialNonce: encrypted.nonce,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<void> markConnected(int id) =>
      (_database.update(
        _database.servers,
      )..where((t) => t.id.equals(id))).write(
        ServersCompanion(
          lastConnectedAt: Value(DateTime.now().toUtc()),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

  /// Persists the dashboard display order. [orderedIds] must list every
  /// non-deleted server id exactly once; each server's position in the list
  /// becomes its [Server.sortOrder].
  Future<void> reorderServers(List<int> orderedIds) async {
    final now = DateTime.now().toUtc();
    await _database.batch((batch) {
      for (var i = 0; i < orderedIds.length; i++) {
        batch.update(
          _database.servers,
          ServersCompanion(sortOrder: Value(i), updatedAt: Value(now)),
          where: (table) => table.id.equals(orderedIds[i]),
        );
      }
    });
  }

  Future<void> rememberHostKey(int id, HostKeyPrompt hostKey) =>
      (_database.update(
        _database.servers,
      )..where((table) => table.id.equals(id))).write(
        ServersCompanion(
          hostKeyAlgorithm: Value(hostKey.algorithm),
          hostKeyFingerprint: Value(hostKey.fingerprint),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

  Future<void> delete(Server server) =>
      (_database.update(
        _database.servers,
      )..where((t) => t.id.equals(server.id))).write(
        ServersCompanion(
          deletedAt: Value(DateTime.now().toUtc()),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

  Future<String> exportArchive(String vaultPassword) async {
    final servers = await _database.select(_database.servers).get();
    final records = servers
        .map(
          (server) => {
            'syncId': server.syncId,
            'name': server.name,
            'host': server.host,
            'port': server.port,
            'username': server.username,
            'lastConnectedAt': server.lastConnectedAt?.toIso8601String(),
            'createdAt': server.createdAt?.toIso8601String(),
            'updatedAt': server.updatedAt?.toIso8601String(),
            'deletedAt': server.deletedAt?.toIso8601String(),
            'credentialType': server.credentialType,
            'encryptedCredential': server.encryptedCredential,
            'credentialNonce': server.credentialNonce,
            'collectStats': server.collectStats,
            'collectSystemInfo': server.collectSystemInfo,
            'proxyType': server.proxyType,
            'proxyHost': server.proxyHost,
            'proxyPort': server.proxyPort,
            'proxyUsername': server.proxyUsername,
            'encryptedProxyPassword': server.encryptedProxyPassword,
            'proxyPasswordNonce': server.proxyPasswordNonce,
            'environment': server.environment,
            'initialSnippets': server.initialSnippets,
            'tags': server.tags,
            'connectionType': server.connectionType,
            'serialConfig': server.serialConfig,
            'sortOrder': server.sortOrder,
          },
        )
        .toList();
    return _vault.encryptPortable(
      jsonEncode({'version': 1, 'servers': records}),
      vaultPassword,
    );
  }

  Future<List<PortableServerRecord>> previewImport(
    String archive,
    String vaultPassword,
  ) async {
    final plain = await _vault.decryptPortable(archive, vaultPassword);
    final payload = jsonDecode(plain) as Map<String, dynamic>;
    final local = await _database.select(_database.servers).get();
    return (payload['servers'] as List<dynamic>).map((item) {
      final value = item as Map<String, dynamic>;
      final existing = local
          .where((s) => s.syncId == value['syncId'])
          .firstOrNull;
      return PortableServerRecord(value, existing);
    }).toList();
  }

  Future<void> applyImport(Iterable<PortableServerRecord> records) async {
    await _database.batch((batch) {
      for (final record in records.where((r) => r.useImported)) {
        final value = record.value;
        final companion = ServersCompanion(
          name: Value(value['name'] as String),
          host: Value(value['host'] as String),
          port: Value(value['port'] as int),
          username: Value(value['username'] as String),
          syncId: Value(value['syncId'] as String),
          credentialType: Value(value['credentialType'] as String?),
          encryptedCredential: Value(value['encryptedCredential'] as String?),
          credentialNonce: Value(value['credentialNonce'] as String?),
          collectStats: Value(value['collectStats'] as bool? ?? true),
          collectSystemInfo: Value(value['collectSystemInfo'] as bool? ?? true),
          proxyType: Value(value['proxyType'] as String?),
          proxyHost: Value(value['proxyHost'] as String?),
          proxyPort: Value(value['proxyPort'] as int?),
          proxyUsername: Value(value['proxyUsername'] as String?),
          encryptedProxyPassword: Value(
            value['encryptedProxyPassword'] as String?,
          ),
          proxyPasswordNonce: Value(value['proxyPasswordNonce'] as String?),
          environment: Value(value['environment'] as String?),
          initialSnippets: Value(value['initialSnippets'] as String?),
          tags: Value(value['tags'] as String?),
          connectionType: Value(value['connectionType'] as String? ?? 'ssh'),
          serialConfig: Value(value['serialConfig'] as String?),
          sortOrder: Value(value['sortOrder'] as int?),
          createdAt: Value(DateTime.parse(value['createdAt'] as String)),
          updatedAt: Value(DateTime.parse(value['updatedAt'] as String)),
          deletedAt: Value(
            value['deletedAt'] == null
                ? null
                : DateTime.parse(value['deletedAt'] as String),
          ),
        );
        if (record.local == null) {
          batch.insert(_database.servers, companion);
        } else {
          batch.update(
            _database.servers,
            companion,
            where: (t) => t.id.equals(record.local!.id),
          );
        }
      }
    });
  }
}

class PortableServerRecord {
  PortableServerRecord(this.value, this.local);
  final Map<String, dynamic> value;
  final Server? local;
  bool useImported = false;
  bool get hasConflict => local != null;
}
