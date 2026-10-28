// Consecutive `times.add(...)` calls are separated by real awaits and a
// cascade would obscure that ordering; the fake's optional failure config is
// genuinely nullable (unset in the happy-path test).
// ignore_for_file: cascade_invocations
// ignore_for_file: use_late_for_private_fields_and_variables

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:route_monitor/appeals/appeal_api.dart';
import 'package:route_monitor/appeals/appeal_form_screen.dart';
import 'package:route_monitor/appeals/appeal_providers.dart';
import 'package:route_monitor/appeals/appeals_screen.dart';
import 'package:route_monitor/appeals/day_time.dart';
import 'package:route_monitor/appeals/released_stop_entry.dart';
import 'package:route_monitor/execution/evidence_api.dart';
import 'package:route_monitor/execution/evidence_capture.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/execution/execution_repository.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/released_stop_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/map_home_screen.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/sync/connectivity.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/sync/sync_status.dart';
import 'package:route_monitor/sync/sync_triggers.dart';
import 'package:route_monitor/sync/sync_worker.dart';
import 'package:route_monitor/ui/app_theme.dart';

import '../appeals/fake_appeal_api.dart';
import '../routing/no_tiles_tile_provider.dart';
import '../support/in_memory_database.dart';

/// DELIVERABLE PROOF for Etapa 6 (RF35): a whole batch is executed with the
/// device offline and synced later with the ORIGINAL device timestamps
/// preserved — and only then is the next batch asked for (spec
/// 2026-10-20-alocacao-automatica §6.4: "Iniciar rota" itself is online, so
/// the route is already IN_PROGRESS when the worker walks into the basement).
/// Spec Ruling 11 + §7 open point 4 — this integration test wires the REAL
/// worker + outbox + repository + UI on an in-memory database and
/// fakes only the outermost seams (Connectivity, the two APIs, the route
/// repository, GPS). The true end-to-end (a real camera in a real basement)
/// is the manual field step.
///
/// This is a widget-level integration test that runs headless in the Flutter
/// test VM (`flutter test test/integration/offline_route_test.dart`), NOT via
/// `flutter drive`, so it needs no device or emulator. It lives under `test/`
/// (not `integration_test/`) on purpose: `flutter test` special-cases the
/// `integration_test/` directory and forces on-device mode for anything in it,
/// which would make this deliverable unrunnable in CI without an emulator.
/// The reconnect panel in the sheet — not the snackbar that says the same.
Finder _nextBatchOfflinePanel() => find.descendant(
  of: find.byType(DraggableScrollableSheet),
  matching: find.text(AppStrings.routeNextBatchOffline),
);

void main() {
  // The scenario drives the REAL SyncWorker + real Drift outbox, whose futures
  // ride the real event loop and real timers. `flutter_test`'s default
  // (fake-async) binding freezes those the moment a Drift-reading widget is
  // mounted; the Live binding runs everything on the real clock, so plain
  // `await` + `tester.pump()` is all that is needed here — no `runAsync`.
  LiveTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a full batch runs offline, syncs later with the original timestamps, '
    'and only then pulls the next batch',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      // ---- Offline phase: 5 actions, nothing may hit the network ----------
      final actionTimes = await fixture.runFullBatchOffline();

      // Nothing reached the "network".
      expect(fixture.executionApi.calls, isEmpty);
      expect(fixture.evidenceApi.calls, isEmpty);

      // 5 outbox rows, all pending.
      final offlineRows = await fixture.store.unsyncedForRoute(_routeId);
      expect(offlineRows, hasLength(5));
      expect(
        offlineRows.map((r) => r.state),
        everyElement(PendingOpState.pending),
      );

      // Both stops are done locally (checked out on device — spec Ruling 3/5).
      expect(
        (await fixture.stopProgress.progressFor(_stop1))?.status,
        StopLocalStatus.done,
      );
      expect(
        (await fixture.stopProgress.progressFor(_stop2))?.status,
        StopLocalStatus.done,
      );

      // Mount the screen; its real sync slot subscribes to the real worker
      // status stream and reports the 5 waiting actions (plural). The batch
      // is finished on the device, so the next one waits for the network.
      await fixture.container.read(myDayProvider.future); // warm: no spinner
      await _pumpApp(tester, fixture);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byTooltip(AppStrings.routePendingSync(5)), findsOneWidget);
      expect(_nextBatchOfflinePanel(), findsOneWidget);
      expect(fixture.routeApi.nextBatchCalls, 0);

      // ---- Timestamp-preservation proof (the RF35 crux) -------------------
      // A real gap: a (wrongly) sync-stamped timestamp would land after
      // `syncStartedAt`; the action-time timestamps in the outbox land before.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final syncStartedAt = _nowUtc();

      // ---- Sync phase: connectivity regained ----------------------------
      // `goOnline` fires SyncTriggers -> syncAll; the explicit await makes the
      // drain deterministic before the assertions.
      fixture.connectivity.goOnline();
      await fixture.worker.syncAll();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // FIFO order, exactly the 5 actions oldest-first — and the next batch
      // only after the server has every one of them.
      expect(fixture.callLog, [
        'checkIn:$_stop1',
        'uploadPhoto',
        'checkOut:$_stop1',
        'checkIn:$_stop2',
        'checkOut:$_stop2',
        'nextBatch',
      ]);

      // Each dispatched call carried the timestamp captured BEFORE that
      // action — never the sync time. Recorded in FIFO/dispatch order:
      // checkIn(s1), uploadPhoto, checkOut(s1), checkIn(s2), checkOut(s2).
      final recorded = <DateTime>[
        fixture.executionApi.scannedAtArgs[0],
        fixture.evidenceApi.capturedAtArgs.single,
        fixture.executionApi.scannedAtArgs[1],
        fixture.executionApi.scannedAtArgs[2],
        fixture.executionApi.scannedAtArgs[3],
      ];
      for (var i = 0; i < 5; i++) {
        expect(
          recorded[i].isBefore(actionTimes[i]),
          isFalse,
          reason: 'call $i timestamp predates its own action',
        );
        expect(
          recorded[i].isBefore(actionTimes[i].add(const Duration(seconds: 2))),
          isTrue,
          reason: 'call $i timestamp is far past its action (sync time?)',
        );
        expect(
          recorded[i].isBefore(syncStartedAt),
          isTrue,
          reason:
              'call $i timestamp is not before the sync — stamped at sync '
              'time, not action time',
        );
        if (i > 0) {
          expect(
            recorded[i].isBefore(recorded[i - 1]),
            isFalse,
            reason: 'timestamps are not monotonically non-decreasing',
          );
        }
      }

      // All 5 rows are now `synced` (state, not deleted — spec Ruling 3).
      final syncedStates = await fixture.rawStates();
      expect(syncedStates, hasLength(5));
      expect(syncedStates, everyElement('synced'));
      expect(await fixture.store.unsyncedForRoute(_routeId), isEmpty);

      // The second batch is on screen and the slot flips to all-clear.
      expect(find.text(AppStrings.dayProgress(2, 2, 3)), findsOneWidget);
      expect(find.text('Sala 201'), findsOneWidget);
      expect(_nextBatchOfflinePanel(), findsNothing);
      expect(find.byTooltip(AppStrings.routeAllSynced), findsOneWidget);

      // ---- Idempotent re-drain -----------------------------------------
      await fixture.worker.syncAll();
      await tester.pump(const Duration(milliseconds: 100));
      expect(fixture.callLog, hasLength(6)); // no new calls
    },
  );

  testWidgets(
    'a hard 422 on the stop-2 check-in blocks that row and holds back its own '
    'check-out; the next-batch ask gets the same batch back',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      // The 2nd checkIn dispatch (stop 2) fails hard.
      fixture.executionApi.failCheckInOnCallWith(2, _dio(status: 422));

      await fixture.runFullBatchOffline();
      await fixture.container.read(myDayProvider.future);

      await _pumpApp(tester, fixture);
      await tester.pump(const Duration(milliseconds: 100));

      fixture.connectivity.goOnline();
      await fixture.worker.syncAll();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      final byKind = await fixture.statesByKind();
      final blocked = await fixture.store.blockedForRoute(_routeId);
      final stillPending = await fixture.store.unsyncedForRoute(_routeId);

      // stop 1's whole chain synced.
      expect(byKind['checkIn'], containsAll(<String>['synced', 'blocked']));
      expect(byKind['evidencePhoto'], ['synced']);
      // The stop-2 check-in is blocked (hard 422, not retried forever).
      expect(blocked, hasLength(1));
      expect(blocked.single.kind, PendingOpKind.checkIn);
      expect(blocked.single.payload['route_stop_id'], _stop2);
      // The stop-2 check-out never dispatched — FIFO halted behind the block.
      expect(stillPending, hasLength(1));
      expect(stillPending.single.kind, PendingOpKind.checkOut);
      expect(stillPending.single.payload['route_stop_id'], _stop2);
      // The held check-out is no network's to deliver, so the pull still
      // asks — and the server, which never got stop 2, hands back batch 1.
      expect(fixture.callLog, [
        'checkIn:$_stop1',
        'uploadPhoto',
        'checkOut:$_stop1',
        'checkIn:$_stop2', // attempted, threw 422
        'nextBatch',
      ]);
      expect(fixture.routeApi.batchesHandedOut, 0);

      // The sync slot shows the blocked state.
      expect(
        find.byTooltip(AppStrings.routeSyncBlockedBanner),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'REVIEW FOCUS 2: an offline check-out for a stop released while the '
    'worker was underground comes back 409 STOP_RELEASED, and the appeal it '
    'opens pre-filled clears the stop from the device',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      // ---- At the door, online: the stop-1 check-in reaches the server ----
      fixture.connectivity.goOnline();
      final execution1 = await fixture.repo.checkIn(
        routeId: _routeId,
        routeStopId: _stop1,
        qrPayload: _qr,
        latitude: -7.23,
        longitude: -35.88,
      );
      await fixture.worker.syncRoute(_routeId);
      expect(fixture.callLog, ['checkIn:$_stop1']);

      // ---- Underground, offline: a photo and the check-out of stop 1, then
      // the whole of stop 2 ------------------------------------------------
      fixture.connectivity.goOffline();
      await fixture.repo.addPhoto(
        routeId: _routeId,
        executionId: execution1,
        photo: _photo,
      );
      await fixture.repo.checkOut(
        routeId: _routeId,
        routeStopId: _stop1,
        qrPayload: _qr,
        latitude: -7.23,
        longitude: -35.88,
      );
      await fixture.runStop2Offline();

      // ---- Meanwhile the server released stop 1 for location silence -----
      fixture.releaseStop1(executionId: execution1);

      await fixture.container.read(myDayProvider.future);
      await _pumpApp(tester, fixture);
      await tester.pump(const Duration(milliseconds: 100));

      // ---- Back above ground: the late writes sync ------------------------
      fixture.connectivity.goOnline();
      await fixture.worker.syncAll();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      // The photo and the check-out of stop 1 got 409 STOP_RELEASED; stop 2
      // went through and the next batch was asked for regardless.
      expect(fixture.callLog, [
        'checkIn:$_stop1',
        'uploadPhoto',
        'checkOut:$_stop1',
        'checkIn:$_stop2',
        'checkOut:$_stop2',
        'nextBatch',
      ]);
      final parked = await fixture.store.blockedForRoute(_routeId);
      expect(parked.map((row) => row.kind), [
        PendingOpKind.evidencePhoto,
        PendingOpKind.checkOut,
      ]);
      expect(parked.map((row) => row.releasedStopId), everyElement(_stop1));
      // Nothing lost on the device: the parked rows keep their payloads.
      expect(parked.last.payload['scanned_at'], isNotNull);

      final checkInAt = fixture.executionApi.scannedAtArgs.first;
      final notice = (await fixture.releasedStops.noticeFor(_stop1))!;
      expect(notice.releaseReason, 'LOCATION_SILENCE');
      expect(notice.appealable, isTrue);
      expect(
        notice.localCheckInAt!.millisecondsSinceEpoch,
        checkInAt.millisecondsSinceEpoch,
      );
      expect(notice.localCheckOutAt, isNotNull);

      // ---- The snackbar offers the appeal ---------------------------------
      // A sync notice may have been up first: the appeal offer replaces it.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(AppStrings.releasedStopsSnackbar), findsOneWidget);
      await tester.tap(find.text(AppStrings.releasedStopsSnackbarAction));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AppealFormScreen), findsOneWidget);
      expect(find.text(formatDayTime(notice.localCheckInAt!)), findsOneWidget);

      await tester.tap(find.text(AppStrings.appealReasonNoSignal));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(
        find.widgetWithText(FilledButton, AppStrings.appealSubmit),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(AppStrings.appealLocalDataWarning), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, AppStrings.appealWarningConfirm),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));

      final filing = fixture.appealApi.filed.single;
      expect(filing.routeStopId, _stop1);
      expect(filing.reason, 'NO_SIGNAL');
      expect(
        filing.claimedExecutedAt!.millisecondsSinceEpoch,
        checkInAt.millisecondsSinceEpoch,
      );

      // ---- Stop 1 is gone from the device; stop 2's history stays ---------
      expect(await fixture.rowsOfStop(_stop1, execution1), isEmpty);
      expect(await fixture.store.blockedForRoute(_routeId), isEmpty);
      expect(await fixture.store.unsyncedForRoute(_routeId), isEmpty);
      expect(await fixture.rawStates(), ['synced', 'synced']);
      expect(await fixture.stopProgress.progressFor(_stop1), isNull);
      expect(await fixture.releasedStops.noticeFor(_stop1), isNull);

      // Back on the route, nothing left to sync.
      expect(find.byType(AppealFormScreen), findsNothing);
      expect(find.byTooltip(AppStrings.routeAllSynced), findsOneWidget);
    },
  );

  group('a release that closes the route (spec §7.2–§7.4)', () {
    /// A button of the device entry on `/recursos` — not the snackbar's
    /// action of the same name.
    Finder entryButton(String label) => find.descendant(
      of: find.byType(ReleasedStopEntry),
      matching: find.widgetWithText(TextButton, label),
    );

    Future<void> settle(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// Offline at stop 1: check-in and check-out (and, with [photo], a
    /// photo in between). Returns the stop-1 execution id.
    Future<String> workStop1Offline(
      _Fixture fixture, {
      bool photo = false,
    }) async {
      final execution = await fixture.repo.checkIn(
        routeId: _routeId,
        routeStopId: _stop1,
        qrPayload: _qr,
      );
      if (photo) {
        await fixture.repo.addPhoto(
          routeId: _routeId,
          executionId: execution,
          photo: _photo,
        );
      }
      await fixture.repo.checkOut(
        routeId: _routeId,
        routeStopId: _stop1,
        qrPayload: _qr,
      );
      return execution;
    }

    /// Mounts the app on the closed day, brings the network back and syncs.
    Future<void> syncTheClosedDay(WidgetTester tester, _Fixture fixture) async {
      await fixture.container.read(myDayProvider.future);
      await _pumpApp(tester, fixture);
      await settle(tester);
      fixture.connectivity.goOnline();
      await fixture.worker.syncAll();
      await settle(tester);
    }

    Future<void> openAppeals(WidgetTester tester) async {
      // "Recursos" sits in the account avatar's menu.
      await tester.tap(find.byTooltip(AppStrings.accountMenuTooltip));
      await settle(tester);
      await tester.tap(find.text(AppStrings.appealsTooltip));
      await settle(tester);
      expect(find.byType(AppealsScreen), findsOneWidget);
    }

    Future<void> expectStop1GoneAndAllSynced(
      _Fixture fixture,
      String execution,
    ) async {
      expect(await fixture.rowsOfStop(_stop1, execution), isEmpty);
      expect(await fixture.stopProgress.progressFor(_stop1), isNull);
      expect(await fixture.releasedStops.noticeFor(_stop1), isNull);
      final status = await fixture.syncStatus();
      expect(status.state, RouteSyncState.idle);
      expect(status.pending, 0);
      expect(status.blocked, 0);
    }

    testWidgets(
      'silence frees every live stop and pauses the route: the parked '
      'check-in, and the check-out held behind it, are appealed from '
      '/recursos and leave the device',
      (tester) async {
        final fixture = await _Fixture.create();
        addTearDown(fixture.dispose);
        final execution = await workStop1Offline(fixture);
        fixture.releaseEveryLiveStop(
          reason: 'LOCATION_SILENCE',
          appealable: true,
          routeStatus: 'PAUSED',
          stop1Execution: execution,
        );
        fixture.appealApi.eligibleStops = [
          AppealableStop(
            routeStopId: _stop1,
            servicePointName: 'Sala 101',
            buildingName: 'Bloco CAA',
            floorLabel: 'Térreo',
            releaseReason: 'LOCATION_SILENCE',
            deadline: DateTime.utc(2026, 9, 5, 12),
          ),
        ];

        await syncTheClosedDay(tester, fixture);

        // The check-in came back 409 and was parked; its check-out stayed
        // behind it (BlockedScope) and never left the device.
        expect(fixture.callLog, ['checkIn:$_stop1']);
        final parked = await fixture.store.blockedForRoute(_routeId);
        expect(parked.single.kind, PendingOpKind.checkIn);
        expect(parked.single.releasedStopId, _stop1);
        final held = await fixture.store.unsyncedForRoute(_routeId);
        expect(held.single.kind, PendingOpKind.checkOut);
        // A paused day draws no sync slot: the blocked-sync screen is out
        // of reach, so /recursos is the way out.
        expect(find.text(AppStrings.routePausedTitle), findsOneWidget);
        expect(find.byTooltip(AppStrings.routeSyncBlockedBanner), findsNothing);
        // The snackbar offered the appeal too; this test takes the other
        // road, so it is put away (it would sit over the form's button).
        await settle(tester);
        expect(find.text(AppStrings.releasedStopsSnackbar), findsOneWidget);
        final messenger = ScaffoldMessenger.of(
          tester.element(find.byType(MapHomeScreen)),
        );
        // Twice: a sync notice queued behind it would follow.
        for (var i = 0; i < 2; i++) {
          messenger.clearSnackBars();
          await settle(tester);
        }

        await openAppeals(tester);
        expect(find.text(AppStrings.appealsLocalTitle), findsOneWidget);
        await tester.tap(entryButton(AppStrings.releasedStopAppealButton));
        await settle(tester);
        expect(find.byType(AppealFormScreen), findsOneWidget);
        await tester.tap(find.text(AppStrings.appealReasonNoSignal));
        await settle(tester);
        await tester.tap(
          find.widgetWithText(FilledButton, AppStrings.appealSubmit),
        );
        await settle(tester);
        await tester.tap(
          find.widgetWithText(FilledButton, AppStrings.appealWarningConfirm),
        );
        await settle(tester);

        final filing = fixture.appealApi.filed.single;
        expect(filing.routeStopId, _stop1);
        expect(
          filing.claimedExecutedAt!.millisecondsSinceEpoch,
          fixture.executionApi.scannedAtArgs.single.millisecondsSinceEpoch,
        );
        await expectStop1GoneAndAllSynced(fixture, execution);
        // Back on /recursos, the device entry is gone.
        expect(find.byType(AppealFormScreen), findsNothing);
        expect(find.text(AppStrings.appealsLocalTitle), findsNothing);
      },
    );

    testWidgets(
      'the end of the day closes the route and the release can no longer be '
      'appealed: from /recursos the worker discards the parked stop',
      (tester) async {
        final fixture = await _Fixture.create();
        addTearDown(fixture.dispose);
        final execution = await workStop1Offline(fixture, photo: true);
        fixture.releaseEveryLiveStop(
          reason: 'END_OF_DAY',
          appealable: false,
          routeStatus: 'DONE',
          stop1Execution: execution,
        );

        await syncTheClosedDay(tester, fixture);

        expect(fixture.callLog, ['checkIn:$_stop1']);
        expect(
          (await fixture.store.blockedForRoute(_routeId)).single.releasedStopId,
          _stop1,
        );
        // The photo and the check-out are held behind the parked check-in.
        expect(await fixture.store.unsyncedForRoute(_routeId), hasLength(2));
        expect(find.text(AppStrings.dayDoneTitle), findsOneWidget);
        expect(find.text(AppStrings.releasedStopsSnackbar), findsNothing);
        // The device stop alone badges the entry.
        expect(find.widgetWithText(Badge, '1'), findsOneWidget);

        await openAppeals(tester);
        expect(find.text(AppStrings.releasedStopNotAppealable), findsOneWidget);
        expect(
          entryButton(AppStrings.releasedStopAppealButton),
          findsNothing,
        );
        await tester.tap(entryButton(AppStrings.releasedStopDiscardButton));
        await settle(tester);
        await tester.tap(
          find.widgetWithText(
            FilledButton,
            AppStrings.releasedStopDiscardButton,
          ),
        );
        await settle(tester);

        await expectStop1GoneAndAllSynced(fixture, execution);
        expect(find.text(AppStrings.appealsLocalTitle), findsNothing);
        expect(fixture.appealApi.attempts, isEmpty);
      },
    );
  });
}

/// Mounts [fixture]'s app on a tall phone-shaped surface: the themed sheet
/// and the appeal form (its 56dp button) fit without scrolling.
Future<void> _pumpApp(WidgetTester tester, _Fixture fixture) async {
  await tester.binding.setSurfaceSize(const Size(420, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(fixture.app());
}

const _routeId = 'r1';
const _stop1 = 's1';
const _stop2 = 's2';
const _qr = 'v1.floor.1.sig';

DateTime _nowUtc() => DateTime.now().toUtc();

final _photo = CapturedPhoto(
  bytes: Uint8List.fromList(const [1, 2, 3, 4]),
  sha256: 'a' * 64,
);

DioException _dio({required int status}) {
  final options = RequestOptions(path: '/check-ins');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<dynamic>(
      requestOptions: options,
      statusCode: status,
      data: 'FLOOR_NOT_ON_ROUTE',
    ),
  );
}

/// What the server released, as every fake of it sees it: the route shows
/// these stops RELEASED, and every later write on them — the evidence of
/// their executions too — gets 409 STOP_RELEASED.
class _ServerReleases {
  final Map<String, ({String reason, bool appealable})> byStop = {};
  final Map<String, String> stopOfExecution = {};

  /// Releases [stop]; [executionId] is its execution, when the device has
  /// evidence for it.
  void release(
    String stop, {
    required String reason,
    required bool appealable,
    String? executionId,
  }) {
    byStop[stop] = (reason: reason, appealable: appealable);
    if (executionId != null) stopOfExecution[executionId] = stop;
  }

  String? reasonFor(String stop) => byStop[stop]?.reason;

  /// The 409 a write on [stop] gets (backend `stop_released_conflict`), or
  /// null while the stop is live.
  DioException? conflictFor(String? stop) {
    final release = byStop[stop];
    if (stop == null || release == null) return null;
    final options = RequestOptions(path: '/check-outs');
    return DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response<dynamic>(
        requestOptions: options,
        statusCode: 409,
        data: {
          'detail': {
            'code': 'STOP_RELEASED',
            'detail': 'Route stop "$stop" was released back to the pool.',
            'route_stop_id': stop,
            'release_reason': release.reason,
            'appealable': release.appealable,
          },
        },
      ),
    );
  }
}

/// Everything the test drives: a real [ProviderContainer] with a real
/// in-memory database, the real [SyncWorker]/[ExecutionRepository]/stores, and
/// recording fakes for the outermost seams only.
class _Fixture {
  _Fixture(
    this.container,
    this.executionApi,
    this.evidenceApi,
    this.routeApi,
    this.connectivity,
    this.appealApi,
    this.server,
    this.callLog,
  );

  final ProviderContainer container;
  final _RecordingExecutionApi executionApi;
  final _RecordingEvidenceApi evidenceApi;
  final _RecordingRouteRepository routeApi;
  final _FakeConnectivity connectivity;
  final RecordingAppealApi appealApi;
  final _ServerReleases server;
  final List<String> callLog;

  static Future<_Fixture> create() async {
    final callLog = <String>[];
    final server = _ServerReleases();
    final executionApi = _RecordingExecutionApi(callLog, server);
    final evidenceApi = _RecordingEvidenceApi(callLog, server);
    final routeApi = _RecordingRouteRepository(callLog, server);
    final connectivity = _FakeConnectivity();
    final appealApi = RecordingAppealApi();
    final db = inMemoryDatabase();

    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        connectivityProvider.overrideWithValue(connectivity),
        executionApiProvider.overrideWithValue(executionApi),
        evidenceApiProvider.overrideWithValue(evidenceApi),
        routeRepositoryProvider.overrideWithValue(routeApi),
        locationServiceProvider.overrideWithValue(_FakeLocationService()),
        apiBaseUrlProvider.overrideWithValue('http://test-base'),
        appealApiProvider.overrideWithValue(appealApi),
      ],
    );
    return _Fixture(
      container,
      executionApi,
      evidenceApi,
      routeApi,
      connectivity,
      appealApi,
      server,
      callLog,
    );
  }

  ExecutionRepository get repo => container.read(executionRepositoryProvider);
  SyncWorker get worker => container.read(syncWorkerProvider);
  LocalWriteStore get store => container.read(localWriteStoreProvider);
  StopProgressStore get stopProgress =>
      container.read(stopProgressStoreProvider);
  ReleasedStopStore get releasedStops =>
      container.read(releasedStopStoreProvider);
  AppDatabase get _db => container.read(appDatabaseProvider);

  /// The map home as the app routes it, `/recursos` included.
  Widget app() {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              MapHomeScreen(mapTileProvider: NoTilesTileProvider()),
        ),
        GoRoute(path: '/recursos', builder: (_, _) => const AppealsScreen()),
      ],
    );
    addTearDown(router.dispose);
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildAppTheme(),
        routerConfig: router,
        builder: (context, child) =>
            SyncTriggers(child: child ?? const SizedBox.shrink()),
      ),
    );
  }

  /// Drives the 5 field actions of the batch through the REAL
  /// [ExecutionRepository] while offline, capturing wall-clock time
  /// immediately before each one. Returns the 5 capture instants in action
  /// order.
  Future<List<DateTime>> runFullBatchOffline() async {
    final times = <DateTime>[];

    times.add(_nowUtc());
    final execution1 = await repo.checkIn(
      routeId: _routeId,
      routeStopId: _stop1,
      qrPayload: _qr,
      latitude: -7.23,
      longitude: -35.88,
    );

    times.add(_nowUtc());
    await repo.addPhoto(
      routeId: _routeId,
      executionId: execution1,
      photo: _photo,
    );

    times.add(_nowUtc());
    await repo.checkOut(
      routeId: _routeId,
      routeStopId: _stop1,
      qrPayload: _qr,
      latitude: -7.23,
      longitude: -35.88,
    );

    times.add(_nowUtc());
    await repo.checkIn(
      routeId: _routeId,
      routeStopId: _stop2,
      qrPayload: _qr,
      latitude: -7.24,
      longitude: -35.89,
    );

    times.add(_nowUtc());
    await repo.checkOut(
      routeId: _routeId,
      routeStopId: _stop2,
      qrPayload: _qr,
      latitude: -7.24,
      longitude: -35.89,
    );

    return times;
  }

  /// Stop 2 checked in and out on the device.
  Future<void> runStop2Offline() async {
    await repo.checkIn(
      routeId: _routeId,
      routeStopId: _stop2,
      qrPayload: _qr,
      latitude: -7.24,
      longitude: -35.89,
    );
    await repo.checkOut(
      routeId: _routeId,
      routeStopId: _stop2,
      qrPayload: _qr,
      latitude: -7.24,
      longitude: -35.89,
    );
  }

  /// The server releases stop 1 alone (LOCATION_SILENCE, appealable), its
  /// route staying IN_PROGRESS.
  void releaseStop1({required String executionId}) => server.release(
    _stop1,
    reason: 'LOCATION_SILENCE',
    appealable: true,
    executionId: executionId,
  );

  /// What the server's release scan actually does (spec §7): every live
  /// stop of the route goes back to the pool and the route becomes
  /// [routeStatus] — PAUSED for silence or leaving campus, DONE at the end
  /// of the day.
  void releaseEveryLiveStop({
    required String reason,
    required bool appealable,
    required String routeStatus,
    String? stop1Execution,
  }) {
    server
      ..release(
        _stop1,
        reason: reason,
        appealable: appealable,
        executionId: stop1Execution,
      )
      ..release(_stop2, reason: reason, appealable: appealable);
    routeApi.routeStatus = routeStatus;
  }

  /// The route's outbox status as the worker reports it to a new listener.
  /// The status after one more (empty) pass: a broadcast stream only
  /// re-reads the outbox for its first listener, and the screen is one.
  Future<RouteSyncStatus> syncStatus() async {
    RouteSyncStatus? last;
    final listening = worker.statusFor(_routeId).listen((s) => last = s);
    await worker.syncRoute(_routeId);
    await Future<void>.delayed(Duration.zero);
    await listening.cancel();
    return last!;
  }

  /// Every outbox row of [stop], its evidence (of [executionId]) included.
  Future<List<String>> rowsOfStop(String stop, String executionId) async {
    final rows = await _db.select(_db.pendingOperations).get();
    return [
      for (final row in rows)
        if (row.payloadJson.contains('"$stop"') ||
            row.payloadJson.contains('"$executionId"'))
          row.id,
    ];
  }

  /// The raw `state` column of every outbox row for the route, FIFO order.
  Future<List<String>> rawStates() async {
    final rows =
        await (_db.select(_db.pendingOperations)
              ..where((r) => r.routeId.equals(_routeId))
              ..orderBy([(r) => OrderingTerm.asc(r.createdAt)]))
            .get();
    return rows.map((r) => r.state).toList();
  }

  Future<Map<String, List<String>>> statesByKind() async {
    final rows = await (_db.select(
      _db.pendingOperations,
    )..where((r) => r.routeId.equals(_routeId))).get();
    final out = <String, List<String>>{};
    for (final r in rows) {
      (out[r.kind] ??= <String>[]).add(r.state);
    }
    return out;
  }

  Future<void> dispose() async {
    // `appDatabaseProvider` is overridden with a value, so its `onDispose`
    // close hook never runs — close the in-memory db here instead, or drift
    // warns about a second AppDatabase on the next test.
    await _db.close();
    container.dispose();
    await connectivity.dispose();
  }
}

class _FakeLocationService implements LocationService {
  @override
  Future<Coordinates> getCurrentPosition({
    required LocationPurpose purpose,
  }) async => const Coordinates(latitude: -7.23, longitude: -35.88);
}

/// Fake [Connectivity] starting offline. `onOnlineChanged` only reports the
/// regained edge, exactly like the real `distinct()` + filter pipeline.
class _FakeConnectivity implements Connectivity {
  bool _online = false;
  final _controller = StreamController<bool>.broadcast();

  @override
  Future<bool> get isOnline async => _online;

  @override
  Stream<bool> get onOnlineChanged => _controller.stream;

  void goOnline() {
    _online = true;
    _controller.add(true);
  }

  /// Emits nothing: `onOnlineChanged` only reports the regained edge.
  void goOffline() => _online = false;

  Future<void> dispose() => _controller.close();
}

/// Records every dispatch and the timestamp arg it received; can be told to
/// throw on the Nth `checkIn` call (hard-error variant).
class _RecordingExecutionApi implements ExecutionApi {
  _RecordingExecutionApi(this._log, this._server);

  final List<String> _log;
  final _ServerReleases _server;
  final List<DateTime> scannedAtArgs = [];
  int _checkInCalls = 0;
  int? _failCheckInOnCall;
  DioException? _failWith;

  void failCheckInOnCallWith(int call, DioException error) {
    _failCheckInOnCall = call;
    _failWith = error;
  }

  @override
  Future<({CheckInResult result, DateTime? serverDate})> checkIn({
    required String executionId,
    required String qrPayload,
    required DateTime scannedAt,
    required String idempotencyKey,
    double? latitude,
    double? longitude,
    String? routeStopId,
    double? clientClockOffsetSeconds,
  }) async {
    _checkInCalls++;
    _log.add('checkIn:$routeStopId');
    scannedAtArgs.add(scannedAt);
    if (_checkInCalls == _failCheckInOnCall) throw _failWith!;
    final conflict = _server.conflictFor(routeStopId);
    if (conflict != null) throw conflict;
    return (
      result: CheckInResult(
        routeStopId: routeStopId!,
        executionId: executionId,
        geoValidation: 'INSIDE',
        flags: const [],
      ),
      serverDate: null,
    );
  }

  @override
  Future<({CheckOutResult result, DateTime? serverDate})> checkOut({
    required String executionId,
    required String qrPayload,
    required DateTime scannedAt,
    required String checkoutIdempotencyKey,
    double? latitude,
    double? longitude,
    String? routeStopId,
    double? clientClockOffsetSeconds,
    String? complaintsSuggestions,
  }) async {
    _log.add('checkOut:$routeStopId');
    scannedAtArgs.add(scannedAt);
    final conflict = _server.conflictFor(routeStopId);
    if (conflict != null) throw conflict;
    return (
      result: CheckOutResult(
        routeStopId: routeStopId!,
        executionId: executionId,
        checkedOutAt: DateTime.utc(2026),
        flags: const [],
      ),
      serverDate: null,
    );
  }

  @override
  Future<void> reportImpediment({
    required String routeId,
    required String? routeStopId,
    required String scope,
    required String reason,
    required DateTime reportedAt,
    String? note,
  }) async => throw UnimplementedError();

  List<String> get calls => _log.where((c) => c.startsWith('check')).toList();
}

class _RecordingEvidenceApi implements EvidenceApi {
  _RecordingEvidenceApi(this._log, this._server);

  final List<String> _log;
  final _ServerReleases _server;
  final List<DateTime> capturedAtArgs = [];

  @override
  Future<DateTime?> uploadPhoto({
    required String executionId,
    required Uint8List bytes,
    required String sha256,
    required DateTime capturedAt,
    required String idempotencyKey,
  }) async {
    _log.add('uploadPhoto');
    capturedAtArgs.add(capturedAt);
    final conflict = _server.conflictFor(
      _server.stopOfExecution[executionId],
    );
    if (conflict != null) throw conflict;
    return null;
  }

  @override
  Future<DateTime?> uploadNote({
    required String executionId,
    required String textBody,
    required DateTime capturedAt,
    required String idempotencyKey,
  }) async {
    _log.add('uploadNote');
    capturedAtArgs.add(capturedAt);
    return null;
  }

  @override
  Future<List<EvidenceItem>> listEvidence(String executionId) async => const [];

  List<String> get calls => _log.where((c) => c.contains('pload')).toList();
}

/// The server side of the day: batch 1 (stops 1 and 2) until it has both
/// check-outs and the next batch is asked for, batch 2 (one new stop) from
/// then on. Asked earlier, it hands batch 1 back unchanged, like B3.
class _RecordingRouteRepository implements RouteRepository {
  _RecordingRouteRepository(this._log, this._server);

  final List<String> _log;
  final _ServerReleases _server;
  int nextBatchCalls = 0;
  int batchesHandedOut = 0;

  /// PAUSED or DONE once a release scan closed the route.
  String routeStatus = 'IN_PROGRESS';

  String _statusOf(String stop) => _server.byStop.containsKey(stop)
      ? 'RELEASED'
      : batchesHandedOut == 0
      ? 'PENDING'
      : 'DONE';

  RouteSummary _route() => RouteSummary(
    id: _routeId,
    fieldWorkerName: 'João',
    routeDate: DateTime(2026, 9, 3),
    status: routeStatus,
    startedAt: DateTime.utc(2026, 9, 3, 8),
    currentBatch: batchesHandedOut == 0 ? 1 : 2,
    stops: [
      RouteStopSummary(
        buildingId: 'b1',
        buildingName: 'Prédio',
        floorLabel: 'Térreo',
        id: _stop1,
        orderIndex: 1,
        batchNumber: 1,
        status: _statusOf(_stop1),
        releaseReason: _server.reasonFor(_stop1),
        servicePointName: 'Sala 101',
        latitude: -7.23,
        longitude: -35.88,
      ),
      RouteStopSummary(
        buildingId: 'b1',
        buildingName: 'Prédio',
        floorLabel: 'Térreo',
        id: _stop2,
        orderIndex: 2,
        batchNumber: 1,
        status: _statusOf(_stop2),
        releaseReason: _server.reasonFor(_stop2),
        servicePointName: 'Sala 102',
        latitude: -7.24,
        longitude: -35.89,
      ),
      if (batchesHandedOut > 0)
        const RouteStopSummary(
          buildingId: 'b1',
          buildingName: 'Prédio',
          floorLabel: 'Térreo',
          id: 's3',
          orderIndex: 3,
          batchNumber: 2,
          status: 'PENDING',
          servicePointName: 'Sala 201',
          latitude: -7.25,
          longitude: -35.9,
        ),
    ],
  );

  @override
  Future<MyDay> fetchMyDay() async => MyDay(
    serviceDay: true,
    route: _route(),
    positionIntervalSeconds: 60,
    silenceWarningMinutes: 30,
    silenceReleaseMinutes: 45,
  );

  @override
  Future<AllocationResult> startOrResume({
    required double lat,
    required double lng,
    required DateTime capturedAt,
  }) async => throw UnimplementedError('the route is already started');

  @override
  Future<AllocationResult> nextBatch(
    String routeId, {
    required double lat,
    required double lng,
    required DateTime capturedAt,
  }) async {
    _log.add('nextBatch');
    nextBatchCalls++;
    bool closed(String stop) =>
        _server.byStop.containsKey(stop) || _log.contains('checkOut:$stop');
    final batchDone = closed(_stop1) && closed(_stop2);
    if (batchDone) batchesHandedOut++;
    return AllocationResult(route: _route(), poolEmpty: false);
  }
}
