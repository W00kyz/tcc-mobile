import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/checkin/scan_screen.dart';
import 'package:route_monitor/execution/conclude_sheet.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/execution/impediment_dialog.dart';
import 'package:route_monitor/execution/room_picker.dart';
import 'package:route_monitor/execution/room_resolution.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/stop_progress_store.dart'
    show StopLocalStatus;
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:uuid/uuid.dart';

// The stop flows of the map home, with no widget of their own: check-in,
// check-out, "Sinalizar impossibilidade" and the scan+GPS dance they share.
// Moved unchanged out of the old `route_screen.dart` (redesign §6.13).

const _uuid = Uuid();

/// A completed scan+GPS read, threaded from `_scanAndLocate` into a
/// check-in or check-out attempt.
class _Scan {
  const _Scan(this.rawValue, this.coordinates);
  final String rawValue;
  final Coordinates? coordinates;
}

/// One route-level "Fazer check-in" action, not a per-stop button: the QR
/// scan resolves which stop it belongs to (and can be ambiguous, Task 18).
/// Checks for a `PENDING` stop specifically, not just "not DONE" — an
/// `IN_PROGRESS` stop (already checked in, awaiting checkout, Task 18) has
/// no `PENDING` candidate left on its floor, so scanning again would only
/// get a confusing 422 FLOOR_NOT_ON_ROUTE from the backend. Only the
/// current batch counts: it is the only one shown, on an IN_PROGRESS route.
///
///     if (canCheckIn(route.currentBatchStops)) showScanButton();
bool canCheckIn(List<RouteStopSummary> batchStops) =>
    batchStops.any((stop) => stop.status == 'PENDING');

/// "Escanear QR": scans, resolves the room on the device, enqueues the
/// check-in and confirms it.
///
///     onPressed: () => startCheckIn(context, ref, route)
Future<void> startCheckIn(
  BuildContext context,
  WidgetRef ref,
  RouteSummary route,
) async {
  final scan = await _scanAndLocate(context, ref, _entryContext(route));
  if (scan == null || !context.mounted) return;

  final routeStopId = await _resolveCheckInStop(context, route, scan);
  if (routeStopId == null || !context.mounted) return;

  // The repository only enqueues + writes local state now (spec Ruling 2):
  // it never throws `AmbiguousRoomException` or a network error, so there
  // is nothing to catch here.
  await ref
      .read(executionRepositoryProvider)
      .checkIn(
        routeId: route.id,
        routeStopId: routeStopId,
        qrPayload: scan.rawValue,
        latitude: scan.coordinates?.latitude,
        longitude: scan.coordinates?.longitude,
      );
  ref.invalidate(myDayProvider);
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text(AppStrings.routeCheckInDone)));
  }
}

/// The QR resolves the stop only after the scan, so the entry line names the
/// building of the batch's next pending stop.
ScanContext _entryContext(RouteSummary route) {
  final next = route.currentBatchStops.firstWhere(
    (stop) => stop.status == 'PENDING',
    orElse: () => route.currentBatchStops.first,
  );
  return EntryScan(next.buildingName);
}

/// The stop a check-in scan belongs to, or null when the worker dismissed
/// the room picker.
Future<String?> _resolveCheckInStop(
  BuildContext context,
  RouteSummary route,
  _Scan scan,
) async {
  // Since Etapa 6 the room is resolved on the device, before the enqueue
  // (spec Ruling 4) — the check-in flow is offline-first and there is no
  // server 409 to lean on. `resolveRoomLocally` always lands on a concrete
  // route_stop_id: either it resolves one automatically or the field
  // worker picks from the pending stops (Ruling P8 — nothing is ever
  // enqueued with a null route_stop_id).
  final pendingStops = route.currentBatchStops
      .where((stop) => stop.status == 'PENDING')
      .toList();
  final resolution = resolveRoomLocally(
    pendingStops: pendingStops,
    latitude: scan.coordinates?.latitude,
    longitude: scan.coordinates?.longitude,
  );

  switch (resolution) {
    case ResolvedRoom(routeStopId: final resolved):
      return resolved;
    case AmbiguousRooms(:final candidates):
      final chosen = await showRoomPicker(context, candidates);
      // Dismissed without choosing → the check-in is cancelled, nothing is
      // written (Etapa 5's behaviour).
      return chosen?.routeStopId;
  }
}

/// The stop whose stamp just fell: set only once its check-out row is in
/// the outbox (RNF06 — the stamp is a consequence of the write, never ahead
/// of it). The card animates that one slot; the map home centres on its
/// building.
///
///     ref.watch(lastStampedStopProvider); // 's1' right after s1's check-out
final lastStampedStopProvider = NotifierProvider<LastStamped, String?>(
  LastStamped.new,
);

class LastStamped extends Notifier<String?> {
  @override
  String? build() => null;

  // A method, not a setter: reads as the action it is at the call site.
  // ignore: use_setters_to_change_properties
  void stamp(String routeStopId) => state = routeStopId;

  void clear() => state = null;
}

/// "Concluir" on an `IN_PROGRESS` stop: the conclusion sheet (one optional
/// observation, redesign §6.6), the exit scan, then the enqueued check-out
/// carrying the observation as `complaints_suggestions`.
///
///     onPressed: () => concludeStop(context, ref, route, stop)
Future<void> concludeStop(
  BuildContext context,
  WidgetRef ref,
  RouteSummary route,
  RouteStopSummary stop,
) async {
  // Before the QR, so the worker never scans and only then finds one more
  // step (spec 2026-10-26-exige-evidencias §6.4). Cancelling abandons the
  // check-out: nothing is enqueued.
  final scanExit = await showConcludeSheet(
    context,
    routeId: route.id,
    stop: stop,
    executionId: _openExecutionOf(ref, stop),
  );
  if (!scanExit || !context.mounted) return;
  final scan = await _scanAndLocate(
    context,
    ref,
    ExitScan(stop.buildingName, stop.floorLabel),
  );
  // A cancelled camera writes nothing; the observation stays in its draft
  // for the next "Concluir" (Review Focus 3).
  if (scan == null || !context.mounted) return;

  await _recordCheckOut(ref, route, stop, scan);
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text(AppStrings.routeCheckOutDone)));
  }
}

/// The stop's open execution on this device, if its progress row is read.
String? _openExecutionOf(WidgetRef ref, RouteStopSummary stop) {
  final entry = ref.read(stopProgressForProvider(stop.id)).asData?.value;
  return entry?.status == StopLocalStatus.inProgress
      ? entry?.executionId
      : null;
}

/// Writes the check-out, then — only then — clears the draft, redraws the
/// stop as done and drops its stamp.
Future<void> _recordCheckOut(
  WidgetRef ref,
  RouteSummary route,
  RouteStopSummary stop,
  _Scan scan,
) async {
  final draft = observationDraftProvider(stop.id);
  // Check-out is always per-stop — the UI already knows which IN_PROGRESS
  // stop it is concluding, so there is no room to resolve. The repository
  // only enqueues + writes local state (spec Ruling 2): no
  // `AmbiguousRoomException`, no network error, nothing to catch.
  await ref
      .read(executionRepositoryProvider)
      .checkOut(
        routeId: route.id,
        routeStopId: stop.id,
        qrPayload: scan.rawValue,
        latitude: scan.coordinates?.latitude,
        longitude: scan.coordinates?.longitude,
        checkoutIdempotencyKey: _uuid.v4(),
        complaintsSuggestions: observationToSend(ref.read(draft)),
      );
  ref.read(draft.notifier).clear();
  _showStopDone(ref, stop);
}

/// What follows a written check-out on screen.
void _showStopDone(WidgetRef ref, RouteStopSummary stop) {
  // The local row is DONE now: re-read it so the slot turns into a stamp.
  ref
    ..invalidate(stopProgressForProvider(stop.id))
    ..read(lastStampedStopProvider.notifier).stamp(stop.id)
    // A local check-out flips the stop to DONE now (spec Ruling 5); this
    // invalidate re-reads myDayProvider so the server view catches up too
    // — the "Concluir" button's visibility is status == 'IN_PROGRESS', and
    // the done-stamp rendering in the card takes over. The reload is also
    // what lets the batch controller see a finished batch and pull the next.
    ..invalidate(myDayProvider);
}

/// Opens [ImpedimentDialog] for a `PENDING` or `IN_PROGRESS` stop and, on a
/// non-null result, enqueues it via `ExecutionRepository.reportImpediment`
/// (spec RF16-RF17, alocação automática §7.1). Same shape as [concludeStop]:
/// read the repo, call it, then a confirmation snackbar; the dialog stays
/// ref-free (pure input collection).
///
///     onPressed: () => signalImpossibility(context, ref, route, stop)
Future<void> signalImpossibility(
  BuildContext context,
  WidgetRef ref,
  RouteSummary route,
  RouteStopSummary stop,
) async {
  final choice = await showImpedimentSheet(context);
  if (choice == null || !context.mounted) return;

  await ref
      .read(executionRepositoryProvider)
      .reportImpediment(
        routeId: route.id,
        routeStopId: choice.scope == 'ROUTE_REMAINDER' ? null : stop.id,
        scope: choice.scope,
        reason: choice.reason,
        note: choice.note,
      );
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text(AppStrings.routeImpedimentReported)),
  );
  // Once the impediment reached the server its stop comes back RELEASED;
  // reloading the day then is what lets an impediment on the last open
  // stop of the batch pull the next one. Offline, the pass is a no-op and
  // the reload serves the device snapshot.
  await ref.read(syncWorkerProvider).syncRoute(route.id);
  if (context.mounted) ref.invalidate(myDayProvider);
}

/// Pushes [ScanScreen] and, if a value came back, pairs it with a
/// tolerant GPS read — the shared first half of both check-in and
/// check-out (Ruling 16: check-out reuses check-in's scan+GPS dance).
/// Returns null when the scan was dismissed or the context is no longer
/// mounted afterward.
Future<_Scan?> _scanAndLocate(
  BuildContext context,
  WidgetRef ref,
  ScanContext scanContext,
) async {
  final rawValue = await Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      builder: (_) => ScanScreen(context: scanContext),
    ),
  );
  if (rawValue == null || !context.mounted) return null;

  final coordinates = await _tryGetPosition(context, ref);
  return _Scan(rawValue, coordinates);
}

/// GPS is tolerated as unavailable here (RF29/RNF13 — a basement has no
/// signal): the backend's Layer 7 already treats a missing position as
/// ACCEPT+flag, so a failure here must not block the check-in, only note
/// it to the field worker.
Future<Coordinates?> _tryGetPosition(
  BuildContext context,
  WidgetRef ref,
) async {
  try {
    return await ref
        .read(locationServiceProvider)
        .getCurrentPosition(purpose: LocationPurpose.checkin);
    // Deliberately broad: GeolocatorLocationService can fail with a
    // StateError (permission denied), a platform exception, or a timeout
    // — all of them mean "proceed without GPS" here, never "block".
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(AppStrings.routeLocationUnavailableCheckIn),
        ),
      );
    }
    return null;
  }
}
