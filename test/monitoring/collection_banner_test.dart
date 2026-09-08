import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/monitoring/collection_banner.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';

void main() {
  Future<void> pump(WidgetTester tester, List<RouteSummary> routes) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [myRoutesProvider.overrideWith((ref) async => routes)],
        child: const MaterialApp(
          home: Scaffold(body: CollectionBanner()),
        ),
      ),
    );
  }

  testWidgets('shows the notice while a route is IN_PROGRESS', (tester) async {
    await pump(tester, [_route('r1', 'IN_PROGRESS')]);
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.collectionBannerText), findsOneWidget);
  });

  testWidgets('renders nothing when no route is IN_PROGRESS', (tester) async {
    await pump(tester, [_route('r1', 'PLANNED')]);
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.collectionBannerText), findsNothing);
  });
}

RouteSummary _route(String id, String status) => RouteSummary(
  id: id,
  fieldWorkerName: 'Ana',
  routeDate: DateTime.utc(2026, 9, 7),
  routeType: 'DAILY',
  status: status,
  startedAt: null,
  stops: const [],
);
