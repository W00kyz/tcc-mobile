import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:route_monitor/ui/app_theme.dart';
import 'package:route_monitor/ui/stamp_painters.dart';

/// A free-standing moss stamp — the card's ink, without a slot's hour —
/// with [mark] (a check by default) in the middle, tilted by [tiltDeg].
/// For the streak and the achievements (redesign §6.8).
///
///     InkStamp(size: 64, seed: 3, tiltDeg: -6, mark: Text('5'))
class InkStamp extends StatelessWidget {
  const InkStamp({
    required this.size,
    required this.seed,
    this.tiltDeg = 0,
    this.mark,
    super.key,
  });

  final double size;
  final int seed;
  final double tiltDeg;
  final Widget? mark;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    return Transform.rotate(
      angle: tiltDeg * math.pi / 180,
      child: CustomPaint(
        painter: StampPainter(seed: seed, palette: p, showCheck: false),
        child: SizedBox.square(
          dimension: size,
          child: Center(
            child: mark ?? Icon(Icons.check, size: size * 0.5, color: p.moss),
          ),
        ),
      ),
    );
  }
}
