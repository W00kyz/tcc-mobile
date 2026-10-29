import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/batch_card_model.dart';
import 'package:route_monitor/ui/app_theme.dart';
import 'package:route_monitor/ui/stamp_painters.dart';

// Spec §4: the stamp drops for 260 ms, then a ring of ink spreads for 320 ms.
const int _dropMs = 260;
const int _ringMs = 320;
const Duration _stampDuration = Duration(milliseconds: _dropMs + _ringMs);
const double _impactAt = _dropMs / (_dropMs + _ringMs);
const double _dropFromScale = 1.6;
const Interval _dropCurve = Interval(
  0,
  _impactAt,
  curve: Curves.easeOutBack,
);

/// One slot of the batch card. Each state reads by mark and by semantic
/// label, never by colour alone. `done` and `stamped` print the moss stamp,
/// `impeded` the brick one; a stamp that just landed ([animateStamp] for
/// moss, [animateImpeded] for brick) drops once.
class StampSlot extends StatefulWidget {
  const StampSlot({
    required this.slot,
    this.size = 48,
    this.animateStamp = false,
    this.animateImpeded = false,
    this.onTap,
    super.key,
  });

  final CardSlot slot;
  final double size;
  final bool animateStamp;
  final bool animateImpeded;

  /// Opens the stop's actions. The slot and its caption are the target —
  /// never under 48dp (the circle alone is [size]).
  final VoidCallback? onTap;

  @override
  State<StampSlot> createState() => _StampSlotState();
}

class _StampSlotState extends State<StampSlot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _impacted = true;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _stampDuration,
      value: 1,
    )..addListener(_onTick);
  }

  /// MediaQuery is readable here, and this runs before the first build, so
  /// the stamp never shows its final frame before it drops.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (_wantsDrop(widget)) _play();
  }

  @override
  void didUpdateWidget(StampSlot old) {
    super.didUpdateWidget(old);
    if (_wantsDrop(widget) && !_wantsDrop(old)) _play();
  }

  /// The drop plays when the slot is a stamp AND its flag is up, so a flag
  /// raised a frame before the face changes still lands on the stamp.
  bool _wantsDrop(StampSlot w) => switch (w.slot.state) {
    SlotState.done || SlotState.stamped => w.animateStamp,
    SlotState.impeded => w.animateImpeded,
    _ => false,
  };

  /// Under reduced motion the controller stays at 1: an instant swap.
  void _play() {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    _impacted = false;
    unawaited(_controller.forward(from: 0));
  }

  /// The haptic is the impact: the end of the drop, once per play.
  void _onTick() {
    if (_impacted || _controller.value < _impactAt) return;
    _impacted = true;
    unawaited(HapticFeedback.mediumImpact());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _hour() {
    final at = widget.slot.stampedAt;
    return at == null ? '' : stampHour(at);
  }

  String _label() {
    final base = _stateLabel();
    return widget.slot.pendingSync
        ? '$base, ${AppStrings.slotPendingSync}'
        : base;
  }

  String _stateLabel() => switch (widget.slot.state) {
    SlotState.done => AppStrings.slotDone(_hour()),
    SlotState.stamped => AppStrings.slotStamped,
    SlotState.impeded => AppStrings.slotImpeded,
    SlotState.released => AppStrings.slotReleased(_reason),
    SlotState.pending => AppStrings.slotPending,
    SlotState.next => AppStrings.slotNext,
    SlotState.inProgress => AppStrings.slotInProgress,
  };

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>()!;
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: _label(),
          container: true,
          button: widget.onTap != null,
          onTap: widget.onTap,
          child: ExcludeSemantics(child: _circle(p)),
        ),
        const SizedBox(height: 3),
        _caption(context, p),
      ],
    );
    return widget.onTap == null ? body : _tappable(body);
  }

  /// A circular ink, like the slot; the tap reaches assistive technology
  /// through the label's own node above, not a second one here.
  Widget _tappable(Widget body) => InkResponse(
    onTap: widget.onTap,
    radius: widget.size / 2 + 8,
    excludeFromSemantics: true,
    child: body,
  );

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
          if (_showsCloud) _syncBadge(p),
        ],
      ),
    );
  }

  /// The cloud: not sent yet, or stamped and waiting for the floor's exit.
  bool get _showsCloud =>
      widget.slot.pendingSync || widget.slot.state == SlotState.stamped;

  Widget _face(FieldPalette p) {
    final slot = widget.slot;
    if (_isStamp(slot.state)) return _stamp(p);
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

  bool _isStamp(SlotState state) =>
      state == SlotState.done ||
      state == SlotState.stamped ||
      state == SlotState.impeded;

  Widget _stamp(FieldPalette p) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final v = _controller.value;
        final drop = _dropCurve.transform(v);
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            if (v > _impactAt && v < 1) _inkRing(p, v),
            _dropped(p, drop, opacity: (v / _impactAt).clamp(0.0, 1.0)),
          ],
        );
      },
    );
  }

  /// The ring of ink spreading out of the stamp once it has landed.
  Widget _inkRing(FieldPalette p, double v) {
    final progress = (v - _impactAt) / (1 - _impactAt);
    return CustomPaint(
      size: Size.square(widget.size),
      painter: InkRingPainter(color: _ink(p), progress: progress),
    );
  }

  Color _ink(FieldPalette p) =>
      widget.slot.state == SlotState.impeded ? p.brick : p.moss;

  /// The stamp at [drop] (0 = high above, 1 = landed): scale 1.6 to 1,
  /// turning from upright to its own tilt, fading in.
  Widget _dropped(FieldPalette p, double drop, {required double opacity}) {
    final tilt = widget.slot.stampRotationDeg * math.pi / 180;
    return Opacity(
      opacity: opacity,
      child: Transform.rotate(
        angle: tilt * drop,
        child: Transform.scale(
          key: const ValueKey('stamp-drop'),
          scale: _dropFromScale + (1 - _dropFromScale) * drop,
          child: _stampBody(p, drop),
        ),
      ),
    );
  }

  Widget _stampBody(FieldPalette p, double drop) => SizedBox.square(
    dimension: widget.size,
    child: CustomPaint(
      painter: StampPainter(
        seed: seedOf(widget.slot.stopId),
        palette: p,
        ink: drop.clamp(0.0, 1.0),
        impossible: widget.slot.state == SlotState.impeded,
      ),
      child: _hourLabel(p),
    ),
  );

  /// Only a stamp that is done carries the hour.
  Widget? _hourLabel(FieldPalette p) {
    if (widget.slot.state != SlotState.done) return null;
    return Align(
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

/// `HH:mm` of a stamp, read straight off the timestamp with no `.toLocal()`:
/// the app's wall-clock-tagged-UTC convention (same as the notifications
/// list). Shared by the card's stamp and the sheet's stop row so both read
/// the same hour.
///
///     stampHour(DateTime.utc(2026, 10, 20, 10, 5)); // '10:05'
String stampHour(DateTime at) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(at.hour)}:${two(at.minute)}';
}
