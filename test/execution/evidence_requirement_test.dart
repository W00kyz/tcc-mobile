import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/evidence_requirement.dart';

void main() {
  group('canConcludeWithEvidence', () {
    test('is false below the minimum, or while the count is loading', () {
      for (final count in <int?>[null, 0, 1]) {
        expect(
          canConcludeWithEvidence(requiresEvidence: true, photoCount: count),
          isFalse,
          reason: 'photoCount=$count',
        );
      }
    });

    test('is true with the minimum number of photos', () {
      expect(
        canConcludeWithEvidence(requiresEvidence: true, photoCount: 2),
        isTrue,
      );
    });

    test('is always true for a stop that does not require evidence', () {
      expect(
        canConcludeWithEvidence(requiresEvidence: false, photoCount: null),
        isTrue,
      );
    });
  });

  test('missingEvidencePhotos counts down to zero', () {
    expect(missingEvidencePhotos(0), 2);
    expect(missingEvidencePhotos(1), 1);
    expect(missingEvidencePhotos(5), 0);
  });

  group('canAddEvidencePhoto', () {
    test('stops at the cap on a stop that requires evidence', () {
      expect(
        canAddEvidencePhoto(requiresEvidence: true, photoCount: 9),
        isTrue,
      );
      expect(
        canAddEvidencePhoto(requiresEvidence: true, photoCount: 10),
        isFalse,
      );
    });

    test('has no cap on a stop that does not require evidence', () {
      expect(
        canAddEvidencePhoto(requiresEvidence: false, photoCount: 50),
        isTrue,
      );
    });
  });
}
