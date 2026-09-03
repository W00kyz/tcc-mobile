import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;

import 'package:route_monitor/api/api_client.dart';
import 'package:route_monitor/api/env.dart';
import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/execution/evidence_api.dart';
import 'package:route_monitor/execution/evidence_capture.dart';
import 'package:route_monitor/execution/evidence_list.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/execution/execution_repository.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/open_execution_store.dart';

/// The on-device SQLite connection, as a true singleton — never construct a
/// second [AppDatabase] for the same file (Task 16 review). Every provider
/// that needs storage watches this one instead of building its own.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final localWriteStoreProvider = Provider<LocalWriteStore>(
  (ref) => DriftLocalWriteStore(ref.watch(appDatabaseProvider)),
);

/// The Ruling 17 lookup table (spec §6.3b) — see `OpenExecutionStore`'s
/// docstring for why the app tracks this itself instead of asking the
/// backend.
final openExecutionStoreProvider = Provider<OpenExecutionStore>(
  (ref) => DriftOpenExecutionStore(ref.watch(appDatabaseProvider)),
);

final executionApiProvider = Provider<ExecutionApi>((ref) {
  final session = ref.watch(sessionProvider);
  final dio = buildDio(
    baseUrl: apiBaseUrlFromEnvironment(),
    accessToken: session?.accessToken,
  );
  return DioExecutionApi(dio);
});

final evidenceApiProvider = Provider<EvidenceApi>((ref) {
  final session = ref.watch(sessionProvider);
  final dio = buildDio(
    baseUrl: apiBaseUrlFromEnvironment(),
    accessToken: session?.accessToken,
  );
  return DioEvidenceApi(dio);
});

/// Real camera capture in production; RouteScreen's tests override this
/// with a fake `EvidenceCapture` instead of touching the platform camera.
final evidenceCaptureProvider = Provider<EvidenceCapture>(
  (ref) => DeviceEvidenceCapture(),
);

final executionRepositoryProvider = Provider<ExecutionRepository>(
  (ref) => ExecutionRepository(
    ref.watch(executionApiProvider),
    ref.watch(localWriteStoreProvider),
    ref.watch(evidenceApiProvider),
    ref.watch(openExecutionStoreProvider),
  ),
);

/// Null both for a stop with no open execution and for the Ruling 17
/// cold-start gap (a stop that turned `IN_PROGRESS` before `OpenExecutions`
/// existed) — RouteScreen hides the evidence buttons entirely on null,
/// rather than guessing.
final FutureProviderFamily<String?, String> openExecutionForProvider =
    FutureProvider.family<String?, String>(
      (ref, routeStopId) =>
          ref.watch(openExecutionStoreProvider).openExecutionFor(routeStopId),
    );

/// One stop's evidence list — the backend's synced items plus this device's
/// own not-yet-synced rows for the same execution. Keyed by `(routeId,
/// executionId)`; a plain Dart record gives this family provider structural
/// `==`/`hashCode` for free.
final FutureProviderFamily<List<EvidenceListEntry>, (String, String)>
stopEvidenceProvider =
    FutureProvider.family<List<EvidenceListEntry>, (String, String)>((
      ref,
      query,
    ) {
      final (routeId, executionId) = query;
      return loadStopEvidence(
        store: ref.watch(localWriteStoreProvider),
        api: ref.watch(evidenceApiProvider),
        routeId: routeId,
        executionId: executionId,
      );
    });
