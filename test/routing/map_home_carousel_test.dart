import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/route_repository.dart';

import '../support/fake_route_repository.dart';
import 'map_home_harness.dart';

// The sheet's batch cards in a carousel (product owner, 2026-10-28): it
// opens on the current batch, a slot opens its stop's sheet, and a pin tap
// brings the current card back. The swipe's snap itself is covered in
// test/ui/batch_card_carousel_test.dart.

void main() {
  group('the batch card carousel', () {
    /// Batch 1 done in "Central de Aulas", batch 2 (current) in "Bloco B".
    RouteSummary twoBatches() => routeWith(
      currentBatch: 2,
      stops: [
        stopIn(id: 's1', buildingName: 'Central de Aulas', status: 'DONE'),
        stopIn(
          id: 's2',
          orderIndex: 2,
          batchNumber: 2,
          buildingId: 'b2',
          buildingName: 'Bloco B',
          floorLabel: '2º andar',
          servicePointName: 'Sala 202',
          latitude: -7.214,
          longitude: -35.906,
        ),
      ],
    );

    testWidgets('opens on the current batch, with a dot per batch', (
      tester,
    ) async {
      await pumpHome(tester, homeWith(repositoryWith(twoBatches())));

      expect(carouselPage(tester), 1);
      expect(shownCard(tester).card.batchNumber, 2);
      expect(find.byKey(const ValueKey('carousel-dot-1')), findsOneWidget);
    });

    testWidgets("tapping a slot opens that stop's sheet with its actions", (
      tester,
    ) async {
      await pumpHome(tester, homeWith(repositoryWith(twoBatches())));
      expect(find.text('Sala 202'), findsNothing);

      await openStopSheet(tester, 's2');

      expect(
        find.descendant(
          of: stopSheet(),
          matching: find.text(AppStrings.buildingFloor('Bloco B', '2º andar')),
        ),
        findsOneWidget,
      );
      expect(find.text('Sala 202'), findsOneWidget);
      expect(
        find.descendant(
          of: stopSheet(),
          matching: find.text(AppStrings.routeSignalImpossibilityButton),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a pin tap animates back to the current batch', (
      tester,
    ) async {
      await pumpHome(tester, homeWith(repositoryWith(twoBatches())));
      await tester.fling(
        find.byKey(const ValueKey('batch-card-carousel')),
        const Offset(300, 0),
        1500,
      );
      await tester.pumpAndSettle();
      expect(carouselPage(tester), 0);

      await tester.tap(pinCircle('b2'));
      await tester.pumpAndSettle();

      expect(carouselPage(tester), 1);
      expect(shownCard(tester).highlightBuildingId, 'b2');
    });
  });
}
