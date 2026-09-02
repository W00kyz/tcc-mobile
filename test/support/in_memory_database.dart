import 'package:drift/native.dart';
import 'package:route_monitor/local/app_database.dart';

/// An [AppDatabase] backed by an in-memory SQLite instance — no file, no
/// migration state carried between tests. Pair with `addTearDown(db.close)`.
AppDatabase inMemoryDatabase() => AppDatabase(NativeDatabase.memory());
