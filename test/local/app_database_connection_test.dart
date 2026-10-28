import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/local/app_database.dart';

void main() {
  test(
    'every connection waits on a lock and runs in WAL — the background '
    'drain opens the same file on a second connection',
    () async {
      final dir = await Directory.systemTemp.createTemp('pragma_test');
      addTearDown(() => dir.delete(recursive: true));
      final db = AppDatabase(
        NativeDatabase(
          File('${dir.path}/route_monitor.sqlite'),
          setup: (raw) => appDatabaseConnectionPragmas.forEach(raw.execute),
        ),
      );
      addTearDown(db.close);

      final timeout = await db.customSelect('PRAGMA busy_timeout').getSingle();
      final journal = await db.customSelect('PRAGMA journal_mode').getSingle();

      expect(
        timeout.data.values.single,
        appDatabaseBusyTimeout.inMilliseconds,
      );
      expect(journal.data.values.single, 'wal');
    },
  );
}
