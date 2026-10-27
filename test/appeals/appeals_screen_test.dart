import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/appeals/appeal_api.dart';
import 'package:route_monitor/appeals/appeal_form_screen.dart';
import 'package:route_monitor/appeals/appeal_providers.dart';
import 'package:route_monitor/appeals/appeals_screen.dart';
import 'package:route_monitor/appeals/day_time.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/released_stop_store.dart';

import '../support/in_memory_database.dart';
import 'fake_appeal_api.dart';

final _deadline = DateTime.utc(2026, 10, 23, 14);

AppealableStop _eligible({
  String id = 'rs-1',
  String name = 'Sala 101',
  String reason = 'LOCATION_SILENCE',
}) => AppealableStop(
  routeStopId: id,
  servicePointName: name,
  buildingName: 'Bloco CAA',
  floorLabel: 'Térreo',
  releaseReason: reason,
  deadline: _deadline,
);

FiledAppeal _appeal({
  required String status,
  String name = 'Sala 202',
  String? reviewNote,
}) => FiledAppeal(
  id: 'ap-$status',
  servicePointName: name,
  buildingName: 'Bloco CAA',
  status: status,
  filedAt: DateTime.utc(2026, 10, 21, 18),
  reviewedByName: status == 'PENDING' ? null : 'Gestora',
  reviewNote: reviewNote,
);

/// A throwing API: the load-error state.
class _FailingAppealApi extends RecordingAppealApi {
  @override
  Future<List<AppealableStop>> eligible() async =>
      throw Exception('no network');
}

/// A fresh device database, closed after the test.
AppDatabase _deviceDb() {
  final db = inMemoryDatabase();
  addTearDown(db.close);
  return db;
}

Widget _app(
  AppealApi api, {
  Widget home = const AppealsScreen(),
  AppDatabase? db,
}) {
  db ??= _deviceDb();
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      appealApiProvider.overrideWithValue(api),
    ],
    child: MaterialApp(home: home),
  );
}

void main() {
  testWidgets(
    'lists the released points the worker can contest with building, '
    'release reason and deadline',
    (tester) async {
      await tester.pumpWidget(
        _app(RecordingAppealApi(eligibleStops: [_eligible()])),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.appealsEligibleTitle), findsOneWidget);
      expect(find.text('Sala 101'), findsOneWidget);
      expect(
        find.text(
          AppStrings.appealEligibleDetails(
            building: 'Bloco CAA',
            floor: 'Térreo',
            reason: AppStrings.releaseReasonLabel('LOCATION_SILENCE'),
            deadline: formatDayTime(_deadline),
          ),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('lists "Meus recursos" with each status and the review', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        RecordingAppealApi(
          myAppeals: [
            _appeal(status: 'PENDING', name: 'Sala 1'),
            _appeal(status: 'ACCEPTED', name: 'Sala 2'),
            _appeal(
              status: 'REJECTED',
              name: 'Sala 3',
              reviewNote: 'Sem registro.',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.appealsMineTitle), findsOneWidget);
    expect(find.text(AppStrings.appealStatusLabel('PENDING')), findsOneWidget);
    expect(find.text(AppStrings.appealStatusLabel('ACCEPTED')), findsOneWidget);
    expect(find.text(AppStrings.appealStatusLabel('REJECTED')), findsOneWidget);
    expect(find.text('Em análise'), findsOneWidget);
    expect(
      find.text(AppStrings.appealReview('Gestora', 'Sem registro.')),
      findsOneWidget,
    );
  });

  testWidgets('says when there is nothing to contest and no appeal yet', (
    tester,
  ) async {
    await tester.pumpWidget(_app(RecordingAppealApi()));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.appealsEligibleEmpty), findsOneWidget);
    expect(find.text(AppStrings.appealsMineEmpty), findsOneWidget);
  });

  testWidgets('a failed load says so', (tester) async {
    await tester.pumpWidget(_app(_FailingAppealApi()));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.appealsLoadError), findsOneWidget);
  });

  testWidgets('tapping a released point opens its appeal form', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(RecordingAppealApi(eligibleStops: [_eligible()])),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sala 101'));
    await tester.pumpAndSettle();

    final form = tester.widget<AppealFormScreen>(find.byType(AppealFormScreen));
    expect(form.routeStopId, 'rs-1');
    expect(form.releaseReason, 'LOCATION_SILENCE');
  });

  group(
    'released stops with data on the device, whatever the route state '
    '(spec §7.5)',
    () {
      /// A device holding parked data for [stop], released for [reason].
      Future<AppDatabase> deviceWith(
        String stop, {
        required String reason,
        required bool appealable,
        AppDatabase? db,
      }) async {
        db ??= _deviceDb();
        final outbox = DriftLocalWriteStore(db);
        await outbox.enqueue(
          id: 'in-$stop',
          kind: PendingOpKind.checkIn,
          routeId: 'old-route',
          payload: {'execution_id': 'exec-$stop', 'route_stop_id': stop},
        );
        await outbox.markStopReleased(
          'in-$stop',
          routeStopId: stop,
          error: '409',
        );
        await DriftReleasedStopStore(db).record(
          routeStopId: stop,
          releaseReason: reason,
          appealable: appealable,
        );
        return db;
      }

      Finder button(String label) => find.widgetWithText(TextButton, label);

      testWidgets(
        'an appealable stop still on the server list offers "Recorrer" '
        '(under its name, listed once) and "Descartar"',
        (tester) async {
          final db = await deviceWith(
            'rs-1',
            reason: 'LOCATION_SILENCE',
            appealable: true,
          );
          await tester.pumpWidget(
            _app(RecordingAppealApi(eligibleStops: [_eligible()]), db: db),
          );
          await tester.pumpAndSettle();

          expect(find.text(AppStrings.appealsLocalTitle), findsOneWidget);
          expect(find.text('Sala 101'), findsOneWidget);
          expect(button(AppStrings.releasedStopAppealButton), findsOneWidget);
          expect(button(AppStrings.releasedStopDiscardButton), findsOneWidget);
          // Not repeated in the server's list, and no "nothing to contest".
          expect(find.text(AppStrings.appealsEligibleEmpty), findsNothing);

          await tester.tap(button(AppStrings.releasedStopAppealButton));
          await tester.pumpAndSettle();
          final form = tester.widget<AppealFormScreen>(
            find.byType(AppealFormScreen),
          );
          expect(form.routeStopId, 'rs-1');
          expect(form.servicePointName, 'Sala 101');
        },
      );

      testWidgets(
        'a stop off the server list (window closed) or released by the '
        'worker offers only "Descartar"',
        (tester) async {
          final db = await deviceWith(
            'rs-1',
            reason: 'END_OF_DAY',
            appealable: true,
          );
          await deviceWith(
            'rs-2',
            reason: 'IMPEDIMENT',
            appealable: false,
            db: db,
          );
          await tester.pumpWidget(_app(RecordingAppealApi(), db: db));
          await tester.pumpAndSettle();

          expect(find.text(AppStrings.releasedStopTitle('rs-1')), findsOne);
          expect(find.text(AppStrings.releasedStopTitle('rs-2')), findsOne);
          expect(button(AppStrings.releasedStopAppealButton), findsNothing);
          expect(
            button(AppStrings.releasedStopDiscardButton),
            findsNWidgets(2),
          );
          expect(
            find.text(AppStrings.releasedStopNotAppealable),
            findsNWidgets(2),
          );
        },
      );

      testWidgets(
        'offline the server cannot say the window closed: an appealable '
        'notice keeps "Recorrer"',
        (tester) async {
          final db = await deviceWith(
            'rs-1',
            reason: 'LEFT_CAMPUS',
            appealable: true,
          );
          await tester.pumpWidget(_app(_FailingAppealApi(), db: db));
          await tester.pumpAndSettle();

          expect(button(AppStrings.releasedStopAppealButton), findsOneWidget);
        },
      );

      testWidgets(
        '"Descartar" confirms, then deletes only that stop from the device',
        (tester) async {
          final db = await deviceWith(
            'rs-1',
            reason: 'IMPEDIMENT',
            appealable: false,
          );
          await deviceWith(
            'rs-2',
            reason: 'IMPEDIMENT',
            appealable: false,
            db: db,
          );
          await tester.pumpWidget(_app(RecordingAppealApi(), db: db));
          await tester.pumpAndSettle();

          await tester.tap(button(AppStrings.releasedStopDiscardButton).first);
          await tester.pumpAndSettle();
          expect(find.text(AppStrings.releasedStopDiscardBody), findsOneWidget);
          await tester.tap(
            find.widgetWithText(
              FilledButton,
              AppStrings.releasedStopDiscardButton,
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text(AppStrings.releasedStopTitle('rs-1')), findsNothing);
          expect(find.text(AppStrings.releasedStopTitle('rs-2')), findsOne);
          final outbox = DriftLocalWriteStore(db);
          expect(
            (await outbox.blockedForRoute('old-route')).map((r) => r.id),
            ['in-rs-2'],
          );
          expect(await DriftReleasedStopStore(db).noticeFor('rs-1'), isNull);
        },
      );

      testWidgets(
        'the entry badge counts device stops and server points, each once',
        (tester) async {
          final db = await deviceWith(
            'rs-1',
            reason: 'LOCATION_SILENCE',
            appealable: true,
          );
          await deviceWith(
            'rs-9',
            reason: 'IMPEDIMENT',
            appealable: false,
            db: db,
          );
          await tester.pumpWidget(
            _app(
              RecordingAppealApi(
                eligibleStops: [
                  _eligible(),
                  _eligible(id: 'rs-2'),
                ],
              ),
              db: db,
              home: Scaffold(
                appBar: AppBar(actions: const [AppealsEntryButton()]),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // rs-1 (both), rs-2 (server), rs-9 (device).
          expect(find.widgetWithText(Badge, '3'), findsOneWidget);
        },
      );
    },
  );

  group('the route screen entry', () {
    Widget entry(AppealApi api) => _app(
      api,
      home: Scaffold(appBar: AppBar(actions: const [AppealsEntryButton()])),
    );

    testWidgets('shows a badge with the count of contestable points', (
      tester,
    ) async {
      await tester.pumpWidget(
        entry(
          RecordingAppealApi(
            eligibleStops: [
              _eligible(),
              _eligible(id: 'rs-2'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip(AppStrings.appealsTooltip), findsOneWidget);
      expect(find.widgetWithText(Badge, '2'), findsOneWidget);
    });

    testWidgets('shows no badge when there is nothing to contest', (
      tester,
    ) async {
      await tester.pumpWidget(entry(RecordingAppealApi()));
      await tester.pumpAndSettle();

      expect(find.byTooltip(AppStrings.appealsTooltip), findsOneWidget);
      expect(find.byType(Badge), findsNothing);
    });
  });
}
