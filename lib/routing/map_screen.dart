import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show TileProvider;

import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/campus_map.dart';
import 'package:route_monitor/routing/route_repository.dart';

/// Full-route trajectory view: the offline campus base map with every stop as
/// a numbered pin and the OSRM legs (or straight approximations) between them.
/// Reached from Task 15's "Ver no mapa" button.
class MapScreen extends StatelessWidget {
  const MapScreen({required this.route, this.tileProviderOverride, super.key});

  final RouteSummary route;

  /// Test seam forwarded to [CampusMap]; null in production so the real
  /// PMTiles vector layer is used.
  final TileProvider? tileProviderOverride;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.mapAppBarTitle)),
      body: CampusMap(
        data: buildRouteMapData(route),
        tileProviderOverride: tileProviderOverride,
      ),
    );
  }
}
