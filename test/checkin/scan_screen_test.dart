import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:route_monitor/checkin/checkin_providers.dart';
import 'package:route_monitor/checkin/qr_verifier.dart';
import 'package:route_monitor/checkin/scan_screen.dart';

// Same fixture as qr_verifier_test.dart: a payload signed by the test key
// "11"*32 for floor_id=00000000-0000-0000-0000-000000000001.
const _publicKeyHex =
    'd04ab232742bb4ab3a1368bd4615e4e6d0224ab71a016baf8520a332c9778737';
const _validPayload =
    'v1.00000000-0000-0000-0000-000000000001.1.'
    'M2wGfprp0zqRRCiAH6VNpSWYftIdtPiCaTBdmfNPtYtX'
    'cf2NmRKTFA-valGS9ElgvVyM4efOZ2rUnOjgMPyvCw==';

BarcodeCapture _captureWith(String rawValue) =>
    BarcodeCapture(barcodes: [Barcode(rawValue: rawValue)]);

void main() {
  late MobileScannerController controller;
  late String? poppedValue;

  Future<void> pumpPusher(WidgetTester tester) async {
    poppedValue = 'not-popped-yet';
    // autoStart: false — a widget test must never touch the camera platform
    // channel (QR doesn't work in an emulator either, see CLAUDE.md); the
    // detection itself is driven directly through MobileScanner.onDetect
    // below instead of a real camera frame.
    controller = MobileScannerController(autoStart: false);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          qrVerifierProvider.overrideWithValue(QrVerifier(_publicKeyHex)),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  poppedValue = await Navigator.of(context).push<String>(
                    MaterialPageRoute<String>(
                      builder: (_) => ScanScreen(controller: controller),
                    ),
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('pops with the raw value when the QR is validly signed', (
    tester,
  ) async {
    await pumpPusher(tester);

    final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
    scanner.onDetect!(_captureWith(_validPayload));
    await tester.pumpAndSettle();

    expect(poppedValue, _validPayload);
    expect(find.byType(ScanScreen), findsNothing);
  });

  testWidgets(
    'shows an error and does not pop when the QR is invalid',
    (tester) async {
      await pumpPusher(tester);

      final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
      scanner.onDetect!(_captureWith('not-a-qr-payload'));
      await tester.pumpAndSettle();

      expect(find.text('QR Code inválido ou adulterado.'), findsOneWidget);
      expect(poppedValue, 'not-popped-yet');
      expect(find.byType(ScanScreen), findsOneWidget);
    },
  );
}
