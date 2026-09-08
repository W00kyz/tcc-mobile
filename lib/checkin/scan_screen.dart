import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:route_monitor/checkin/checkin_providers.dart';
import 'package:route_monitor/checkin/qr_verifier.dart';
import 'package:route_monitor/l10n/strings.dart';

/// A pure scanner: verifies the QR signature offline (RF29, RNF13 — no
/// network in a basement) and, on a valid QR, pops with the raw scanned
/// string. It knows nothing about GPS or check-in — RouteScreen handles
/// both once it gets the raw value back.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({this.controller, super.key});

  /// Test-only override — production always lets [MobileScanner] build its
  /// own controller (and start the real camera). Widget tests inject one
  /// with `autoStart: false` so `flutter test` never touches a camera
  /// platform channel (QR doesn't work in an emulator either — CLAUDE.md).
  final MobileScannerController? controller;

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  bool _isProcessing = false;

  Future<void> _handleDetection(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final rawValue = capture.barcodes.firstOrNull?.rawValue;
    if (rawValue == null) return;

    setState(() => _isProcessing = true);

    QrPayload? payload;
    try {
      payload = await ref.read(qrVerifierProvider).verify(rawValue);
      // Belt-and-suspenders: QrVerifier.verify already catches internally
      // and returns null on any malformed/attacker-controlled QR content,
      // but a stray future exception type must still never wedge the screen
      // with _isProcessing stuck true (MobileScanner's onDetect has no
      // try/catch of its own around the callback body).
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      payload = null;
    }
    if (payload == null) {
      _showMessage(AppStrings.scanInvalidQr);
      if (mounted) setState(() => _isProcessing = false);
      return;
    }

    if (mounted) Navigator.of(context).pop(rawValue);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.scanAppBarTitle)),
      body: MobileScanner(
        controller: widget.controller,
        onDetect: _handleDetection,
      ),
    );
  }
}
