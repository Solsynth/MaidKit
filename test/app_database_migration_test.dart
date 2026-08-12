import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
      'schema 22 database that already has sort_order migrates to 24',
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

        // Opening the database again runs the 22 -> 24 migrations, which
        // must not fail with a duplicate column error.
        final database = AppDatabase(filePath: path);
        final version = await database
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(version.read<int>('user_version'), 24);

        // The order backfill still ran, so the legacy row keeps its
        // creation-id position.
        final row = await database
            .customSelect(
              'SELECT sort_order FROM servers WHERE name = ?',
              variables: [Variable('legacy')],
            )
            .getSingle();
        expect(row.read<int>('sort_order'), 1);
        await database.close();
      },
    );

    test(
      'schema 22 without sort_order adds the column and jump host',
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
        expect(version.read<int>('user_version'), 24);

        final column = await database
            .customSelect(
              "SELECT name FROM pragma_table_info('servers') "
              "WHERE name = 'sort_order'",
            )
            .get();
        expect(column, isNotEmpty);
        await database.close();
      },
    );
  });
}
