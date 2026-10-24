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

Widget _app(AppealApi api, {Widget home = const AppealsScreen()}) {
  final db = inMemoryDatabase();
  addTearDown(db.close);
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
