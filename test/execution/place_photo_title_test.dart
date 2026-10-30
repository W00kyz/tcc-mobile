import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/evidence_capture.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/execution/task_photos.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/ui/app_theme.dart';

import '../routing/map_home_harness.dart';
import '../routing/place_fixtures.dart';
import '../support/fake_evidence_camera.dart';
import '../support/fake_route_repository.dart';

// The camera screen of a task names where it is: "Prédio · Andar" for a
// room, the place's name alone for an outdoor place.

Future<void> _openCamera(WidgetTester tester, RouteStopSummary stop) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localWriteStoreProvider.overrideWithValue(InMemoryLocalWriteStore()),
        evidenceCameraProvider.overrideWithValue(FakeEvidenceCamera()),
        capturedFileCompressorProvider.overrideWithValue(
          (path) async => CapturedPhoto(bytes: onePixelPng, sha256: path),
        ),
        evidenceApiProvider.overrideWithValue(FakeEvidenceApi()),
        stopProgressStoreProvider.overrideWithValue(FakeStopProgressStore()),
        syncWorkerProvider.overrideWithValue(RecordingSyncWorker()),
        apiBaseUrlProvider.overrideWithValue('http://test-base'),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: TaskPhotos(
            route: routeWith(stops: [stop]),
            stop: stop,
            executionId: 'exec-1',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip(AppStrings.taskAddPhotos));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a place stop titles the camera with its name alone', (
    tester,
  ) async {
    await _openCamera(tester, placeStopIn(id: 'p1s1'));

    expect(find.text('Praça central'), findsOneWidget);
    expect(find.textContaining('·'), findsNothing);
  });

  testWidgets('a room stop titles the camera "Prédio · Andar"', (
    tester,
  ) async {
    await _openCamera(
      tester,
      stopIn(id: 's1', buildingName: 'CAA', floorLabel: '1'),
    );

    expect(find.text('CAA · Andar 1'), findsOneWidget);
  });
}
