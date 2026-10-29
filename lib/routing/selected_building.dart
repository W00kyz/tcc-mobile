import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The building whose pin the worker tapped: the other pins dim (redesign
/// §6.3) and the sheet shows that building's floor card. Null hides the
/// sheet while a route is worked: the map shows whole.
///
///     ref.read(selectedBuildingProvider.notifier).select('b2');
final selectedBuildingProvider = NotifierProvider<SelectedBuilding, String?>(
  SelectedBuilding.new,
);

class SelectedBuilding extends Notifier<String?> {
  @override
  String? build() => null;

  // A method, not a setter: reads as the action it is at the call site.
  // ignore: use_setters_to_change_properties
  void select(String buildingId) => state = buildingId;

  void clear() => state = null;
}
