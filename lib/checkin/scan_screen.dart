import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:route_monitor/checkin/checkin_providers.dart';
import 'package:route_monitor/checkin/qr_verifier.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/route_providers.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({required this.routeStopId, super.key});

  final String routeStopId;

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
      _showMessage('QR Code inválido ou adulterado.');
      if (mounted) setState(() => _isProcessing = false);
      return;
    }

    final Coordinates position;
    try {
      position = await ref.read(locationServiceProvider).getCurrentPosition();
      // Deliberately broad: GeolocatorLocationService can fail with a
      // StateError (permission denied), a platform exception, or a timeout
      // — all of them map to the same user-facing message here.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      _showMessage('Não foi possível obter sua localização.');
      if (mounted) setState(() => _isProcessing = false);
      return;
    }

    try {
      await ref
          .read(checkInRepositoryProvider)
          .checkIn(
            routeStopId: widget.routeStopId,
            qrPayload: rawValue,
            latitude: position.latitude,
            longitude: position.longitude,
          );
      ref.invalidate(myRoutesProvider);
      if (mounted) Navigator.of(context).pop();
      // Deliberately broad: DioCheckInRepository can fail with a DioException
      // (network/HTTP) or another unexpected error — all map to the same
      // user-facing message here.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      _showMessage('Não foi possível registrar o check-in.');
      if (mounted) setState(() => _isProcessing = false);
    }
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
      appBar: AppBar(title: const Text('Ler QR Code')),
      body: MobileScanner(onDetect: _handleDetection),
    );
  }
}
