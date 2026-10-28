import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

/// An already-compressed photo, ready for `ExecutionRepository.addPhoto`.
class CapturedPhoto {
  const CapturedPhoto({required this.bytes, required this.sha256});

  final Uint8List bytes;
  final String sha256;
}

/// The seam over `image_picker` + `flutter_image_compress` (Ruling 11, Etapa
/// 5 design §6.4 — the OS camera app, not the `camera` package) that keeps
/// the map home's tests off the platform camera channel (docs/
/// CLAUDE.base.md — "wrap third-party libs behind a thin interface").
// ignore: one_member_abstracts
abstract class EvidenceCapture {
  /// Opens the device's camera app and returns the compressed photo plus its
  /// sha256, or null if the field worker cancels the camera.
  Future<CapturedPhoto?> takePhoto();
}

/// [ImagePicker.pickImage]'s call shape, narrowed to what
/// [DeviceEvidenceCapture] uses — injectable so its test never opens a real
/// camera.
typedef PickImage =
    Future<XFile?> Function({
      required ImageSource source,
      double? maxWidth,
      int? imageQuality,
    });

/// [FlutterImageCompress.compressWithFile]'s call shape, narrowed the same
/// way.
typedef CompressFile =
    Future<Uint8List?> Function(
      String path, {
      int quality,
      int minWidth,
      int minHeight,
    });

/// Spec §6.3: side ≤ 1600 px, JPEG quality 70, target ≤ ~500 KB — one
/// recompress pass at quality 50 if the first pass is still over that.
const int _targetBytes = 500 * 1024;

class DeviceEvidenceCapture implements EvidenceCapture {
  DeviceEvidenceCapture({PickImage? pickImage, CompressFile? compress})
    : _pickImage = pickImage ?? ImagePicker().pickImage,
      _compress = compress ?? FlutterImageCompress.compressWithFile;

  final PickImage _pickImage;
  final CompressFile _compress;

  @override
  Future<CapturedPhoto?> takePhoto() async {
    final file = await _openCamera();
    if (file == null) return null;

    var compressed = await _compress(
      file.path,
      quality: 70,
      minWidth: 1600,
      minHeight: 1600,
    );
    if (compressed == null) {
      throw StateError('Photo compression failed for "${file.path}".');
    }
    if (compressed.lengthInBytes > _targetBytes) {
      final recompressed = await _compress(
        file.path,
        quality: 50,
        minWidth: 1600,
        minHeight: 1600,
      );
      if (recompressed != null) compressed = recompressed;
    }
    return CapturedPhoto(
      bytes: compressed,
      sha256: sha256.convert(compressed).toString(),
    );
  }

  Future<XFile?> _openCamera() async {
    try {
      return await _pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 70,
      );
      // Deliberately broad, same discipline as LocationService/QrVerifier:
      // the OS camera app / image_picker plugin can fail with a
      // PlatformException (no camera, permission denied) — treated the same
      // as "the field worker didn't get a photo" rather than crashing the
      // stop screen.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return null;
    }
  }
}
