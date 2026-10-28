import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

/// A 1x1 transparent PNG — served as the whole tile, for every coordinate.
final Uint8List _transparentPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

/// Base-tile provider that keeps a widget test off vector_map_tiles' real
/// (async, timer-scheduling) tile pipeline. Inject it as
/// `CampusMap.tileProviderOverride` / `MapHomeScreen.mapTileProvider`.
class NoTilesTileProvider extends TileProvider {
  @override
  ImageProvider<Object> getImage(
    TileCoordinates coordinates,
    TileLayer options,
  ) => MemoryImage(_transparentPng);
}
