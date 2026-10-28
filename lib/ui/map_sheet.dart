import 'dart:async';

import 'package:flutter/material.dart';
import 'package:route_monitor/ui/app_theme.dart';

/// The three heights of the home sheet (spec §6.2): closed, half (initial)
/// and open.
const List<double> kMapSheetSnaps = [0.22, 0.5, 0.9];
const double kMapSheetInitial = 0.5;

/// The bottom sheet over the map: a drag handle, a scrolling [header] +
/// [body], and an optional [stickyFooter] that never scrolls away — "Escanear
/// QR" must stay on screen at every height (spec §5 anti-goal).
///
///     MapSheet(header: NextStopRow(...), body: card, stickyFooter: scanButton)
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
    return LayoutBuilder(
      builder: (context, constraints) => DraggableScrollableSheet(
        controller: _controller,
        // Spelled out although it is the default: the half height is a
        // design decision (spec §6.2), not an accident of the framework.
        // ignore: avoid_redundant_argument_values
        initialChildSize: kMapSheetInitial,
        minChildSize: kMapSheetSnaps.first,
        maxChildSize: kMapSheetSnaps.last,
        snap: true,
        snapSizes: kMapSheetSnaps,
        builder: (context, scrollController) =>
            _surface(scrollController, constraints.maxHeight),
      ),
    );
  }

  Widget _surface(ScrollController scrollController, double parentHeight) {
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
  });

  final DraggableScrollableController controller;
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
        height: 24,
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
      kMapSheetSnaps.first,
      kMapSheetSnaps.last,
    );
    controller.jumpTo(next);
  }

  void _snap() {
    if (!controller.isAttached) return;
    final size = controller.size;
    final nearest = kMapSheetSnaps.reduce(
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
