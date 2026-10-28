import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/local/app_database.dart';

void main() {
  test(
    'the connection pragma makes SQLite wait on a lock instead of failing at '
    'once — the background drain opens the same file on another connection',
    () async {
      final db = AppDatabase(
        NativeDatabase.memory(
          setup: (raw) => raw.execute(appDatabaseBusyTimeoutPragma),
        ),
      );
      addTearDown(db.close);

      final row = await db.customSelect('PRAGMA busy_timeout').getSingle();

      expect(row.data.values.single, appDatabaseBusyTimeout.inMilliseconds);
    },
  );
}
