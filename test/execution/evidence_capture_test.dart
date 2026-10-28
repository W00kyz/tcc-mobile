import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/evidence_capture.dart';

void main() {
  test(
    'compressCapturedFile compresses the file (quality 70 first, side <= '
    '1600) and returns the bytes plus their real sha256',
    () async {
      final compressedBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final qualities = <int>[];

      final result = await compressCapturedFile(
        '/fake/photo.jpg',
        compress:
            (path, {quality = 70, minWidth = 1600, minHeight = 1600}) async {
              expect(path, '/fake/photo.jpg');
              expect(minWidth, 1600);
              expect(minHeight, 1600);
              qualities.add(quality);
              return compressedBytes;
            },
      );

      expect(qualities, [70]);
      expect(result.bytes, same(compressedBytes));
      expect(result.sha256, sha256.convert(compressedBytes).toString());
    },
  );

  test(
    'recompresses once at quality 50 when the first pass is still over '
    '~500 KB, and returns that smaller result',
    () async {
      final overTarget = Uint8List(600 * 1024);
      final underTarget = Uint8List(100 * 1024);
      final qualities = <int>[];

      final result = await compressCapturedFile(
        '/fake/photo.jpg',
        compress:
            (path, {quality = 70, minWidth = 1600, minHeight = 1600}) async {
              qualities.add(quality);
              return quality == 70 ? overTarget : underTarget;
            },
      );

      expect(qualities, [70, 50]);
      expect(result.bytes, same(underTarget));
      expect(result.sha256, sha256.convert(underTarget).toString());
    },
  );

  test(
    'keeps the first-pass result when a quality-50 recompress somehow fails '
    '(returns null) instead of losing the photo',
    () async {
      final overTarget = Uint8List(600 * 1024);
      var calls = 0;

      final result = await compressCapturedFile(
        '/fake/photo.jpg',
        compress:
            (path, {quality = 70, minWidth = 1600, minHeight = 1600}) async {
              calls++;
              return calls == 1 ? overTarget : null;
            },
      );

      expect(result.bytes, same(overTarget));
    },
  );

  test(
    'throws a descriptive StateError when the first compression pass '
    'returns null',
    () async {
      await expectLater(
        compressCapturedFile(
          '/fake/photo.jpg',
          compress:
              (path, {quality = 70, minWidth = 1600, minHeight = 1600}) async =>
                  null,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('/fake/photo.jpg'),
          ),
        ),
      );
    },
  );
}
