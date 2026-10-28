import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

CardSlot doneSlot() => slot(SlotState.done, at: DateTime(2026, 1, 1, 9, 5));

Widget host(
  Widget child, {
  bool disableAnimations = false,
  double textScale = 1,
}) => MaterialApp(
  theme: buildAppTheme(),
  home: MediaQuery(
    data: MediaQueryData(
      disableAnimations: disableAnimations,
      textScaler: TextScaler.linear(textScale),
    ),
    child: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('released shows its reason on screen', (t) async {
    await t.pumpWidget(
      host(StampSlot(slot: slot(SlotState.released, reason: 'LEFT_CAMPUS'))),
    );
    expect(find.text('Saiu do campus'), findsOneWidget);
    expect(find.bySemanticsLabel('Liberado: Saiu do campus'), findsOneWidget);
  });

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

  testWidgets('pendingSync is announced', (t) async {
    await t.pumpWidget(
      host(
        StampSlot(
          slot: slot(
            SlotState.done,
            sync: true,
            at: DateTime(2026, 1, 1, 10, 20),
          ),
        ),
      ),
    );
    expect(
      find.bySemanticsLabel('Concluído às 10:20, aguardando envio'),
      findsOneWidget,
    );
  });

  testWidgets('animateStamp runs when motion is allowed', (t) async {
    await t.pumpWidget(host(StampSlot(slot: doneSlot(), animateStamp: true)));
    await t.pump(const Duration(milliseconds: 100));
    expect(t.hasRunningAnimations, isTrue);
    await t.pumpAndSettle();
    expect(find.text('09:05'), findsOneWidget);
  });

  testWidgets('animateStamp shows the final frame with disableAnimations', (
    t,
  ) async {
    await t.pumpWidget(
      host(
        StampSlot(slot: doneSlot(), animateStamp: true),
        disableAnimations: true,
      ),
    );
    await t.pump(const Duration(milliseconds: 100));
    expect(t.hasRunningAnimations, isFalse);
    expect(find.text('09:05'), findsOneWidget);
  });

  testWidgets('stamp plays once, not on later dependency changes', (t) async {
    var haptics = 0;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics++;
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final w = StampSlot(slot: doneSlot(), animateStamp: true);
    await t.pumpWidget(host(w));
    await t.pumpAndSettle();
    expect(haptics, 1);
    await t.pumpWidget(host(w, textScale: 1.3));
    await t.pump();
    expect(t.hasRunningAnimations, isFalse);
    expect(haptics, 1);
  });

  testWidgets('animateStamp flipping to true animates', (t) async {
    await t.pumpWidget(host(StampSlot(slot: doneSlot())));
    await t.pump();
    expect(t.hasRunningAnimations, isFalse);
    await t.pumpWidget(host(StampSlot(slot: doneSlot(), animateStamp: true)));
    await t.pump(const Duration(milliseconds: 50));
    expect(t.hasRunningAnimations, isTrue);
    await t.pumpAndSettle();
  });
}
