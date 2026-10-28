import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// An already-compressed photo, ready for `ExecutionRepository.addPhoto`.
class CapturedPhoto {
  const CapturedPhoto({required this.bytes, required this.sha256});

  final Uint8List bytes;
  final String sha256;
}

/// [FlutterImageCompress.compressWithFile]'s call shape, narrowed to what
/// [compressCapturedFile] uses — injectable so its test never reaches the
/// platform channel.
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

/// Compresses the camera file at [path] and returns the bytes plus their
/// sha256. Throws a [StateError] if the first pass produces nothing; a failed
/// second pass keeps the first result rather than losing the photo.
Future<CapturedPhoto> compressCapturedFile(
  String path, {
  CompressFile compress = FlutterImageCompress.compressWithFile,
}) async {
  var compressed = await compress(
    path,
    quality: 70,
    minWidth: 1600,
    minHeight: 1600,
  );
  if (compressed == null) {
    throw StateError('Photo compression failed for "$path".');
  }
  if (compressed.lengthInBytes > _targetBytes) {
    final recompressed = await compress(
      path,
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
