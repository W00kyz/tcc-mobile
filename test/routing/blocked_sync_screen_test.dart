import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/routing/blocked_sync_screen.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/sync/sync_status.dart';
import 'package:route_monitor/sync/sync_worker.dart';

/// A minimal in-memory [LocalWriteStore] for the blocked-rows list — only
/// `blockedForRoute` and `resetToPending` are exercised here.
class _FakeLocalWriteStore implements LocalWriteStore {
  final Map<String, PendingOperationRow> rows = {};

  void seedBlocked(
    String id, {
    required PendingOpKind kind,
    required Map<String, dynamic> payload,
    required String lastError,
    String routeId = 'r1',
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
  Future<void> dispose() async {}
}

Widget _screen(_FakeLocalWriteStore store, _FakeSyncWorker worker) =>
    ProviderScope(
      overrides: [
        localWriteStoreProvider.overrideWithValue(store),
        syncWorkerProvider.overrideWithValue(worker),
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
}
