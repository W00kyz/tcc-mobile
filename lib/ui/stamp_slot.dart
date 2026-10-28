import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/ui/app_theme.dart';
import 'package:route_monitor/ui/stamp_painters.dart';

const Duration _stampDuration = Duration(milliseconds: 220);

/// One slot of the batch card. Each state reads by mark and by semantic
/// label, never by colour alone.
class StampSlot extends StatefulWidget {
  const StampSlot({
    required this.slot,
    this.size = 48,
    this.animateStamp = false,
    super.key,
  });

  final CardSlot slot;
  final double size;
  final bool animateStamp;

  @override
  State<StampSlot> createState() => _StampSlotState();
}

class _StampSlotState extends State<StampSlot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _stampDuration,
      value: 1,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.animateStamp && !reduce && _controller.value == 1) {
      unawaited(HapticFeedback.lightImpact());
      unawaited(_controller.forward(from: 0));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _hour() {
    final at = widget.slot.stampedAt;
    if (at == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(at.hour)}:${two(at.minute)}';
  }

  String _label() => switch (widget.slot.state) {
    SlotState.done => AppStrings.slotDone(_hour()),
    SlotState.released => AppStrings.slotReleased(_reason),
    SlotState.pending => AppStrings.slotPending,
    SlotState.next => AppStrings.slotNext,
    SlotState.inProgress => AppStrings.slotInProgress,
  };

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>()!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: _label(),
          container: true,
          child: ExcludeSemantics(child: _circle(p)),
        ),
        const SizedBox(height: 3),
        _caption(context, p),
      ],
    );
  }

  Widget _circle(FieldPalette p) {
    final s = widget.size;
    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          _face(p),
          if (widget.slot.pendingSync) _syncBadge(p),
        ],
      ),
    );
  }

  Widget _face(FieldPalette p) {
    final slot = widget.slot;
    if (slot.state == SlotState.done) return _stamp(p);
    final kind = switch (slot.state) {
      SlotState.next => RingKind.next,
      SlotState.inProgress => RingKind.inProgress,
      SlotState.released => RingKind.released,
      _ => RingKind.pending,
    };
    return CustomPaint(
      size: Size.square(widget.size),
      painter: RingPainter(kind: kind, palette: p),
    );
  }

  Widget _stamp(FieldPalette p) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeOut.transform(_controller.value);
        return Transform.rotate(
          angle: widget.slot.stampRotationDeg * 3.14159265 / 180,
          child: Transform.scale(
            scale: 1.15 - 0.15 * t,
            child: SizedBox.square(
              dimension: widget.size,
              child: CustomPaint(
                painter: StampPainter(
                  seed: seedOf(widget.slot.stopId),
                  palette: p,
                  ink: t,
                ),
                child: Align(
                  alignment: const Alignment(0, 0.45),
                  child: Text(
                    _hour(),
                    style: TextStyle(
                      color: p.moss,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _syncBadge(FieldPalette p) {
    return Positioned(
      top: -3,
      right: -6,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: p.white,
          border: Border.all(color: p.rule),
        ),
        child: Icon(Icons.cloud_upload_outlined, size: 12, color: p.muted),
      ),
    );
  }

  Widget _caption(BuildContext context, FieldPalette p) {
    final slot = widget.slot;
    final released = slot.state == SlotState.released;
    final style = TextStyle(
      fontSize: 11,
      height: 14 / 11,
      fontWeight: FontWeight.w600,
      color: released ? p.muted : p.ink,
    );
    return SizedBox(
      width: widget.size + 12,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            slot.floorLabel,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style.copyWith(
              decoration: released ? TextDecoration.lineThrough : null,
            ),
          ),
          if (released && _reason != null) _reasonText(p),
        ],
      ),
    );
  }

  String? get _reason {
    final code = widget.slot.releaseReason;
    return code == null ? null : AppStrings.releaseReasonLabel(code);
  }

  Widget _reasonText(FieldPalette p) {
    return Text(
      _reason!,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 11, height: 12 / 11, color: p.muted),
    );
  }
}
