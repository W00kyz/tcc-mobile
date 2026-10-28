import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/checkin/checkin_providers.dart';
import 'package:route_monitor/checkin/scan_screen.dart' show ExitScan;
import 'package:route_monitor/execution/conclude_sheet.dart'
    show observationDraftProvider;
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/batch_card_model.dart' show SlotState;
import 'package:route_monitor/routing/building_card_model.dart';
import 'package:route_monitor/routing/home_notices.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/routing/scan_and_locate.dart';
import 'package:route_monitor/routing/stop_actions.dart'
    show LastStamped, lastStampedStopProvider;
import 'package:route_monitor/sync/sync_providers.dart' show syncWorkerProvider;
import 'package:uuid/uuid.dart';

// The floor flows of the per-building route, with no widget of their own: one
// QR check-in opens a floor's tasks, "Concluir tarefa" stamps one locally, and
// one exit scan checks out every stamped task of the floor.

const _uuid = Uuid();

/// The stop whose task was just reported impossible: the card draws that one
/// slot as a red stamp, the map home centres on its building. Same shape as
/// [lastStampedStopProvider].
///
///     ref.watch(lastImpededStopProvider); // 's1' right after s1's report
final lastImpededStopProvider = NotifierProvider<LastStamped, String?>(
  LastStamped.new,
);

/// "Escanear QR" on a floor: one scan checks in every open task of that
/// floor. An unverifiable QR gets the invalid-QR notice; a floor with no open
/// task of the worker's gets [AppStrings.floorHasNoOpenTasks]. Either way
/// nothing is enqueued.
///
///     onPressed: () => checkInFloor(context, ref, route)
Future<void> checkInFloor(
  BuildContext context,
  WidgetRef ref,
  RouteSummary route,
) async {
  final notify = homeNotifier(ref, context);
  final scan = await scanAndLocate(context, ref, entryScanContext(route));
  if (scan == null || !context.mounted) return;

  final qr = await ref.read(qrVerifierProvider).verify(scan.rawValue);
  if (qr == null) return notify(AppStrings.scanInvalidQr);
  final stops = await _openCandidates(ref, route, qr.floorId);
  if (stops.isEmpty) return notify(AppStrings.floorHasNoOpenTasks);

  await _enqueueCheckIns(ref, route, stops, scan);
  ref.invalidate(myDayProvider);
  notify(AppStrings.floorCheckInDone(stops.length));
}

/// One check-in per stop, all with the scan's QR and each its own key. The
/// repository only enqueues + writes local state: nothing to catch.
Future<void> _enqueueCheckIns(
  WidgetRef ref,
  RouteSummary route,
  List<RouteStopSummary> stops,
  ScanResult scan,
) async {
  final repository = ref.read(executionRepositoryProvider);
  for (final stop in stops) {
    await repository.checkIn(
      routeId: route.id,
      routeStopId: stop.id,
      qrPayload: scan.rawValue,
      latitude: scan.coordinates?.latitude,
      longitude: scan.coordinates?.longitude,
      idempotencyKey: _uuid.v4(),
    );
    ref.invalidate(stopProgressForProvider(stop.id));
  }
}

/// The floor's `PENDING` stops that a scan may still check in: one the device
/// already checked in (any local status) or the worker reported impossible is
/// out, so a second scan before the sync never repeats a check-in.
Future<List<RouteStopSummary>> _openCandidates(
  WidgetRef ref,
  RouteSummary route,
  String floorId,
) async {
  final candidates = checkInCandidates(route, floorId);
  final touched = await ref
      .read(stopProgressStoreProvider)
      .allForRoute(candidates.map((stop) => stop.id));
  final started = {for (final entry in touched) entry.routeStopId};
  // The store, not the provider: a stream provider nobody watches never
  // emits under `read`.
  final impeded = await ref
      .read(localWriteStoreProvider)
      .watchImpededStopIds(route.id)
      .first;
  return [
    for (final stop in candidates)
      if (!started.contains(stop.id) && !impeded.contains(stop.id)) stop,
  ];
}

/// "Concluir tarefa": stamps [stop] on the device with its [observation] and
/// lets its held photos leave. Nothing is checked out until the floor's exit
/// scan.
///
///     await concludeTask(ref, route, stop, observation: 'trocada');
Future<void> concludeTask(
  WidgetRef ref,
  RouteSummary route,
  RouteStopSummary stop, {
  String? observation,
}) async {
  final entry = await ref.read(stopProgressStoreProvider).progressFor(stop.id);
  await ref
      .read(executionRepositoryProvider)
      .stampTask(
        routeId: route.id,
        routeStopId: stop.id,
        executionId: entry?.executionId,
        observation: observation,
      );
  ref
    ..invalidate(stopProgressForProvider(stop.id))
    ..invalidate(observationDraftProvider(stop.id))
    ..read(lastStampedStopProvider.notifier).stamp(stop.id);
}

/// "Não consigo fazer este ponto" on one task: enqueues the `STOP`
/// impediment, drops the photos held for it and draws the red stamp. Once the
/// impediment reached the server its stop comes back `RELEASED`; the sync
/// pass and the day reload below are what let the batch move on.
///
///     await signalTaskImpossible(context, ref, route, stop, reason: 'OTHER');
Future<void> signalTaskImpossible(
  BuildContext context,
  WidgetRef ref,
  RouteSummary route,
  RouteStopSummary stop, {
  required String reason,
  String? note,
}) async {
  final notify = homeNotifier(ref, context);
  await _recordImpediment(ref, route, stop, reason, note);
  notify(AppStrings.taskImpededDone);
  await ref.read(syncWorkerProvider).syncRoute(route.id);
  if (context.mounted) ref.invalidate(myDayProvider);
}

Future<void> _recordImpediment(
  WidgetRef ref,
  RouteSummary route,
  RouteStopSummary stop,
  String reason,
  String? note,
) async {
  final entry = await ref.read(stopProgressStoreProvider).progressFor(stop.id);
  await ref
      .read(executionRepositoryProvider)
      .impedeTask(
        routeId: route.id,
        routeStopId: stop.id,
        reason: reason,
        note: note,
        executionId: entry?.executionId,
      );
  ref
    ..invalidate(observationDraftProvider(stop.id))
    ..read(lastImpededStopProvider.notifier).stamp(stop.id);
}

/// "Concluir andar": one exit scan, then one check-out per stamped task of
/// [floor], each carrying the observation stored with its stamp.
///
///     onPressed: () => checkOutFloor(context, ref, route, floor)
Future<void> checkOutFloor(
  BuildContext context,
  WidgetRef ref,
  RouteSummary route,
  FloorRow floor,
) async {
  final stamped = _stampedStopIds(floor);
  if (stamped.isEmpty) return;
  final notify = homeNotifier(ref, context);
  final building = route.stops.firstWhere((s) => s.id == stamped.first);
  final exit = ExitScan(building.buildingName, floor.label);
  final scan = await scanAndLocate(context, ref, exit);
  if (scan == null) return;
  if (!await _isFloorExitQr(ref, floor, scan, notify)) return;

  for (final stopId in stamped) {
    await _checkOutStamped(ref, route, stopId, scan);
  }
  ref.invalidate(myDayProvider);
  notify(AppStrings.floorCheckOutDone);
}

List<String> _stampedStopIds(FloorRow floor) => [
  for (final slot in floor.slots)
    if (slot.state == SlotState.stamped) slot.stopId,
];

/// Whether [scan] is a verified QR of [floor], saying why not otherwise. A
/// floor of a snapshot cached before the backend sent floor ids has nothing to
/// compare with, so any verified QR passes (the backend still checks it).
Future<bool> _isFloorExitQr(
  WidgetRef ref,
  FloorRow floor,
  ScanResult scan,
  void Function(String) notify,
) async {
  final qr = await ref.read(qrVerifierProvider).verify(scan.rawValue);
  if (qr == null) {
    notify(AppStrings.scanInvalidQr);
    return false;
  }
  final wrongFloor = floor.floorId != null && qr.floorId != floor.floorId;
  if (wrongFloor) notify(AppStrings.exitQrWrongFloor(floor.label));
  return !wrongFloor;
}

/// One stamped task's check-out, with the observation read back from the
/// store (it outlives the sheet that wrote it).
Future<void> _checkOutStamped(
  WidgetRef ref,
  RouteSummary route,
  String stopId,
  ScanResult scan,
) async {
  final entry = await ref.read(stopProgressStoreProvider).progressFor(stopId);
  await ref
      .read(executionRepositoryProvider)
      .checkOut(
        routeId: route.id,
        routeStopId: stopId,
        qrPayload: scan.rawValue,
        latitude: scan.coordinates?.latitude,
        longitude: scan.coordinates?.longitude,
        checkoutIdempotencyKey: _uuid.v4(),
        complaintsSuggestions: entry?.observation,
      );
  ref.invalidate(stopProgressForProvider(stopId));
}
