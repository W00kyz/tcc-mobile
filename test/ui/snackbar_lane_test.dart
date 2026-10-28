import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/ui/snackbar_lane.dart';

SnackBuilder _snack(String text) =>
    (margin) => SnackBar(
      content: Text(text),
      margin: margin,
      behavior: SnackBarBehavior.floating,
    );

void main() {
  testWidgets('a superseded notice queued behind another never shows', (
    tester,
  ) async {
    final sheet = DraggableScrollableController();
    late SnackbarLane lane;
    late BuildContext home;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              home = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    lane = SnackbarLane(contextOf: () => home, sheet: sheet);
    final seen = <String>[];
    void record() {
      for (final text in ['offer', 'A', 'B']) {
        if (find.text(text).evaluate().isNotEmpty) seen.add(text);
      }
    }

    lane.show(SnackKind.appeal, _snack('offer'));
    await tester.pump();
    lane
      ..show(SnackKind.sync, _snack('A'))
      ..show(SnackKind.sync, _snack('B'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      record();
    }
    expect(seen.toSet(), {'offer'});

    ScaffoldMessenger.of(home).clearSnackBars();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      record();
    }
    expect(seen.toSet(), {'offer', 'B'});
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });
}
