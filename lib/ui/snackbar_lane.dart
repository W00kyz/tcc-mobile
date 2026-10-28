import 'dart:async';

import 'package:flutter/material.dart';

import 'package:route_monitor/ui/map_sheet.dart';

/// Who a snackbar belongs to: a newer one of the same kind replaces an older.
enum SnackKind { sync, appeal }

/// Builds the snackbar once its turn comes, with the margin of that moment.
typedef SnackBuilder = SnackBar Function(EdgeInsets margin);

/// Bottom margin that lifts a floating snackbar over the map sheet, so it
/// never covers "Escanear QR" (spec §6.7).
///
///     SnackBar(margin: sheetSnackBarMargin(context, controller), ...)
EdgeInsets sheetSnackBarMargin(
  BuildContext context,
  DraggableScrollableController sheet,
) {
  final fraction = sheet.isAttached ? sheet.size : kMapSheetInitial;
  final height = MediaQuery.sizeOf(context).height * fraction;
  return EdgeInsets.fromLTRB(16, 0, 16, height + 8);
}

/// The home's one snackbar line: only one is ever handed to the messenger,
/// the rest wait here, so a superseded notice is dropped before it is seen
/// (at most one per kind waits; the newest wins).
///
///     lane.show(SnackKind.sync, (margin) => SnackBar(margin: margin, ...))
class SnackbarLane {
  SnackbarLane({required this.contextOf, required this.sheet});

  /// The home's context while it is mounted, null after.
  final BuildContext? Function() contextOf;
  final DraggableScrollableController sheet;

  final List<(SnackKind, SnackBuilder)> _waiting = [];
  (SnackKind, ScaffoldFeatureController<SnackBar, SnackBarClosedReason>)?
  _current;

  void show(SnackKind kind, SnackBuilder build) {
    _waiting
      ..removeWhere((entry) => entry.$1 == kind)
      ..add((kind, build));
    final current = _current;
    if (current == null) return _next();
    if (current.$1 == kind) current.$2.close();
  }

  void _next() {
    final context = contextOf();
    if (context == null) return _waiting.clear();
    if (_waiting.isEmpty) return;
    final (kind, build) = _waiting.removeAt(0);
    final shown = ScaffoldMessenger.of(
      context,
    ).showSnackBar(build(sheetSnackBarMargin(context, sheet)));
    _current = (kind, shown);
    unawaited(shown.closed.then((_) => _onClosed(shown)));
  }

  void _onClosed(ScaffoldFeatureController<SnackBar, SnackBarClosedReason> c) {
    if (_current?.$2 != c) return;
    _current = null;
    _next();
  }
}
