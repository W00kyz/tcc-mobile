import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/ui/app_theme.dart';

double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double contrastRatio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('colorScheme maps tokens', () {
    final scheme = buildAppTheme().colorScheme;
    expect(scheme.primary, const Color(0xFF1F1F1D));
    expect(scheme.secondary, const Color(0xFF3E5C4A));
    expect(scheme.error, const Color(0xFFB5452F));
    expect(scheme.surface, const Color(0xFFEDEDEA));
    expect(scheme.surfaceContainer, const Color(0xFFDEDED9));
    expect(scheme.outline, const Color(0xFFBDBDB6));
  });

  test('text theme uses Hanken Grotesk', () {
    final t = buildAppTheme().textTheme;
    final styles = [
      t.displayLarge,
      t.displayMedium,
      t.displaySmall,
      t.headlineLarge,
      t.headlineMedium,
      t.headlineSmall,
      t.titleLarge,
      t.titleMedium,
      t.titleSmall,
      t.bodyLarge,
      t.bodyMedium,
      t.bodySmall,
      t.labelLarge,
      t.labelMedium,
      t.labelSmall,
    ].whereType<TextStyle>();
    expect(styles, isNotEmpty);
    for (final s in styles) {
      expect(s.fontFamily, 'HankenGrotesk');
    }
  });

  test('FieldPalette is registered', () {
    final palette = buildAppTheme().extension<FieldPalette>();
    expect(palette, isNotNull);
    expect(palette!.mapGround, const Color(0xFFE3E3DF));
  });

  test('muted on paper meets AA', () {
    const p = FieldPalette.light;
    expect(contrastRatio(p.muted, p.paper), greaterThanOrEqualTo(4.5));
  });
}
