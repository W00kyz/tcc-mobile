import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;

import 'package:route_monitor/appeals/appeal_api.dart';
import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/execution/execution_providers.dart'
    show apiBaseUrlProvider, stopProgressForProvider;
import 'package:route_monitor/local/released_stop_store.dart';
import 'package:route_monitor/sync/sync_providers.dart';

/// The worker's appeals API (spec 2026-10-20-alocacao-automatica §7.5).
/// Base URL through [apiBaseUrlProvider] so tests can pin it.
final appealApiProvider = Provider<AppealApi>((ref) {
  final dio = buildUserScopedSessionDio(
    ref,
    baseUrl: ref.watch(apiBaseUrlProvider),
  );
  return DioAppealApi(dio);
});

/// "Pontos liberados que você pode contestar" — also the route screen's
/// badge count. Invalidated when a release is announced, on resume and
/// reconnect, and after an appeal or a discard.
final appealEligibleProvider = FutureProvider<List<AppealableStop>>(
  (ref) => ref.watch(appealApiProvider).eligible(),
);

/// "Meus recursos" with their decisions.
final myAppealsProvider = FutureProvider<List<FiledAppeal>>(
  (ref) => ref.watch(appealApiProvider).mine(),
);

/// The device's notice for one released stop, or null when it has none.
final FutureProviderFamily<ReleasedStopNotice?, String>
releasedStopNoticeProvider = FutureProvider.family<ReleasedStopNotice?, String>(
  (ref, routeStopId) =>
      ref.watch(releasedStopStoreProvider).noticeFor(routeStopId),
);

/// Deletes everything the device holds for the released [routeStopId]
/// ([ReleasedStopStore.discardStop]) and refreshes every view of it: the
/// blocked list, the stop chips, the sync banner, the appeal lists. Run once
/// the appeal is on record, or when the worker gives up on the stop.
///
///     await discardReleasedStop(ref, notice.routeStopId);
Future<void> discardReleasedStop(WidgetRef ref, String routeStopId) async {
  await ref.read(releasedStopStoreProvider).discardStop(routeStopId);
  ref
    ..invalidate(blockedOperationsProvider)
    ..invalidate(stopSyncChipProvider)
    ..invalidate(stopProgressForProvider)
    ..invalidate(releasedStopNoticeProvider(routeStopId))
    // Re-subscribing makes the worker re-emit the route's status: nothing
    // else would tell the banner the parked rows are gone.
    ..invalidate(routeSyncStatusProvider)
    ..invalidate(appealEligibleProvider)
    ..invalidate(myAppealsProvider);
}
