import 'dart:io';
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

  test('Hanken Grotesk ships one static file per weight', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final family = RegExp(
      r'family: HankenGrotesk\n((?:\s+.*\n)+?)\s+- family:',
    ).firstMatch(pubspec)!.group(1)!;
    final entries = RegExp(
      r'asset: (\S+)\s+weight: (\d+)',
    ).allMatches(family).map((m) => (m.group(1)!, m.group(2)!)).toList();
    expect(entries.map((e) => e.$2), ['400', '500', '600', '700']);
    expect(entries.map((e) => e.$1).toSet(), hasLength(4));
    for (final e in entries) {
      expect(File(e.$1).existsSync(), isTrue, reason: e.$1);
    }
    final contents = entries.map((e) => File(e.$1).readAsBytesSync().length);
    expect(contents.every((n) => n > 10000), isTrue);
    final distinct = entries
        .map(
          (e) => File(
            e.$1,
          ).readAsBytesSync().fold<int>(0, (h, b) => (h * 31 + b) & 0x7fffffff),
        )
        .toSet();
    expect(distinct, hasLength(4), reason: 'static instances must differ');
  });
}
