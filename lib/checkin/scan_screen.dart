import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:route_monitor/checkin/checkin_providers.dart';
import 'package:route_monitor/checkin/qr_verifier.dart';
import 'package:route_monitor/checkin/scan_overlay.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/ui/app_theme.dart';

/// What the scan is for; picks the context line under the frame.
sealed class ScanContext {
  const ScanContext(this.buildingName);
  final String buildingName;

  String get label;
}

/// Check-in scan: `Entrada · <prédio>`.
class EntryScan extends ScanContext {
  const EntryScan(super.buildingName);

  @override
  String get label => AppStrings.scanEntryContext(buildingName);
}

/// Check-out scan: `Saída · <prédio> · <andar>`.
class ExitScan extends ScanContext {
  const ExitScan(super.buildingName, this.floorLabel);
  final String floorLabel;

  @override
  String get label => AppStrings.scanExitContext(buildingName, floorLabel);
}

enum _ScanFeedback { idle, valid, invalid }

const _invalidStripDuration = Duration(seconds: 3);

/// A pure scanner: verifies the QR signature offline (RF29, RNF13 — no
/// network in a basement) and, on a valid QR, pops with the raw scanned
/// string. It knows nothing about GPS or check-in — `stop_actions.dart`
/// handles both once it gets the raw value back.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({required this.context, this.controller, super.key});

  /// Entry or exit: only changes the line under the frame.
  final ScanContext context;

  /// Test-only override — production builds its own controller (and starts
  /// the real camera). Widget tests inject one with `autoStart: false` so
  /// `flutter test` never touches a camera platform channel (QR doesn't
  /// work in an emulator either — CLAUDE.md).
  final MobileScannerController? controller;

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  late final MobileScannerController _controller =
      widget.controller ?? MobileScannerController();
  bool _isProcessing = false;
  _ScanFeedback _feedback = _ScanFeedback.idle;
  Timer? _stripTimer;

  @override
  void dispose() {
    _stripTimer?.cancel();
    if (widget.controller == null) unawaited(_controller.dispose());
    super.dispose();
  }

  Future<void> _handleDetection(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final rawValue = capture.barcodes.firstOrNull?.rawValue;
    if (rawValue == null) return;

    setState(() => _isProcessing = true);
    final payload = await _verify(rawValue);
    if (!mounted) return;
    if (payload == null) return _rejectCode();

    setState(() => _feedback = _ScanFeedback.valid);
    unawaited(HapticFeedback.mediumImpact());
    Navigator.of(context).pop(rawValue);
  }

  Future<QrPayload?> _verify(String rawValue) async {
    try {
      return await ref.read(qrVerifierProvider).verify(rawValue);
      // Belt-and-suspenders: QrVerifier.verify already catches internally
      // and returns null on any malformed/attacker-controlled QR content,
      // but a stray future exception type must still never wedge the screen
      // with _isProcessing stuck true.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return null;
    }
  }

  void _rejectCode() {
    _stripTimer?.cancel();
    _stripTimer = Timer(_invalidStripDuration, () {
      if (mounted) setState(() => _feedback = _ScanFeedback.idle);
    });
    setState(() {
      _isProcessing = false;
      _feedback = _ScanFeedback.invalid;
    });
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
    } on MobileScannerException {
      // Camera not running (or no torch): nothing to toggle.
    }
  }

  Color _bracketColor(FieldPalette p) => switch (_feedback) {
    _ScanFeedback.idle => kScanOverlayWhite,
    _ScanFeedback.valid => p.moss,
    _ScanFeedback.invalid => p.brick,
  };

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>()!;
    return Scaffold(
      backgroundColor: p.ink,
      body: LayoutBuilder(
        builder: (context, box) {
          final cutout = scanCutout(box.biggest);
          return Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: _controller,
                scanWindow: cutout,
                onDetect: _handleDetection,
                errorBuilder: (_, error) => _errorView(error),
              ),
              IgnorePointer(
                child: CustomPaint(
                  painter: ScanOverlayPainter(
                    cutout: cutout,
                    bracketColor: _bracketColor(p),
                  ),
                ),
              ),
              ..._copy(cutout, box.maxHeight, p),
              _Footer(controller: _controller, onTorch: _toggleTorch),
            ],
          );
        },
      ),
    );
  }

  Widget _errorView(MobileScannerException error) {
    if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
      return const ScanPermissionDenied();
    }
    return const _OverlayText(AppStrings.scanCameraError);
  }

  List<Widget> _copy(Rect cutout, double height, FieldPalette p) {
    return [
      Positioned(
        left: 24,
        right: 24,
        bottom: height - cutout.top + 20,
        child: const _OverlayText(AppStrings.scanFramingPrompt),
      ),
      Positioned(
        left: 24,
        right: 24,
        top: cutout.bottom + 20,
        child: Column(
          children: [
            _OverlayText(widget.context.label),
            if (_feedback == _ScanFeedback.invalid) ...[
              const SizedBox(height: 16),
              _InvalidStrip(color: p.brick),
            ],
          ],
        ),
      ),
    ];
  }
}

class _OverlayText extends StatelessWidget {
  const _OverlayText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(color: kScanOverlayWhite),
  );
}

class _InvalidStrip extends StatelessWidget {
  const _InvalidStrip({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    color: color,
    child: Text(
      AppStrings.scanInvalidQr,
      textAlign: TextAlign.center,
      style: Theme.of(
        context,
      ).textTheme.bodyLarge?.copyWith(color: kScanOverlayWhite),
    ),
  );
}

class _Footer extends StatelessWidget {
  const _Footer({required this.controller, required this.onTorch});
  final MobileScannerController controller;
  final VoidCallback onTorch;

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(
      foregroundColor: kScanOverlayWhite,
      minimumSize: const Size(48, 48),
    );
    return Positioned(
      left: 16,
      right: 16,
      bottom: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ValueListenableBuilder<MobileScannerState>(
                valueListenable: controller,
                builder: (_, state, _) => TextButton.icon(
                  key: const Key('scan-torch'),
                  style: style,
                  onPressed: onTorch,
                  icon: Icon(
                    state.torchState == TorchState.on
                        ? Icons.flashlight_on
                        : Icons.flashlight_off,
                  ),
                  label: const Text(AppStrings.scanTorch),
                ),
              ),
              TextButton(
                style: style,
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(AppStrings.scanCancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown instead of the camera when the permission was refused: says why
/// the app needs it and opens the system settings.
class ScanPermissionDenied extends StatelessWidget {
  const ScanPermissionDenied({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>()!;
    final text = Theme.of(context).textTheme;
    return ColoredBox(
      color: p.paper,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(AppStrings.scanPermissionTitle, style: text.titleLarge),
            const SizedBox(height: 12),
            Text(AppStrings.scanPermissionBody, style: text.bodyLarge),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => unawaited(openAppSettings()),
              child: const Text(AppStrings.scanOpenSettings),
            ),
          ],
        ),
      ),
    );
  }
}
