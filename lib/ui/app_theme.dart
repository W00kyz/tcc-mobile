import 'package:flutter/material.dart';

/// Family name of the bundled UI font (pubspec `flutter.fonts`).
const String kUiFont = 'HankenGrotesk';

/// Family name of the bundled display font, used only for the card title and
/// the full-card headline.
const String kDisplayFont = 'BowlbyOneSC';

/// Snackbar surface (not part of the token table).
const Color kInverseSurface = Color(0xFF2F2F2C);

/// Field-app colour tokens (spec section 6.1). Read with
/// `Theme.of(context).extension<FieldPalette>()!`.
@immutable
class FieldPalette extends ThemeExtension<FieldPalette> {
  const FieldPalette({
    required this.paper,
    required this.card,
    required this.white,
    required this.ink,
    required this.muted,
    required this.moss,
    required this.rule,
    required this.brick,
    required this.mapGround,
    required this.mapRoad,
    required this.mapBuilding,
  });

  static const FieldPalette light = FieldPalette(
    paper: Color(0xFFEDEDEA),
    card: Color(0xFFDEDED9),
    white: Color(0xFFFAFAF8),
    ink: Color(0xFF1F1F1D),
    muted: Color(0xFF55554F),
    moss: Color(0xFF3E5C4A),
    rule: Color(0xFFBDBDB6),
    brick: Color(0xFFB5452F),
    mapGround: Color(0xFFE3E3DF),
    mapRoad: Color(0xFFF4F4F1),
    mapBuilding: Color(0xFFD6D6D1),
  );

  final Color paper;
  final Color card;
  final Color white;
  final Color ink;
  final Color muted;
  final Color moss;
  final Color rule;
  final Color brick;
  final Color mapGround;
  final Color mapRoad;
  final Color mapBuilding;

  @override
  FieldPalette copyWith({
    Color? paper,
    Color? card,
    Color? white,
    Color? ink,
    Color? muted,
    Color? moss,
    Color? rule,
    Color? brick,
    Color? mapGround,
    Color? mapRoad,
    Color? mapBuilding,
  }) => FieldPalette(
    paper: paper ?? this.paper,
    card: card ?? this.card,
    white: white ?? this.white,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    moss: moss ?? this.moss,
    rule: rule ?? this.rule,
    brick: brick ?? this.brick,
    mapGround: mapGround ?? this.mapGround,
    mapRoad: mapRoad ?? this.mapRoad,
    mapBuilding: mapBuilding ?? this.mapBuilding,
  );

  @override
  FieldPalette lerp(ThemeExtension<FieldPalette>? other, double t) {
    if (other is! FieldPalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return FieldPalette(
      paper: l(paper, other.paper),
      card: l(card, other.card),
      white: l(white, other.white),
      ink: l(ink, other.ink),
      muted: l(muted, other.muted),
      moss: l(moss, other.moss),
      rule: l(rule, other.rule),
      brick: l(brick, other.brick),
      mapGround: l(mapGround, other.mapGround),
      mapRoad: l(mapRoad, other.mapRoad),
      mapBuilding: l(mapBuilding, other.mapBuilding),
    );
  }
}

ThemeData buildAppTheme() {
  const p = FieldPalette.light;
  final scheme = ColorScheme(
    brightness: Brightness.light,
    primary: p.ink,
    onPrimary: p.white,
    secondary: p.moss,
    onSecondary: p.white,
    error: p.brick,
    onError: p.white,
    surface: p.paper,
    onSurface: p.ink,
    onSurfaceVariant: p.muted,
    surfaceContainerLowest: p.white,
    surfaceContainerLow: p.paper,
    surfaceContainer: p.card,
    surfaceContainerHigh: p.card,
    surfaceContainerHighest: p.card,
    outline: p.rule,
    outlineVariant: p.rule,
    inverseSurface: kInverseSurface,
    onInverseSurface: p.white,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.paper,
    fontFamily: kUiFont,
    extensions: const [p],
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: kUiFont,
      bodyColor: p.ink,
      displayColor: p.ink,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.ink,
        foregroundColor: p.white,
        minimumSize: const Size.fromHeight(56),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontFamily: kUiFont,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: kInverseSurface,
      contentTextStyle: TextStyle(fontFamily: kUiFont, color: p.white),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.paper,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
  );
}
