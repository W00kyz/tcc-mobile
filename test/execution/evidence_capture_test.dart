import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:route_monitor/execution/evidence_capture.dart';

void main() {
  test(
    'takePhoto compresses the picked file (quality 70 first) and returns '
    'the compressed bytes plus their real sha256',
    () async {
      final compressedBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final qualities = <int>[];
      final capture = DeviceEvidenceCapture(
        pickImage: ({required source, maxWidth, imageQuality}) async {
          expect(source, ImageSource.camera);
          expect(maxWidth, 1600);
          expect(imageQuality, 70);
          return XFile('/fake/photo.jpg');
        },
        compress:
            (path, {quality = 70, minWidth = 1600, minHeight = 1600}) async {
              expect(path, '/fake/photo.jpg');
              expect(minWidth, 1600);
              expect(minHeight, 1600);
              qualities.add(quality);
              return compressedBytes;
            },
      );

      final result = await capture.takePhoto();

      expect(qualities, [70]);
      expect(result, isNotNull);
      expect(result!.bytes, same(compressedBytes));
      expect(result.sha256, sha256.convert(compressedBytes).toString());
    },
  );

  test(
    'returns null without compressing when the field worker cancels the '
    'camera',
    () async {
      var compressCalled = false;
      final capture = DeviceEvidenceCapture(
        pickImage: ({required source, maxWidth, imageQuality}) async => null,
        compress:
            (path, {quality = 70, minWidth = 1600, minHeight = 1600}) async {
              compressCalled = true;
              return Uint8List(0);
            },
      );

      expect(await capture.takePhoto(), isNull);
      expect(compressCalled, isFalse);
    },
  );

  test(
    'recompresses once at quality 50 when the first pass is still over '
    '~500 KB, and returns that smaller result',
    () async {
      final overTarget = Uint8List(600 * 1024);
      final underTarget = Uint8List(100 * 1024);
      final qualities = <int>[];
      final capture = DeviceEvidenceCapture(
        pickImage: ({required source, maxWidth, imageQuality}) async =>
            XFile('/fake/photo.jpg'),
        compress:
            (path, {quality = 70, minWidth = 1600, minHeight = 1600}) async {
              qualities.add(quality);
              return quality == 70 ? overTarget : underTarget;
            },
      );

      final result = await capture.takePhoto();

      expect(qualities, [70, 50]);
      expect(result!.bytes, same(underTarget));
      expect(result.sha256, sha256.convert(underTarget).toString());
    },
  );

  test(
    'keeps the first-pass result when a quality-50 recompress somehow fails '
    '(returns null) instead of losing the photo',
    () async {
      final overTarget = Uint8List(600 * 1024);
      var calls = 0;
      final capture = DeviceEvidenceCapture(
        pickImage: ({required source, maxWidth, imageQuality}) async =>
            XFile('/fake/photo.jpg'),
        compress:
            (path, {quality = 70, minWidth = 1600, minHeight = 1600}) async {
              calls++;
              return calls == 1 ? overTarget : null;
            },
      );

      final result = await capture.takePhoto();

      expect(result!.bytes, same(overTarget));
    },
  );

  test(
    'throws a descriptive StateError when the first compression pass '
    'returns null',
    () async {
      final capture = DeviceEvidenceCapture(
        pickImage: ({required source, maxWidth, imageQuality}) async =>
            XFile('/fake/photo.jpg'),
        compress:
            (path, {quality = 70, minWidth = 1600, minHeight = 1600}) async =>
                null,
      );

      await expectLater(
        capture.takePhoto(),
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

  test(
    'returns null when the camera platform call itself throws (no camera, '
    'permission denied)',
    () async {
      final capture = DeviceEvidenceCapture(
        pickImage: ({required source, maxWidth, imageQuality}) async =>
            throw StateError('camera unavailable'),
        compress:
            (path, {quality = 70, minWidth = 1600, minHeight = 1600}) async =>
                Uint8List(0),
      );

      expect(await capture.takePhoto(), isNull);
    },
  );
}
