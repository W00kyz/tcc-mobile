import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/monitoring/collection_banner.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';

import '../support/fake_route_repository.dart';

void main() {
  Future<void> pump(WidgetTester tester, RouteSummary? route) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          myDayProvider.overrideWith((ref) async => myDayWith(route)),
        ],
        child: const MaterialApp(
          home: Scaffold(body: CollectionBanner()),
        ),
      ),
    );
  }

  testWidgets('shows the notice while a route is IN_PROGRESS', (tester) async {
    await pump(tester, routeWith(stops: const []));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.collectionBannerText), findsOneWidget);
  });

  testWidgets('renders nothing while the route is PAUSED', (tester) async {
    await pump(tester, routeWith(status: 'PAUSED', stops: const []));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.collectionBannerText), findsNothing);
  });

  testWidgets('renders nothing before the first batch', (tester) async {
    await pump(tester, null);
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.collectionBannerText), findsNothing);
  });
}
