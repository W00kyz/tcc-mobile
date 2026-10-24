import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:route_monitor/execution/evidence_api.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/monitoring/monitoring_providers.dart';
import 'package:route_monitor/monitoring/silence_watchdog.dart';
import 'package:route_monitor/sync/sync_providers.dart';

import '../support/fake_connectivity.dart';
import '../support/in_memory_database.dart';

void main() {
  // The wiring of spec 2026-10-20-alocacao-automatica §7.3: a check-in counts
  // for the silence clock once the sync worker delivers it, at its scan time.
  test(
    'a check-in delivered by syncWorkerProvider quiets the watchdog',
    () async {
      final scannedAt = DateTime.utc(2026, 10, 20, 8, 40);
      var now = scannedAt.subtract(const Duration(minutes: 40));
      final watchdog = SilenceWatchdog(
        clock: () => now,
        scheduler: _NoopScheduler(),
        warningMinutes: 30,
        releaseMinutes: 45,
      )..startWatching();
      final db = inMemoryDatabase();
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          connectivityProvider.overrideWithValue(
            FakeConnectivity(isOnline: true),
          ),
          executionApiProvider.overrideWithValue(_AcceptingExecutionApi()),
          evidenceApiProvider.overrideWithValue(_UnusedEvidenceApi()),
          silenceWatchdogProvider.overrideWithValue(watchdog),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(localWriteStoreProvider)
          .enqueue(
            id: 'k1',
            kind: PendingOpKind.checkIn,
            routeId: 'r1',
            payload: {
              'execution_id': 'e1',
              'qr_payload': 'v1.floor.1.sig',
              'scanned_at': scannedAt.toIso8601String(),
              'idempotency_key': 'k1',
              'route_stop_id': 's1',
            },
          );

      await container.read(syncWorkerProvider).syncRoute('r1');

      now = scannedAt.add(const Duration(minutes: 1));
      expect(watchdog.currentWarning(), isNull);
    },
  );
}

class _AcceptingExecutionApi implements ExecutionApi {
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
  }) async => (
    result: const CheckInResult(
      routeStopId: 's1',
      executionId: 'e1',
      geoValidation: 'INSIDE',
      flags: [],
    ),
    serverDate: null,
  );

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
    String? formVersionId,
    List<Map<String, Object?>>? answers,
  }) => throw UnimplementedError();

  @override
  Future<void> reportImpediment({
    required String routeId,
    required String? routeStopId,
    required String scope,
    required String reason,
    required DateTime reportedAt,
    String? note,
  }) => throw UnimplementedError();
}

/// No evidence row is queued here, so nothing may reach it.
class _UnusedEvidenceApi extends Mock implements EvidenceApi {}

class _NoopScheduler implements LocalScheduler {
  @override
  Future<void> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> cancel(int id) async {}
}
