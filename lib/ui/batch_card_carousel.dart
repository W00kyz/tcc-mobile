import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/ui/app_theme.dart';
import 'package:route_monitor/ui/batch_card.dart';

/// Each page takes this share of the width, so the neighbours peek in at the
/// edges and read as "there is more to swipe".
const double kCarouselViewportFraction = 0.88;

/// Space between two cards: half of it on each side of a page.
const double _pageGap = 8;
const double _dotSize = 8;
const Duration _toCurrentDuration = Duration(milliseconds: 300);

/// The day's batch cards, one per page, swiped sideways (product owner,
/// 2026-10-28, over spec §6.2's stop list): a swipe pulls the next card to
/// the centre and settles there. Opens on the current batch, and goes back
/// to it when a building is highlighted (a pin tap) or a stamp falls.
///
///     BatchCardCarousel(
///       cards: cards,
///       currentBatch: route.currentBatch,
///       onSlotTap: (slot) => showStopSheet(context, route, slot),
///     )
class BatchCardCarousel extends StatefulWidget {
  const BatchCardCarousel({
    required this.cards,
    required this.currentBatch,
    this.highlightBuildingId,
    this.stampingStopId,
    this.onSlotTap,
    super.key,
  });

  final List<BatchCard> cards;
  final int currentBatch;
  final String? highlightBuildingId;

  /// The one stop whose stamp falls; see [BatchCardView.stampingStopId].
  final String? stampingStopId;
  final ValueChanged<CardSlot>? onSlotTap;

  @override
  State<BatchCardCarousel> createState() => _BatchCardCarouselState();
}

class _BatchCardCarouselState extends State<BatchCardCarousel> {
  late final PageController _pages = PageController(
    initialPage: _currentIndex,
    viewportFraction: kCarouselViewportFraction,
  );
  late int _shown = _currentIndex;

  /// The current batch's page; the last one if it has no card.
  int get _currentIndex {
    final index = widget.cards.indexWhere(
      (card) => card.batchNumber == widget.currentBatch,
    );
    return index >= 0 ? index : widget.cards.length - 1;
  }

  @override
  void didUpdateWidget(BatchCardCarousel old) {
    super.didUpdateWidget(old);
    final highlighted =
        widget.highlightBuildingId != null &&
        widget.highlightBuildingId != old.highlightBuildingId;
    final stamped =
        widget.stampingStopId != null &&
        widget.stampingStopId != old.stampingStopId;
    final newBatch = widget.currentBatch != old.currentBatch;
    if (highlighted || stamped || newBatch) _showCurrent();
  }

  /// After this frame: the page count may have changed with the cards.
  void _showCurrent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pages.hasClients) return;
      unawaited(
        _pages.animateToPage(
          _currentIndex,
          duration: _toCurrentDuration,
          curve: Curves.easeOut,
        ),
      );
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => _pager(constraints.maxWidth),
        ),
        if (widget.cards.length >= 2) _dots(context),
      ],
    );
  }

  /// The pager is as tall as the tallest card: every card is laid out,
  /// unseen, to size the stack ([_SizingGhost]), and the pages fill it.
  Widget _pager(double width) {
    final cardWidth = width * kCarouselViewportFraction - _pageGap;
    return Stack(
      children: [
        for (final card in widget.cards)
          _SizingGhost(
            child: SizedBox(
              width: cardWidth,
              child: BatchCardView(card: card),
            ),
          ),
        Positioned.fill(child: _pageView()),
      ],
    );
  }

  Widget _pageView() {
    return PageView.builder(
      key: const ValueKey('batch-card-carousel'),
      controller: _pages,
      // The "pull" to the centre of the next card. `padEnds` (the default)
      // centres the first and last cards too.
      physics: const PageScrollPhysics(),
      itemCount: widget.cards.length,
      onPageChanged: (page) => setState(() => _shown = page),
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: _pageGap / 2),
        child: BatchCardView(
          card: widget.cards[index],
          highlightBuildingId: widget.highlightBuildingId,
          stampingStopId: widget.stampingStopId,
          onSlotTap: widget.onSlotTap,
        ),
      ),
    );
  }

  /// Where the shown card sits among the day's batches. Circles only; the
  /// cards' own titles say which batch it is, so the dots stay silent.
  Widget _dots(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.cards.length; i++)
              _dot(i, active: i == _shown, palette: p),
          ],
        ),
      ),
    );
  }

  Widget _dot(
    int index, {
    required bool active,
    required FieldPalette palette,
  }) {
    return Container(
      key: ValueKey('carousel-dot-$index'),
      width: _dotSize,
      height: _dotSize,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? palette.ink : palette.rule,
      ),
    );
  }
}

/// Laid out — so its size counts in a [Stack] — but never painted, hit,
/// read by assistive technology or found by a test finder: a stand-in that
/// only measures.
class _SizingGhost extends SingleChildRenderObjectWidget {
  const _SizingGhost({required super.child});

  @override
  SingleChildRenderObjectElement createElement() => _SizingGhostElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSizingGhost();
}

class _SizingGhostElement extends SingleChildRenderObjectElement {
  _SizingGhostElement(super.widget);

  // Offstage for the widget inspector and finders, like `Offstage`.
  @override
  void debugVisitOnstageChildren(ElementVisitor visitor) {}
}

class _RenderSizingGhost extends RenderProxyBox {
  @override
  void paint(PaintingContext context, Offset offset) {}

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) => false;

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {}
}
