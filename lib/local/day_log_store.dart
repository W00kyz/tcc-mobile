import 'package:drift/drift.dart';
import 'package:route_monitor/local/app_database.dart';

/// A decoded `DayLog` row, free of any Drift type.
class DayLogEntry {
  const DayLogEntry({
    required this.day,
    required this.serviceDay,
    required this.pointsDone,
    required this.cardsCompleted,
    required this.cleanCards,
  });

  /// Local midnight of the logged date.
  final DateTime day;
  final bool serviceDay;
  final int pointsDone;
  final int cardsCompleted;
  final int cleanCards;
}

/// `YYYY-MM-DD` of [at]'s local calendar date — the `day_log` key.
///
///     dayKey(DateTime(2026, 10, 21, 9)); // '2026-10-21'
String dayKey(DateTime at) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${at.year.toString().padLeft(4, '0')}-${two(at.month)}-'
      '${two(at.day)}';
}

/// The personal day log (redesign §6.8): what the streak and achievements
/// are computed from. Every method takes the moment it records and keys it
/// by that moment's local date.
abstract class DayLogStore {
  /// The day was seen through `GET /routes/me`; [serviceDay] is its
  /// `service_day`. Counts already recorded are kept.
  Future<void> recordDayOpened(DateTime day, {required bool serviceDay});

  /// One more stop concluded on [day]. Called inside the check-out's
  /// transaction, so it is rolled back with it.
  Future<void> recordStopDone(DateTime day);

  /// One more batch card completed on [day]; [clean] when nothing was left
  /// to send at that moment.
  Future<void> recordCardCompleted(DateTime day, {required bool clean});

  /// Every logged day, oldest first.
  Future<List<DayLogEntry>> all();
}

class DriftDayLogStore implements DayLogStore {
  DriftDayLogStore(this._db);

  final AppDatabase _db;

  @override
  Future<void> recordDayOpened(DateTime day, {required bool serviceDay}) {
    return _upsert(
      DayLogCompanion.insert(day: dayKey(day), serviceDay: Value(serviceDay)),
      (old) => DayLogCompanion(serviceDay: Value(serviceDay)),
    );
  }

  @override
  Future<void> recordStopDone(DateTime day) {
    return _upsert(
      DayLogCompanion.insert(day: dayKey(day), pointsDone: const Value(1)),
      (old) => DayLogCompanion.custom(
        pointsDone: old.pointsDone + const Constant(1),
      ),
    );
  }

  @override
  Future<void> recordCardCompleted(DateTime day, {required bool clean}) {
    final cleanStep = clean ? 1 : 0;
    return _upsert(
      DayLogCompanion.insert(
        day: dayKey(day),
        cardsCompleted: const Value(1),
        cleanCards: Value(cleanStep),
      ),
      (old) => DayLogCompanion.custom(
        cardsCompleted: old.cardsCompleted + const Constant(1),
        cleanCards: old.cleanCards + Constant(cleanStep),
      ),
    );
  }

  /// One statement: insert the day, or apply [onExisting] to its row. Never
  /// read-then-write — the background drain shares the file.
  Future<void> _upsert(
    DayLogCompanion fresh,
    Insertable<DayLogData> Function($DayLogTable old) onExisting,
  ) {
    return _db.into(_db.dayLog).insert(fresh, onConflict: DoUpdate(onExisting));
  }

  @override
  Future<List<DayLogEntry>> all() async {
    final rows = await (_db.select(
      _db.dayLog,
    )..orderBy([(row) => OrderingTerm.asc(row.day)])).get();
    return rows.map(_toEntry).toList();
  }

  DayLogEntry _toEntry(DayLogData row) => DayLogEntry(
    day: DateTime.parse(row.day),
    serviceDay: row.serviceDay,
    pointsDone: row.pointsDone,
    cardsCompleted: row.cardsCompleted,
    cleanCards: row.cleanCards,
  );
}
