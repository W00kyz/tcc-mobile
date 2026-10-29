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
/// With no sheet attached only the start bar is on screen: the snackbar sits
/// just above it ([startBarReach], default [startBarHeight]) instead of at
/// the half line.
///
///     SnackBar(margin: sheetSnackBarMargin(context, controller), ...)
EdgeInsets sheetSnackBarMargin(
  BuildContext context,
  DraggableScrollableController sheet, {
  double Function(BuildContext)? startBarReach,
}) {
  final height = sheet.isAttached
      ? MediaQuery.sizeOf(context).height *
            math.min(sheet.size, kMapSheetInitial)
      : (startBarReach ?? startBarHeight)(context);
  return EdgeInsets.fromLTRB(16, 0, 16, height + 8);
}

/// One snackbar the lane handed to the messenger.
class _Shown {
  _Shown(this.kind);

  final SnackKind kind;
  late final ScaffoldFeatureController<SnackBar, SnackBarClosedReason>
  controller;

  /// The messenger's current snackbar (its content was built — the
  /// Scaffold builds only that one), so `close()` is safe.
  bool current = false;

  /// Superseded before it showed: closed as soon as it does.
  bool stale = false;

  bool _closing = false;

  /// Closes it once: a second `close()` with accessible navigation on would
  /// complete the messenger's completer twice.
  void close() {
    if (_closing) return;
    _closing = true;
    controller.close();
  }
}

/// The home's one snackbar line: only one is ever handed to the messenger,
/// the rest wait here, so a superseded notice is dropped before it is seen
/// (at most one per replaceable kind waits; the newest wins).
///
///     lane.show(SnackKind.sync, AppStrings.routeAllSynced)
class SnackbarLane {
  SnackbarLane({
    required this.contextOf,
    required this.sheet,
    this.startBarReach,
  });

  /// The home's context while it is mounted, null after.
  final BuildContext? Function() contextOf;
  final DraggableScrollableController sheet;

  /// How high the start bar reaches while no sheet is shown (it grows with
  /// a caption); null means [startBarHeight] with no caption.
  final double Function(BuildContext)? startBarReach;

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
    if (shown.current) return shown.close();
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
        content: _CurrentMark(
          onCurrent: () => _onCurrent(shown),
          child: Text(text),
        ),
        // A margin needs a floating snackbar; the theme says so too.
        behavior: SnackBarBehavior.floating,
        margin: sheetSnackBarMargin(
          context,
          sheet,
          startBarReach: startBarReach,
        ),
        action: action,
      ),
    );
    _current = shown;
    unawaited(shown.controller.closed.then((_) => _onClosed(shown)));
  }

  void _onCurrent(_Shown shown) {
    shown.current = true;
    if (shown.stale && _current == shown) shown.close();
  }

  void _onClosed(_Shown shown) {
    if (_current != shown) return;
    _current = null;
    _next();
  }
}

/// Tells the lane its snackbar became the messenger's current one: the
/// Scaffold builds the content of that snackbar alone, never of a queued
/// one.
class _CurrentMark extends StatefulWidget {
  const _CurrentMark({required this.onCurrent, required this.child});

  final VoidCallback onCurrent;
  final Widget child;

  @override
  State<_CurrentMark> createState() => _CurrentMarkState();
}

class _CurrentMarkState extends State<_CurrentMark> {
  @override
  void initState() {
    super.initState();
    // After this frame: a stale notice closes outside the build.
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onCurrent());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
