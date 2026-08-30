import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// The Dart counterpart of app.domain.qr.crypto (backend Task 7) — same
/// payload format `v1.<floor_id>.<version>.<signature_b64url>`, verified
/// fully offline, no network call (RF29, RNF13: a basement has no signal).
class QrPayload {
  const QrPayload({required this.floorId, required this.version});
  final String floorId;
  final int version;
}

class QrVerifier {
  QrVerifier(this._publicKeyHex);

  final String _publicKeyHex;
  static final _algorithm = Ed25519();

  Future<QrPayload?> verify(String payload) async {
    final parts = payload.split('.');
    if (parts.length != 4 || parts[0] != 'v1') return null;

    // floorId's shape (UUID or not) is never checked here, unlike the
    // backend — not exploitable: it only survives below if it carries a
    // valid signature from the server's private key, and ScanScreen doesn't
    // read it back out, it forwards the raw rawValue and lets the backend
    // do the floor cross-reference.
    final floorId = parts[1];
    final version = int.tryParse(parts[2]);
    if (version == null) return null;

    try {
      final signatureBytes = base64Url.decode(base64Url.normalize(parts[3]));
      final signable = utf8.encode('v1.$floorId.$version');
      final publicKey = SimplePublicKey(
        _hexToBytes(_publicKeyHex),
        type: KeyPairType.ed25519,
      );
      final isValid = await _algorithm.verify(
        signable,
        signature: Signature(signatureBytes, publicKey: publicKey),
      );

      return isValid ? QrPayload(floorId: floorId, version: version) : null;
      // Deliberately broad: a well-formed-base64-but-wrong-length signature
      // (cryptography's ArgumentError/StateError, e.g. "Ed25519 signature
      // must be 64 bytes") or a malformed QR_PUBLIC_KEY_HEX build-define
      // (ArgumentError/FormatException from _hexToBytes/SimplePublicKey)
      // must never crash the scanner — the QR content is attacker/typo-
      // controlled and there is no signal underground to fall back on
      // (RF29, RNF13), so any failure here just means "not a valid QR".
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return null;
    }
  }
}

Uint8List _hexToBytes(String hex) {
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < hex.length; i += 2) {
    bytes[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
  }
  return bytes;
}
