import 'package:maid_kit/data/local/app_database.dart' hide WorkspaceSnapshot;
import 'workspace_snapshot.dart';

/// Persists the "last session" [WorkspaceSnapshot] in the app database.
///
/// A single row keyed `last` keeps one snapshot, matching the issue's
/// "restore the workspace I closed" scope; named multi-workspaces can extend
/// this later by keying more rows.
class WorkspaceSnapshotStore {
  WorkspaceSnapshotStore(this._db);

  static const lastId = 'last';

  final AppDatabase _db;

  Future<void> save(WorkspaceSnapshot snapshot) async {
    await _db
        .into(_db.workspaceSnapshots)
        .insertOnConflictUpdate(
          WorkspaceSnapshotsCompanion.insert(
            id: lastId,
            payload: snapshot.encode(),
            updatedAt: DateTime.now(),
          ),
        );
  }

  Future<WorkspaceSnapshot?> load() async {
    final row = await (_db.select(
      _db.workspaceSnapshots,
    )..where((table) => table.id.equals(lastId))).getSingleOrNull();
    if (row == null) return null;
    return WorkspaceSnapshot.decode(row.payload);
  }

  Future<void> clear() async {
    await (_db.delete(
      _db.workspaceSnapshots,
    )..where((table) => table.id.equals(lastId))).go();
  }

  Stream<WorkspaceSnapshot?> watch() async* {
    yield* (_db.select(
      _db.workspaceSnapshots,
    )..where((table) => table.id.equals(lastId))).watchSingleOrNull().map(
      (row) => row == null ? null : WorkspaceSnapshot.decode(row.payload),
    );
  }
}
