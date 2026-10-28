import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/ui/app_theme.dart';
import 'package:route_monitor/ui/map_sheet.dart';

Widget _harness({
  DraggableScrollableController? controller,
  Widget? footer = const SizedBox(
    height: 56,
    child: Center(child: Text('rodape')),
  ),
}) => MaterialApp(
  theme: buildAppTheme(),
  home: Scaffold(
    body: Stack(
      children: [
        MapSheet(
          controller: controller,
          header: const Text('cabecalho'),
          body: Column(
            children: [
              for (var i = 0; i < 40; i++)
                SizedBox(height: 40, child: Text('linha $i')),
            ],
          ),
          stickyFooter: footer,
        ),
      ],
    ),
  ),
);

void main() {
  testWidgets('snaps at 0.22 / 0.5 / 0.9 and starts at 0.5', (tester) async {
    // A typical phone: 390×844.
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_harness());

    final sheet = tester.widget<DraggableScrollableSheet>(
      find.byType(DraggableScrollableSheet),
    );
    expect(sheet.snap, isTrue);
    expect(sheet.snapSizes, const [0.22, 0.5, 0.9]);
    expect(sheet.initialChildSize, 0.5);
    expect(sheet.minChildSize, 0.22);
    expect(sheet.maxChildSize, 0.9);
  });

  testWidgets('the footer stays on screen at every snap', (tester) async {
    final controller = DraggableScrollableController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_harness(controller: controller));

    for (final size in [0.22, 0.5, 0.9]) {
      controller.jumpTo(size);
      await tester.pumpAndSettle();
      expect(find.text('rodape').hitTestable(), findsOneWidget);
      expect(find.text('cabecalho').hitTestable(), findsOneWidget);
    }
  });

  testWidgets('the body scrolls under a fixed footer', (tester) async {
    await tester.pumpWidget(_harness());
    final footerTop = tester.getTopLeft(find.text('rodape')).dy;

    await tester.drag(find.text('linha 3'), const Offset(0, -2000));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('rodape')).dy, footerTop);
  });

  testWidgets('dragging the handle moves the sheet', (tester) async {
    final controller = DraggableScrollableController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_harness(controller: controller));

    await tester.drag(
      find.byKey(const ValueKey('map-sheet-handle')),
      const Offset(0, -250),
    );
    await tester.pumpAndSettle();

    expect(controller.size, 0.9);
  });

  testWidgets('without a footer, nothing is reserved', (tester) async {
    await tester.pumpWidget(_harness(footer: null));

    expect(find.text('rodape'), findsNothing);
    expect(find.text('cabecalho'), findsOneWidget);
  });

  group('mapSheetSnaps', () {
    test('a regular phone closes at 0.22', () {
      expect(mapSheetSnaps(844, bottomInset: 24, hasFooter: true), const [
        0.22,
        0.5,
        0.9,
      ]);
    });

    test('a small phone with a gesture bar closes high enough for the next '
        'stop and the button', () {
      final snaps = mapSheetSnaps(640, bottomInset: 48, hasFooter: true);

      // handle 24 + next stop 56 + button 64 + inset 48 = 192 px.
      expect(snaps.first * 640, closeTo(192, 0.001));
      expect(snaps.sublist(1), const [0.5, 0.9]);
    });

    test('the closed height never reaches the half one', () {
      expect(
        mapSheetSnaps(200, bottomInset: 48, hasFooter: true).first,
        lessThan(0.5),
      );
    });
  });
}
