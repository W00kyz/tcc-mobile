import 'package:flutter/material.dart';

import 'package:route_monitor/routing/route_repository.dart';

/// Full-route trajectory view (Task 16 fleshes out the body with the offline
/// map and the OSRM polyline). Kept minimal here so Task 15's "Ver no mapa"
/// button has a real destination to navigate to.
class MapScreen extends StatelessWidget {
  const MapScreen({required this.route, super.key});

  final RouteSummary route;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trajeto da rota')),
      body: Center(
        child: Text('Mapa da rota de ${route.fieldWorkerName} em construção.'),
      ),
    );
  }
}
