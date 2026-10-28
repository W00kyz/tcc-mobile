import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:route_monitor/ui/app_theme.dart';

const int _ringPoints = 24;
const double _ringJitter = 0.04;

/// Deterministic pseudo-random jitter in [-1, 1] for point [i] of [seed].
double _jitter(int seed, int i) {
  final v = math.sin(seed * 12.9898 + i * 78.233) * 43758.5453;
  return (v - v.floorToDouble()) * 2 - 1;
}

int seedOf(String stopId) => stopId.codeUnits.fold(7, (a, b) => a * 31 + b);

/// The inked stamp: irregular ring, 13% moss fill and a check.
class StampPainter extends CustomPainter {
  StampPainter({required this.seed, required this.palette, this.ink = 1});

  final int seed;
  final FieldPalette palette;

  /// 0..1, how far the ink has spread.
  final double ink;

  Path ringPath(Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 2;
    final pts = [
      for (var i = 0; i < _ringPoints; i++)
        c +
            Offset.fromDirection(
              2 * math.pi * i / _ringPoints,
              r * (1 + _ringJitter * _jitter(seed, i)),
            ),
    ];
    final path = Path()
      ..moveTo((pts.last.dx + pts[0].dx) / 2, (pts.last.dy + pts[0].dy) / 2);
    for (var i = 0; i < pts.length; i++) {
      final n = pts[(i + 1) % pts.length];
      path.quadraticBezierTo(
        pts[i].dx,
        pts[i].dy,
        (pts[i].dx + n.dx) / 2,
        (pts[i].dy + n.dy) / 2,
      );
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final ring = ringPath(size);
    canvas
      ..drawPath(
        ring,
        Paint()..color = palette.moss.withValues(alpha: 0.13 * ink),
      )
      ..drawPath(
        ring,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 + 1.5 * (1 - ink)
          ..color = palette.moss.withValues(alpha: 0.4 + 0.6 * ink),
      );
    final w = size.width;
    final check = Path()
      ..moveTo(w * 0.34, w * 0.34)
      ..lineTo(w * 0.43, w * 0.43)
      ..lineTo(w * 0.62, w * 0.24);
    canvas.drawPath(
      check,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = palette.moss,
    );
  }

  @override
  bool shouldRepaint(StampPainter old) => old.seed != seed || old.ink != ink;
}

enum RingKind { pending, next, inProgress, released }

/// Rings of the non-done states: plain, dashed, dashed with a dot, struck.
class RingPainter extends CustomPainter {
  RingPainter({required this.kind, required this.palette});

  final RingKind kind;
  final FieldPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 2;
    final dashed = kind == RingKind.next || kind == RingKind.inProgress;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = dashed ? 2 : 1.5
      ..color = dashed ? palette.ink : palette.rule;
    if (dashed) {
      _dashedCircle(canvas, c, r, paint);
    } else {
      canvas.drawCircle(c, r, paint);
    }
    if (kind == RingKind.inProgress) {
      canvas.drawCircle(c, r * 0.22, Paint()..color = palette.ink);
    }
    if (kind == RingKind.released) _strike(canvas, c, r);
  }

  void _dashedCircle(Canvas canvas, Offset c, double r, Paint paint) {
    const dashes = 18;
    const sweep = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        i * sweep,
        sweep * 0.55,
        false,
        paint,
      );
    }
  }

  void _strike(Canvas canvas, Offset c, double r) {
    final d = r * math.sqrt1_2;
    canvas.drawLine(
      c + Offset(-d, d),
      c + Offset(d, -d),
      Paint()
        ..strokeWidth = 1.5
        ..color = palette.muted,
    );
  }

  @override
  bool shouldRepaint(RingPainter old) => old.kind != kind;
}
