import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:route_monitor/ui/map_sheet.dart';

/// Who a snackbar belongs to: a newer `sync` or `appeal` one replaces an
/// older of its kind; an `action` one (the confirmation of something the
/// worker did, e.g. "Check-in registrado.") is never replaced, each waits
/// its turn.
enum SnackKind { sync, appeal, action }

/// Bottom margin that lifts a floating snackbar over the map sheet, so it
/// never covers "Escanear QR" (spec §6.7). The sheet's fraction counts up to
/// the half height only: at the open snap (0.9) the snackbar would land
/// under the top bar, so it floats at the half line, still clear of the
/// sticky footer (final review M-1).
///
///     SnackBar(margin: sheetSnackBarMargin(context, controller), ...)
EdgeInsets sheetSnackBarMargin(
  BuildContext context,
  DraggableScrollableController sheet,
) {
  final size = sheet.isAttached ? sheet.size : kMapSheetInitial;
  final fraction = math.min(size, kMapSheetInitial);
  final height = MediaQuery.sizeOf(context).height * fraction;
  return EdgeInsets.fromLTRB(16, 0, 16, height + 8);
}

/// One snackbar the lane handed to the messenger.
class _Shown {
  _Shown(this.kind);

  final SnackKind kind;
  late final ScaffoldFeatureController<SnackBar, SnackBarClosedReason>
  controller;

  /// On screen: the messenger's current snackbar, safe to `close()`.
  bool visible = false;

  /// Superseded before it showed: closed as soon as it does.
  bool stale = false;
}

/// The home's one snackbar line: only one is ever handed to the messenger,
/// the rest wait here, so a superseded notice is dropped before it is seen
/// (at most one per replaceable kind waits; the newest wins).
///
///     lane.show(SnackKind.sync, AppStrings.routeAllSynced)
class SnackbarLane {
  SnackbarLane({required this.contextOf, required this.sheet});

  /// The home's context while it is mounted, null after.
  final BuildContext? Function() contextOf;
  final DraggableScrollableController sheet;

  final List<(SnackKind, String, SnackBarAction?)> _waiting = [];
  _Shown? _current;

  /// Queues [text] (with an optional [action]) as a [kind] snackbar.
  void show(SnackKind kind, String text, {SnackBarAction? action}) {
    if (kind != SnackKind.action) {
      _waiting.removeWhere((entry) => entry.$1 == kind);
    }
    _waiting.add((kind, text, action));
    final current = _current;
    if (current == null) return _next();
    if (kind != SnackKind.action && current.kind == kind) _retire(current);
  }

  /// Closes [shown] only while it really is the messenger's current
  /// snackbar: `close()` on one still queued behind a snackbar shown outside
  /// the lane asserts in debug and hides the wrong one in release
  /// (scaffold.dart, `hideCurrentSnackBar`). Otherwise it goes the moment it
  /// shows.
  void _retire(_Shown shown) {
    if (shown.visible) return shown.controller.close();
    shown.stale = true;
  }

  void _next() {
    final context = contextOf();
    if (context == null) return _waiting.clear();
    if (_waiting.isEmpty) return;
    final (kind, text, action) = _waiting.removeAt(0);
    final shown = _Shown(kind);
    shown.controller = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        // A margin needs a floating snackbar; the theme says so too.
        behavior: SnackBarBehavior.floating,
        margin: sheetSnackBarMargin(context, sheet),
        action: action,
        onVisible: () => _onVisible(shown),
      ),
    );
    _current = shown;
    unawaited(shown.controller.closed.then((_) => _onClosed(shown)));
  }

  void _onVisible(_Shown shown) {
    shown.visible = true;
    if (shown.stale) shown.controller.close();
  }

  void _onClosed(_Shown shown) {
    if (_current != shown) return;
    _current = null;
    _next();
  }
}
