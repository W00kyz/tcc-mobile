import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/ui/app_theme.dart';
import 'package:route_monitor/ui/stamp_slot.dart';

CardSlot slot(
  SlotState state, {
  bool sync = false,
  String? reason,
  DateTime? at,
}) => CardSlot(
  stopId: 's1',
  state: state,
  floorLabel: '2º andar',
  stampedAt: at,
  pendingSync: sync,
  releaseReason: reason,
  stampRotationDeg: 3,
);

Widget host(Widget child, {bool disableAnimations = false}) => MaterialApp(
  theme: buildAppTheme(),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('done shows hour and label', (t) async {
    await t.pumpWidget(
      host(
        StampSlot(slot: slot(SlotState.done, at: DateTime(2026, 1, 1, 10, 20))),
      ),
    );
    expect(find.text('10:20'), findsOneWidget);
    expect(find.bySemanticsLabel('Concluído às 10:20'), findsOneWidget);
  });

  testWidgets('other states carry semantic labels', (t) async {
    final cases = {
      SlotState.pending: 'Pendente',
      SlotState.next: 'Próximo',
      SlotState.inProgress: 'Em andamento',
    };
    for (final e in cases.entries) {
      await t.pumpWidget(host(StampSlot(slot: slot(e.key))));
      expect(find.bySemanticsLabel(e.value), findsOneWidget);
    }
    await t.pumpWidget(
      host(StampSlot(slot: slot(SlotState.released, reason: 'Sem sinal'))),
    );
    expect(find.bySemanticsLabel('Liberado: Sem sinal'), findsOneWidget);
  });

  testWidgets('pendingSync shows the cloud icon', (t) async {
    await t.pumpWidget(
      host(StampSlot(slot: slot(SlotState.pending, sync: true))),
    );
    expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
  });

  testWidgets('animateStamp honours disableAnimations', (t) async {
    await t.pumpWidget(
      host(
        StampSlot(
          slot: slot(SlotState.done, at: DateTime(2026, 1, 1, 9, 5)),
          animateStamp: true,
        ),
        disableAnimations: true,
      ),
    );
    expect(find.text('09:05'), findsOneWidget);
    expect(t.hasRunningAnimations, isFalse);
  });

  testWidgets('animateStamp runs and settles', (t) async {
    await t.pumpWidget(
      host(
        StampSlot(
          slot: slot(SlotState.done, at: DateTime(2026, 1, 1, 9, 5)),
          animateStamp: true,
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 100));
    expect(t.hasRunningAnimations, isTrue);
    await t.pumpAndSettle();
    expect(find.text('09:05'), findsOneWidget);
  });
}
