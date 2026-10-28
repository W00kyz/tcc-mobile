import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/ui/app_theme.dart';
import 'package:route_monitor/ui/building_pin.dart';
import 'package:route_monitor/ui/stamp_painters.dart';

BuildingGroup group(String name) => BuildingGroup(
  buildingId: 'a',
  buildingName: name,
  position: const LatLng(0, 0),
  slots: [
    for (final (i, st) in [
      SlotState.done,
      SlotState.next,
      SlotState.pending,
    ].indexed)
      CardSlot(
        stopId: '$i',
        state: st,
        floorLabel: 'T',
        stampedAt: null,
        pendingSync: false,
        releaseReason: null,
        stampRotationDeg: 0,
      ),
  ],
);

Widget host(Widget w) => MaterialApp(
  theme: buildAppTheme(),
  home: Scaffold(body: Center(child: w)),
);

void main() {
  testWidgets('shows count and label', (t) async {
    await t.pumpWidget(host(BuildingPin(group: group('Central de Aulas'))));
    expect(find.text('1/3'), findsOneWidget);
    expect(find.text('Central de Aulas'), findsOneWidget);
  });

  testWidgets('long names are cut with an ellipsis at 16 chars', (t) async {
    final name = 'A' * 30;
    await t.pumpWidget(host(BuildingPin(group: group(name))));
    expect(find.text('${'A' * 15}…'), findsOneWidget);
  });

  RingPainter? ring(WidgetTester t) => t
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((c) => c.painter)
      .whereType<RingPainter>()
      .firstOrNull;

  BuildingGroup of(List<SlotState> states) => BuildingGroup(
    buildingId: 'a',
    buildingName: 'Prédio',
    position: const LatLng(0, 0),
    slots: [
      for (final (i, st) in states.indexed)
        CardSlot(
          stopId: '$i',
          state: st,
          floorLabel: 'T',
          stampedAt: null,
          pendingSync: false,
          releaseReason: null,
          stampRotationDeg: 0,
        ),
    ],
  );

  testWidgets('pending building: no dashed ring', (t) async {
    await t.pumpWidget(host(BuildingPin(group: of([SlotState.pending]))));
    expect(ring(t), isNull);
  });

  testWidgets('building with the next slot has a dashed ring', (t) async {
    await t.pumpWidget(host(BuildingPin(group: of([SlotState.next]))));
    expect(ring(t), isNotNull);
  });

  testWidgets('inProgress: dashed ring and seal', (t) async {
    await t.pumpWidget(
      host(BuildingPin(group: of([SlotState.pending]), inProgress: true)),
    );
    expect(ring(t), isNotNull);
    expect(find.bySemanticsLabel('Em andamento'), findsOneWidget);
  });

  testWidgets('complete building is moss filled', (t) async {
    await t.pumpWidget(host(BuildingPin(group: of([SlotState.done]))));
    final box = t
        .widgetList<Container>(find.byType(Container))
        .map(
          (c) => c.decoration,
        )
        .whereType<BoxDecoration>()
        .first;
    expect(box.color, FieldPalette.light.moss);
  });

  testWidgets('selected grows the pin', (t) async {
    await t.pumpWidget(
      host(BuildingPin(group: of([SlotState.pending]), selected: true)),
    );
    await t.pumpAndSettle();
    expect(t.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1.2);
  });

  testWidgets('dimmed is 40% opaque', (t) async {
    await t.pumpWidget(
      host(BuildingPin(group: of([SlotState.pending]), dimmed: true)),
    );
    expect(t.widget<Opacity>(find.byType(Opacity)).opacity, 0.4);
  });
}
