import 'package:flutter/material.dart';

import 'package:route_monitor/ui/app_theme.dart';

/// Share of the screen width taken by the square scan window (spec 6.4).
const double kScanWindowFraction = 0.7;

const double _bracketStroke = 4;
const double _bracketLength = 28;

/// The square scan window: [kScanWindowFraction] of the width, centred in
/// [size]. The painter cuts it out and `MobileScanner.scanWindow` reads it,
/// so what is lit is exactly what is scanned.
Rect scanCutout(Size size) => Rect.fromCenter(
  center: size.center(Offset.zero),
  width: size.width * kScanWindowFraction,
  height: size.width * kScanWindowFraction,
);

/// Dims the camera (60% black) around [cutout], then draws the four corner
/// brackets in [bracketColor] and a discreet scan line across the middle.
class ScanOverlayPainter extends CustomPainter {
  const ScanOverlayPainter({required this.cutout, required this.bracketColor});

  final Rect cutout;
  final Color bracketColor;

  @override
  void paint(Canvas canvas, Size size) {
    _paintScrim(canvas, size);
    _paintBrackets(canvas);
    _paintScanLine(canvas);
  }

  void _paintScrim(Canvas canvas, Size size) {
    final scrim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRect(cutout),
    );
    canvas.drawPath(scrim, Paint()..color = kScanScrim);
  }

  void _paintBrackets(Canvas canvas) {
    final paint = Paint()
      ..color = bracketColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _bracketStroke
      ..strokeCap = StrokeCap.square;
    final path = Path();
    for (final corner in [
      (cutout.topLeft, 1.0, 1.0),
      (cutout.topRight, -1.0, 1.0),
      (cutout.bottomLeft, 1.0, -1.0),
      (cutout.bottomRight, -1.0, -1.0),
    ]) {
      final (origin, dx, dy) = corner;
      path
        ..moveTo(origin.dx + dx * _bracketLength, origin.dy)
        ..lineTo(origin.dx, origin.dy)
        ..lineTo(origin.dx, origin.dy + dy * _bracketLength);
    }
    canvas.drawPath(path, paint);
  }

  void _paintScanLine(Canvas canvas) {
    final paint = Paint()
      ..color = kScanOverlayWhite.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    final y = cutout.center.dy;
    canvas.drawLine(
      Offset(cutout.left + 16, y),
      Offset(cutout.right - 16, y),
      paint,
    );
  }

  @override
  bool shouldRepaint(ScanOverlayPainter old) =>
      old.cutout != cutout || old.bracketColor != bracketColor;
}
