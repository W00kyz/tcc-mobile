import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/ui/app_theme.dart';
import 'package:route_monitor/ui/batch_card.dart';
import 'package:route_monitor/ui/batch_card_carousel.dart';
import 'package:route_monitor/ui/stamp_slot.dart';

const double _width = 400;

CardSlot _slot(String id, SlotState state) => CardSlot(
  stopId: id,
  state: state,
  floorLabel: 'Térreo',
  stampedAt: state == SlotState.done ? DateTime(2026, 1, 1, 8) : null,
  pendingSync: false,
  releaseReason: null,
  stampRotationDeg: 0,
);

/// Batch [n], one building with [slots] stops (all done but the current
/// batch's).
BatchCard _card(int n, {int slots = 2, bool done = true}) => BatchCard(
  batchNumber: n,
  groups: [
    BuildingGroup(
      buildingId: 'b$n',
      buildingName: 'Prédio $n',
      slots: [
        for (var i = 0; i < slots; i++)
          _slot('s$n-$i', done ? SlotState.done : SlotState.pending),
      ],
      position: const LatLng(0, 0),
    ),
  ],
);

/// Three batches, the third the current one.
List<BatchCard> _threeBatches() => [
  _card(1),
  _card(2),
  _card(3, done: false),
];

Future<void> _pump(
  WidgetTester tester, {
  required List<BatchCard> cards,
  int currentBatch = 3,
  String? highlightBuildingId,
  ValueChanged<CardSlot>? onSlotTap,
}) async {
  tester.view
    ..physicalSize = const Size(_width, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: BatchCardCarousel(
            cards: cards,
            currentBatch: currentBatch,
            highlightBuildingId: highlightBuildingId,
            onSlotTap: onSlotTap,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _pager() => find.byKey(const ValueKey('batch-card-carousel'));

double _page(WidgetTester tester) =>
    tester.widget<PageView>(_pager()).controller!.page!;

Finder _dots() => find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith('carousel-dot-'),
);

void main() {
  testWidgets('opens on the current batch', (tester) async {
    await _pump(tester, cards: _threeBatches());

    expect(_page(tester), 2);
  });

  testWidgets('a short drag that crosses no threshold snaps back', (
    tester,
  ) async {
    await _pump(tester, cards: _threeBatches());

    // A slow drag, a quarter of the page: no fling, under half.
    await tester.timedDrag(
      _pager(),
      const Offset(_width * 0.25, 0),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();

    expect(_page(tester), 2);
  });

  testWidgets('a drag past half the page settles centred on the next card', (
    tester,
  ) async {
    await _pump(tester, cards: _threeBatches());

    await tester.timedDrag(
      _pager(),
      const Offset(_width * 0.6, 0),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();

    expect(_page(tester), 1);
  });

  testWidgets('a fling settles centred on the next card', (tester) async {
    await _pump(tester, cards: _threeBatches());

    await tester.fling(_pager(), const Offset(_width * 0.2, 0), 1500);
    await tester.pumpAndSettle();

    final page = _page(tester);
    expect(page, 1);
    expect(page, page.roundToDouble());
  });

  testWidgets('the dots show only with two or more batches, all circles', (
    tester,
  ) async {
    await _pump(tester, cards: [_card(1, done: false)], currentBatch: 1);
    expect(_dots(), findsNothing);

    await _pump(tester, cards: _threeBatches());
    expect(_dots(), findsNWidgets(3));
    for (final dot in tester.widgetList<Container>(_dots())) {
      expect((dot.decoration! as BoxDecoration).shape, BoxShape.circle);
    }
  });

  testWidgets('the pager is as tall as the tallest card', (tester) async {
    await _pump(
      tester,
      cards: [_card(1, slots: 12), _card(2, slots: 1, done: false)],
      currentBatch: 2,
    );

    final pager = tester.getSize(_pager()).height;
    final shown = tester.getSize(find.byType(BatchCardView).last).height;
    // The short card fills the pager the tall one sized: no overflow, no
    // jump when swiping between them.
    expect(pager, shown);
    expect(pager, greaterThan(200));
  });

  testWidgets('a slot tap reports that slot, on a 48dp target', (
    tester,
  ) async {
    CardSlot? tapped;
    await _pump(
      tester,
      cards: _threeBatches(),
      onSlotTap: (slot) => tapped = slot,
    );
    final slot = find.byWidgetPredicate(
      (widget) => widget is StampSlot && widget.slot.stopId == 's3-1',
    );

    await tester.tap(slot);

    expect(tapped?.stopId, 's3-1');
    final size = tester.getSize(slot);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    // The slot's own label node, unchanged, now a button with a tap.
    final label = find.descendant(
      of: slot,
      matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label != null,
      ),
    );
    expect(
      tester.getSemantics(label),
      isSemantics(
        label: AppStrings.slotPending,
        isButton: true,
        hasTapAction: true,
      ),
    );
  });

  testWidgets('a building highlighted brings the current batch back', (
    tester,
  ) async {
    await _pump(tester, cards: _threeBatches());
    await tester.fling(_pager(), const Offset(_width * 0.2, 0), 1500);
    await tester.pumpAndSettle();
    expect(_page(tester), 1);

    await _pump(tester, cards: _threeBatches(), highlightBuildingId: 'b3');

    expect(_page(tester), 2);
  });
}
