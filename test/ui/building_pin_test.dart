import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/routing/building_card_model.dart';
import 'package:route_monitor/ui/app_theme.dart';
import 'package:route_monitor/ui/building_pin.dart';
import 'package:route_monitor/ui/stamp_painters.dart';

DayBuilding building(
  List<SlotState> states, {
  String name = 'Prédio',
  int number = 2,
}) => DayBuilding(
  buildingId: 'a',
  name: name,
  number: number,
  position: const LatLng(0, 0),
  floors: [
    FloorRow(
      floorId: 'f1',
      label: 'Térreo',
      slots: [
        for (final (i, st) in states.indexed)
          CardSlot(
            stopId: '$i',
            state: st,
            floorLabel: 'Térreo',
            stampedAt: null,
            pendingSync: false,
            releaseReason: null,
            stampRotationDeg: 0,
          ),
      ],
    ),
  ],
);

Widget host(Widget w) => MaterialApp(
  theme: buildAppTheme(),
  home: Scaffold(body: Center(child: w)),
);

RingPainter? ring(WidgetTester t) => t
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((c) => c.painter)
    .whereType<RingPainter>()
    .firstOrNull;

void main() {
  testWidgets('a pending pin shows its number and the name', (t) async {
    await t.pumpWidget(
      host(
        BuildingPin(
          building: building([SlotState.pending], name: 'Central de Aulas'),
        ),
      ),
    );
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Central de Aulas'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('a complete pin shows a check and no number', (t) async {
    await t.pumpWidget(
      host(BuildingPin(building: building([SlotState.done]))),
    );
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text('2'), findsNothing);
  });

  testWidgets('a building of impeded tasks only reads as complete', (t) async {
    await t.pumpWidget(
      host(BuildingPin(building: building([SlotState.impeded]))),
    );
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('the pin is a 40dp head over a 10dp stem', (t) async {
    await t.pumpWidget(
      host(BuildingPin(building: building([SlotState.pending]))),
    );
    final number = t.getRect(find.text('2'));
    final pin = t.getRect(find.byKey(const ValueKey('pin-teardrop')));
    expect(pin.size, const Size(40, 50));
    expect(number.center.dy, closeTo(pin.top + 20, 1));
  });

  testWidgets('long names are cut with an ellipsis at 16 chars', (t) async {
    await t.pumpWidget(
      host(
        BuildingPin(building: building([SlotState.pending], name: 'A' * 30)),
      ),
    );
    expect(find.text('${'A' * 15}…'), findsOneWidget);
  });

  testWidgets('only the next pin paints the dashed ring', (t) async {
    await t.pumpWidget(
      host(BuildingPin(building: building([SlotState.pending]))),
    );
    expect(ring(t), isNull);

    await t.pumpWidget(
      host(BuildingPin(building: building([SlotState.next]), isNext: true)),
    );
    expect(ring(t), isNotNull);
  });

  testWidgets('selected grows the pin by 15% from the tip', (t) async {
    await t.pumpWidget(
      host(
        BuildingPin(building: building([SlotState.pending]), selected: true),
      ),
    );
    await t.pumpAndSettle();
    final scale = t.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(scale.scale, 1.15);
    expect(scale.alignment, Alignment.bottomCenter);
  });

  testWidgets('dimmed is 45% opaque', (t) async {
    await t.pumpWidget(
      host(BuildingPin(building: building([SlotState.pending]), dimmed: true)),
    );
    expect(t.widget<Opacity>(find.byType(Opacity)).opacity, 0.45);
  });

  testWidgets('showLabel false hides the name, never the number', (t) async {
    await t.pumpWidget(
      host(
        BuildingPin(
          building: building([SlotState.pending], name: 'Central de Aulas'),
          showLabel: false,
        ),
      ),
    );
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Central de Aulas'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Central de Aulas')), findsOneWidget);
  });

  testWidgets('reads number, name and closed over total tasks', (t) async {
    await t.pumpWidget(
      host(
        BuildingPin(
          building: building([
            SlotState.done,
            SlotState.pending,
            SlotState.pending,
          ], name: 'Biblioteca'),
        ),
      ),
    );
    expect(
      find.bySemanticsLabel('2. Biblioteca, 1 de 3 tarefas'),
      findsOneWidget,
    );
  });

  testWidgets('the name sits above the pin', (t) async {
    await t.pumpWidget(
      host(
        BuildingPin(
          building: building([SlotState.pending], name: 'Central de Aulas'),
        ),
      ),
    );
    final label = t.getRect(find.text('Central de Aulas'));
    final pin = t.getRect(find.byKey(const ValueKey('pin-teardrop')));
    expect(label.bottom, lessThanOrEqualTo(pin.top));
    expect(label.center.dx, closeTo(pin.center.dx, 1));
  });
}
