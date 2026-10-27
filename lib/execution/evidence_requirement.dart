import 'dart:math';

/// The photos a stop that requires evidence needs before "Concluir" opens
/// (spec 2026-10-26-exige-evidencias §6.4). The backend does not refuse a
/// short check-out, it flags `INSUFFICIENT_EVIDENCE`: this is the real gate.
const int minEvidencePhotos = 2;

/// The most photos one such stop takes, app-side only. Stops that do not
/// require evidence stay unlimited, as before.
const int maxEvidencePhotos = 10;

/// How many photos are still missing, never negative.
///
/// ```dart
/// missingEvidencePhotos(1); // 1
/// ```
int missingEvidencePhotos(int photoCount) =>
    max(0, minEvidencePhotos - photoCount);

/// Whether "Concluir" may be offered. [photoCount] is `null` while the count
/// is still loading: never release before knowing.
bool canConcludeWithEvidence({
  required bool requiresEvidence,
  required int? photoCount,
}) {
  if (!requiresEvidence) return true;
  if (photoCount == null) return false;
  return photoCount >= minEvidencePhotos;
}

/// Whether "Adicionar foto" is still enabled: capped only on a stop that
/// requires evidence.
bool canAddEvidencePhoto({
  required bool requiresEvidence,
  required int photoCount,
}) => !requiresEvidence || photoCount < maxEvidencePhotos;
