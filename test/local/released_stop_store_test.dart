import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/forms/form_draft_store.dart';
import 'package:route_monitor/forms/form_schema.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/released_stop_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';

import '../support/in_memory_database.dart';

const _checkInAt = '2026-10-21T13:05:00.000Z';
const _checkOutAt = '2026-10-21T13:40:00.000Z';

void main() {
  late AppDatabase db;
  late DriftLocalWriteStore outbox;
  late DriftReleasedStopStore released;
  late DriftStopProgressStore progress;
  late DriftFormDraftStore drafts;

  setUp(() {
    db = inMemoryDatabase();
    addTearDown(db.close);
    outbox = DriftLocalWriteStore(db);
    released = DriftReleasedStopStore(
      db,
      now: () => DateTime.utc(2026, 10, 21, 15),
    );
    progress = DriftStopProgressStore(db);
    drafts = DriftFormDraftStore(db);
  });

  /// Stop [stop]'s offline work: a check-in (execution `exec-<stop>`), a
  /// photo and a note of that execution, a check-out.
  Future<void> workedOffline(String stop, {String route = 'r1'}) async {
    await outbox.enqueue(
      id: 'in-$stop',
      kind: PendingOpKind.checkIn,
      routeId: route,
      payload: {
        'execution_id': 'exec-$stop',
        'route_stop_id': stop,
        'scanned_at': _checkInAt,
      },
    );
    await outbox.enqueue(
      id: 'photo-$stop',
      kind: PendingOpKind.evidencePhoto,
      routeId: route,
      payload: {'execution_id': 'exec-$stop', 'bytes_b64': 'AAAA'},
    );
    await outbox.enqueue(
      id: 'note-$stop',
      kind: PendingOpKind.evidenceNote,
      routeId: route,
      payload: {'execution_id': 'exec-$stop', 'text_body': 'ok'},
    );
    await outbox.enqueue(
      id: 'out-$stop',
      kind: PendingOpKind.checkOut,
      routeId: route,
      payload: {
        // A check-out's execution_id is a throwaway the backend ignores.
        'execution_id': 'throwaway-$stop',
        'route_stop_id': stop,
        'scanned_at': _checkOutAt,
        'answers': [
          {'stable_key': 'q1', 'value': 'limpo'},
        ],
      },
    );
    await progress.upsertInProgress(stop, 'exec-$stop');
    await progress.markDone(stop);
  }

  group('record', () {
    test(
      "fills the local check-in and check-out times from the stop's outbox "
      'rows, whatever their state',
      () async {
        await workedOffline('s1');
        // The check-in reached the server before the stop was released.
        await outbox.markSynced('in-s1');

        final created = await released.record(
          routeStopId: 's1',
          releaseReason: 'LOCATION_SILENCE',
          appealable: true,
        );

        final notice = (await released.noticeFor('s1'))!;
        expect(created, isTrue);
        expect(notice.releaseReason, 'LOCATION_SILENCE');
        expect(notice.appealable, isTrue);
        expect(notice.localCheckInAt, DateTime.parse(_checkInAt));
        expect(notice.localCheckOutAt, DateTime.parse(_checkOutAt));
        expect(notice.createdAt, DateTime.utc(2026, 10, 21, 15));
      },
    );

    test('a stop never checked in on this device has no local times', () async {
      await released.record(
        routeStopId: 's9',
        releaseReason: 'END_OF_DAY',
        appealable: true,
      );

      final notice = (await released.noticeFor('s9'))!;
      expect(notice.localCheckInAt, isNull);
      expect(notice.localCheckOutAt, isNull);
    });

    test(
      'the first notice of a stop wins: a second 409 of the same stop creates '
      'nothing',
      () async {
        await released.record(
          routeStopId: 's1',
          releaseReason: 'LEFT_CAMPUS',
          appealable: true,
        );

        final again = await released.record(
          routeStopId: 's1',
          releaseReason: 'LEFT_CAMPUS',
          appealable: false,
        );

        expect(again, isFalse);
        expect((await released.noticeFor('s1'))!.appealable, isTrue);
      },
    );
  });

  test('appealableNotices lists only the appealable ones', () async {
    await released.record(
      routeStopId: 's1',
      releaseReason: 'LEFT_CAMPUS',
      appealable: true,
    );
    await released.record(
      routeStopId: 's2',
      releaseReason: 'IMPEDIMENT',
      appealable: false,
    );

    final notices = await released.appealableNotices();

    expect(notices.map((n) => n.routeStopId), ['s1']);
  });

  group('discardStop', () {
    test(
      "deletes the stop's outbox rows, evidence, answers, progress and "
      'notice — and nothing of another stop',
      () async {
        await workedOffline('s1');
        await workedOffline('s2');
        await drafts.snapshotFrom(
          'exec-s1',
          's1',
          const FormSchema(
            formVersionId: 'v1',
            questions: [
              FormQuestion(
                stableKey: 'q1',
                orderIndex: 0,
                prompt: 'Estado',
                type: QuestionType.text,
                required: true,
                options: [],
                contentHash: 'h1',
              ),
            ],
          ),
        );
        await outbox.markStopReleased(
          'out-s1',
          routeStopId: 's1',
          error: 'HTTP 409',
        );
        await released.record(
          routeStopId: 's1',
          releaseReason: 'LOCATION_SILENCE',
          appealable: true,
        );

        await released.discardStop('s1');

        final left = await outbox.unsyncedForRoute('r1');
        expect(left.map((row) => row.id).toSet(), {
          'in-s2',
          'photo-s2',
          'note-s2',
          'out-s2',
        });
        expect(await outbox.blockedForRoute('r1'), isEmpty);
        expect(await drafts.itemsFor('exec-s1'), isEmpty);
        expect(await progress.progressFor('s1'), isNull);
        expect(await progress.progressFor('s2'), isNotNull);
        expect(await released.noticeFor('s1'), isNull);
      },
    );

    test(
      'finds the evidence of an execution whose check-in row is already gone, '
      'through the stop progress',
      () async {
        await progress.upsertInProgress('s1', 'exec-s1');
        await outbox.enqueue(
          id: 'photo-s1',
          kind: PendingOpKind.evidencePhoto,
          routeId: 'r1',
          payload: {'execution_id': 'exec-s1', 'bytes_b64': 'AAAA'},
        );

        await released.discardStop('s1');

        expect(await outbox.unsyncedForRoute('r1'), isEmpty);
      },
    );
  });
}
