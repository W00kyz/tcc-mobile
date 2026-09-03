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
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/sync/sync_providers.dart';

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

/// Wraps `apiBaseUrlFromEnvironment()` for widgets that need the raw base
/// URL rather than a whole `Dio` client — e.g. `route_screen.dart`'s
/// synced-photo thumbnail, which builds a `NetworkImage` URL by hand. Going
/// through a provider (instead of calling the env function directly from
/// build()) lets a test override it with a fixed value, rather than
/// requiring a real `--dart-define=API_BASE_URL=...` under `flutter test`.
final Provider<String> apiBaseUrlProvider = Provider<String>(
  (ref) => apiBaseUrlFromEnvironment(),
);

/// The Ruling 17 lookup table (spec §6.3b) — see `StopProgressStore`'s
/// docstring for why the app tracks this itself instead of asking the
/// backend.
final stopProgressStoreProvider = Provider<StopProgressStore>(
  (ref) => DriftStopProgressStore(ref.watch(appDatabaseProvider)),
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
    ref.watch(localWriteStoreProvider),
    ref.watch(stopProgressStoreProvider),
    ref.watch(syncMetaStoreProvider),
    ref.watch(syncWorkerProvider),
  ),
);

/// True once "Iniciar rota" has been tapped for `routeId` on this device —
/// the optimistic marker RouteScreen reads so the route flips to "iniciada"
/// before the outbox row syncs (spec Ruling 5).
final FutureProviderFamily<bool, String> routeStartedLocallyProvider =
    FutureProvider.family<bool, String>(
      (ref, routeId) async =>
          await ref.watch(syncMetaStoreProvider).getRouteStartedAt(routeId) !=
          null,
    );

/// Null both for an untouched stop and for the Ruling 17 cold-start gap (a
/// stop that turned `IN_PROGRESS` before `StopProgress` existed) — RouteScreen
/// hides the evidence buttons entirely on null, and also on a `done` entry.
final FutureProviderFamily<StopProgressEntry?, String> stopProgressForProvider =
    FutureProvider.family<StopProgressEntry?, String>(
      (ref, routeStopId) =>
          ref.watch(stopProgressStoreProvider).progressFor(routeStopId),
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
