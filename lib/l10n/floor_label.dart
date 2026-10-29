import 'package:route_monitor/l10n/strings.dart';

final RegExp _bareNumber = RegExp(r'^\d+$');

/// A floor label as the worker reads it: a bare number from the backend
/// becomes `Andar <n>`, anything else ("Térreo", "1º andar") stays.
///
///     floorDisplayLabel('1');      // 'Andar 1'
///     floorDisplayLabel('Térreo'); // 'Térreo'
String floorDisplayLabel(String raw) =>
    _bareNumber.hasMatch(raw) ? AppStrings.floorNumbered(raw) : raw;
