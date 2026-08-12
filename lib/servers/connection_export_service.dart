import 'dart:convert';

import 'package:maid_kit/data/local/app_database.dart';

import 'server_models.dart';
import 'vault_service.dart';

/// Exports server connections in portable, human-readable formats.
///
/// Complements [DatabaseBackupService]: the `.mkb` archive is the canonical
/// full backup, while this service produces JSON/CSV files meant for other
/// tools and for sharing server lists with a team.
///
/// Sensitive fields (credentials, proxy passwords, environment variables)
/// are excluded from the redacted document. When a passphrase is supplied
/// they are collected into a single `secrets` block encrypted with the same
/// portable scheme as the `.mkb` archive, keyed by the server's position in
/// the exported list.
class ConnectionExportService {
  ConnectionExportService(this._database, this._vault);

  static const String formatName = 'maidkit-connections';
  static const int formatVersion = 1;

  /// CSV columns. Serial servers keep the `connectionType` marker; their
  /// serial settings and any secrets do not fit the flat format.
  static const List<String> csvHeader = [
    'name',
    'host',
    'port',
    'username',
    'authType',
    'tags',
    'connectionType',
  ];

  final AppDatabase _database;
  final VaultService _vault;

  /// Exports all active servers as a JSON document.
  ///
  /// Without [passphrase] the document is redacted: no passwords, private
  /// keys, proxy passwords, or environment variables are included. With one,
  /// those fields are collected into the passphrase-encrypted `secrets`
  /// block (see [VaultService.encryptPortable]).
  Future<String> exportJson({String? passphrase}) async {
    final servers = await _activeServers();
    final credentials = await _database
        .select(_database.savedCredentials)
        .get();
    final credentialsById = {
      for (final credential in credentials) credential.id: credential,
    };
    final serversById = {for (final server in servers) server.id: server};

    final serverRecords = <Map<String, Object?>>[
      for (final server in servers)
        _redactedServerRecord(server, credentialsById, serversById),
    ];
    final credentialRecords = <Map<String, Object?>>[
      for (final credential in credentials)
        {'name': credential.name, 'authType': credential.credentialType},
    ];

    final document = <String, Object?>{
      'format': formatName,
      'version': formatVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'servers': serverRecords,
      'savedCredentials': credentialRecords,
    };

    if (passphrase != null) {
      final secretRecords = <Map<String, Object?>>[];
      for (final (index, server) in servers.indexed) {
        secretRecords.add(
          await _secretRecordFor(server, index, credentialsById),
        );
      }
      final credentialSecrets = <Map<String, Object?>>[];
      for (final (index, credential) in credentials.indexed) {
        credentialSecrets.add({
          'index': index,
          'credential': await _decryptCredential(
            credential.encryptedCredential,
            credential.credentialNonce,
          ),
        });
      }
      document['secrets'] = await _vault.encryptPortable(
        jsonEncode({
          'servers': secretRecords,
          'savedCredentials': credentialSecrets,
        }),
        passphrase,
      );
    }

    return jsonEncode(document);
  }

  /// Exports all active servers as a CSV document. Always redacted.
  Future<String> exportCsv() async {
    final servers = await _activeServers();
    final credentials = await _database
        .select(_database.savedCredentials)
        .get();
    final credentialsById = {
      for (final credential in credentials) credential.id: credential,
    };
    final buffer = StringBuffer('${csvHeader.join(',')}\n');
    for (final server in servers) {
      buffer
        ..writeAll([
          _csvField(server.name),
          _csvField(server.host),
          '${server.port}',
          _csvField(server.username),
          _csvField(credentialsById[server.credentialId]?.credentialType ?? ''),
          _csvField(decodeStringList(server.tags).map(_escapeTag).join(',')),
          server.connectionType,
        ], ',')
        ..writeln();
    }
    return buffer.toString();
  }

  Future<List<Server>> _activeServers() => (_database.select(
    _database.servers,
  )..where((table) => table.deletedAt.isNull())).get();

  Map<String, Object?> _redactedServerRecord(
    Server server,
    Map<int, SavedCredential> credentialsById,
    Map<int, Server> serversById,
  ) {
    final jumpHost = server.jumpHostServerId == null
        ? null
        : serversById[server.jumpHostServerId!];
    final record = <String, Object?>{
      'name': server.name,
      'host': server.host,
      'port': server.port,
      'username': server.username,
      'authType': credentialsById[server.credentialId]?.credentialType,
      'tags': decodeStringList(server.tags),
      'connectionType': server.connectionType,
      'syncId': server.syncId,
      'jumpHostSyncId': jumpHost?.syncId,
      'proxy': ?_redactedProxy(server),
    };
    final serialConfig = server.serialConfig;
    if (serialConfig != null &&
        server.connectionType == ServerConnectionType.serial.name) {
      record['serial'] = jsonDecode(serialConfig);
    }
    return record;
  }

  /// The proxy without its password; the password travels in the secrets
  /// block when a passphrase is used.
  Map<String, Object?>? _redactedProxy(Server server) {
    final type = server.proxyType;
    final host = server.proxyHost;
    if (type == null ||
        type == ServerProxyType.none.name ||
        host == null ||
        host.isEmpty) {
      return null;
    }
    return {
      'type': type,
      'host': host,
      'port': server.proxyPort ?? 1080,
      'username': server.proxyUsername,
    };
  }

  /// Decrypts the credential attached to [server] (via the shared credential
  /// store), or null when the server has none.
  Future<Map<String, Object?>?> _secretCredentialFor(
    Server server,
    Map<int, SavedCredential> credentialsById,
  ) async {
    final row = server.credentialId == null
        ? null
        : credentialsById[server.credentialId];
    if (row == null) return null;
    return {
      'credential': await _decryptCredential(
        row.encryptedCredential,
        row.credentialNonce,
      ),
    };
  }

  Future<Map<String, Object?>> _secretRecordFor(
    Server server,
    int index,
    Map<int, SavedCredential> credentialsById,
  ) async {
    final entry = <String, Object?>{
      'index': index,
      ...?await _secretCredentialFor(server, credentialsById),
    };
    if (server.encryptedProxyPassword != null &&
        server.proxyPasswordNonce != null) {
      entry['proxyPassword'] = await _vault.decrypt(
        EncryptedValue(
          bytes: server.encryptedProxyPassword!,
          nonce: server.proxyPasswordNonce!,
        ),
        context: 'server-proxy-password',
      );
    }
    final environment = decodeEnvironmentMap(server.environment);
    if (environment.isNotEmpty) entry['environment'] = environment;
    return entry;
  }

  Future<Map<String, Object?>> _decryptCredential(
    String ciphertext,
    String nonce,
  ) async {
    final value = await _vault.decrypt(
      EncryptedValue(bytes: ciphertext, nonce: nonce),
      context: 'server-credential',
    );
    return ServerCredential.decode(value).toJson();
  }
}

String _csvField(String value) {
  if (value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

/// Escapes a tag for the comma-joined CSV column so tags containing commas
/// or backslashes round-trip losslessly.
String _escapeTag(String tag) =>
    tag.replaceAll(r'\', r'\\').replaceAll(',', r'\,');
