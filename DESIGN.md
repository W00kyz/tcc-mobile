---
name: Cartão do Lote (Field App)
description: A Flutter field app for campus cleaning workers, built as a bakery loyalty card on a stone-grey map.
colors:
  paper: "#EDEDEA"
  card: "#DEDED9"
  white: "#FAFAF8"
  ink: "#1F1F1D"
  muted: "#55554F"
  moss: "#3E5C4A"
  rule: "#BDBDB6"
  brick: "#B5452F"
  map-ground: "#E3E3DF"
  map-road: "#F4F4F1"
  map-building: "#D6D6D1"
  inverse-surface: "#2F2F2C"
typography:
  display-card:
    fontFamily: "Bowlby One SC"
    fontSize: "17sp"
    fontWeight: 400
    lineHeight: "22sp"
    letterSpacing: "0.51sp"
  title-count:
    fontFamily: "Hanken Grotesk"
    fontSize: "15sp"
    fontWeight: 700
  body:
    fontFamily: "Hanken Grotesk"
    fontSize: "14sp"
    fontWeight: 400
  label-chip:
    fontFamily: "Hanken Grotesk"
    fontSize: "13sp"
    fontWeight: 500
  caption:
    fontFamily: "Hanken Grotesk"
    fontSize: "12sp"
    fontWeight: 400
  label-stamp:
    fontFamily: "Hanken Grotesk"
    fontSize: "11sp"
    fontWeight: 700
rounded:
  sheet: "28px"
  card: "16px"
  pill: "9999px"
  circle: "50%"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  touch-min: "48px"
components:
  button-primary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.white}"
    rounded: "{rounded.pill}"
    height: "56px"
  map-sheet:
    backgroundColor: "{colors.paper}"
    rounded: "{rounded.sheet}"
  batch-card:
    backgroundColor: "{colors.card}"
    textColor: "{colors.ink}"
    rounded: "{rounded.card}"
    padding: "12px"
  stamp-slot-done:
    backgroundColor: "{colors.moss}"
    textColor: "{colors.white}"
    rounded: "{rounded.circle}"
    size: "48px"
  stamp-slot-pending:
    backgroundColor: "{colors.white}"
    rounded: "{rounded.circle}"
    size: "48px"
  building-pin:
    backgroundColor: "{colors.white}"
    textColor: "{colors.ink}"
    rounded: "{rounded.circle}"
    size: "40px"
  building-pin-complete:
    backgroundColor: "{colors.moss}"
    textColor: "{colors.white}"
    rounded: "{rounded.circle}"
  snackbar:
    backgroundColor: "{colors.inverse-surface}"
    textColor: "{colors.white}"
---

# Design System: Cartão do Lote (Field App)

Recorded from the shipped Flutter build (`lib/ui/app_theme.dart` and `lib/ui/*.dart`). Native platform: no detector ran and no device screenshots exist, so every value comes from source.

## Overview

**Creative North Star: "The Bakery Loyalty Card"**

Each batch of service points is a stamp card: one circle per point, stamped moss with the hour on conclusion, a full card when the batch closes. The ground is stone-grey paper, the ink is graphite, and a single moss stamp ink marks what is done. Material 3 supplies navigation and controls; the world lends only type, palette, density and the stamp gesture.

The user is a cleaning worker walking campus in sun or basement, one hand on the phone. The system is quiet, large-targeted and legible outdoors; colour is scarce so that marks can carry meaning.

**Key Characteristics:**
- Monochrome stone and graphite, one moss accent, brick only for alerts.
- The circle is the only form for pins, slots, progress dots and avatar.
- State is read by mark (stamp, dashed ring, empty, struck), never by colour alone.
- Stamps sit a few degrees off-axis (-9 to +9 deg) with an irregular ink edge drawn in a `CustomPainter`.
- Light theme only.

## Colors

Cool stone greys with graphite ink and one muted green; no saturated hue except an alert brick.

### Primary
- **Graphite Ink** (`ink`): text, the primary button, the route line, dashed "next" rings. Also the Material `primary`.

### Secondary
- **Moss Stamp Ink** (`moss`): done, success, progress; filled stamp and complete building pin. Material `secondary`.

### Tertiary
- **Brick Alert** (`brick`): error, blocked, silence. Material `error`. Never decoration.

### Neutral
- **Stone Paper** (`paper`): app ground, sheet surface.
- **Card Grey** (`card`): the batch card and fields (`surfaceContainer*`).
- **Chalk White** (`white`): top bar, pending pins, secondary buttons, text on ink and moss.
- **Muted Graphite** (`muted`): secondary copy (AA on paper).
- **Rule Grey** (`rule`): dividers, empty circles, card border (`outline`).
- **Map Ground / Road / Building** (`map-ground`, `map-road`, `map-building`): the PMTiles style in greys.
- **Inverse Surface** (`inverse-surface`): snackbar background.

Named constants outside the table, all in `app_theme.dart`: position halo (ink at 13%), QR scan scrim and overlay white, and a camera-chrome set (`kCameraChrome` #121211, dock, fade, control fill and line, slot line, soft and disabled text).

### Named Rules
**The Scarce Moss Rule.** Moss means a point or building is done. It is not an accent for buttons or links.
**The Brick Is Alarm Rule.** Brick appears only when something is wrong or blocked.
**The Theme-Only Colour Rule.** Screens read colour from `FieldPalette` / `ColorScheme`. A raw `Colors.*` or `Color(0x...)` outside `lib/ui/app_theme.dart` fails `test/ui/no_raw_colors_test.dart`; a colour with no token becomes a named constant in `app_theme.dart`.

## Typography

**Display Font:** Bowlby One SC (bundled asset, regular only)
**Body Font:** Hanken Grotesk (bundled 400, 500, 600, 700)

**Character:** A heavy small-caps shop-sign face for the card title against a plain, readable grotesk for everything else. Fonts ship as assets, never downloaded.

### Hierarchy
- **Display** (Bowlby One SC, 17sp, 22sp line, +0.51 tracking): "Cartão do Lote N" title and the full-card headline only.
- **Title** (Hanken 700, 15sp): the done/total count.
- **Label** (Hanken 500, 13sp): map chip text; 600 at 12sp for pin labels; 600 at 11sp for slot hour; 700 at 11sp for badges.
- **Body / Caption** (Hanken 400): Material 3 default text theme with Hanken applied; 12sp muted for subtitles and 11sp muted for slot captions.

### Named Rules
**The One Display Rule.** Bowlby One SC is for the card title and full-card headline. Everything else is Hanken Grotesk.

## Layout

Full-bleed map with a floating pill top bar and a bottom sheet. The batch card is a 4-column slot grid, grouped per building; past 12 stops (3 rows) the grid scrolls inside the card (max 300dp). Card padding 12dp, group gap 8dp. Touch targets are at least 48dp: the map chip reads 32dp tall inside a 48dp target, the sync indicator is a 28dp mark inside a 48dp target, stamp slots are 48dp, the primary button is 56dp. The "Escanear QR" button is a sticky footer visible at every sheet height.

## Elevation & Depth

Mostly tonal: paper on stone map, card grey on paper, hairline `rule` borders. The one lift is the map sheet (Material elevation 8, shadow colour `ink`). Snackbars float above the sheet via a computed bottom margin. Pins change state with a 120 ms transition.

### Named Rules
**The Hairline Over Shadow Rule.** Separate content with a `rule` border or tone step; only the map sheet carries a shadow.

## Shapes

The circle is the only form: building pin (40dp), batch-card slot (48dp), progress dot, avatar. Containers use fixed radii: sheet top corners 28dp, batch card 16dp, primary button a 56dp-high pill (`StadiumBorder`). Empty and next circles are drawn as rings (1.5dp plain, 2dp dashed in ink, 18 dashes); released is struck diagonally.

### Named Rules
**The Mark-Not-Colour Rule.** Slot and pin states are distinguished by mark: stamped (moss disc, check, hour, rotated) is done; dashed ink ring is next; dashed ring with pulsing dot is in progress; empty rule ring is pending; struck circle is released; a small cloud icon marks pending sync. Every slot also has a semantic label.

## Components

### Buttons
- **Shape:** 56dp pill. **Primary:** ink fill, white label, Hanken 600, full width.

### Map Sheet
Draggable sheet, top corners 28dp, paper, 32x4 grip. Snaps 0.22 / 0.5 / 0.9, initial 0.5. On a short screen the closed snap grows (capped at 0.45) so the next-stop row and the scan button fit.

### Batch Card
Card grey, 16dp radius, rule border, 12dp padding; Display title, muted subtitle and count, then per-building slot groups.

### Stamp Slot
48dp circle. Stamp press: scale 1.15 to 1 over 220 ms with a light haptic; skipped under reduced motion.

### Building Pin
40dp circle with code and an n/m badge; white with rule outline when pending, dashed when it holds the next or in-progress stop, moss when every point is done.

### Sync indicator and snackbars
28dp mark in a 48dp target; the snackbar lane uses the floating inverse-surface snackbar lifted over the sheet.

## Do's and Don'ts

### Do:
- **Do** take every colour from `FieldPalette` or `ColorScheme`; add a named constant in `app_theme.dart` for anything new.
- **Do** keep touch targets at 48dp or more, and the primary action a 56dp pill.
- **Do** express state by mark and semantic label, with colour as reinforcement only.
- **Do** keep the "Escanear QR" action reachable at all three sheet heights.
- **Do** honour reduced motion by swapping instantly.

### Don't:
- **Don't** use `Colors.*` or hex literals in screens.
- **Don't** use moss as a decorative accent or brick for anything but alerts.
- **Don't** set Bowlby One SC outside the card title and full-card headline.
- **Don't** convey state with colour alone.
- **Don't** download fonts at runtime.
