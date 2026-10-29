---
name: Cartão do Lote (Field App)
description: A Flutter field app for campus cleaning workers, built as a bakery loyalty card per building on a stone-grey map.
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
  floor-card:
    backgroundColor: "{colors.card}"
    textColor: "{colors.ink}"
    rounded: "{rounded.card}"
    padding: "12px"
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
  stamp-slot-stamped:
    textColor: "{colors.moss}"
    rounded: "{rounded.circle}"
    size: "48px"
  stamp-slot-impeded:
    textColor: "{colors.brick}"
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
    stemHeight: "10px"
  building-pin-complete:
    backgroundColor: "{colors.muted}"
    textColor: "{colors.white}"
    rounded: "{rounded.circle}"
    size: "40px"
    stemHeight: "10px"
  task-dialog:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.sheet}"
    padding: "24px"
  start-bar:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.white}"
    rounded: "{rounded.pill}"
    height: "56px"
  snackbar:
    backgroundColor: "{colors.inverse-surface}"
    textColor: "{colors.white}"
---

# Design System: Cartão do Lote (Field App)

Recorded from the shipped Flutter build (`lib/ui/app_theme.dart` and `lib/ui/*.dart`). Native platform: no detector ran and no device screenshots exist, so every value comes from source.

## Overview

**Creative North Star: "The Bakery Loyalty Card"**

Each building of the day's route is a stamp card: one circle per task, one row per floor. A task is stamped moss when the worker concludes it and the stamp falls onto the card; a task that cannot be done is stamped brick with a cross. The hour is added when the floor is checked out, and a full card is celebrated when a batch closes. The ground is stone-grey paper, the ink is graphite, a single moss stamp ink marks what is done and brick marks what is impossible. Material 3 supplies navigation and controls; the world lends only type, palette, density and the stamp gesture.

The user is a cleaning worker walking campus in sun or basement, one hand on the phone. The system is quiet, large-targeted and legible outdoors; colour is scarce so that marks can carry meaning.

**Key Characteristics:**
- Monochrome stone and graphite, one moss accent, brick only for what is impossible or wrong.
- The circle is the form for slots, progress dots and avatar; the building pin is a circle on a stem (a teardrop).
- State is read by mark (stamp, dashed ring, empty, struck), never by colour alone.
- Stamps sit a few degrees off-axis (-9 to +9 deg) with an irregular ink edge drawn in a `CustomPainter`.
- Light theme only.

## Colors

Cool stone greys with graphite ink and one muted green; no saturated hue except an alert brick.

### Primary
- **Graphite Ink** (`ink`): text, the primary button, the route line, dashed "next" rings. Also the Material `primary`.

### Secondary
- **Moss Stamp Ink** (`moss`): a task concluded or done, success, progress; the stamped and done stamp. Material `secondary`.

### Tertiary
- **Brick Alert** (`brick`): error, blocked, silence, and the impossible stamp (a task the worker could not do, drawn as a brick disc with a cross). Also the "Sinalizar impossibilidade" text action. Material `error`. Never decoration.

### Neutral
- **Stone Paper** (`paper`): app ground, sheet surface.
- **Card Grey** (`card`): the floor card, batch card and fields (`surfaceContainer*`).
- **Chalk White** (`white`): top bar, pending pins, secondary buttons, text on ink and moss.
- **Muted Graphite** (`muted`): secondary copy (AA on paper); the fill of a finished building pin.
- **Rule Grey** (`rule`): dividers, empty circles, card border (`outline`).
- **Map Ground / Road / Building** (`map-ground`, `map-road`, `map-building`): the PMTiles style in greys.
- **Inverse Surface** (`inverse-surface`): snackbar background.

Named constants outside the table, all in `app_theme.dart`: position halo (ink at 13%), QR scan scrim and overlay white, and a camera-chrome set (`kCameraChrome` #121211, dock, fade, control fill and line, slot line, soft and disabled text).

### Named Rules
**The Scarce Moss Rule.** Moss means a task is done. It is not an accent for buttons or links, and a finished building is grey, not moss.
**The Brick Is Alarm Rule.** Brick appears only when something is wrong, blocked or impossible: the error colour, the impossible stamp and the action that reports it. Done is moss and impossible is brick; there is no blue.
**The Theme-Only Colour Rule.** Screens read colour from `FieldPalette` / `ColorScheme`. A raw `Colors.*` or `Color(0x...)` outside `lib/ui/app_theme.dart` fails `test/ui/no_raw_colors_test.dart`; a colour with no token becomes a named constant in `app_theme.dart`.

## Typography

**Display Font:** Bowlby One SC (bundled asset, regular only)
**Body Font:** Hanken Grotesk (bundled 400, 500, 600, 700)

**Character:** A heavy small-caps shop-sign face for the card title against a plain, readable grotesk for everything else. Fonts ship as assets, never downloaded.

### Hierarchy
- **Display** (Bowlby One SC, 17sp, 22sp line, +0.51 tracking): the floor card title ("Complete N tarefas", "Prédio concluído") and the full-card headline only.
- **Title** (Hanken 700, 15sp): the done/total count.
- **Label** (Hanken 500, 13sp): map chip text; 600 at 13sp for floor labels; 600 at 12sp for pin names; 700 at 15sp for the number in a building pin; 600 at 11sp for slot hour; 700 at 11sp for badges.
- **Body / Caption** (Hanken 400): Material 3 default text theme with Hanken applied; 12sp muted for subtitles and 11sp muted for slot captions.

### Named Rules
**The One Display Rule.** Bowlby One SC is for the floor card title and full-card headline. Everything else is Hanken Grotesk.

## Layout

Full-bleed map with a floating pill top bar. Before the route starts (and while it is paused) there is no sheet: only the 56dp "Iniciar rota" (or "Retomar") pill, anchored at the bottom with a 16dp gutter and, when paused, a muted caption chip above it. Once the route is in progress every building of the day is a numbered pin and a bottom sheet is always shown, over the building the worker selected or, with no selection, the one holding the next task. The sheet header reads "Próximo ponto" (or "Prédio selecionado"), "Nome do prédio · Andar", and the distance. Its body is the floor card: the title, then one row per floor with its label over a wrapping row of 48dp stamp slots (8dp gaps), 12dp card padding. Touch targets are at least 48dp: the map chip reads 32dp tall inside a 48dp target, the sync indicator is a 28dp mark inside a 48dp target, stamp slots are 48dp, the primary button is 56dp.

The scan footer is sticky at every sheet height. "Escanear QR" is disabled until the worker is within 80 m of the building shown (enabled with no known position), and reads "Escanear QR de saída" once a floor is checked in, enabling only when every open task of that floor is stamped or impossible. Tapping a task that is not complete opens the task dialog.

## Elevation & Depth

Mostly tonal: paper on stone map, card grey on paper, hairline `rule` borders. The one lift is the map sheet (Material elevation 8, shadow colour `ink`). Snackbars float above the sheet via a computed bottom margin. Pins change state with a 120 ms transition; a selected pin grows 15% from its tip. A stamp lands with the one authored motion (see Stamp Slot).

### Named Rules
**The Hairline Over Shadow Rule.** Separate content with a `rule` border or tone step; only the map sheet carries a shadow.

## Shapes

The circle is the form of the slot (48dp), the progress dot and the avatar. The building pin is a 40dp circle joined to a 10dp tapered stem (a teardrop), its tip standing on the building. Containers use fixed radii: sheet top corners 28dp, task dialog 28dp, floor card 16dp, primary button a 56dp-high pill (`StadiumBorder`). Empty and next circles are drawn as rings (1.5dp plain, 2dp dashed in ink, 18 dashes); released is struck diagonally.

### Named Rules
**The Mark-Not-Colour Rule.** Slot and pin states are distinguished by mark: moss stamp with a check and the hour (rotated, irregular ink edge) is done; the same stamp with no hour and a small cloud badge is stamped, waiting for the floor's exit scan; brick stamp with a cross is impossible; dashed ink ring is next; dashed ring with pulsing dot is in progress; empty rule ring is pending; struck circle is released; a small cloud icon also marks pending sync. A building pin carries its route number, or a check on grey when finished, and a dashed ring when it holds the next task. Every slot and pin also has a semantic label.

## Components

### Buttons
- **Shape:** 56dp pill. **Primary:** ink fill, white label, Hanken 600, full width.

### Map Sheet
Draggable sheet, top corners 28dp, paper, 32x4 grip. Snaps 0.22 / 0.5 / 0.9, initial 0.5. On a short screen the closed snap grows (capped at 0.45) so the header and the scan button fit. Shown only while the route is in progress.

### Start Bar
The sheet's stand-in before the route starts and while paused: a 56dp ink pill, full width with a 16dp gutter, bottom-anchored over the map. A paused route adds a paper caption chip (16dp radius, rule border) with the reason above it.

### Floor Card
Card grey, 16dp radius, rule border, 12dp padding. Display title ("Complete N tarefas", or "Prédio concluído"), then one row per floor in route order: a 13sp 600 label over wrapping 48dp stamp slots.

### Batch Card
The same card for a whole batch, shown only in the full-card moment when a batch closes.

### Stamp Slot
48dp circle with a 11sp floor caption; the whole slot and caption is the tap target. Faces: pending, next, in progress, stamped, done, impossible, released (see the Mark-Not-Colour Rule).

The stamp drop is the one authored motion. A new stamp falls from scale 1.6 and opacity 0 to 1.0 in 260 ms (`easeOutBack`), turning from upright to its own tilt (-9 to +9 deg); at the impact a medium haptic fires and a ring of ink spreads from 1.0 to 1.35 of the stamp's radius, 35% to 0 opacity, over 320 ms. Moss for a concluded task, brick for an impossible one. Under reduced motion the swap is instant, with no haptic.

### Building Pin
A teardrop: a 40dp circle on a 10dp stem, with the building name in a small paper label above it (hidden when the map is zoomed out). White with a rule outline and its route number when pending; grey with a white check when every task is closed; the next building wears the dashed ink ring.

### Task Dialog
Paper dialog, 28dp radius, 24dp padding, a close button in the corner. Service point and "Building · Floor" at the top, then the service type and, when it needs evidence, "Exige pelo menos 2 fotos"; a notes field (2000 characters), a camera action with removable thumbnails, and two actions: "Sinalizar impossibilidade" (text, brick) and "Concluir tarefa" (filled). Without a floor check-in, photos and "Concluir tarefa" are disabled with a notice; reporting impossibility always works and opens a second dialog for the reason.

### Sync indicator and snackbars
28dp mark in a 48dp target; the snackbar lane uses the floating inverse-surface snackbar lifted over the sheet.

## Do's and Don'ts

### Do:
- **Do** take every colour from `FieldPalette` or `ColorScheme`; add a named constant in `app_theme.dart` for anything new.
- **Do** keep touch targets at 48dp or more, and the primary action a 56dp pill.
- **Do** express state by mark and semantic label, with colour as reinforcement only.
- **Do** keep the scan footer reachable at all three sheet heights, disabled (with the reason in words) rather than hidden when the worker is too far.
- **Do** honour reduced motion by swapping instantly.

### Don't:
- **Don't** use `Colors.*` or hex literals in screens.
- **Don't** use moss as a decorative accent, brick for anything but what is wrong or impossible, or blue for anything.
- **Don't** set Bowlby One SC outside the floor card title and full-card headline.
- **Don't** convey state with colour alone.
- **Don't** download fonts at runtime.
