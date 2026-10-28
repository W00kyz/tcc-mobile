import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/ui/snackbar_lane.dart';

/// A bare home with an attached sheet; returns its lane and context.
Future<(SnackbarLane, BuildContext, DraggableScrollableController)> _pumpLane(
  WidgetTester tester,
) async {
  final sheet = DraggableScrollableController();
  addTearDown(sheet.dispose);
  late BuildContext home;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            home = context;
            return DraggableScrollableSheet(
              controller: sheet,
              minChildSize: 0.22,
              maxChildSize: 0.9,
              builder: (_, scroll) => ListView(controller: scroll),
            );
          },
        ),
      ),
    ),
  );
  return (SnackbarLane(contextOf: () => home, sheet: sheet), home, sheet);
}

/// Pumps [steps] × 200 ms, recording which of [texts] were on screen.
Future<Set<String>> _watch(
  WidgetTester tester,
  List<String> texts, {
  int steps = 10,
}) async {
  final seen = <String>{};
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    for (final text in texts) {
      if (find.text(text).evaluate().isNotEmpty) seen.add(text);
    }
  }
  return seen;
}

void main() {
  testWidgets('a superseded notice queued behind another never shows', (
    tester,
  ) async {
    final (lane, home, _) = await _pumpLane(tester);

    lane.show(SnackKind.appeal, 'offer');
    await tester.pump();
    lane
      ..show(SnackKind.sync, 'A')
      ..show(SnackKind.sync, 'B');
    expect(await _watch(tester, ['offer', 'A', 'B'], steps: 6), {'offer'});

    ScaffoldMessenger.of(home).clearSnackBars();
    final after = await _watch(tester, ['offer', 'A', 'B']);
    expect(after, contains('B'));
    expect(after, isNot(contains('A')));
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });

  testWidgets('replacing a notice queued behind a foreign snackbar does not '
      'close the foreign one (final review I-2)', (tester) async {
    final (lane, home, _) = await _pumpLane(tester);
    ScaffoldMessenger.of(
      home,
    ).showSnackBar(const SnackBar(content: Text('foreign')));
    await tester.pump();

    lane.show(SnackKind.sync, 'A');
    await tester.pump();
    lane.show(SnackKind.sync, 'B');
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.text('foreign'), findsOneWidget);

    final seen = await _watch(tester, ['foreign', 'A', 'B'], steps: 60);
    expect(seen, containsAll(['foreign', 'B']));
    expect(find.text('A'), findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });

  testWidgets('action notices are never replaced: each waits its turn', (
    tester,
  ) async {
    final (lane, _, _) = await _pumpLane(tester);

    lane
      ..show(SnackKind.action, 'one')
      ..show(SnackKind.action, 'two');
    // Two seconds in, "one" is still up: "two" did not cut it short.
    expect(await _watch(tester, ['one', 'two']), {'one'});
    expect(find.text('one'), findsOneWidget);

    expect(await _watch(tester, ['one', 'two'], steps: 50), contains('two'));
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });

  testWidgets('at the open snap the margin stops at the half line (M-1)', (
    tester,
  ) async {
    final (_, home, sheet) = await _pumpLane(tester);
    final height = MediaQuery.sizeOf(home).height;

    sheet.jumpTo(0.9);
    await tester.pump();
    expect(sheetSnackBarMargin(home, sheet).bottom, height * 0.5 + 8);

    sheet.jumpTo(0.22);
    await tester.pump();
    expect(
      sheetSnackBarMargin(home, sheet).bottom,
      closeTo(height * 0.22 + 8, 0.01),
    );
  });
}
