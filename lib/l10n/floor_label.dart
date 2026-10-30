import 'package:route_monitor/l10n/strings.dart';

final RegExp _bareNumber = RegExp(r'^\d+$');

/// A floor label as the worker reads it: a bare number from the backend
/// becomes `Andar <n>`, anything else ("Térreo", "1º andar") stays.
///
///     floorDisplayLabel('1');      // 'Andar 1'
///     floorDisplayLabel('Térreo'); // 'Térreo'
String floorDisplayLabel(String raw) =>
    _bareNumber.hasMatch(raw) ? AppStrings.floorNumbered(raw) : raw;

/// Where a stop is: `Prédio · Andar` for a room, the site's name alone for an
/// outdoor place, which has no floor (null or empty [floorLabel]).
///
///     siteWithFloor('CAA', '1');          // 'CAA · Andar 1'
///     siteWithFloor('Praça central', null); // 'Praça central'
String siteWithFloor(String site, String? floorLabel) {
  if (floorLabel == null || floorLabel.isEmpty) return site;
  return AppStrings.buildingFloor(site, floorDisplayLabel(floorLabel));
}
