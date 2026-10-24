import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/appeals/appeal_api.dart';
import 'package:route_monitor/appeals/appeal_form_screen.dart';
import 'package:route_monitor/appeals/appeal_providers.dart';
import 'package:route_monitor/appeals/day_time.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/released_stop_store.dart';

import '../support/in_memory_database.dart';
import 'fake_appeal_api.dart';

final _checkInAt = DateTime.utc(2026, 10, 21, 13, 5);

void main() {
  late AppDatabase db;
  late DriftLocalWriteStore outbox;
  late DriftReleasedStopStore released;
  late RecordingAppealApi api;

  setUp(() {
    db = inMemoryDatabase();
    addTearDown(db.close);
    outbox = DriftLocalWriteStore(db);
    released = DriftReleasedStopStore(db);
    api = RecordingAppealApi();
  });

  /// Stop s1 was checked in and out offline, then released while the device
  /// was away: the check-out came back 409 STOP_RELEASED and was parked.
  Future<void> parkedReleasedStop() async {
    await outbox.enqueue(
      id: 'in-s1',
      kind: PendingOpKind.checkIn,
      routeId: 'r1',
      payload: {
        'execution_id': 'exec-s1',
        'route_stop_id': 's1',
        'scanned_at': _checkInAt.toIso8601String(),
      },
    );
    await outbox.markSynced('in-s1');
    await outbox.enqueue(
      id: 'photo-s1',
      kind: PendingOpKind.evidencePhoto,
      routeId: 'r1',
      payload: {'execution_id': 'exec-s1', 'bytes_b64': 'AAAA'},
    );
    await outbox.enqueue(
      id: 'out-s1',
      kind: PendingOpKind.checkOut,
      routeId: 'r1',
      payload: {
        'execution_id': 'throwaway',
        'route_stop_id': 's1',
        'scanned_at': '2026-10-21T13:40:00.000Z',
        'answers': [
          {'stable_key': 'q1', 'value': 'limpo'},
        ],
      },
    );
    await outbox.markStopReleased('out-s1', routeStopId: 's1', error: '409');
    await released.record(
      routeStopId: 's1',
      releaseReason: 'LOCATION_SILENCE',
      appealable: true,
    );
  }

  /// The form, pushed over a host page so a successful send can pop back.
  Widget app() => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      appealApiProvider.overrideWithValue(api),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<bool>(
                builder: (_) => const AppealFormScreen(
                  routeStopId: 's1',
                  releaseReason: 'LOCATION_SILENCE',
                  servicePointName: 'Sala 101',
                ),
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );

  Future<void> openForm(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> sendWith(WidgetTester tester, String reasonLabel) async {
    await tester.tap(find.text(reasonLabel));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, AppStrings.appealSubmit),
    );
    await tester.pumpAndSettle();
  }

  Future<void> confirmWarning(WidgetTester tester) async {
    await tester.tap(
      find.widgetWithText(FilledButton, AppStrings.appealWarningConfirm),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'pre-fills the declared time with the local check-in and names the point '
    'and the release reason',
    (tester) async {
      await parkedReleasedStop();
      await openForm(tester);

      expect(find.text('Sala 101'), findsOneWidget);
      expect(
        find.text(
          AppStrings.appealReleaseReason(
            AppStrings.releaseReasonLabel('LOCATION_SILENCE'),
          ),
        ),
        findsOneWidget,
      );
      expect(find.text(formatDayTime(_checkInAt)), findsOneWidget);
      for (final label in [
        AppStrings.appealReasonNoSignal,
        AppStrings.appealReasonLeftBriefly,
        AppStrings.appealReasonAppClosed,
        AppStrings.appealReasonOther,
      ]) {
        expect(find.text(label), findsOneWidget);
      }
    },
  );

  testWidgets('"Enviar recurso" waits for a reason', (tester) async {
    await openForm(tester);

    final submit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, AppStrings.appealSubmit),
    );
    expect(submit.onPressed, isNull);
  });

  testWidgets(
    'warns that the offline photos and answers will be erased; cancelling '
    'sends nothing and keeps them',
    (tester) async {
      await parkedReleasedStop();
      await openForm(tester);

      await sendWith(tester, AppStrings.appealReasonNoSignal);

      expect(find.text(AppStrings.appealLocalDataWarning), findsOneWidget);
      await tester.tap(
        find.widgetWithText(TextButton, AppStrings.commonCancel),
      );
      await tester.pumpAndSettle();

      expect(api.filed, isEmpty);
      expect(await outbox.blockedForRoute('r1'), hasLength(1));
    },
  );

  testWidgets(
    'sends the declaration and then deletes the local evidence, answers and '
    'outbox rows of the stop',
    (tester) async {
      await parkedReleasedStop();
      await openForm(tester);

      await tester.enterText(find.byType(TextField), 'Subsolo sem sinal.');
      await sendWith(tester, AppStrings.appealReasonNoSignal);
      await confirmWarning(tester);

      final filing = api.filed.single;
      expect(filing.routeStopId, 's1');
      expect(filing.reason, 'NO_SIGNAL');
      expect(filing.note, 'Subsolo sem sinal.');
      expect(filing.claimedExecutedAt, _checkInAt);
      expect(filing.idempotencyKey, isNotEmpty);
      expect(await outbox.blockedForRoute('r1'), isEmpty);
      expect(await outbox.unsyncedForRoute('r1'), isEmpty);
      expect(await released.noticeFor('s1'), isNull);
      // Back on the host page, with the confirmation.
      expect(find.text('abrir'), findsOneWidget);
      expect(find.text(AppStrings.appealSent), findsOneWidget);
    },
  );

  testWidgets(
    'a refusal says why and keeps the local data for the worker to discard',
    (tester) async {
      await parkedReleasedStop();
      api.fileError = const NotAppealableException('WINDOW_EXPIRED');
      await openForm(tester);

      await sendWith(tester, AppStrings.appealReasonOther);
      await confirmWarning(tester);

      expect(
        find.text(AppStrings.appealRefusal('WINDOW_EXPIRED')),
        findsOneWidget,
      );
      expect(await outbox.blockedForRoute('r1'), hasLength(1));
      expect(await released.noticeFor('s1'), isNotNull);
    },
  );

  testWidgets(
    'ALREADY_APPEALED says so and clears the local data: the appeal on record '
    'already covers the stop',
    (tester) async {
      await parkedReleasedStop();
      api.fileError = const NotAppealableException('ALREADY_APPEALED');
      await openForm(tester);

      await sendWith(tester, AppStrings.appealReasonOther);
      await confirmWarning(tester);

      expect(find.text('Você já recorreu deste ponto.'), findsOneWidget);
      expect(await outbox.blockedForRoute('r1'), isEmpty);
      expect(await released.noticeFor('s1'), isNull);
      expect(find.text('abrir'), findsOneWidget);
    },
  );

  testWidgets('a network failure keeps the form open to try again', (
    tester,
  ) async {
    await parkedReleasedStop();
    api.fileError = DioException(
      requestOptions: RequestOptions(path: '/appeals'),
    );
    await openForm(tester);

    await sendWith(tester, AppStrings.appealReasonOther);
    await confirmWarning(tester);

    expect(find.text(AppStrings.appealSendError), findsOneWidget);
    expect(find.text(AppStrings.appealSubmit), findsOneWidget);
    expect(await released.noticeFor('s1'), isNotNull);
  });

  testWidgets(
    'with no local check-in the time is not declared and none is sent',
    (tester) async {
      await openForm(tester);

      expect(find.text(AppStrings.appealClaimedTimeNone), findsOneWidget);
      await sendWith(tester, AppStrings.appealReasonAppClosed);
      await confirmWarning(tester);

      expect(api.filed.single.claimedExecutedAt, isNull);
      expect(api.filed.single.note, isNull);
    },
  );
}
