import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/local/background_ask_store.dart';

import '../support/in_memory_database.dart';

void main() {
  test(
    'remembers, across store instances, that the question was asked',
    () async {
      final db = inMemoryDatabase();
      addTearDown(db.close);

      expect(await DriftBackgroundAskStore(db).wasAsked(), isFalse);
      await DriftBackgroundAskStore(db).markAsked();

      expect(await DriftBackgroundAskStore(db).wasAsked(), isTrue);
    },
  );
}
