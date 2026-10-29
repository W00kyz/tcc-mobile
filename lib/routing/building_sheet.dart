import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'package:route_monitor/l10n/floor_label.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/batch_card_model.dart' show SlotState;
import 'package:route_monitor/routing/building_card_model.dart';
import 'package:route_monitor/routing/floor_actions.dart';
import 'package:route_monitor/routing/live_approach.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/routing/scan_proximity.dart';
import 'package:route_monitor/ui/app_theme.dart';

// The home sheet while a route is worked: which building it is about, its
// floor card (`FloorCard`, the body) and the one scan action, gated by how
// near the worker is and by the floor's stamps.

/// The floor the sheet names: the one checked in, else the one holding the
/// next task, else the first with a task still open. Null when every task of
/// the building is closed.
///
///     currentFloorOf(building)?.label; // '1º andar'
FloorRow? currentFloorOf(DayBuilding building) =>
    openFloorOf(building) ??
    _floorWith(building, (s) => s == SlotState.next) ??
    _floorWith(building, (s) => s == SlotState.pending);

FloorRow? _floorWith(DayBuilding building, bool Function(SlotState) test) =>
    building.floors.where((f) => f.slots.any((s) => test(s.state))).firstOrNull;

/// "Próximo ponto" (or "Prédio selecionado" after a pin tap), the building
/// and its current floor, and how far the worker is from it.
///
///     BuildingSheetHeader(building: b, selected: false)
class BuildingSheetHeader extends ConsumerWidget {
  const BuildingSheetHeader({
    required this.building,
    required this.selected,
    super.key,
  });

  final DayBuilding building;

  /// The worker tapped this building's pin; otherwise it is the next one.
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    final distance = _distanceText(ref.watch(workerPositionProvider));
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(child: _titles(p)),
            if (distance != null) _distance(distance, p),
          ],
        ),
      ),
    );
  }

  Widget _titles(FieldPalette p) {
    final label = selected
        ? AppStrings.buildingSheetSelected
        : AppStrings.buildingSheetNext;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: p.muted)),
        Text(
          _placeText(),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: p.ink,
          ),
        ),
      ],
    );
  }

  /// `Nome · Andar`, or the name alone once no floor has work left.
  String _placeText() {
    final floor = currentFloorOf(building);
    if (floor == null) return building.name;
    return AppStrings.buildingFloor(
      building.name,
      floorDisplayLabel(floor.label),
    );
  }

  /// Straight-line metres from the worker's last fix; null without one.
  String? _distanceText(LatLng? worker) {
    if (worker == null) return null;
    final meters = const Distance()(worker, building.position).round();
    return AppStrings.meters(meters);
  }

  Widget _distance(String text, FieldPalette p) => Text(
    text,
    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink),
  );
}

/// The floor checked in somewhere other than [building], if any: only one
/// floor is open at a time, so its exit scan comes before any other entry.
///
///     final elsewhere = openFloorElsewhere(buildings, building);
OpenFloor? openFloorElsewhere(
  List<DayBuilding> buildings,
  DayBuilding building,
) => openFloorOfDay(
  buildings.where((other) => other.buildingId != building.buildingId),
);

/// The sheet's fixed footer: "Escanear QR" to check in to a floor of
/// [building], or "Escanear QR de saída" while a floor is checked in. Off
/// until the worker is near the building, the exit also until every task
/// checked in on the floor is stamped, and the entry while [openElsewhere]
/// (another building's floor) still waits for its exit; a caption above
/// says which.
///
///     ScanFooter(route: route, building: building)
class ScanFooter extends ConsumerWidget {
  const ScanFooter({
    required this.route,
    required this.building,
    this.openElsewhere,
    super.key,
  });

  final RouteSummary route;
  final DayBuilding building;

  /// A floor of another building still checked in.
  final OpenFloor? openElsewhere;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final floor = openFloorOf(building);
    final near = isNearBuilding(
      ref.watch(workerPositionProvider),
      building.position,
    );
    final caption = _blockedCaption(near: near, floor: floor);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (caption != null) _FooterCaption(text: caption),
        _button(context, ref, floor, enabled: caption == null),
      ],
    );
  }

  Widget _button(
    BuildContext context,
    WidgetRef ref,
    FloorRow? floor, {
    required bool enabled,
  }) => FilledButton.icon(
    key: const ValueKey('scan-footer-button'),
    onPressed: enabled ? () => _scan(context, ref, floor) : null,
    icon: const Icon(Icons.qr_code_scanner),
    label: Text(
      floor == null ? AppStrings.scanQrButton : AppStrings.scanExitQrButton,
    ),
  );

  /// Why the button is off, or null when it is on. An open floor elsewhere
  /// comes first (its exit is owed wherever the worker stands), then
  /// proximity: stamping the rest does not help a worker who is not there.
  String? _blockedCaption({required bool near, required FloorRow? floor}) {
    final other = openElsewhere;
    if (floor == null && other != null) {
      return AppStrings.scanFinishOpenFloor(
        other.building.name,
        floorDisplayLabel(other.floor.label),
      );
    }
    if (!near) return AppStrings.scanNeedsProximity;
    if (floor != null && !floor.readyForCheckOut) {
      return AppStrings.scanExitNeedsAllTasks;
    }
    return null;
  }

  Future<void> _scan(BuildContext context, WidgetRef ref, FloorRow? floor) {
    if (floor == null) return checkInFloor(context, ref, route, building);
    return checkOutFloor(context, ref, route, floor);
  }
}

/// The footer for [building] among the day's [buildings]; null for a
/// finished building, which has nothing left to scan.
///
///     stickyFooter: scanFooterFor(route, buildings, building)
ScanFooter? scanFooterFor(
  RouteSummary route,
  List<DayBuilding> buildings,
  DayBuilding building,
) {
  if (building.complete) return null;
  return ScanFooter(
    route: route,
    building: building,
    openElsewhere: openFloorElsewhere(buildings, building),
  );
}

/// Why the scan button is off, centred above it in muted 12sp.
class _FooterCaption extends StatelessWidget {
  const _FooterCaption({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: p.muted),
      ),
    );
  }
}

/// The building the sheet is about: the one whose pin was tapped, else the
/// one with a floor checked in (its exit scan is owed), else the next one,
/// else the first with work left, else the last. Null with no building.
///
///     final building = sheetBuildingOf(buildings, selectedId);
DayBuilding? sheetBuildingOf(List<DayBuilding> buildings, String? selectedId) {
  if (buildings.isEmpty) return null;
  return buildings.where((b) => b.buildingId == selectedId).firstOrNull ??
      buildings.where((b) => openFloorOf(b) != null).firstOrNull ??
      nextBuilding(buildings) ??
      buildings.where((b) => !b.complete).firstOrNull ??
      buildings.last;
}
