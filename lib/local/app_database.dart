import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// Local write-ahead log for execution actions (check-in/out, evidence).
///
/// Ruling 1 (Etapa 5 design §4.1): every execution write lands here as a
/// `PENDING` row inside a Drift transaction *before* the UI confirms "saved",
/// then a synchronous drain flips it to `SYNCED`/`FAILED`. Etapa 6 swaps only
/// the drain policy — this table and the `LocalWriteStore` seam stay put.
class PendingOperations extends Table {
  /// Equals the operation's idempotency key (UUID v4 generated on the device).
  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get routeId => text()();
  TextColumn get payloadJson => text()();

  /// Epoch milliseconds from the device clock at enqueue time.
  IntColumn get createdAt => integer()();
  TextColumn get state => text().withDefault(const Constant('pending'))();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One row per stop with an open (checked-in, not yet checked-out) execution
/// — the app's own record of the `execution_id` the evidence endpoints need
/// (spec §6.3b Ruling 17: `RouteStopOut` from `GET /routes/me` has no
/// `execution_id` field, and the field worker has no access to the
/// MANAGER/ADMIN-only `GET /executions`). Written on a successful check-in,
/// deleted on a successful check-out.
class OpenExecutions extends Table {
  TextColumn get routeStopId => text()();
  TextColumn get executionId => text()();

  @override
  Set<Column> get primaryKey => {routeStopId};
}

@DriftDatabase(tables: [PendingOperations, OpenExecutions])
class AppDatabase extends _$AppDatabase {
  /// [executor] defaults to the on-device SQLite file; tests inject
  /// `NativeDatabase.memory()` so no suite ever touches real storage.
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'route_monitor'));

  @override
  int get schemaVersion => 2;

  // Additive-only: nobody has schema 1 installed outside development (spec
  // §6.3b Ruling 17), so onUpgrade only ever needs to add OpenExecutions —
  // existing PendingOperations rows are left untouched.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(openExecutions);
      }
    },
  );
}
