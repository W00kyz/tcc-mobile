import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:route_monitor/checkin/checkin_providers.dart';
import 'package:route_monitor/checkin/qr_verifier.dart';
import 'package:route_monitor/checkin/scan_overlay.dart';
import 'package:route_monitor/checkin/scan_screen.dart';
import 'package:route_monitor/ui/app_theme.dart';

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

  Future<void> pumpPusher(
    WidgetTester tester, {
    ScanContext scanContext = const EntryScan('Central de Aulas'),
  }) async {
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
          theme: buildAppTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  poppedValue = await Navigator.of(context).push<String>(
                    MaterialPageRoute<String>(
                      builder: (_) => ScanScreen(
                        context: scanContext,
                        controller: controller,
                      ),
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

  testWidgets('shows framing copy and context', (tester) async {
    await pumpPusher(
      tester,
      scanContext: const ExitScan('Central de Aulas', '1º andar'),
    );

    expect(find.text('Aponte para o QR Code do andar'), findsOneWidget);
    expect(find.text('Saída · Central de Aulas · 1º andar'), findsOneWidget);
  });

  testWidgets('entry context names the building', (tester) async {
    await pumpPusher(tester);

    expect(find.text('Entrada · Central de Aulas'), findsOneWidget);
  });

  testWidgets('invalid QR shows the inline strip and stays open', (
    tester,
  ) async {
    await pumpPusher(tester);

    final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
    scanner.onDetect!(_captureWith('not-a-qr-payload'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Esse QR não é do sistema. Tente o QR fixado no andar.'),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(poppedValue, 'not-popped-yet');
    expect(find.byType(ScanScreen), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(
      find.text('Esse QR não é do sistema. Tente o QR fixado no andar.'),
      findsNothing,
    );
  });

  testWidgets('valid QR pops with the raw value', (tester) async {
    await pumpPusher(tester);

    final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
    scanner.onDetect!(_captureWith(_validPayload));
    await tester.pumpAndSettle();

    expect(poppedValue, _validPayload);
    expect(find.byType(ScanScreen), findsNothing);
  });

  testWidgets('scan window matches the overlay cutout', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpPusher(tester);

    final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<ScanOverlayPainter>()
        .single;
    const side = 390 * 0.7;
    final expected = Rect.fromCenter(
      center: const Offset(195, 422),
      width: side,
      height: side,
    );
    expect(scanner.scanWindow, painter.cutout);
    expect(scanner.scanWindow!.width, closeTo(expected.width, 0.01));
    expect(scanner.scanWindow!.center, expected.center);
  });

  testWidgets('torch button is 48dp+ and labelled Lanterna', (tester) async {
    await pumpPusher(tester);

    final torch = find.bySemanticsLabel('Lanterna');
    expect(torch, findsOneWidget);
    final size = tester.getSize(find.byKey(const Key('scan-torch')));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(find.text('Lanterna'), findsOneWidget);
  });

  testWidgets('Cancelar closes the scanner without a value', (tester) async {
    await pumpPusher(tester);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(poppedValue, isNull);
  });

  testWidgets('permission-denied view explains and offers settings', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: ScanPermissionDenied()),
      ),
    );

    expect(find.text('Abrir configurações'), findsOneWidget);
    expect(find.textContaining('câmera'), findsWidgets);
  });
}
