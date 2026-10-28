import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/appeals/appeal_form_screen.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/released_stop_store.dart';
import 'package:route_monitor/routing/blocked_sync_screen.dart';
import 'package:route_monitor/sync/sync_progress.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/sync/sync_status.dart';
import 'package:route_monitor/sync/sync_worker.dart';

/// A minimal in-memory [LocalWriteStore] for the blocked-rows list — only
/// `blockedForRoute` and `resetToPending` are exercised here.
class _FakeLocalWriteStore implements LocalWriteStore {
  @override
  Future<bool> deletePendingPhoto(String operationId) =>
      throw UnimplementedError();

  final Map<String, PendingOperationRow> rows = {};

  void seedBlocked(
    String id, {
    required PendingOpKind kind,
    required Map<String, dynamic> payload,
    required String lastError,
    String routeId = 'r1',
    String? releasedStopId,
  }) {
    rows[id] = PendingOperationRow(
      id: id,
      kind: kind,
      routeId: routeId,
      payload: payload,
      createdAt: rows.length,
      state: PendingOpState.blocked,
      lastError: lastError,
      attempts: 5,
      nextAttemptAt: null,
      releasedStopId: releasedStopId,
    );
  }

  @override
  Future<List<PendingOperationRow>> blockedForRoute(String routeId) async =>
      rows.values
          .where(
            (r) => r.routeId == routeId && r.state == PendingOpState.blocked,
          )
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Future<void> resetToPending(String id) async {
    final row = rows[id]!;
    rows[id] = PendingOperationRow(
      id: row.id,
      kind: row.kind,
      routeId: row.routeId,
      payload: row.payload,
      createdAt: row.createdAt,
      state: PendingOpState.pending,
      lastError: null,
      attempts: 0,
      nextAttemptAt: null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The released stops this device knows; `discardStop` drops the stop's
/// parked rows from [_outbox], like the Drift store's delete.
class _FakeReleasedStopStore implements ReleasedStopStore {
  _FakeReleasedStopStore(this._outbox, this.notices);

  final _FakeLocalWriteStore _outbox;
  final Map<String, ReleasedStopNotice> notices;
  final List<String> discarded = [];

  @override
  Future<ReleasedStopNotice?> noticeFor(String routeStopId) async =>
      notices[routeStopId];

  @override
  Future<void> discardStop(String routeStopId) async {
    discarded.add(routeStopId);
    notices.remove(routeStopId);
    _outbox.rows.removeWhere(
      (_, row) => row.releasedStopId == routeStopId,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ReleasedStopNotice _notice(String stop, {required bool appealable}) =>
    ReleasedStopNotice(
      routeStopId: stop,
      releaseReason: appealable ? 'LOCATION_SILENCE' : 'IMPEDIMENT',
      appealable: appealable,
      localCheckInAt: null,
      localCheckOutAt: null,
      createdAt: DateTime.utc(2026, 10, 21),
    );

/// Records `unblock`/`syncAll` and mirrors the real worker's `unblock` →
/// `resetToPending` so an invalidation actually drops the row from the list.
class _FakeSyncWorker implements SyncWorker {
  _FakeSyncWorker(this._store);

  final _FakeLocalWriteStore _store;
  final List<String> unblocked = [];
  int syncAllCount = 0;

  @override
  Future<void> unblock(String operationId) async {
    unblocked.add(operationId);
    await _store.resetToPending(operationId);
  }

  @override
  Future<void> syncAll() async => syncAllCount++;

  @override
  Future<void> syncRoute(String routeId) async {}

  @override
  Stream<RouteSyncStatus> statusFor(String routeId) => const Stream.empty();

  @override
  Stream<SyncProgress> get progress => const Stream.empty();

  @override
  Future<void> dispose() async {}
}

Widget _screen(
  _FakeLocalWriteStore store,
  _FakeSyncWorker worker, {
  ReleasedStopStore? releasedStops,
}) => ProviderScope(
  overrides: [
    localWriteStoreProvider.overrideWithValue(store),
    syncWorkerProvider.overrideWithValue(worker),
    releasedStopStoreProvider.overrideWithValue(
      releasedStops ?? _FakeReleasedStopStore(store, {}),
    ),
  ],
  child: const MaterialApp(home: BlockedSyncScreen(routeId: 'r1')),
);

void main() {
  testWidgets('lists the blocked rows with their kind label and lastError', (
    tester,
  ) async {
    final store = _FakeLocalWriteStore()
      ..seedBlocked(
        'op-1',
        kind: PendingOpKind.checkIn,
        payload: {'route_stop_id': 's1'},
        lastError: 'HTTP 422 FLOOR_NOT_ON_ROUTE',
      )
      ..seedBlocked(
        'op-2',
        kind: PendingOpKind.evidencePhoto,
        payload: {'execution_id': 'exec-9'},
        lastError: 'HTTP 413 payload too large',
      );
    final worker = _FakeSyncWorker(store);

    await tester.pumpWidget(_screen(store, worker));
    await tester.pumpAndSettle();

    expect(
      find.text(
        AppStrings.blockedSyncRowLabel(AppStrings.blockedSyncKindCheckIn, 's1'),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        AppStrings.blockedSyncRowLabel(
          AppStrings.blockedSyncKindPhoto,
          'exec-9',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('HTTP 422 FLOOR_NOT_ON_ROUTE'), findsOneWidget);
    expect(find.text('HTTP 413 payload too large'), findsOneWidget);
    expect(
      find.widgetWithText(TextButton, AppStrings.blockedSyncRetryButton),
      findsNWidgets(2),
    );
  });

  testWidgets(
    '"Tentar de novo" calls unblock(id), then syncAll, and the row drops off '
    'the refreshed list',
    (tester) async {
      final store = _FakeLocalWriteStore()
        ..seedBlocked(
          'op-1',
          kind: PendingOpKind.checkIn,
          payload: {'route_stop_id': 's1'},
          lastError: 'HTTP 422',
        )
        ..seedBlocked(
          'op-2',
          kind: PendingOpKind.checkOut,
          payload: {'route_stop_id': 's2'},
          lastError: 'HTTP 422',
        );
      final worker = _FakeSyncWorker(store);

      await tester.pumpWidget(_screen(store, worker));
      await tester.pumpAndSettle();

      await tester.tap(
        find
            .widgetWithText(TextButton, AppStrings.blockedSyncRetryButton)
            .first,
      );
      await tester.pumpAndSettle();

      expect(worker.unblocked, ['op-1']);
      expect(worker.syncAllCount, 1);
      expect(
        find.text(
          AppStrings.blockedSyncRowLabel(
            AppStrings.blockedSyncKindCheckIn,
            's1',
          ),
        ),
        findsNothing,
      );
      expect(
        find.text(
          AppStrings.blockedSyncRowLabel(
            AppStrings.blockedSyncKindCheckOut,
            's2',
          ),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('shows the empty message when nothing is blocked', (
    tester,
  ) async {
    final store = _FakeLocalWriteStore();
    final worker = _FakeSyncWorker(store);

    await tester.pumpWidget(_screen(store, worker));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.blockedSyncEmpty), findsOneWidget);
  });

  group('rows parked on a released stop (spec 2026-10-20 §7.5)', () {
    _FakeLocalWriteStore parkedStore() => _FakeLocalWriteStore()
      ..seedBlocked(
        'photo-1',
        kind: PendingOpKind.evidencePhoto,
        payload: {'execution_id': 'exec-1'},
        lastError: 'HTTP 409 STOP_RELEASED',
        releasedStopId: 's1',
      )
      ..seedBlocked(
        'out-1',
        kind: PendingOpKind.checkOut,
        payload: {'route_stop_id': 's1'},
        lastError: 'HTTP 409 STOP_RELEASED',
        releasedStopId: 's1',
      )
      ..seedBlocked(
        'in-2',
        kind: PendingOpKind.checkIn,
        payload: {'route_stop_id': 's2'},
        lastError: 'HTTP 422',
      );

    testWidgets(
      'show once per stop with the release reason, and never offer a retry '
      'that would only replay the same 409',
      (tester) async {
        final store = parkedStore();
        final released = _FakeReleasedStopStore(store, {
          's1': _notice('s1', appealable: true),
        });

        await tester.pumpWidget(
          _screen(store, _FakeSyncWorker(store), releasedStops: released),
        );
        await tester.pumpAndSettle();

        expect(find.text(AppStrings.releasedStopTitle('s1')), findsOne);
        expect(
          find.text(
            AppStrings.releasedStopReason(
              AppStrings.releaseReasonLabel('LOCATION_SILENCE'),
            ),
          ),
          findsOneWidget,
        );
        // Only the unrelated 422 row keeps "Tentar de novo".
        expect(
          find.widgetWithText(TextButton, AppStrings.blockedSyncRetryButton),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(TextButton, AppStrings.releasedStopAppealButton),
          findsOneWidget,
        );
      },
    );

    testWidgets('"Recorrer" opens the appeal form of that stop', (
      tester,
    ) async {
      final store = parkedStore();
      final released = _FakeReleasedStopStore(store, {
        's1': _notice('s1', appealable: true),
      });
      await tester.pumpWidget(
        _screen(store, _FakeSyncWorker(store), releasedStops: released),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(TextButton, AppStrings.releasedStopAppealButton),
      );
      await tester.pumpAndSettle();

      final form = tester.widget<AppealFormScreen>(
        find.byType(AppealFormScreen),
      );
      expect(form.routeStopId, 's1');
      expect(form.releaseReason, 'LOCATION_SILENCE');
    });

    testWidgets(
      'a release the worker caused offers no appeal, only discarding the '
      'local data after a confirmation — the worker is never stuck',
      (tester) async {
        final store = parkedStore();
        final released = _FakeReleasedStopStore(store, {
          's1': _notice('s1', appealable: false),
        });
        await tester.pumpWidget(
          _screen(store, _FakeSyncWorker(store), releasedStops: released),
        );
        await tester.pumpAndSettle();

        expect(
          find.widgetWithText(TextButton, AppStrings.releasedStopAppealButton),
          findsNothing,
        );
        await tester.tap(
          find.widgetWithText(TextButton, AppStrings.releasedStopDiscardButton),
        );
        await tester.pumpAndSettle();
        expect(find.text(AppStrings.releasedStopDiscardBody), findsOneWidget);
        await tester.tap(
          find.widgetWithText(
            FilledButton,
            AppStrings.releasedStopDiscardButton,
          ),
        );
        await tester.pumpAndSettle();

        expect(released.discarded, ['s1']);
        expect(
          find.text(AppStrings.releasedStopTitle('s1')),
          findsNothing,
        );
        expect(
          find.text(
            AppStrings.blockedSyncRowLabel(
              AppStrings.blockedSyncKindCheckIn,
              's2',
            ),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('cancelling the discard keeps everything', (tester) async {
      final store = parkedStore();
      final released = _FakeReleasedStopStore(store, {
        's1': _notice('s1', appealable: true),
      });
      await tester.pumpWidget(
        _screen(store, _FakeSyncWorker(store), releasedStops: released),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(TextButton, AppStrings.releasedStopDiscardButton),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(TextButton, AppStrings.commonCancel),
      );
      await tester.pumpAndSettle();

      expect(released.discarded, isEmpty);
      expect(find.text(AppStrings.releasedStopTitle('s1')), findsOne);
    });
  });
}
