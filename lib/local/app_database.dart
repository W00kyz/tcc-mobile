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

@DriftDatabase(tables: [PendingOperations])
class AppDatabase extends _$AppDatabase {
  /// [executor] defaults to the on-device SQLite file; tests inject
  /// `NativeDatabase.memory()` so no suite ever touches real storage.
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'route_monitor'));

  @override
  int get schemaVersion => 1;
}
