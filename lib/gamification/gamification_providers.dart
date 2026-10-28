import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/execution/execution_providers.dart'
    show appDatabaseProvider, dayLogStoreProvider;
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/day_log_store.dart';
import 'package:route_monitor/local/local_write_store.dart' show PendingOpKind;

/// Every logged day, oldest first — the profile's streak and achievements.
/// Auto-disposed: the profile re-reads the log each time it opens, so the
/// check-outs and days logged meanwhile show (nothing else invalidates it).
final FutureProvider<List<DayLogEntry>> dayLogEntriesProvider =
    FutureProvider.autoDispose<List<DayLogEntry>>(
      (ref) => ref.watch(dayLogStoreProvider).all(),
    );

/// The clock the gamification reads "today" from; tests pin it.
final gamificationClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// When the first of [routeStopIds] was checked in on this device, or null
/// when none was (a batch worked on another device).
typedef FirstCheckInLookup =
    Future<DateTime?> Function(Iterable<String> routeStopIds);

/// The full card's "em 3 h 43 min" starts at the batch's first check-in.
final firstCheckInLookupProvider = Provider<FirstCheckInLookup>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (routeStopIds) => firstCheckInAt(db, routeStopIds);
});

/// Reads the outbox: a check-in row is never deleted once synced (only a
/// released stop's rows are discarded), and its `created_at` is the scan's
/// device time. Nothing else on the device keeps the check-in time —
/// `stop_progress.updated_at` moves to the check-out.
///
///     await firstCheckInAt(db, ['s1', 's2']); // 2026-10-21 07:42
Future<DateTime?> firstCheckInAt(
  AppDatabase db,
  Iterable<String> routeStopIds,
) async {
  final ids = routeStopIds.toList();
  if (ids.isEmpty) return null;
  final marks = List.filled(ids.length, '?').join(', ');
  final row = await db
      .customSelect(
        'SELECT MIN(created_at) AS first FROM pending_operations '
        'WHERE kind = ? '
        "AND json_extract(payload_json, '\$.route_stop_id') IN ($marks)",
        variables: [
          Variable.withString(PendingOpKind.checkIn.name),
          for (final id in ids) Variable.withString(id),
        ],
        readsFrom: {db.pendingOperations},
      )
      .getSingle();
  final first = row.read<int?>('first');
  return first == null ? null : DateTime.fromMillisecondsSinceEpoch(first);
}
