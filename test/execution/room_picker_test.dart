import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/execution/room_picker.dart';

const _far = RoomCandidate(
  routeStopId: 's-far',
  servicePointId: 'sp-far',
  name: 'Sala 202',
  distanceM: 9.5,
);
const _near = RoomCandidate(
  routeStopId: 's-near',
  servicePointId: 'sp-near',
  name: 'Sala 101',
  distanceM: 1.1,
);
const _unknown = RoomCandidate(
  routeStopId: 's-unknown',
  servicePointId: 'sp-unknown',
  name: 'Sala 303',
);

/// Pumps a host screen with a button that opens the picker and stashes
/// whatever it resolves to in [captured] — every test below opens it, drives
/// some interaction, then reads [captured].
Future<void> _openPicker(
  WidgetTester tester,
  List<RoomCandidate> candidates,
  List<RoomCandidate?> captured,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            captured.add(await showRoomPicker(context, candidates));
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'renders candidates nearest-first with the first pre-selected',
    (tester) async {
      await _openPicker(tester, [_far, _near, _unknown], []);

      expect(
        find.text('Vários pontos correspondem — escolha o certo:'),
        findsOneWidget,
      );

      // Nearest-first: "Sala 101" (1.1 m) must render above "Sala 202"
      // (9.5 m) even though it was passed second — the picker re-sorts
      // defensively rather than trusting caller order.
      final nearOffset = tester.getTopLeft(find.text('Sala 101'));
      final farOffset = tester.getTopLeft(find.text('Sala 202'));
      expect(nearOffset.dy, lessThan(farOffset.dy));

      // The nearest candidate is pre-selected: its row shows the "checked"
      // icon, every other row shows "unchecked".
      final nearTile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Sala 101'),
          matching: find.byType(ListTile),
        ),
      );
      expect((nearTile.leading! as Icon).icon, Icons.radio_button_checked);
      final farTile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Sala 202'),
          matching: find.byType(ListTile),
        ),
      );
      expect((farTile.leading! as Icon).icon, Icons.radio_button_off);

      // A candidate with a null distance still renders, with no distance
      // line crashing on a null format.
      expect(find.text('Sala 303'), findsOneWidget);
    },
  );

  testWidgets('confirming without changing selection returns the nearest', (
    tester,
  ) async {
    final captured = <RoomCandidate?>[];
    await _openPicker(tester, [_far, _near], captured);

    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
    await tester.pumpAndSettle();

    expect(captured, [_near]);
  });

  testWidgets('tapping a different row then confirming returns that one', (
    tester,
  ) async {
    final captured = <RoomCandidate?>[];
    await _openPicker(tester, [_far, _near], captured);

    await tester.tap(find.text('Sala 202'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
    await tester.pumpAndSettle();

    expect(captured, [_far]);
  });

  testWidgets('dismissing without choosing returns null', (tester) async {
    final captured = <RoomCandidate?>[];
    await _openPicker(tester, [_far, _near], captured);

    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await tester.pumpAndSettle();

    expect(captured, [null]);
  });
}
