import 'package:flutter_test/flutter_test.dart';
import 'package:maid_kit/servers/database_models.dart';

const _inspectionFixture = '''
---MAIDKIT-DB-BEGIN---
---MAIDKIT-DB-PG---
version: 15.4 (Ubuntu 15.4-2.pgdg22.04+1)
service: postgresql@15-main
running: true
enabled: true
port: 5432
datadir: /var/lib/postgresql/15/main
config: /etc/postgresql/15/main/postgresql.conf
bin: /usr/lib/postgresql/15/bin
cli: /usr/lib/postgresql/15/bin/psql
databases:
db: template1|postgres|8019315|7.7 MB|UTF8
db: app|deploy|123456789|117.7 MB|UTF8
connections: 4
---MAIDKIT-DB-MYSQL---
version: mysqld  Ver 8.0.35 for Linux on x86_64
service: mysql
running: true
enabled: true
port: 3306
socket: /var/run/mysqld/mysqld.sock
datadir: /var/lib/mysql
config: /etc/mysql/my.cnf
cli: /usr/bin/mysql
error: database credentials are not available (root socket auth and /etc/mysql/debian.cnf both failed)
---MAIDKIT-DB-PGBACKREST---
version: pgBackRest 2.53
config: /etc/pgbackrest.conf
stanzas: main
info-json: [{"name":"main","backup":[{"label":"20240814-153641F","type":"full","timestamp":1723642601.642842,"size":3962121,"duration":0.39,"database":{"id":1,"name":"app"}}],"db":[{"id":1,"name":"app","repo":{"key":1,"cipher":"none","storage":"local","path":"/var/lib/pgbackrest","type":"repo1"}}]}]
---MAIDKIT-DB-END---
''';

void main() {
  group('parseDatabaseInspectionOutput', () {
    test('parses the PostgreSQL section', () {
      final result = parseDatabaseInspectionOutput(_inspectionFixture);
      final pg = result.instanceFor(DatabaseEngine.postgres);
      expect(pg, isNotNull);
      expect(pg!.version, '15.4 (Ubuntu 15.4-2.pgdg22.04+1)');
      expect(pg.serviceName, 'postgresql@15-main');
      expect(pg.running, isTrue);
      expect(pg.enabled, isTrue);
      expect(pg.port, '5432');
      expect(pg.dataDirectory, '/var/lib/postgresql/15/main');
      expect(pg.configFile, '/etc/postgresql/15/main/postgresql.conf');
      expect(pg.binaryDirectory, '/usr/lib/postgresql/15/bin');
      expect(pg.connections, 4);
      expect(pg.databases, hasLength(2));
      final app = pg.databases[1];
      expect(app.name, 'app');
      expect(app.owner, 'deploy');
      expect(app.sizeBytes, 123456789);
      expect(app.sizeLabel, '117.7 MB');
      expect(app.encoding, 'UTF8');
    });

    test('parses a MySQL section with an error', () {
      final result = parseDatabaseInspectionOutput(_inspectionFixture);
      final mysql = result.instanceFor(DatabaseEngine.mysql);
      expect(mysql, isNotNull);
      expect(mysql!.version, contains('8.0.35'));
      expect(mysql.serviceName, 'mysql');
      expect(mysql.socket, '/var/run/mysqld/mysqld.sock');
      expect(mysql.databases, isEmpty);
      expect(mysql.error, contains('credentials'));
    });

    test('parses the pgBackRest section', () {
      final result = parseDatabaseInspectionOutput(_inspectionFixture);
      final pgBackRest = result.pgBackRest;
      expect(pgBackRest.installed, isTrue);
      expect(pgBackRest.version, 'pgBackRest 2.53');
      expect(pgBackRest.configFile, '/etc/pgbackrest.conf');
      expect(pgBackRest.stanzas, hasLength(1));
      final stanza = pgBackRest.stanzas.first;
      expect(stanza.name, 'main');
      expect(stanza.databases, ['app']);
      expect(stanza.repositoryPath, '/var/lib/pgbackrest');
      expect(stanza.backups, hasLength(1));
      final backup = stanza.backups.first;
      expect(backup.label, '20240814-153641F');
      expect(backup.type, 'full');
      expect(backup.sizeBytes, 3962121);
      expect(backup.database, 'app');
      expect(backup.timestamp!.year, 2024);
    });

    test('reports not installed when pgBackRest is absent', () {
      const fixture =
          '---MAIDKIT-DB-BEGIN---\n'
          '---MAIDKIT-DB-PGBACKREST---\n'
          'installed: false\n'
          '---MAIDKIT-DB-END---\n';
      final result = parseDatabaseInspectionOutput(fixture);
      expect(result.pgBackRest.installed, isFalse);
      expect(result.pgBackRest.stanzas, isEmpty);
    });

    test('returns no instances when no engines are detected', () {
      const fixture = '---MAIDKIT-DB-BEGIN---\n---MAIDKIT-DB-END---\n';
      final result = parseDatabaseInspectionOutput(fixture);
      expect(result.instances, isEmpty);
    });
  });

  group('parsePgBackRestInfoJson', () {
    test('parses backups and repository path', () {
      const json =
          '[{"name":"demo","backup":[{"label":"20240814-153641F","type":"full","timestamp":1723642601.642842,"size":3962121,"duration":0.39,"database":{"id":1,"name":"demo"}}],"db":[{"id":1,"name":"demo","repo":{"key":1,"cipher":"none","storage":"local","path":"/var/lib/pgbackrest","type":"repo1"}}]}]';
      final stanzas = parsePgBackRestInfoJson(json);
      expect(stanzas, hasLength(1));
      final stanza = stanzas.first;
      expect(stanza.name, 'demo');
      expect(stanza.databases, ['demo']);
      expect(stanza.repositoryPath, '/var/lib/pgbackrest');
      expect(stanza.latestBackup!.type, 'full');
      expect(stanza.latestBackup!.timestamp!.isUtc, isFalse);
    });
    test('parses current pgBackRest backup schema', () {
      const json =
          '[{"name":"main","repo":[{"path":"/srv/pgbackrest"}],"db":[{"name":"app"}],"backup":['
          '{"label":"older","type":"full","timestamp":{"start":1700000000,"stop":1700000010},"database":[{"name":"app"}]},'
          '{"label":"newer","type":"incr","timestamp":{"start":1701000000,"stop":1701000010},"database":[{"name":"app"}]}]}]';
      final stanza = parsePgBackRestInfoJson(json).single;
      expect(stanza.repositoryPath, '/srv/pgbackrest');
      expect(stanza.latestBackup!.label, 'newer');
      expect(stanza.latestBackup!.database, 'app');
      expect(stanza.latestBackup!.timestamp, isNotNull);
    });

    test('handles malformed json', () {
      expect(parsePgBackRestInfoJson('not json'), isEmpty);
      expect(parsePgBackRestInfoJson('{"name":"x"}'), isEmpty);
    });
  });

  group('parseDatabaseBackupListing', () {
    test('parses find -printf output', () {
      const listing =
          'postgres-app-20260816-093000.dump\t3962121\t2026-08-16 09:30\n'
          'mysql-app-20260815-221500.sql.gz\t1024\t2026-08-15 22:15\n';
      final files = parseDatabaseBackupListing(listing, '/var/backups/pg');
      expect(files, hasLength(2));
      expect(files[0].name, 'postgres-app-20260816-093000.dump');
      expect(
        files[0].path,
        '/var/backups/pg/postgres-app-20260816-093000.dump',
      );
      expect(files[0].sizeBytes, 3962121);
      expect(files[0].modifiedLabel, '2026-08-16 09:30');
      expect(files[1].sizeBytes, 1024);
    });

    test('skips malformed rows', () {
      const listing = 'broken\n\t\t\nfile.sql\t123\t2026-08-16 09:30\n';
      final files = parseDatabaseBackupListing(listing, '/backups');
      expect(files, hasLength(1));
      expect(files.first.name, 'file.sql');
    });
  });
  group('parseDatabaseMetrics (daemon JSON)', () {
    test('parses postgres and mysql entries', () {
      final snapshot = parseDatabaseMetrics({
        'engines': [
          {
            'engine': 'postgres',
            'available': true,
            'version': '15.4',
            'connections': 4,
            'max_connections': 100,
            'memory_bytes': 134217728,
            'cache_hit_ratio': 0.99,
            'commits': 105,
            'rollbacks': 1,
            'blks_hit': 9958,
            'blks_read': 52,
            'deadlocks': 0,
            'temp_bytes': 4096,
            'databases': [
              {
                'name': 'app',
                'connections': 3,
                'commits': 100,
                'rollbacks': 1,
                'blks_hit': 9950,
                'blks_read': 50,
              },
            ],
          },
          {
            'engine': 'mariadb',
            'available': true,
            'connections': 5,
            'max_connections': 151,
            'memory_bytes': 134217728,
            'memory_used_bytes': 67108864,
            'cache_hit_ratio': 0.998,
            'queries': 123456,
            'slow_queries': 3,
            'uptime_seconds': 99999,
          },
        ],
      });
      final pg = snapshot.forEngine(DatabaseEngine.postgres);
      expect(pg, isNotNull);
      expect(pg!.connections, 4);
      expect(pg.maxConnections, 100);
      expect(pg.memoryBytes, 134217728);
      expect(pg.commits, 105);
      expect(pg.databases, hasLength(1));
      expect(pg.databases.first.name, 'app');
      expect(pg.databases.first.connections, 3);
      // MariaDB entry is found when the selector asks for MySQL.
      final mysql = snapshot.forEngine(DatabaseEngine.mysql);
      expect(mysql, isNotNull);
      expect(mysql!.engine, DatabaseEngine.mariadb);
      expect(mysql.queries, 123456);
      expect(mysql.memoryUsedBytes, 67108864);
    });

    test('skips unknown engines and malformed entries', () {
      final snapshot = parseDatabaseMetrics({
        'engines': [
          {'engine': 'oracle', 'available': true},
          'not a map',
          {'engine': 'postgres', 'available': false, 'error': 'nope'},
        ],
      });
      expect(snapshot.engines, hasLength(1));
      expect(snapshot.engines.first.available, isFalse);
      expect(snapshot.engines.first.error, 'nope');
    });
  });

  group('parseDatabaseMetricsText (SSH probe)', () {
    test('parses postgres markers', () {
      final snapshot = parseDatabaseMetricsText('''
--DB-PG-ROWS--
app|3|100|1|50|9950|0|4096
template1|0|5|0|2|8|0|0
--DB-PG-MAXCONN--
100
--DB-PG-SHARED--
128MB
--DB-PG-VERSION--
postgres (PostgreSQL) 15.4 (Ubuntu 15.4-2.pgdg22.04+1)
''');
      final pg = snapshot.forEngine(DatabaseEngine.postgres);
      expect(pg, isNotNull);
      expect(pg!.connections, 3);
      expect(pg.maxConnections, 100);
      expect(pg.memoryBytes, 128 << 20);
      expect(pg.commits, 105);
      expect(pg.tempBytes, 4096);
      expect(pg.version, '15.4 (Ubuntu 15.4-2.pgdg22.04+1)');
      expect(pg.cacheHitRatio, closeTo(9958 / 10010, 1e-9));
      expect(pg.databases, hasLength(2));
    });

    test('parses mysql markers and tags mariadb', () {
      final snapshot = parseDatabaseMetricsText('''
--DB-MY-STATUS--
Threads_connected	5
Max_used_connections	12
Threads_running	1
Innodb_buffer_pool_pages_total	8192
Innodb_buffer_pool_pages_data	4096
Innodb_buffer_pool_pages_dirty	64
Innodb_buffer_pool_read_requests	100000
Innodb_buffer_pool_reads	200
Queries	123456
Slow_queries	3
Uptime	99999
Innodb_page_size	16384
--DB-MY-VARS--
innodb_buffer_pool_size	134217728
max_connections	151
--DB-MY-VERSION--
10.11.6-MariaDB-0+deb12u1
''');
      final mysql = snapshot.forEngine(DatabaseEngine.mysql);
      expect(mysql, isNotNull);
      expect(mysql!.engine, DatabaseEngine.mariadb);
      expect(mysql.connections, 5);
      expect(mysql.maxConnections, 151);
      expect(mysql.memoryBytes, 134217728);
      expect(mysql.memoryUsedBytes, 4096 * 16384);
      expect(mysql.memoryDirtyBytes, 64 * 16384);
      expect(mysql.cacheHitRatio, closeTo(100000 / 100200, 1e-9));
      expect(mysql.queries, 123456);
      expect(mysql.slowQueries, 3);
    });

    test('returns no engines for empty probe output', () {
      final snapshot = parseDatabaseMetricsText('--DB-PG-ROWS--\n');
      expect(snapshot.engines, isEmpty);
    });
  });

  group('computeDatabaseRates', () {
    final base = DatabaseEngineMetrics(
      engine: DatabaseEngine.postgres,
      available: true,
    );

    test('computes transactions per second from deltas', () {
      final previous = DatabaseEngineMetrics(
        engine: DatabaseEngine.postgres,
        available: true,
        commits: 1000,
        rollbacks: 10,
      );
      final current = DatabaseEngineMetrics(
        engine: DatabaseEngine.postgres,
        available: true,
        commits: 1060,
        rollbacks: 12,
      );
      final rates = computeDatabaseRates(
        previous: previous,
        previousAt: DateTime(2026, 1, 1, 0, 0, 0),
        current: current,
        currentAt: DateTime(2026, 1, 1, 0, 1, 0),
      );
      expect(rates.transactionsPerSecond, closeTo(62 / 60, 1e-9));
      expect(rates.queriesPerSecond, isNull);
    });

    test('computes queries per second for mysql', () {
      final previous = DatabaseEngineMetrics(
        engine: DatabaseEngine.mysql,
        available: true,
        queries: 10000,
      );
      final current = DatabaseEngineMetrics(
        engine: DatabaseEngine.mysql,
        available: true,
        queries: 11200,
      );
      final rates = computeDatabaseRates(
        previous: previous,
        previousAt: DateTime(2026, 1, 1, 0, 0, 0),
        current: current,
        currentAt: DateTime(2026, 1, 1, 0, 0, 10),
      );
      expect(rates.queriesPerSecond, closeTo(120, 1e-9));
    });

    test('clamps counter resets and missing samples', () {
      final previous = DatabaseEngineMetrics(
        engine: DatabaseEngine.postgres,
        available: true,
        commits: 5000,
        rollbacks: 5,
      );
      final current = DatabaseEngineMetrics(
        engine: DatabaseEngine.postgres,
        available: true,
        commits: 100,
        rollbacks: 1,
      );
      final rates = computeDatabaseRates(
        previous: previous,
        previousAt: DateTime(2026, 1, 1, 0, 0, 0),
        current: current,
        currentAt: DateTime(2026, 1, 1, 0, 1, 0),
      );
      expect(rates.transactionsPerSecond, isNull);
      expect(
        computeDatabaseRates(
          previous: null,
          previousAt: null,
          current: base,
          currentAt: DateTime(2026, 1, 1),
        ).transactionsPerSecond,
        isNull,
      );
    });
  });
}
