// Diagnostic entry point: checks whether this browser can host the web database
// at all — IndexedDB access through `package:sqlite3`, then drift's storage
// implementations. Results go to the browser console.
//
//   flutter build web --release -t tool/db_probe.dart
//   # serve build/web, then open it
import 'package:drift/wasm.dart';
import 'package:flutter/widgets.dart';
// This entry point exercises the packages the web database is built on, so it
// may name a package the app itself only uses transitively.
// ignore: depend_on_referenced_packages
import 'package:sqlite3/wasm.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());

  debugPrint('PROBE: starting');
  try {
    final sqlite3 = await WasmSqlite3.loadFromUrl(
      Uri.base.resolve('sqlite3.wasm'),
    );
    debugPrint('PROBE: sqlite3 loaded ${sqlite3.version}');
    final memory = sqlite3.openInMemory();
    memory.execute('CREATE TABLE t (x INTEGER)');
    memory.execute('INSERT INTO t VALUES (42)');
    debugPrint('PROBE: raw sqlite3 ok ${memory.select('SELECT x FROM t')}');
    memory.close();
  } catch (error, stackTrace) {
    debugPrint('PROBE: raw sqlite3 failed $error\n$stackTrace');
  }
  try {
    final databases = await IndexedDbFileSystem.databases();
    debugPrint('PROBE: indexedDb databases=$databases');
  } catch (error) {
    debugPrint('PROBE: indexedDb databases failed $error');
  }
  try {
    final fileSystem = await IndexedDbFileSystem.open(dbName: 'probe_fs');
    debugPrint('PROBE: indexedDb file system ok ${fileSystem.name}');
  } catch (error) {
    debugPrint('PROBE: indexedDb file system failed $error');
  }
  try {
    final sqlite3 = await WasmSqlite3.loadFromUrl(
      Uri.base.resolve('sqlite3.wasm'),
    );
    debugPrint('PROBE: sqlite3 loaded ${sqlite3.version}');
    final fileSystem = await IndexedDbFileSystem.open(dbName: 'probe_persist');
    debugPrint('PROBE: file system opened');
    sqlite3.registerVirtualFileSystem(fileSystem, makeDefault: true);
    debugPrint('PROBE: file system registered');
    final database = WasmDatabase(sqlite3: sqlite3, path: 'probe_persist');
    debugPrint('PROBE: executor created');
    final rows = await database.runSelect('SELECT 42 AS n', []);
    debugPrint('PROBE: manual database ok rows=$rows');
    await database.close();
    debugPrint('PROBE: manual database closed');
  } catch (error) {
    debugPrint('PROBE: manual database failed $error');
  }
  try {
    final probe = await WasmDatabase.probe(
      sqlite3Uri: Uri.base.resolve('sqlite3.wasm'),
      driftWorkerUri: Uri.base.resolve('drift_worker.js'),
      databaseName: 'probe_db',
    );
    debugPrint(
      'PROBE: drift available=${probe.availableStorages} '
      'missing=${probe.missingFeatures}',
    );
    for (final implementation in probe.availableStorages) {
      try {
        final connection = await probe.open(implementation, 'probe_db');
        final rows = await connection.executor.runSelect('SELECT 42 AS n', []);
        debugPrint('PROBE: drift $implementation ok rows=$rows');
        await connection.close();
        return;
      } catch (error) {
        debugPrint('PROBE: drift $implementation failed $error');
      }
    }
  } catch (error) {
    debugPrint('PROBE: drift failed $error');
  }
}
