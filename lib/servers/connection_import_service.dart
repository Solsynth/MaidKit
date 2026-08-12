import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import 'package:maid_kit/data/local/app_database.dart';

import 'connection_export_service.dart';
import 'connection_import_adapters.dart';
import 'server_models.dart';
import 'server_repository.dart';
import 'vault_service.dart';

/// Raised when a JSON document contains a passphrase-encrypted `secrets`
/// block but no passphrase was supplied.
class ConnectionSecretsLockedException implements Exception {
  const ConnectionSecretsLockedException();

  @override
  String toString() => 'This export contains encrypted secrets.';
}

/// Raised when the passphrase supplied for a protected export is incorrect.
class ConnectionSecretsPassphraseException implements Exception {
  const ConnectionSecretsPassphraseException();

  @override
  String toString() => 'The passphrase is incorrect.';
}

/// One row of the import preview. [existing] is set when a non-deleted server
/// with the same host, port, and username already exists.
class ImportCandidate {
  const ImportCandidate({required this.connection, this.existing});

  final ImportedConnection connection;
  final Server? existing;

  bool get isDuplicate => existing != null;
}

class ConnectionImportResult {
  const ConnectionImportResult({required this.created});

  final int created;
}

/// The outcome of parsing a batch of picked connection files.
class ConnectionFilesPreview {
  const ConnectionFilesPreview({
    required this.candidates,
    this.firstError,
    this.aborted = false,
  });

  final List<ImportCandidate> candidates;

  /// The first non-fatal parse error (e.g. a wrong passphrase or an
  /// unrecognized file) when some files failed but others parsed.
  final Object? firstError;

  /// True when the user cancelled the passphrase prompt; parsing stopped.
  final bool aborted;

  bool get isEmpty => candidates.isEmpty;
}

/// Imports connections from MaidKit's own JSON/CSV exports (see
/// [ConnectionExportService]).
///
/// JSON exports fall into two shapes:
/// - redacted: no credentials, proxy passwords, or environment variables are
///   present, so imported servers are created without a credential;
/// - protected: a passphrase-encrypted `secrets` block carries them, keyed by
///   the server's position in the exported list.
///
/// CSV is always redacted and carries only name/host/port/username/tags/
/// connectionType.
class ConnectionImportService {
  ConnectionImportService(this._database, this._vault);

  final AppDatabase _database;
  final VaultService _vault;

  /// Parses a JSON export and matches candidates against existing servers.
  ///
  /// Throws [ConnectionSecretsLockedException] when the document has a
  /// `secrets` block and [passphrase] is null, and
  /// [ConnectionSecretsPassphraseException] when the passphrase is wrong.
  Future<List<ImportCandidate>> previewJson(
    String content, {
    String? passphrase,
  }) async {
    final document = _decodeDocument(content);

    final rawServers = document['servers'];
    if (rawServers is! List) {
      throw const FormatException('Invalid servers list in connections file.');
    }

    final secrets = await _decryptSecrets(document['secrets'], passphrase);
    final serverSecrets = <int, Map<String, dynamic>>{};
    if (secrets != null) {
      final rawServerSecrets = secrets['servers'];
      if (rawServerSecrets is List) {
        for (final item in rawServerSecrets) {
          if (item is Map<String, dynamic> && item['index'] is int) {
            serverSecrets[item['index'] as int] = item;
          }
        }
      }
    }

    final existing = await _activeServers();
    final candidates = <ImportCandidate>[];
    for (final (index, raw) in rawServers.indexed) {
      if (raw is! Map<String, dynamic>) {
        throw FormatException('Invalid server record at index $index.');
      }
      final connection = _parseServerRecord(raw, index, serverSecrets);
      candidates.add(
        ImportCandidate(
          connection: connection,
          existing: _findExisting(existing, connection),
        ),
      );
    }
    return candidates;
  }

  /// Parses a CSV export (see [ConnectionExportService.csvHeader]) and
  /// matches candidates against existing servers.
  Future<List<ImportCandidate>> previewCsv(String content) async {
    final rows = _parseCsv(content);
    if (rows.isEmpty) {
      throw const FormatException('The connections CSV file is empty.');
    }
    if (!_matchesHeader(rows.first)) {
      throw const FormatException('Unsupported connections CSV header.');
    }

    final existing = await _activeServers();
    final candidates = <ImportCandidate>[];
    for (final row in rows.skip(1)) {
      final connection = _parseCsvRecord(row);
      candidates.add(
        ImportCandidate(
          connection: connection,
          existing: _findExisting(existing, connection),
        ),
      );
    }
    return candidates;
  }

  /// Routes [content] to the right parser: MaidKit JSON (redacted or
  /// protected), MaidKit CSV, or a third-party client via
  /// [detectThirdPartyAdapter]. [baseDirectory] is the folder of the picked
  /// file, used to resolve relative private-key paths.
  ///
  /// Throws [ConnectionSecretsLockedException] when a protected MaidKit JSON
  /// needs a passphrase.
  Future<List<ImportCandidate>> previewAny(
    String content, {
    String? baseDirectory,
    String? passphrase,
  }) async {
    if (content.trimLeft().startsWith('{')) {
      try {
        return await previewJson(content, passphrase: passphrase);
      } on FormatException {
        // Not a MaidKit JSON document; fall through to the other formats.
      }
    }
    final rows = _parseCsv(content);
    if (rows.isNotEmpty && _matchesHeader(rows.first)) {
      return previewCsv(content);
    }
    return previewThirdParty(content, baseDirectory: baseDirectory);
  }

  /// Parses a batch of picked files with [previewAny], prompting once for a
  /// passphrase via [requestPassphrase] when a protected MaidKit JSON needs
  /// one. A null result from [requestPassphrase] (user cancelled) aborts the
  /// batch. Wrong passphrases and unreadable or unrecognized files are
  /// recorded in [ConnectionFilesPreview.firstError]; files that parse still
  /// contribute candidates.
  Future<ConnectionFilesPreview> previewFiles(
    List<String> paths, {
    Future<String?> Function()? requestPassphrase,
  }) async {
    final candidates = <ImportCandidate>[];
    String? passphrase;
    Object? firstError;

    for (final path in paths) {
      final String content;
      try {
        content = await File(path).readAsString();
      } catch (error) {
        firstError ??= error;
        continue;
      }
      final baseDirectory = File(path).parent.path;
      try {
        candidates.addAll(
          await previewAny(
            content,
            baseDirectory: baseDirectory,
            passphrase: passphrase,
          ),
        );
      } on ConnectionSecretsLockedException {
        if (passphrase != null) {
          firstError ??= const ConnectionSecretsLockedException();
          continue;
        }
        final entered = await requestPassphrase?.call();
        if (entered == null) {
          return ConnectionFilesPreview(candidates: candidates, aborted: true);
        }
        passphrase = entered;
        try {
          candidates.addAll(
            await previewAny(
              content,
              baseDirectory: baseDirectory,
              passphrase: passphrase,
            ),
          );
        } on ConnectionSecretsPassphraseException {
          firstError ??= const ConnectionSecretsPassphraseException();
        } on Exception catch (error) {
          firstError ??= error;
        }
      } on ConnectionSecretsPassphraseException {
        firstError ??= const ConnectionSecretsPassphraseException();
      } on Exception catch (error) {
        firstError ??= error;
      }
    }
    return ConnectionFilesPreview(
      candidates: candidates,
      firstError: firstError,
    );
  }

  /// Parses a third-party client file (OpenSSH config, FinalShell, XShell,
  /// SecureCRT, MobaXterm, PuTTY) and matches candidates against existing
  /// servers. Throws [FormatException] when the format is unrecognized.
  Future<List<ImportCandidate>> previewThirdParty(
    String content, {
    String? baseDirectory,
  }) async {
    final adapter = detectThirdPartyAdapter(content);
    if (adapter == null) {
      throw const FormatException('Unrecognized connection file.');
    }
    final existing = await _activeServers();
    final connections = adapter.parse(content, baseDirectory: baseDirectory);
    return [
      for (final connection in connections)
        ImportCandidate(
          connection: connection,
          existing: _findExisting(existing, connection),
        ),
    ];
  }

  /// Creates the selected candidates inside one transaction.
  Future<ConnectionImportResult> import(List<ImportCandidate> selected) async {
    final repository = ServerRepository(_database, _vault);
    var created = 0;
    await _database.transaction(() async {
      final createdServers = <(ImportedConnection, Server)>[];
      for (final candidate in selected) {
        final connection = candidate.connection;
        final server = await repository.create(
          ServerDraft(
            name: connection.name,
            host: connection.host,
            port: connection.port,
            username: connection.username,
            credential: connection.credential,
            credentialName: connection.credential == null
                ? null
                : connection.name,
            proxy: connection.proxy,
            environment: connection.environment,
            tags: connection.tags,
            connectionType: connection.connectionType,
            serialConfig: connection.serialConfig,
          ),
        );
        createdServers.add((connection, server));
        created += 1;
      }
      final serversBySourceSyncId = {
        for (final entry in createdServers)
          if (entry.$1.sourceSyncId != null) entry.$1.sourceSyncId!: entry.$2,
      };
      for (final entry in createdServers) {
        final sourceJumpId = entry.$1.jumpHostSyncId;
        final jumpHost = sourceJumpId == null
            ? null
            : serversBySourceSyncId[sourceJumpId];
        if (sourceJumpId != null && jumpHost == null) continue;
        await repository.setJumpHostServerId(entry.$2.id, jumpHost?.id);
      }
    });
    return ConnectionImportResult(created: created);
  }

  Map<String, dynamic> _decodeDocument(String content) {
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Not a MaidKit connections JSON file.');
    }
    if (decoded['format'] != ConnectionExportService.formatName) {
      throw const FormatException('Unsupported connections file format.');
    }
    if (decoded['version'] != ConnectionExportService.formatVersion) {
      throw const FormatException('Unsupported connections file version.');
    }
    return decoded;
  }

  Future<Map<String, dynamic>?> _decryptSecrets(
    Object? block,
    String? passphrase,
  ) async {
    if (block == null) return null;
    if (passphrase == null) {
      throw const ConnectionSecretsLockedException();
    }
    final String clearText;
    try {
      clearText = await _vault.decryptPortable(block as String, passphrase);
    } on SecretBoxAuthenticationError {
      throw const ConnectionSecretsPassphraseException();
    } on FormatException {
      throw const ConnectionSecretsPassphraseException();
    } on TypeError {
      throw const FormatException('Invalid secrets block in connections file.');
    }
    final decoded = jsonDecode(clearText);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid secrets block in connections file.');
    }
    return decoded;
  }

  ImportedConnection _parseServerRecord(
    Map<String, dynamic> raw,
    int index,
    Map<int, Map<String, dynamic>> serverSecrets,
  ) {
    final connectionType =
        _stringField(
              raw,
              'connectionType',
              fallback: ServerConnectionType.ssh.name,
            ) ==
            ServerConnectionType.serial.name
        ? ServerConnectionType.serial
        : ServerConnectionType.ssh;

    SerialConfig? serialConfig;
    if (connectionType == ServerConnectionType.serial) {
      final rawSerial = raw['serial'];
      if (rawSerial is Map<String, dynamic>) {
        serialConfig = SerialConfig(
          device: _stringField(rawSerial, 'device'),
          baudRate: rawSerial['baudRate'] is int
              ? rawSerial['baudRate'] as int
              : 115200,
          dataBits: rawSerial['dataBits'] is int
              ? rawSerial['dataBits'] as int
              : 8,
          parity: _serialParity(rawSerial['parity']),
          stopBits: rawSerial['stopBits'] is int
              ? rawSerial['stopBits'] as int
              : 1,
          flowControl: _serialFlowControl(rawSerial['flowControl']),
        );
      }
    }

    ServerProxy? proxy;
    final rawProxy = raw['proxy'];
    if (rawProxy is Map<String, dynamic>) {
      proxy = ServerProxy(
        type: _proxyType(rawProxy['type']),
        host: _stringField(rawProxy, 'host'),
        port: rawProxy['port'] is int ? rawProxy['port'] as int : 1080,
        username: rawProxy['username'] as String?,
      );
    }

    ServerCredential? credential;
    Map<String, String> environment = const {};
    String? proxyPassword;
    final secrets = serverSecrets[index];
    if (secrets != null) {
      final rawCredential = secrets['credential'];
      if (rawCredential is Map<String, dynamic>) {
        credential =
            _stringField(rawCredential, 'type') ==
                CredentialType.privateKey.name
            ? ServerCredential.privateKey(
                privateKey: rawCredential['privateKey'] as String? ?? '',
                keyPassphrase: rawCredential['keyPassphrase'] as String?,
              )
            : ServerCredential.password(
                rawCredential['password'] as String? ?? '',
              );
      }
      proxyPassword = secrets['proxyPassword'] as String?;
      final rawEnvironment = secrets['environment'];
      if (rawEnvironment is Map<String, dynamic>) {
        environment = rawEnvironment.map(
          (key, value) => MapEntry(key, value.toString()),
        );
      }
    }

    if (proxy != null && proxyPassword != null) {
      proxy = ServerProxy(
        type: proxy.type,
        host: proxy.host,
        port: proxy.port,
        username: proxy.username,
        password: proxyPassword,
      );
    }

    final rawTags = raw['tags'];
    return ImportedConnection(
      name: _stringField(raw, 'name'),
      host: _stringField(raw, 'host'),
      port: raw['port'] is int ? raw['port'] as int : 22,
      username: _stringField(raw, 'username'),
      connectionType: connectionType,
      sourceSyncId: raw['syncId'] as String?,
      credential: credential,
      proxy: proxy,
      jumpHostSyncId: raw['jumpHostSyncId'] as String?,
      environment: environment,
      tags: rawTags is List
          ? [
              for (final tag in rawTags)
                if (tag is String && tag.isNotEmpty) tag,
            ]
          : const [],
      serialConfig: serialConfig,
    );
  }

  ImportedConnection _parseCsvRecord(List<String> row) {
    if (row.length < ConnectionExportService.csvHeader.length) {
      throw const FormatException('Invalid row in connections CSV file.');
    }
    final port = row[2].trim();
    if (port.isNotEmpty && int.tryParse(port) == null) {
      throw FormatException('Invalid port "$port" in connections CSV file.');
    }
    final connectionType = row[6].trim() == ServerConnectionType.serial.name
        ? ServerConnectionType.serial
        : ServerConnectionType.ssh;
    return ImportedConnection(
      name: row[0].trim(),
      host: row[1].trim(),
      port: int.tryParse(port) ?? 22,
      username: row[3].trim(),
      connectionType: connectionType,
      // CSV is always redacted: no credential, proxy, or environment.
      tags: _splitTags(row[5]),
    );
  }

  bool _matchesHeader(List<String> header) {
    if (header.length != ConnectionExportService.csvHeader.length) {
      return false;
    }
    for (var i = 0; i < header.length; i++) {
      if (header[i].trim() != ConnectionExportService.csvHeader[i]) {
        return false;
      }
    }
    return true;
  }

  Server? _findExisting(List<Server> servers, ImportedConnection connection) {
    final host = connection.host.toLowerCase();
    for (final server in servers) {
      if (server.host.toLowerCase() == host &&
          server.port == connection.port &&
          server.username == connection.username) {
        return server;
      }
    }
    return null;
  }

  Future<List<Server>> _activeServers() => (_database.select(
    _database.servers,
  )..where((table) => table.deletedAt.isNull())).get();

  static String _stringField(
    Map<String, dynamic> map,
    String key, {
    String fallback = '',
  }) {
    final value = map[key];
    return value is String ? value : fallback;
  }

  static SerialParity _serialParity(Object? value) {
    if (value is! String) return SerialParity.none;
    for (final parity in SerialParity.values) {
      if (parity.name == value) return parity;
    }
    return SerialParity.none;
  }

  static SerialFlowControl _serialFlowControl(Object? value) {
    if (value is! String) return SerialFlowControl.none;
    for (final control in SerialFlowControl.values) {
      if (control.name == value) return control;
    }
    return SerialFlowControl.none;
  }

  static ServerProxyType _proxyType(Object? value) {
    if (value is! String) return ServerProxyType.none;
    for (final type in ServerProxyType.values) {
      if (type.name == value) return type;
    }
    return ServerProxyType.none;
  }

  /// Splits the comma-joined CSV tags column, honoring the escaping in
  /// ConnectionExportService: `\,` is a literal comma and `\\` a literal
  /// backslash, so tags containing either round-trip losslessly.
  static List<String> _splitTags(String field) {
    final tags = <String>[];
    final buffer = StringBuffer();
    var index = 0;
    while (index < field.length) {
      final char = field[index];
      if (char == r'\' && index + 1 < field.length) {
        buffer.write(field[index + 1]);
        index += 2;
        continue;
      }
      if (char == ',') {
        tags.add(buffer.toString());
        buffer.clear();
        index += 1;
        continue;
      }
      buffer.write(char);
      index += 1;
    }
    tags.add(buffer.toString());
    return [
      for (final tag in tags)
        if (tag.trim().isNotEmpty) tag.trim(),
    ];
  }
}

/// Minimal RFC-4180 parser: quoted fields with doubled quotes, commas and
/// newlines inside quotes, CRLF tolerated.
List<List<String>> _parseCsv(String content) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var index = 0;

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    if (row.length != 1 || row.first.isNotEmpty) {
      rows.add(row);
    }
    row = <String>[];
  }

  while (index < content.length) {
    final char = content[index];
    if (inQuotes) {
      if (char == '"') {
        if (index + 1 < content.length && content[index + 1] == '"') {
          field.write('"');
          index += 2;
          continue;
        }
        inQuotes = false;
        index += 1;
        continue;
      }
      field.write(char);
      index += 1;
      continue;
    }
    if (char == '"' && field.isEmpty) {
      inQuotes = true;
      index += 1;
      continue;
    }
    if (char == ',') {
      endField();
      index += 1;
      continue;
    }
    if (char == '\n') {
      endRow();
      index += 1;
      continue;
    }
    if (char == '\r') {
      index += 1;
      continue;
    }
    field.write(char);
    index += 1;
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    endRow();
  }
  return rows;
}
