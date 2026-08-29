/// Build-time configuration, never hardcoded (docs/CLAUDE.base.md,
/// mobile/CLAUDE.md — QR/GPS don't exist in an emulator, and the base
/// address changes with the test network).
///
/// Usage:
///     flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000 \
///                  --dart-define=QR_PUBLIC_KEY_HEX=<output of backend Task 7>
library;

String apiBaseUrlFromEnvironment() {
  const value = String.fromEnvironment('API_BASE_URL');
  if (value.isEmpty) {
    throw StateError(
      'API_BASE_URL not set; pass '
      '--dart-define=API_BASE_URL=http://<host>:8000.',
    );
  }
  return value;
}

String qrPublicKeyHexFromEnvironment() {
  const value = String.fromEnvironment('QR_PUBLIC_KEY_HEX');
  if (value.isEmpty) {
    throw StateError(
      'QR_PUBLIC_KEY_HEX not set; run '
      '`uv run python -m app.scripts.generate_qr_keypair` in the backend '
      'and pass --dart-define=QR_PUBLIC_KEY_HEX=<value>.',
    );
  }
  return value;
}
