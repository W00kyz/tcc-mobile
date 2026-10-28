import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// Local write-ahead log for execution actions (check-in/out, evidence).
///
/// Ruling 1 (Etapa 5 design §4.1): every execution write lands here as a
/// `PENDING` row inside a Drift transaction *before* the UI confirms "saved".
/// Etapa 6 turns the synchronous drain into a background outbox worker — the
/// `attempts` / `nextAttemptAt` columns carry the per-row retry schedule the
/// worker reads (spec Ruling 6: capped exponential backoff).
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

  /// How many sync attempts this row has already burned (spec Ruling 6).
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// Epoch milliseconds before which the worker must not retry this row.
  /// Null means "eligible now" (never attempted, or retry window elapsed).
  IntColumn get nextAttemptAt => integer().nullable()();

  /// The released stop a `409 STOP_RELEASED` parked this `blocked` row on
  /// (spec 2026-10-20-alocacao-automatica §7.5) — named by the server, since
  /// an evidence row carries no stop of its own. Null for any other row.
  TextColumn get releasedStopId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One row per stop the worker has advanced locally — the app's own record of
/// the `execution_id` the evidence endpoints need (spec §6.3b Ruling 17:
/// `RouteStopOut` from `GET /routes/me` has no `execution_id`, and the field
/// worker has no access to the MANAGER/ADMIN-only `GET /executions`).
///
/// Replaces Etapa 5's `OpenExecutions`: the 2→3 migration copies every
/// `open_executions` row here with `local_status = 'IN_PROGRESS'` before
/// dropping the old table.
class StopProgress extends Table {
  TextColumn get routeStopId => text()();
  TextColumn get executionId => text()();

  /// `'IN_PROGRESS'` | `'DONE'`.
  TextColumn get localStatus => text()();

  /// Epoch milliseconds of the last local transition for this stop.
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {routeStopId};
}

/// Flat key/value store for the sync worker's own bookkeeping (last full-sync
/// timestamp, backoff ceiling markers, …). Spec Ruling 9.
class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// One row per stop the server released while this device still had
/// writes for it — the late check-in/check-out/evidence came back `409
/// STOP_RELEASED` (spec 2026-10-20-alocacao-automatica §7.5). It holds what
/// the appeal is pre-filled with, and lives until the appeal is sent or the
/// worker discards the stop's local data.
class ReleasedStops extends Table {
  TextColumn get routeStopId => text()();

  /// The server's `release_reason` (`LEFT_CAMPUS`, `LOCATION_SILENCE`, …).
  TextColumn get releaseReason => text()();
  BoolColumn get appealable => boolean()();

  /// Epoch milliseconds of the device scans this stop's outbox rows held.
  IntColumn get localCheckInAt => integer().nullable()();
  IntColumn get localCheckOutAt => integer().nullable()();

  /// Epoch milliseconds when the 409 was first seen.
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {routeStopId};
}

/// One row per local day the worker opened the app or concluded a stop on —
/// the source of the personal streak and achievements (redesign §6.8). It
/// lives only on this device: reinstalling the app resets it, by design.
/// `pointsDone` is bumped in the same transaction as the check-out it counts
/// (`ExecutionRepository.checkOut`).
class DayLog extends Table {
  /// Local calendar date, ISO `YYYY-MM-DD`.
  TextColumn get day => text()();

  /// The server's `service_day` for that date; a day with no service never
  /// breaks the streak.
  BoolColumn get serviceDay => boolean().withDefault(const Constant(true))();
  IntColumn get pointsDone => integer().withDefault(const Constant(0))();
  IntColumn get cardsCompleted => integer().withDefault(const Constant(0))();

  /// Completed cards that had nothing left to send when recorded.
  IntColumn get cleanCards => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {day};
}

/// How long a statement waits for another connection's lock before failing.
const Duration appDatabaseBusyTimeout = Duration(seconds: 5);

/// IMPORTANT: run on every connection to the device file. The background
/// drain (redesign §6.9, `background_sync.dart`) opens this same file on a
/// second connection — its own isolate, sometimes its own engine — while the
/// app may be writing.
/// - `busy_timeout`: SQLite's default is zero, so the loser of a lock race
///   failed at once with "database is locked" — a failed `markSynced` would
///   even be classified hard and block a row the server already took.
/// - WAL: readers never wait on the writer, and a deferred read-then-write
///   transaction (`ReleasedStopStore.record`) cannot deadlock against the
///   other connection the way it can in rollback mode, where the busy
///   handler is skipped and SQLITE_BUSY comes back at once.
final List<String> appDatabaseConnectionPragmas = [
  'PRAGMA busy_timeout = ${appDatabaseBusyTimeout.inMilliseconds}',
  'PRAGMA journal_mode = WAL',
];

@DriftDatabase(
  tables: [
    PendingOperations,
    StopProgress,
    SyncMeta,
    ReleasedStops,
    DayLog,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// [executor] defaults to the on-device SQLite file; tests inject
  /// `NativeDatabase.memory()` so no suite ever touches real storage.
  AppDatabase([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'route_monitor',
              native: DriftNativeOptions(
                setup: (db) => appDatabaseConnectionPragmas.forEach(db.execute),
              ),
            ),
      );

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // No `from < 2` branch: Etapa 5 shipped at schema 2, so no released
      // build is below it. A dev still on schema 1 wipes app data and reopens
      // at schema 3 via onCreate (spec §6.3b Ruling 17 / Etapa 5 §6.3b
      // precedent). Keeping a `from < 2` branch here is impossible anyway —
      // it would have to `createTable(openExecutions)`, and that table object
      // no longer exists in the generated code.
      if (from < 3) {
        await m.addColumn(pendingOperations, pendingOperations.attempts);
        await m.addColumn(pendingOperations, pendingOperations.nextAttemptAt);
        await m.createTable(stopProgress);
        await m.createTable(syncMeta);
        // Carry the Ruling 17 lookup rows forward, then retire the old table.
        // Raw SQL: `open_executions` is no longer a drift table object.
        await customStatement(
          'INSERT INTO stop_progress '
          '(route_stop_id, execution_id, local_status, updated_at) '
          "SELECT route_stop_id, execution_id, 'IN_PROGRESS', "
          "CAST(strftime('%s', 'now') AS INTEGER) * 1000 "
          'FROM open_executions',
        );
        await customStatement('DROP TABLE open_executions');
      }
      // No `from < 4` branch any more: it created `form_draft_items`, a
      // table the `from < 7` step below drops again, and its drift table
      // object no longer exists in the generated code.
      if (from < 5) {
        // "Iniciar rota" left the outbox: it is an online call now (spec
        // 2026-10-20-alocacao-automatica §9). A queued `startRoute` row would
        // make `PendingOpKind.values.byName` throw on the next drain, and its
        // replay would hit an endpoint that no longer exists.
        await customStatement(
          "DELETE FROM pending_operations WHERE kind = 'startRoute'",
        );
        // The optimistic "iniciada" markers went with it, and the cached
        // `/routes/me` body was a route list — the new body is a `MyDay`.
        await customStatement(
          'DELETE FROM sync_meta '
          "WHERE key LIKE 'route:%:started_at' "
          "OR key LIKE 'routes_me_snapshot:%'",
        );
      }
      if (from < 6) {
        // A row M2 already parked on a STOP_RELEASED keeps a null stop: the
        // old build never recorded which stop the server named.
        await m.addColumn(pendingOperations, pendingOperations.releasedStopId);
        await m.createTable(releasedStops);
      }
      if (from < 7) {
        // Forms left the app (spec 2026-10-26-exige-evidencias §6.4). The
        // outbox is untouched: a check-out queued with form fields is sent
        // without them (SyncWorker._performCheckOut).
        await m.deleteTable('form_draft_items');
      }
      if (from < 8) {
        // Personal gamification (redesign §6.8): a new, empty day log. The
        // streak starts counting from the first day this build runs.
        await m.createTable(dayLog);
      }
    },
  );
}
