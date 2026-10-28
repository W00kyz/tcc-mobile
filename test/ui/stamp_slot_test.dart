import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/ui/app_theme.dart';
import 'package:route_monitor/ui/stamp_painters.dart';
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

  group('drop animation', () {
    double dropScale(WidgetTester t) => t
        .widget<Transform>(find.byKey(const ValueKey('stamp-drop')))
        .transform
        .getMaxScaleOnAxis();

    /// Haptic types the platform channel saw.
    List<String> recordHaptics(WidgetTester t) {
      final seen = <String>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            seen.add(call.arguments as String);
          }
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      return seen;
    }

    testWidgets('the stamp falls from above its size and settles at 1', (
      t,
    ) async {
      await t.pumpWidget(host(StampSlot(slot: doneSlot(), animateStamp: true)));
      await t.pump();
      await t.pump(const Duration(milliseconds: 40));
      expect(dropScale(t), greaterThan(1));
      await t.pump(const Duration(milliseconds: 600));
      expect(dropScale(t), 1);
    });

    testWidgets('disableAnimations draws the final stamp at once', (t) async {
      final haptics = recordHaptics(t);
      await t.pumpWidget(
        host(
          StampSlot(slot: doneSlot(), animateStamp: true),
          disableAnimations: true,
        ),
      );
      expect(dropScale(t), 1);
      await t.pump(const Duration(milliseconds: 700));
      expect(t.hasRunningAnimations, isFalse);
      expect(haptics, isEmpty);
    });

    testWidgets('a medium haptic lands with the impact, not before', (t) async {
      final haptics = recordHaptics(t);
      await t.pumpWidget(host(StampSlot(slot: doneSlot(), animateStamp: true)));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(haptics, isEmpty);
      await t.pump(const Duration(milliseconds: 600));
      expect(haptics, ['HapticFeedbackType.mediumImpact']);
    });

    testWidgets('animateImpeded drops the brick stamp', (t) async {
      await t.pumpWidget(
        host(StampSlot(slot: slot(SlotState.impeded), animateImpeded: true)),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 40));
      expect(dropScale(t), greaterThan(1));
      await t.pumpAndSettle();
      expect(dropScale(t), 1);
    });

    testWidgets('the flag alone does not play a face that is no stamp yet', (
      t,
    ) async {
      await t.pumpWidget(
        host(StampSlot(slot: slot(SlotState.inProgress), animateStamp: true)),
      );
      await t.pump();
      expect(t.hasRunningAnimations, isFalse);
      await t.pumpWidget(
        host(StampSlot(slot: slot(SlotState.stamped), animateStamp: true)),
      );
      await t.pump(const Duration(milliseconds: 40));
      expect(t.hasRunningAnimations, isTrue);
      await t.pumpAndSettle();
    });
  });

  group('stamp faces', () {
    StampPainter painterOf(WidgetTester t) => t
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<StampPainter>()
        .single;

    testWidgets('impeded is a brick stamp with a cross, no hour', (t) async {
      await t.pumpWidget(host(StampSlot(slot: slot(SlotState.impeded))));
      final painter = painterOf(t);
      expect(painter.color, FieldPalette.light.brick);
      expect(painter.impossible, isTrue);
      expect(find.byType(Text), findsOneWidget); // only the floor label
      expect(find.bySemanticsLabel('Impossibilitado'), findsOneWidget);
    });

    testWidgets('stamped is a moss stamp with no hour and a cloud badge', (
      t,
    ) async {
      await t.pumpWidget(host(StampSlot(slot: slot(SlotState.stamped))));
      final painter = painterOf(t);
      expect(painter.color, FieldPalette.light.moss);
      expect(painter.impossible, isFalse);
      expect(find.byType(Text), findsOneWidget);
      expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
      expect(
        find.bySemanticsLabel('Carimbado, aguardando a saída do andar'),
        findsOneWidget,
      );
    });

    testWidgets('done keeps moss and its hour', (t) async {
      await t.pumpWidget(host(StampSlot(slot: doneSlot())));
      expect(painterOf(t).color, FieldPalette.light.moss);
      expect(find.byIcon(Icons.cloud_upload_outlined), findsNothing);
    });
  });
}
