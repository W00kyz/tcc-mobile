import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/complaints_dialog.dart';

void main() {
  /// Opens the dialog and exposes what it resolves to through [result].
  Future<void> openDialog(
    WidgetTester tester,
    void Function(ComplaintsDialogResult?) onResult,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                onResult(await showComplaintsDialog(context)),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('"Continuar" returns the typed text', (tester) async {
    ComplaintsDialogResult? result;
    var resolved = false;
    await openDialog(tester, (r) {
      result = r;
      resolved = true;
    });

    expect(find.text(AppStrings.complaintsDialogTitle), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Falta papel');
    await tester.tap(find.text(AppStrings.complaintsContinue));
    await tester.pumpAndSettle();

    expect(resolved, isTrue);
    expect(result?.text, 'Falta papel');
  });

  testWidgets('"Continuar" with only spaces returns a null text', (
    tester,
  ) async {
    ComplaintsDialogResult? result;
    await openDialog(tester, (r) => result = r);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text(AppStrings.complaintsContinue));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.text, isNull);
  });

  testWidgets('"Cancelar" returns null', (tester) async {
    ComplaintsDialogResult? result;
    var resolved = false;
    await openDialog(tester, (r) {
      result = r;
      resolved = true;
    });

    await tester.enterText(find.byType(TextField), 'Falta papel');
    await tester.tap(find.text(AppStrings.commonCancel));
    await tester.pumpAndSettle();

    expect(resolved, isTrue);
    expect(result, isNull);
  });

  testWidgets('the field is truncated to 2000 characters', (tester) async {
    await openDialog(tester, (_) {});

    await tester.enterText(find.byType(TextField), 'a' * 2001);
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text.length, 2000);
    expect(field.maxLines, greaterThan(1));
  });
}
