import 'dart:convert';

/// Database engines the Databases tab can inspect and maintain.
enum DatabaseEngine { postgres, mysql, mariadb }

extension DatabaseEngineX on DatabaseEngine {
  String get label => switch (this) {
    DatabaseEngine.postgres => 'PostgreSQL',
    DatabaseEngine.mysql => 'MySQL',
    DatabaseEngine.mariadb => 'MariaDB',
  };

  bool get isPostgres => this == DatabaseEngine.postgres;

  bool get isMySqlLike =>
      this == DatabaseEngine.mysql || this == DatabaseEngine.mariadb;
}

/// Quick maintenance operations offered per engine.
enum DatabaseMaintenanceAction {
  vacuumAnalyze,
  analyze,
  check,
  optimize,
  repair,
}

extension DatabaseMaintenanceActionX on DatabaseMaintenanceAction {
  String get id => switch (this) {
    DatabaseMaintenanceAction.vacuumAnalyze => 'vacuum_analyze',
    DatabaseMaintenanceAction.analyze => 'analyze',
    DatabaseMaintenanceAction.check => 'check',
    DatabaseMaintenanceAction.optimize => 'optimize',
    DatabaseMaintenanceAction.repair => 'repair',
  };

  String get label => switch (this) {
    DatabaseMaintenanceAction.vacuumAnalyze => 'VACUUM ANALYZE',
    DatabaseMaintenanceAction.analyze => 'ANALYZE',
    DatabaseMaintenanceAction.check => 'CHECK',
    DatabaseMaintenanceAction.optimize => 'OPTIMIZE',
    DatabaseMaintenanceAction.repair => 'REPAIR',
  };

  static DatabaseMaintenanceAction? fromId(String id) {
    for (final action in DatabaseMaintenanceAction.values) {
      if (action.id == id) return action;
    }
    return null;
  }
}

/// Maintenance actions available for [DatabaseEngine.postgres].
const postgresMaintenanceActions = [
  DatabaseMaintenanceAction.vacuumAnalyze,
  DatabaseMaintenanceAction.analyze,
];

/// Maintenance actions available for MySQL-like engines.
const mysqlMaintenanceActions = [
  DatabaseMaintenanceAction.check,
  DatabaseMaintenanceAction.analyze,
  DatabaseMaintenanceAction.optimize,
  DatabaseMaintenanceAction.repair,
];

/// A single database at the server level (no tables / data rows).
class DatabaseInfo {
  const DatabaseInfo({
    required this.name,
    this.owner,
    this.sizeBytes,
    this.sizeLabel,
    this.encoding,
  });

  final String name;
  final String? owner;
  final int? sizeBytes;
  final String? sizeLabel;
  final String? encoding;
}

/// One detected database engine installation on the host.
class DatabaseInstance {
  const DatabaseInstance({
    required this.engine,
    this.version,
    this.serviceName,
    this.running,
    this.enabled,
    this.port,
    this.socket,
    this.dataDirectory,
    this.configFile,
    this.binaryDirectory,
    this.cliPath,
    this.databases = const [],
    this.connections,
    this.error,
  });

  final DatabaseEngine engine;
  final String? version;

  /// systemd unit name (e.g. `postgresql@15-main`, `mysql`, `mariadb`).
  final String? serviceName;

  /// null when the service manager could not report state.
  final bool? running;

  /// null when the service manager could not report the boot state.
  final bool? enabled;

  final String? port;
  final String? socket;
  final String? dataDirectory;
  final String? configFile;
  final String? binaryDirectory;
  final String? cliPath;
  final List<DatabaseInfo> databases;
  final int? connections;

  /// Set when the engine was detected but its databases could not be read
  /// (for example MySQL without usable credentials).
  final String? error;
}

/// One pgBackRest backup set.
class PgBackRestBackup {
  const PgBackRestBackup({
    required this.label,
    required this.type,
    this.timestamp,
    this.sizeBytes,
    this.durationSeconds,
    this.database,
  });

  final String label;

  /// `full`, `incr` or `diff`.
  final String type;
  final DateTime? timestamp;
  final int? sizeBytes;
  final double? durationSeconds;
  final String? database;
}

/// One pgBackRest stanza (a named PostgreSQL cluster).
class PgBackRestStanza {
  const PgBackRestStanza({
    required this.name,
    this.databases = const [],
    this.repositoryPath,
    this.backups = const [],
  });

  final String name;
  final List<String> databases;
  final String? repositoryPath;
  final List<PgBackRestBackup> backups;

  PgBackRestBackup? get latestBackup => backups.isEmpty ? null : backups.first;
}

/// pgBackRest installation status on the host.
class PgBackRestStatus {
  const PgBackRestStatus({
    required this.installed,
    this.version,
    this.configFile,
    this.stanzas = const [],
    this.error,
  });

  final bool installed;
  final String? version;
  final String? configFile;
  final List<PgBackRestStanza> stanzas;
  final String? error;
}

/// Full result of the remote database inspection probe.
class DatabaseInspectionResult {
  const DatabaseInspectionResult({
    required this.instances,
    required this.pgBackRest,
    required this.collectedAt,
  });

  /// Detected engines in enum order.
  final List<DatabaseInstance> instances;
  final PgBackRestStatus pgBackRest;
  final DateTime collectedAt;

  DatabaseInstance? instanceFor(DatabaseEngine engine) =>
      instances.where((instance) => instance.engine == engine).firstOrNull;
}

/// A dump file found in a remote backup directory.
class DatabaseBackupFile {
  const DatabaseBackupFile({
    required this.name,
    required this.path,
    this.sizeBytes,
    this.modifiedLabel,
  });

  final String name;
  final String path;
  final int? sizeBytes;
  final String? modifiedLabel;
}

/// Backup sets managed by pgBackRest, keyed by stanza name.
const databaseInspectionBeginMarker = '---MAIDKIT-DB-BEGIN---';
const databaseInspectionEndMarker = '---MAIDKIT-DB-END---';
const _pgSection = '---MAIDKIT-DB-PG---';
const _mysqlSection = '---MAIDKIT-DB-MYSQL---';
const _mariadbSection = '---MAIDKIT-DB-MARIADB---';
const _pgBackRestSection = '---MAIDKIT-DB-PGBACKREST---';

const databaseBackupPathMarker = 'MAIDKIT_DB_BACKUP_PATH=';

/// Parses the database inspection probe output into a result.
///
/// The probe emits one section per detected engine plus a pgBackRest section.
/// Sections are `key: value` lines; database rows use `db: name|owner|bytes|
/// sizeLabel|encoding`. When the outer markers are missing the whole output
/// is still scanned so callers see partial data instead of nothing.
DatabaseInspectionResult parseDatabaseInspectionOutput(String output) {
  final begin = output.indexOf(databaseInspectionBeginMarker);
  final end = output.indexOf(
    databaseInspectionEndMarker,
    begin < 0 ? 0 : begin,
  );
  final body = begin >= 0 && end > begin
      ? output.substring(begin + databaseInspectionBeginMarker.length, end)
      : output;

  String section(String marker) {
    final start = body.indexOf(marker);
    if (start < 0) return '';
    final contentStart = start + marker.length;
    var end = body.length;
    for (final other in [
      _pgSection,
      _mysqlSection,
      _mariadbSection,
      _pgBackRestSection,
    ]) {
      if (other == marker) continue;
      final index = body.indexOf(other, contentStart);
      if (index >= 0 && index < end) end = index;
    }
    return body.substring(contentStart, end);
  }

  final instances = <DatabaseInstance>[];
  final pg = _parseInstanceSection(
    section(_pgSection),
    DatabaseEngine.postgres,
  );
  if (pg != null) instances.add(pg);
  final mysql = _parseInstanceSection(
    section(_mysqlSection),
    DatabaseEngine.mysql,
  );
  if (mysql != null) instances.add(mysql);
  final mariadb = _parseInstanceSection(
    section(_mariadbSection),
    DatabaseEngine.mariadb,
  );
  if (mariadb != null) instances.add(mariadb);

  return DatabaseInspectionResult(
    instances: instances,
    pgBackRest: _parsePgBackRestSection(section(_pgBackRestSection)),
    collectedAt: DateTime.now(),
  );
}

DatabaseInstance? _parseInstanceSection(String section, DatabaseEngine engine) {
  if (section.trim().isEmpty) return null;
  final lines = section.split('\n');

  String? value(String key) {
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (!line.startsWith('$key: ')) continue;
      return line.substring(key.length + 2).trim();
    }
    return null;
  }

  final databases = <DatabaseInfo>[];
  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (!line.startsWith('db: ')) continue;
    final fields = line.substring(4).split('|');
    if (fields.isEmpty || fields[0].isEmpty) continue;
    databases.add(
      DatabaseInfo(
        name: fields[0],
        owner: fields.length > 1 && fields[1].isNotEmpty ? fields[1] : null,
        sizeBytes: fields.length > 2 ? int.tryParse(fields[2]) : null,
        sizeLabel: fields.length > 3 && fields[3].isNotEmpty ? fields[3] : null,
        encoding: fields.length > 4 && fields[4].isNotEmpty ? fields[4] : null,
      ),
    );
  }

  bool? parseBool(String? raw) {
    if (raw == null) return null;
    if (raw == 'true') return true;
    if (raw == 'false') return false;
    return null;
  }

  return DatabaseInstance(
    engine: engine,
    version: value('version'),
    serviceName: value('service'),
    running: parseBool(value('running')),
    enabled: parseBool(value('enabled')),
    port: value('port'),
    socket: value('socket'),
    dataDirectory: value('datadir'),
    configFile: value('config'),
    binaryDirectory: value('bin'),
    cliPath: value('cli'),
    databases: databases,
    connections: int.tryParse(value('connections') ?? ''),
    error: value('error'),
  );
}

PgBackRestStatus _parsePgBackRestSection(String section) {
  if (section.trim().isEmpty) {
    return const PgBackRestStatus(installed: false);
  }
  final lines = section.split('\n');

  String? value(String key) {
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (!line.startsWith('$key: ')) continue;
      return line.substring(key.length + 2).trim();
    }
    return null;
  }

  if (value('installed') == 'false') {
    return const PgBackRestStatus(installed: false);
  }

  final json = value('info-json');
  final stanzas = json == null || json.isEmpty
      ? const <PgBackRestStanza>[]
      : parsePgBackRestInfoJson(json);

  return PgBackRestStatus(
    installed: true,
    version: value('version'),
    configFile: value('config'),
    stanzas: stanzas,
    error: value('error'),
  );
}

/// Parses `pgbackrest info --output=json` into stanzas.
///
/// Tolerant of schema drift across pgBackRest releases: unknown fields are
/// skipped, malformed entries are dropped, and a stanza with no backups is
/// still reported so the UI can offer a first backup.
List<PgBackRestStanza> parsePgBackRestInfoJson(String json) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } catch (_) {
    return const [];
  }
  if (decoded is! List) return const [];
  final stanzas = <PgBackRestStanza>[];
  for (final raw in decoded) {
    if (raw is! Map) continue;
    final name = raw['name']?.toString() ?? '';
    if (name.isEmpty) continue;

    final databases = <String>[];
    final dbRaw = raw['db'];
    if (dbRaw is List) {
      for (final db in dbRaw) {
        if (db is! Map) continue;
        final dbName = db['name']?.toString();
        if (dbName != null && dbName.isNotEmpty) databases.add(dbName);
      }
    }

    String? repositoryPath;
    final repoRaw = raw['repo'];
    if (repoRaw is List) {
      for (final repo in repoRaw) {
        if (repo is! Map) continue;
        final path = repo['path']?.toString();
        if (path != null && path.isNotEmpty) {
          repositoryPath = path;
          break;
        }
      }
    }
    if (repositoryPath == null && dbRaw is List) {
      for (final db in dbRaw) {
        if (db is! Map) continue;
        final repo = db['repo'];
        if (repo is Map) {
          final path = repo['path']?.toString();
          if (path != null && path.isNotEmpty) {
            repositoryPath = path;
            break;
          }
        }
      }
    }

    final backups = <PgBackRestBackup>[];
    final backupRaw = raw['backup'];
    if (backupRaw is List) {
      for (final backup in backupRaw) {
        if (backup is! Map) continue;
        final label = backup['label']?.toString() ?? '';
        if (label.isEmpty) continue;
        final timestamp = backup['timestamp'];
        backups.add(
          PgBackRestBackup(
            label: label,
            type: backup['type']?.toString() ?? 'full',
            timestamp: timestamp is num
                ? DateTime.fromMillisecondsSinceEpoch(
                    (timestamp * 1000).round(),
                    isUtc: true,
                  ).toLocal()
                : null,
            sizeBytes: backup['size'] is num
                ? (backup['size'] as num).toInt()
                : null,
            durationSeconds: backup['duration'] is num
                ? (backup['duration'] as num).toDouble()
                : null,
            database: backup['database'] is Map
                ? backup['database']['name']?.toString()
                : null,
          ),
        );
      }
    }

    stanzas.add(
      PgBackRestStanza(
        name: name,
        databases: databases,
        repositoryPath: repositoryPath,
        backups: backups,
      ),
    );
  }
  return stanzas;
}

/// Parses `find -printf '%f\t%s\t%TY-%Tm-%Td %TH:%TM'` output.
List<DatabaseBackupFile> parseDatabaseBackupListing(
  String output,
  String directory,
) {
  final files = <DatabaseBackupFile>[];
  for (final rawLine in output.split('\n')) {
    final fields = rawLine.split('\t');
    if (fields.length < 3 || fields[0].isEmpty) continue;
    files.add(
      DatabaseBackupFile(
        name: fields[0],
        path: '$directory/${fields[0]}',
        sizeBytes: int.tryParse(fields[1]),
        modifiedLabel: fields[2],
      ),
    );
  }
  return files;
}

// ---------------------------------------------------------------------------
// Performance metrics (daemon `databaseMetrics` SSE event, /api/v1/
// database-metrics, and the SSH fallback probe)
// ---------------------------------------------------------------------------

/// One PostgreSQL database's `pg_stat_database` counters.
class DatabaseConnectionInfo {
  const DatabaseConnectionInfo({
    required this.name,
    this.connections,
    this.commits,
    this.rollbacks,
    this.blksHit,
    this.blksRead,
    this.deadlocks,
  });

  final String name;
  final int? connections;
  final int? commits;
  final int? rollbacks;
  final int? blksHit;
  final int? blksRead;
  final int? deadlocks;
}

/// One engine's health snapshot. PostgreSQL fills the transaction / cache
/// counters plus per-database rows; MySQL-like engines fill the query /
/// buffer-pool counters. [memoryBytes] is `shared_buffers` for PostgreSQL
/// and `innodb_buffer_pool_size` for MySQL-like engines.
class DatabaseEngineMetrics {
  const DatabaseEngineMetrics({
    required this.engine,
    required this.available,
    this.error,
    this.version,
    this.connections,
    this.maxConnections,
    this.memoryBytes,
    this.memoryUsedBytes,
    this.memoryDirtyBytes,
    this.cacheHitRatio,
    this.commits,
    this.rollbacks,
    this.blksHit,
    this.blksRead,
    this.deadlocks,
    this.tempBytes,
    this.queries,
    this.slowQueries,
    this.threadsRunning,
    this.maxUsedConnections,
    this.uptimeSeconds,
    this.bytesReceived,
    this.bytesSent,
    this.databases = const [],
  });

  final DatabaseEngine engine;
  final bool available;
  final String? error;
  final String? version;
  final int? connections;
  final int? maxConnections;
  final int? memoryBytes;
  final int? memoryUsedBytes;
  final int? memoryDirtyBytes;
  final double? cacheHitRatio;
  final int? commits;
  final int? rollbacks;
  final int? blksHit;
  final int? blksRead;
  final int? deadlocks;
  final int? tempBytes;
  final int? queries;
  final int? slowQueries;
  final int? threadsRunning;
  final int? maxUsedConnections;
  final int? uptimeSeconds;
  final int? bytesReceived;
  final int? bytesSent;
  final List<DatabaseConnectionInfo> databases;

  int? get activeConnections => connections;
}

/// Snapshot of every engine the daemon (or SSH probe) could reach.
class DatabaseMetricsSnapshot {
  const DatabaseMetricsSnapshot({
    required this.collectedAt,
    required this.engines,
  });

  final DateTime collectedAt;
  final List<DatabaseEngineMetrics> engines;

  /// Metrics for [engine]; MySQL and MariaDB entries are interchangeable
  /// (a MariaDB host reports engine `mariadb`, the selector may show `mysql`).
  DatabaseEngineMetrics? forEngine(DatabaseEngine engine) {
    for (final entry in engines) {
      if (entry.engine == engine) return entry;
      if (engine.isMySqlLike && entry.engine.isMySqlLike) return entry;
    }
    return null;
  }
}

/// Rates derived from two consecutive metric samples.
class DatabaseMetricsRates {
  const DatabaseMetricsRates({
    this.transactionsPerSecond,
    this.queriesPerSecond,
  });

  /// PostgreSQL transactions (commit + rollback) per second.
  final double? transactionsPerSecond;

  /// MySQL-like queries per second.
  final double? queriesPerSecond;
}

DatabaseEngine? _engineFromWire(String name) {
  for (final engine in DatabaseEngine.values) {
    if (engine.name == name) return engine;
  }
  return null;
}

/// Parses the daemon `databaseMetrics` payload (SSE event or
/// `/api/v1/database-metrics`). Unknown engines are skipped.
DatabaseMetricsSnapshot parseDatabaseMetrics(Map<String, dynamic> json) {
  final engines = <DatabaseEngineMetrics>[];
  final rawEngines = json['engines'];
  if (rawEngines is List) {
    for (final raw in rawEngines) {
      if (raw is! Map) continue;
      final engine = _engineFromWire(raw['engine']?.toString() ?? '');
      if (engine == null) continue;
      final databases = <DatabaseConnectionInfo>[];
      final rawDatabases = raw['databases'];
      if (rawDatabases is List) {
        for (final db in rawDatabases) {
          if (db is! Map) continue;
          final name = db['name']?.toString();
          if (name == null || name.isEmpty) continue;
          databases.add(
            DatabaseConnectionInfo(
              name: name,
              connections: (db['connections'] as num?)?.toInt(),
              commits: (db['commits'] as num?)?.toInt(),
              rollbacks: (db['rollbacks'] as num?)?.toInt(),
              blksHit: (db['blks_hit'] as num?)?.toInt(),
              blksRead: (db['blks_read'] as num?)?.toInt(),
              deadlocks: (db['deadlocks'] as num?)?.toInt(),
            ),
          );
        }
      }
      final error = raw['error']?.toString();
      engines.add(
        DatabaseEngineMetrics(
          engine: engine,
          available: raw['available'] == true,
          error: error == null || error.isEmpty ? null : error,
          version: raw['version']?.toString(),
          connections: (raw['connections'] as num?)?.toInt(),
          maxConnections: (raw['max_connections'] as num?)?.toInt(),
          memoryBytes: (raw['memory_bytes'] as num?)?.toInt(),
          memoryUsedBytes: (raw['memory_used_bytes'] as num?)?.toInt(),
          memoryDirtyBytes: (raw['memory_dirty_bytes'] as num?)?.toInt(),
          cacheHitRatio: (raw['cache_hit_ratio'] as num?)?.toDouble(),
          commits: (raw['commits'] as num?)?.toInt(),
          rollbacks: (raw['rollbacks'] as num?)?.toInt(),
          blksHit: (raw['blks_hit'] as num?)?.toInt(),
          blksRead: (raw['blks_read'] as num?)?.toInt(),
          deadlocks: (raw['deadlocks'] as num?)?.toInt(),
          tempBytes: (raw['temp_bytes'] as num?)?.toInt(),
          queries: (raw['queries'] as num?)?.toInt(),
          slowQueries: (raw['slow_queries'] as num?)?.toInt(),
          threadsRunning: (raw['threads_running'] as num?)?.toInt(),
          maxUsedConnections: (raw['max_used_connections'] as num?)?.toInt(),
          uptimeSeconds: (raw['uptime_seconds'] as num?)?.toInt(),
          bytesReceived: (raw['bytes_received'] as num?)?.toInt(),
          bytesSent: (raw['bytes_sent'] as num?)?.toInt(),
          databases: databases,
        ),
      );
    }
  }
  return DatabaseMetricsSnapshot(collectedAt: DateTime.now(), engines: engines);
}

const _pgMetricsRowsMarker = '--DB-PG-ROWS--';
const _pgMetricsMaxConnMarker = '--DB-PG-MAXCONN--';
const _pgMetricsSharedMarker = '--DB-PG-SHARED--';
const _pgMetricsVersionMarker = '--DB-PG-VERSION--';
const _mysqlStatusMarker = '--DB-MY-STATUS--';
const _mysqlVarsMarker = '--DB-MY-VARS--';
const _mysqlVersionMarker = '--DB-MY-VERSION--';

/// Parses the SSH fallback probe output (marker-delimited text, the same
/// shape the daemon collector produces before JSON marshaling).
DatabaseMetricsSnapshot parseDatabaseMetricsText(String output) {
  final engines = <DatabaseEngineMetrics>[];
  final pg = _parsePostgresMetricsText(output);
  if (pg != null) engines.add(pg);
  final mysql = _parseMySqlMetricsText(output);
  if (mysql != null) engines.add(mysql);
  return DatabaseMetricsSnapshot(collectedAt: DateTime.now(), engines: engines);
}

String _sectionBetween(String output, String start, String end) {
  final startIndex = output.indexOf(start);
  if (startIndex < 0) return '';
  final contentStart = startIndex + start.length;
  final endIndex = end.isEmpty ? -1 : output.indexOf(end, contentStart);
  return output
      .substring(contentStart, endIndex < 0 ? output.length : endIndex)
      .trim();
}

DatabaseEngineMetrics? _parsePostgresMetricsText(String output) {
  final rows = _sectionBetween(
    output,
    _pgMetricsRowsMarker,
    _pgMetricsMaxConnMarker,
  );
  if (rows.isEmpty) return null;
  final databases = <DatabaseConnectionInfo>[];
  var connections = 0, commits = 0, rollbacks = 0;
  var blksRead = 0, blksHit = 0, deadlocks = 0, tempBytes = 0;
  for (final rawLine in rows.split('\n')) {
    final fields = rawLine.trim().split('|');
    if (fields.length < 8 || fields[0].isEmpty) continue;
    final values = fields.sublist(1, 8).map(int.tryParse).toList();
    if (values.any((value) => value == null)) continue;
    final c = values[0]!;
    connections += c;
    commits += values[1]!;
    rollbacks += values[2]!;
    blksRead += values[3]!;
    blksHit += values[4]!;
    deadlocks += values[5]!;
    tempBytes += values[6]!;
    databases.add(
      DatabaseConnectionInfo(
        name: fields[0],
        connections: c,
        commits: values[1],
        rollbacks: values[2],
        blksRead: values[3],
        blksHit: values[4],
        deadlocks: values[5],
      ),
    );
  }
  if (databases.isEmpty) return null;
  double? cacheHitRatio;
  final total = blksHit + blksRead;
  if (total > 0) cacheHitRatio = blksHit / total;
  final maxConnections = int.tryParse(
    _sectionBetween(output, _pgMetricsMaxConnMarker, _pgMetricsSharedMarker),
  );
  final memoryBytes = _parseSizeBytes(
    _sectionBetween(output, _pgMetricsSharedMarker, _pgMetricsVersionMarker),
  );
  final versionRaw = _sectionBetween(output, _pgMetricsVersionMarker, '');
  final version = versionRaw.isEmpty
      ? null
      : versionRaw
            .replaceFirst(RegExp(r'^postgres \(PostgreSQL\) '), '')
            .trim();
  return DatabaseEngineMetrics(
    engine: DatabaseEngine.postgres,
    available: true,
    version: version == null || version.isEmpty ? null : version,
    connections: connections,
    maxConnections: maxConnections,
    memoryBytes: memoryBytes,
    cacheHitRatio: cacheHitRatio,
    commits: commits,
    rollbacks: rollbacks,
    blksHit: blksHit,
    blksRead: blksRead,
    deadlocks: deadlocks,
    tempBytes: tempBytes,
    databases: databases,
  );
}

DatabaseEngineMetrics? _parseMySqlMetricsText(String output) {
  final status = _sectionBetween(output, _mysqlStatusMarker, _mysqlVarsMarker);
  if (status.isEmpty) return null;
  final values = <String, String>{};
  for (final rawLine in status.split('\n')) {
    final fields = rawLine.split('\t');
    if (fields.length != 2 || fields[0].trim().isEmpty) continue;
    values[fields[0].trim()] = fields[1].trim();
  }
  int? value(String name) => int.tryParse(values[name] ?? '');

  final pageSize = value('Innodb_page_size');
  final pagesData = value('Innodb_buffer_pool_pages_data');
  final pagesDirty = value('Innodb_buffer_pool_pages_dirty');
  double? cacheHitRatio;
  final requests = value('Innodb_buffer_pool_read_requests');
  final reads = value('Innodb_buffer_pool_reads');
  if (requests != null && reads != null && requests + reads > 0) {
    cacheHitRatio = requests / (requests + reads);
  }

  final vars = <String, String>{};
  for (final rawLine in _sectionBetween(
    output,
    _mysqlVarsMarker,
    _mysqlVersionMarker,
  ).split('\n')) {
    final fields = rawLine.split('\t');
    if (fields.length != 2 || fields[0].trim().isEmpty) continue;
    vars[fields[0].trim()] = fields[1].trim();
  }
  final version = _sectionBetween(output, _mysqlVersionMarker, '');
  var engine = DatabaseEngine.mysql;
  if (version.toLowerCase().contains('mariadb')) {
    engine = DatabaseEngine.mariadb;
  }
  return DatabaseEngineMetrics(
    engine: engine,
    available: true,
    version: version.isEmpty ? null : version,
    connections: value('Threads_connected'),
    maxConnections: int.tryParse(vars['max_connections'] ?? ''),
    memoryBytes: _parseSizeBytes(vars['innodb_buffer_pool_size'] ?? ''),
    memoryUsedBytes: pageSize != null && pagesData != null
        ? pageSize * pagesData
        : null,
    memoryDirtyBytes: pageSize != null && pagesDirty != null
        ? pageSize * pagesDirty
        : null,
    cacheHitRatio: cacheHitRatio,
    queries: value('Queries'),
    slowQueries: value('Slow_queries'),
    threadsRunning: value('Threads_running'),
    maxUsedConnections: value('Max_used_connections'),
    uptimeSeconds: value('Uptime'),
    bytesReceived: value('Bytes_received'),
    bytesSent: value('Bytes_sent'),
  );
}

/// Converts PostgreSQL/MySQL size strings ("128MB", "1GB", "8192") to bytes.
int? _parseSizeBytes(String raw) {
  var trimmed = raw.trim().toLowerCase();
  if (trimmed.isEmpty) return null;
  var multiplier = 1;
  for (final (suffix, factor) in [
    ('gb', 1 << 30),
    ('g', 1 << 30),
    ('mb', 1 << 20),
    ('m', 1 << 20),
    ('kb', 1 << 10),
    ('k', 1 << 10),
    ('b', 1),
  ]) {
    if (trimmed.endsWith(suffix)) {
      trimmed = trimmed.substring(0, trimmed.length - suffix.length).trim();
      multiplier = factor;
      break;
    }
  }
  final value = int.tryParse(trimmed);
  return value == null ? null : value * multiplier;
}

/// Computes per-second rates from two consecutive samples. Counters that
/// reset (server restart) clamp to zero instead of producing negative rates.
DatabaseMetricsRates computeDatabaseRates({
  required DatabaseEngineMetrics? previous,
  required DateTime? previousAt,
  required DatabaseEngineMetrics current,
  required DateTime currentAt,
}) {
  if (previous == null || previousAt == null) {
    return const DatabaseMetricsRates();
  }
  final seconds = currentAt.difference(previousAt).inMilliseconds / 1000.0;
  if (seconds <= 0) return const DatabaseMetricsRates();
  double? transactionsPerSecond;
  final prevCommits = previous.commits;
  final prevRollbacks = previous.rollbacks;
  final curCommits = current.commits;
  final curRollbacks = current.rollbacks;
  if (prevCommits != null &&
      prevRollbacks != null &&
      curCommits != null &&
      curRollbacks != null) {
    final delta = (curCommits - prevCommits) + (curRollbacks - prevRollbacks);
    if (delta >= 0) transactionsPerSecond = delta / seconds;
  }
  double? queriesPerSecond;
  final prevQueries = previous.queries;
  final curQueries = current.queries;
  if (prevQueries != null && curQueries != null) {
    final delta = curQueries - prevQueries;
    if (delta >= 0) queriesPerSecond = delta / seconds;
  }
  return DatabaseMetricsRates(
    transactionsPerSecond: transactionsPerSecond,
    queriesPerSecond: queriesPerSecond,
  );
}
