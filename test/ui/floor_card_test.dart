import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/routing/building_card_model.dart';
import 'package:route_monitor/ui/app_theme.dart';
import 'package:route_monitor/ui/floor_card.dart';
import 'package:route_monitor/ui/stamp_slot.dart';

CardSlot _slot(String id, SlotState state) => CardSlot(
  stopId: id,
  state: state,
  floorLabel: 'Andar',
  stampedAt: state == SlotState.done ? DateTime(2026, 10, 28, 9) : null,
  pendingSync: false,
  releaseReason: null,
  stampRotationDeg: 0,
);

DayBuilding _building(List<FloorRow> floors) => DayBuilding(
  buildingId: 'b1',
  name: 'Central de Aulas',
  number: 1,
  position: const LatLng(-7.21, -35.91),
  floors: floors,
);

final DayBuilding _twoFloors = _building([
  FloorRow(
    floorId: 'f1',
    label: 'Andar 1',
    slots: [_slot('s1', SlotState.next), _slot('s2', SlotState.pending)],
  ),
  FloorRow(
    floorId: 'f2',
    label: 'Andar 2',
    slots: [_slot('s3', SlotState.pending)],
  ),
]);

Future<void> _pump(
  WidgetTester tester,
  DayBuilding building, {
  void Function(CardSlot, FloorRow)? onSlotTap,
  String? animateStopId,
}) => tester.pumpWidget(
  MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: SingleChildScrollView(
        child: FloorCard(
          building: building,
          onSlotTap: onSlotTap ?? (_, _) {},
          animateStopId: animateStopId,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('the title counts the tasks in the display face', (
    tester,
  ) async {
    await _pump(tester, _twoFloors);

    final title = tester.widget<Text>(find.text(AppStrings.floorCardTitle(3)));
    expect(title.style?.fontFamily, kDisplayFont);
    expect(AppStrings.floorCardTitle(1), 'Complete 1 tarefa');
  });

  testWidgets('one row per floor, in order, each with its slots', (
    tester,
  ) async {
    await _pump(tester, _twoFloors);

    final first = tester.getTopLeft(find.text('Andar 1')).dy;
    final second = tester.getTopLeft(find.text('Andar 2')).dy;
    expect(first, lessThan(second));
    expect(find.byType(StampSlot), findsNWidgets(3));
    // s3 sits under "Andar 2", below both slots of "Andar 1".
    final s3 = find.byKey(const ValueKey('floor-slot-s3'));
    expect(tester.getTopLeft(s3).dy, greaterThan(second));
  });

  testWidgets('slots are 48dp, 8dp apart, and report the tap with the floor', (
    tester,
  ) async {
    final taps = <(String, String)>[];
    await _pump(
      tester,
      _twoFloors,
      onSlotTap: (slot, floor) => taps.add((slot.stopId, floor.label)),
    );

    final s1 = tester.getRect(find.byKey(const ValueKey('floor-slot-s1')));
    final s2 = tester.getRect(find.byKey(const ValueKey('floor-slot-s2')));
    expect(s1.width, greaterThanOrEqualTo(48));
    expect(s1.height, greaterThanOrEqualTo(48));
    expect(s2.left - s1.right, 8);

    await tester.tap(find.byKey(const ValueKey('floor-slot-s3')));
    expect(taps, [('s3', 'Andar 2')]);
  });

  testWidgets('only the slot just stamped animates', (tester) async {
    await _pump(tester, _twoFloors, animateStopId: 's2');

    final animating = tester
        .widgetList<StampSlot>(find.byType(StampSlot))
        .where((slot) => slot.animateStamp)
        .map((slot) => slot.slot.stopId);
    expect(animating, ['s2']);
  });

  testWidgets('a finished building reads "Prédio concluído"', (tester) async {
    await _pump(
      tester,
      _building([
        FloorRow(
          floorId: 'f1',
          label: 'Andar 1',
          slots: [_slot('s1', SlotState.done), _slot('s2', SlotState.impeded)],
        ),
      ]),
    );

    expect(find.text(AppStrings.floorCardDone), findsOneWidget);
    expect(find.textContaining('Complete'), findsNothing);
  });
}
