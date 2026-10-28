import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:route_monitor/ui/app_theme.dart';

/// The three heights of the home sheet (spec §6.2): closed, half (initial)
/// and open. The closed one grows past 0.22 on a short screen (see
/// [mapSheetSnaps]).
const List<double> kMapSheetSnaps = [0.22, 0.5, 0.9];
const double kMapSheetInitial = 0.5;

/// What the closed sheet must show whole: the handle, one 56dp header row
/// (the next stop) and the footer (56dp button + 8dp above and at least 8dp
/// below).
const double _handleHeight = 24;
const double _closedHeaderHeight = 56;
const double _footerHeight = 56 + 8;
const double _footerMinBottom = 8;

/// The closed snap never goes past this, so it stays below the half height.
const double _maxClosedSize = 0.45;

/// The sheet's snaps for a [parentHeight]-tall screen whose system bar takes
/// [bottomInset]: the closed height is 22% unless that cannot fit the next
/// stop and "Escanear QR" (spec §6.2) — on a small phone with a gesture bar
/// it grows to the pixels they need.
///
///     mapSheetSnaps(640, bottomInset: 48, hasFooter: true); // [0.3, 0.5, 0.9]
List<double> mapSheetSnaps(
  double parentHeight, {
  required double bottomInset,
  required bool hasFooter,
}) {
  if (parentHeight <= 0) return kMapSheetSnaps;
  final bottom = bottomInset > _footerMinBottom
      ? bottomInset
      : _footerMinBottom;
  final needed =
      _handleHeight +
      _closedHeaderHeight +
      (hasFooter ? _footerHeight + bottom : bottomInset);
  final closed = (needed / parentHeight).clamp(
    kMapSheetSnaps.first,
    _maxClosedSize,
  );
  return [closed, kMapSheetSnaps[1], kMapSheetSnaps.last];
}

/// One line of caption over the start bar (12sp text in an 8dp-padded
/// chip) plus its 8dp gap to the pill.
const double kStartBarCaptionHeight = 16 + 2 * 8 + 8;

/// How high the start bar (the bottom-only pill shown instead of a sheet
/// before the route starts or while paused) reaches from the screen's bottom
/// edge: the 56dp pill above the system bar, at least 16dp up, and the
/// caption over it when [withCaption]. What the map camera, "Minha posição"
/// and the snackbars clear when no sheet is shown.
///
///     bottom: startBarHeight(context) + 16
double startBarHeight(BuildContext context, {bool withCaption = false}) {
  final inset = MediaQuery.paddingOf(context).bottom;
  final caption = withCaption ? kStartBarCaptionHeight : 0.0;
  return math.max<double>(inset, 16) + 56 + caption;
}

/// The bottom sheet over the map: a drag handle, a scrolling [header] +
/// [body], and an optional [stickyFooter] that never scrolls away — "Escanear
/// QR" must stay on screen at every height (spec §5 anti-goal).
///
///     MapSheet(header: header, body: card, stickyFooter: scanFooter)
class MapSheet extends StatefulWidget {
  const MapSheet({
    required this.header,
    required this.body,
    this.stickyFooter,
    this.controller,
    super.key,
  });

  final Widget header;
  final Widget body;
  final Widget? stickyFooter;

  /// Drives the sheet from outside (a pin tap sends it to the half height);
  /// one is made internally when null.
  final DraggableScrollableController? controller;

  @override
  State<MapSheet> createState() => _MapSheetState();
}

class _MapSheetState extends State<MapSheet> {
  DraggableScrollableController? _ownController;

  DraggableScrollableController get _controller =>
      widget.controller ?? (_ownController ??= DraggableScrollableController());

  @override
  void dispose() {
    _ownController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        final snaps = mapSheetSnaps(
          constraints.maxHeight,
          bottomInset: bottomInset,
          hasFooter: widget.stickyFooter != null,
        );
        return DraggableScrollableSheet(
          controller: _controller,
          // Spelled out although it is the default: the half height is a
          // design decision (spec §6.2), not an accident of the framework.
          // ignore: avoid_redundant_argument_values
          initialChildSize: kMapSheetInitial,
          minChildSize: snaps.first,
          maxChildSize: snaps.last,
          snap: true,
          snapSizes: snaps,
          builder: (context, scrollController) =>
              _surface(scrollController, constraints.maxHeight, snaps),
        );
      },
    );
  }

  Widget _surface(
    ScrollController scrollController,
    double parentHeight,
    List<double> snaps,
  ) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    final footer = widget.stickyFooter;
    return Material(
      color: p.paper,
      elevation: 8,
      shadowColor: p.ink,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _SheetHandle(
            controller: _controller,
            palette: p,
            parentHeight: parentHeight,
            snaps: snaps,
          ),
          Expanded(child: _scrollArea(scrollController)),
          if (footer != null) _footer(footer),
        ],
      ),
    );
  }

  Widget _scrollArea(ScrollController scrollController) {
    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [widget.header, widget.body],
      ),
    );
  }

  Widget _footer(Widget footer) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: footer,
      ),
    );
  }
}

/// The 32×4 grip; dragging it moves the sheet and snaps on release (the
/// scroll area alone would not let a finger on the handle drag).
class _SheetHandle extends StatelessWidget {
  const _SheetHandle({
    required this.controller,
    required this.palette,
    required this.parentHeight,
    required this.snaps,
  });

  final DraggableScrollableController controller;

  /// Where a release settles: the sheet's own snaps.
  final List<double> snaps;
  final FieldPalette palette;

  /// The height the sheet's fractions are of.
  final double parentHeight;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('map-sheet-handle'),
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (details) => _dragBy(details.delta.dy),
      onVerticalDragEnd: (_) => _snap(),
      child: SizedBox(
        height: _handleHeight,
        width: double.infinity,
        child: Center(
          child: Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: palette.rule,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  void _dragBy(double dy) {
    if (!controller.isAttached || parentHeight <= 0) return;
    final next = (controller.size - dy / parentHeight).clamp(
      snaps.first,
      snaps.last,
    );
    controller.jumpTo(next);
  }

  void _snap() {
    if (!controller.isAttached) return;
    final size = controller.size;
    final nearest = snaps.reduce(
      (a, b) => (a - size).abs() <= (b - size).abs() ? a : b,
    );
    unawaited(
      controller.animateTo(
        nearest,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      ),
    );
  }
}
