import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/ui/app_theme.dart';
import 'package:route_monitor/ui/batch_card.dart';

CardSlot s(String id, SlotState st, String floor) => CardSlot(
  stopId: id,
  state: st,
  floorLabel: floor,
  stampedAt: st == SlotState.done ? DateTime(2026, 1, 1, 8) : null,
  pendingSync: false,
  releaseReason: null,
  stampRotationDeg: 0,
);

BuildingGroup g(String id, String name, List<CardSlot> slots) => BuildingGroup(
  buildingId: id,
  buildingName: name,
  slots: slots,
  position: const LatLng(0, 0),
);

void main() {
  testWidgets('shows title, score, released and groups', (t) async {
    final card = BatchCard(
      batchNumber: 2,
      groups: [
        g('a', 'Central de Aulas', [
          s('1', SlotState.done, 'Térreo'),
          s('2', SlotState.done, '1º andar'),
          s('3', SlotState.next, '2º andar'),
        ]),
        g('b', 'Biblioteca', [
          s('4', SlotState.done, 'Térreo'),
          s('5', SlotState.pending, '3º andar'),
          s('6', SlotState.pending, '4º andar'),
          s('7', SlotState.pending, '5º andar'),
          s('8', SlotState.released, '6º andar'),
        ]),
      ],
    );
    await t.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SingleChildScrollView(child: BatchCardView(card: card)),
        ),
      ),
    );
    expect(find.text('CARTÃO DO LOTE 2'), findsOneWidget);
    expect(find.text('3/7'), findsOneWidget);
    expect(find.text('1 liberado'), findsOneWidget);
    expect(find.text('Central de Aulas'), findsOneWidget);
    expect(find.text('Biblioteca'), findsOneWidget);
    expect(find.text('2º andar'), findsOneWidget);
    expect(find.text('6º andar'), findsOneWidget);
  });

  testWidgets('more than 12 stops scroll inside the card', (t) async {
    final card = BatchCard(
      batchNumber: 1,
      groups: [
        g('a', 'Central', [
          for (var i = 0; i < 16; i++) s('$i', SlotState.pending, 'Andar $i'),
        ]),
      ],
    );
    await t.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Column(children: [BatchCardView(card: card)]),
        ),
      ),
    );
    final scroll = find.byKey(const ValueKey('batch-card-scroll'));
    final state = t.state<ScrollableState>(
      find.descendant(of: scroll, matching: find.byType(Scrollable)),
    );
    expect(state.position.maxScrollExtent, greaterThan(0));
  });

  testWidgets('building subtitle is one line with ellipsis', (t) async {
    final card = BatchCard(
      batchNumber: 1,
      groups: [
        g('a', 'N' * 80, [s('1', SlotState.pending, 'T')]),
      ],
    );
    await t.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: BatchCardView(card: card)),
      ),
    );
    final text = t.widget<Text>(find.text('N' * 80));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
  });
}
