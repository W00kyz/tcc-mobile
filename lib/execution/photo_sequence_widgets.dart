import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/local_write_store.dart' show PendingOpState;
import 'package:route_monitor/ui/app_theme.dart';

/// One photo taken in this session: its outbox row id and its bytes.
class SessionShot {
  const SessionShot({required this.id, required this.bytes});

  final String id;
  final Uint8List bytes;
}

/// Where a shot's outbox row stands, as the strip and the viewer show it.
enum ShotStatus { delivered, notSent, blocked }

/// The status of a shot whose outbox row is in [state]; null means the row
/// is no longer unsent nor blocked, i.e. delivered (synced rows are not
/// listed by the store's unsent/blocked queries).
///
///     shotStatusFor(PendingOpState.sending); // ShotStatus.notSent
ShotStatus shotStatusFor(PendingOpState? state) => switch (state) {
  null || PendingOpState.synced => ShotStatus.delivered,
  PendingOpState.blocked => ShotStatus.blocked,
  PendingOpState.pending ||
  PendingOpState.failed ||
  PendingOpState.sending ||
  PendingOpState.held => ShotStatus.notSent,
};

/// Only a row no sync worker holds and the server never took can go:
/// `sending` is in flight, `synced` is delivered (`deletePendingPhoto`).
bool shotDeletable(PendingOpState? state) =>
    state == PendingOpState.pending ||
    state == PendingOpState.failed ||
    state == PendingOpState.held ||
    state == PendingOpState.blocked;

FieldPalette _palette(BuildContext context) =>
    Theme.of(context).extension<FieldPalette>()!;

/// The "n de min obrigatórias" / "n fotos" pill over the viewfinder.
class CounterPill extends StatelessWidget {
  const CounterPill({required this.count, required this.minimum, super.key});

  final int count;
  final int? minimum;

  @override
  Widget build(BuildContext context) {
    final p = _palette(context);
    final min = minimum;
    final label = min == null
        ? AppStrings.photoSequenceCounter(count)
        : AppStrings.photoSequenceRequiredCounter(count, min);
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: p.white,
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: p.ink,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A taken photo in the strip: 60dp square, tap opens it large.
class ShotThumbnail extends StatelessWidget {
  const ShotThumbnail({
    required this.shot,
    required this.number,
    required this.status,
    required this.onTap,
    super.key,
  });

  final SessionShot shot;
  final int number;
  final ShotStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = _palette(context);
    return Semantics(
      button: true,
      label: AppStrings.photoSequencePhoto(number),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.white, width: 2),
            image: DecorationImage(
              image: MemoryImage(shot.bytes),
              fit: BoxFit.cover,
            ),
          ),
          child: Align(
            alignment: Alignment.bottomRight,
            child: _Badge(number: number, status: status),
          ),
        ),
      ),
    );
  }
}

/// Delivered: a cloud with a tick. Blocked: a brick disc with a crossed
/// cloud — shape and colour both, never colour alone (spec §5). Not sent
/// yet: the shot's number.
class _Badge extends StatelessWidget {
  const _Badge({required this.number, required this.status});

  final int number;
  final ShotStatus status;

  @override
  Widget build(BuildContext context) {
    final p = _palette(context);
    final blocked = status == ShotStatus.blocked;
    return Container(
      margin: const EdgeInsets.all(3),
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: blocked ? p.brick : p.ink,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: _content(p),
    );
  }

  Widget _content(FieldPalette p) => switch (status) {
    ShotStatus.delivered => Icon(Icons.cloud_done, size: 12, color: p.white),
    ShotStatus.blocked => Icon(Icons.cloud_off, size: 12, color: p.white),
    ShotStatus.notSent => Text(
      '$number',
      style: TextStyle(
        color: p.white,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  };
}

/// A dashed empty slot for a photo still required.
class PendingSlot extends StatelessWidget {
  const PendingSlot({required this.number, super.key});

  final int number;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppStrings.photoSequencePending(number),
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kCameraSlotLine, width: 2),
        ),
        alignment: Alignment.center,
        child: Text(
          '$number',
          style: const TextStyle(
            color: kCameraSoftText,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// The round shutter, 72dp.
class ShutterButton extends StatelessWidget {
  const ShutterButton({required this.onTap, super.key});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = _palette(context);
    return Semantics(
      button: true,
      label: AppStrings.photoSequenceShutter,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 80,
          height: 80,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: p.white, width: 3),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: onTap == null ? kCameraDisabledText : p.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// "Pronto" with the "Falta n" caption below it while disabled.
class DoneButton extends StatelessWidget {
  const DoneButton({required this.missing, required this.onTap, super.key});

  final int missing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = _palette(context);
    final enabled = onTap != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: enabled ? p.white : kCameraControlFill,
          shape: StadiumBorder(
            side: BorderSide(
              color: enabled ? p.white : kCameraControlLine,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: Container(
              height: 48,
              constraints: const BoxConstraints(minWidth: 96),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              alignment: Alignment.center,
              child: Text(
                AppStrings.photoSequenceDone,
                style: TextStyle(
                  color: enabled ? p.ink : kCameraDisabledText,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        if (!enabled && missing > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              AppStrings.photoSequenceMissing(missing),
              style: const TextStyle(color: kCameraSoftText, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
