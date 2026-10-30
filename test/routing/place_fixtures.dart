import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/routing/stop_completion.dart';

/// A stop of the outdoor place [placeId], completed by location: no
/// building, no floor, PENDING in batch 1 unless told otherwise.
RouteStopSummary placeStopIn({
  required String id,
  String placeId = 'p1',
  String placeName = 'Praça central',
  int orderIndex = 1,
  int batchNumber = 1,
  String status = 'PENDING',
  String? servicePointName,
  double latitude = -7.215,
  double longitude = -35.915,
}) => RouteStopSummary(
  id: id,
  orderIndex: orderIndex,
  batchNumber: batchNumber,
  status: status,
  servicePointName: servicePointName ?? 'Ponto $id',
  buildingId: null,
  buildingName: placeName,
  floorLabel: null,
  placeId: placeId,
  completion: StopCompletion.location,
  latitude: latitude,
  longitude: longitude,
);
