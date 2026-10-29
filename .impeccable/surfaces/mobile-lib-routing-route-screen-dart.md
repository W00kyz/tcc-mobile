---
version: 1
slug: "mobile-lib-routing-route-screen-dart"
primary_target: "mobile/lib/routing/route_screen.dart"
related_targets: ["mobile/lib/checkin/scan_screen.dart"]
---

## Scope

Field app (Android, Flutter, Material 3), whole-app redesign. Visitor mode: Operate. Primary surface: the map home (route screen); secondary: QR camera, photo sequence camera, conclusion sheet, auth/consent/my-data/appeals/notifications screens inheriting the same world. Spec: docs/specs/2026-10-27-redesign-app-campo-design.md.

## Audience and job

Outsourced cleaning worker on the UFCG campus, walking between buildings all day, sun or basement, one hand. Job: reach the next point, scan, photograph, conclude, and know it was sent. Gamification is personal only (batch card, day progress, streak, achievements), computed from real execution data.

## Direction contract

THESIS: Each batch is a bakery loyalty card: one circle per service point, stamped with the hour on conclusion, full card when the batch closes. Refuses the category default of a blue-pin Google Maps clone with a list sheet and a progress ring glued on.

OWN-WORLD: Stone-grey paper #EDEDEA ground, graphite ink #1F1F1D, a single moss rubber-stamp ink #3E5C4A, rule grey #BDBDB6, brick #B5452F only for alerts. Hanken Grotesk for all UI; Bowlby One SC only for the card title. Circles are the one form: pins, card slots, progress dots. States by mark, not colour: stamped = done, dashed ring = next, empty = pending, struck = released. Stamps sit a few degrees off-axis with an imperfect ink edge.

STORY: The worker opens the app, sees where to go next and how full today's card is, walks, scans, shoots photos in one go, concludes, and watches the stamp land. Sync is never a doubt: a snackbar while open, an Android notification when not.

FIRST VIEWPORT: Before the route starts: the full-bleed grey campus map, the floating pill top bar (avatar, "Lote 2 · 3 de 8" with progress dots, bell) and only the full-width graphite "Iniciar rota" pill at the bottom, no sheet. Once started: every building of the day is a numbered teardrop pin (name above, route number inside; grey with a check when finished; dashed ring on the building holding the next task) joined by the graphite route line. The bottom sheet is always up, over the selected building or the next one: header "Próximo ponto" / "CAA · 1º andar" with the distance, then the floor card ("Complete 6 tarefas", one row per floor, one 48dp circle per task), then the sticky graphite "Escanear QR" footer, disabled until the worker is within 80 m of the building. Tapping an open task opens a dialog with its details, a notes field, photos, "Sinalizar impossibilidade" and "Concluir tarefa". Sync snackbar floats just above the sheet.

FORM: Cartão Fidelidade, the pick card (grounded list position 1), re-roll round 1, seed key b173a11e.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Signature interaction

Stamp drop: "Concluir tarefa" closes the dialog and the task's circle receives the moss stamp, falling from scale 1.6 (opacity 0 to 1, 260 ms, easeOutBack, turning to its own tilt), with a medium haptic at the impact and a ring of ink spreading out (1.0 to 1.35, 320 ms). "Sinalizar impossibilidade" drops the same stamp in brick with a cross. The hour is added when the floor's exit QR is scanned; the building pin updates its state and the last stamp of the batch triggers the full-card moment. Reduced motion: instant swap, no haptic.

## Unresolved

Building short code (CAA) does not exist in the data model; see spec §decisões.
