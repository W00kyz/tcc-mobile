import 'package:route_monitor/local/day_log_store.dart';

/// In-memory [DayLogStore] that records every call; the real Drift
/// behaviour is proven by day_log_store_test.dart.
class RecordingDayLogStore implements DayLogStore {
  RecordingDayLogStore({List<DayLogEntry> entries = const []})
    : entries = [...entries];

  final List<DayLogEntry> entries;
  final List<String> calls = [];

  /// When set, `recordStopDone` throws it (the atomicity test).
  Exception? failStopDone;

  @override
  Future<void> recordDayOpened(DateTime day, {required bool serviceDay}) async {
    calls.add('opened:${dayKey(day)}:$serviceDay');
  }

  @override
  Future<void> recordStopDone(DateTime day) async {
    final failure = failStopDone;
    if (failure != null) throw failure;
    calls.add('stopDone:${dayKey(day)}');
  }

  @override
  Future<void> recordCardCompleted(DateTime day, {required bool clean}) async {
    calls.add('cardCompleted:${dayKey(day)}:$clean');
  }

  @override
  Future<List<DayLogEntry>> all() async => entries;
}
