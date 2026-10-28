import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/impossibility_reason_dialog.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/ui/app_theme.dart';

void main() {
  /// Opens the reason dialog from a button; [results] gets what it returns.
  Future<List<String?>> pumpHost(
    WidgetTester tester, {
    bool noteTrimmed = false,
  }) async {
    final results = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => results.add(
                await showImpossibilityReasonDialog(
                  context,
                  noteTrimmed: noteTrimmed,
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    return results;
  }

  FilledButton confirmButton(WidgetTester tester) => tester.widget(
    find.widgetWithText(FilledButton, AppStrings.commonConfirm),
  );

  testWidgets('it is a dialog offering the four reasons', (tester) async {
    await pumpHost(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(AppStrings.impossibilityReasonTitle), findsOneWidget);
    for (final (_, label) in impossibilityReasons) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('Confirmar stays closed until a reason is picked, then returns '
      'its wire value', (tester) async {
    final results = await pumpHost(tester);
    expect(confirmButton(tester).onPressed, isNull);

    await tester.tap(find.text(AppStrings.impedimentReasonAccessBlocked));
    await tester.pump();
    await tester.tap(find.text(AppStrings.commonConfirm));
    await tester.pumpAndSettle();

    expect(results, ['ACCESS_BLOCKED']);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('Cancelar returns no reason', (tester) async {
    final results = await pumpHost(tester);

    await tester.tap(find.text(AppStrings.impedimentReasonOther));
    await tester.pump();
    await tester.tap(find.text(AppStrings.commonCancel));
    await tester.pumpAndSettle();

    expect(results, [null]);
  });

  testWidgets('it warns about a trimmed note only when told to', (
    tester,
  ) async {
    await pumpHost(tester);
    expect(find.text(AppStrings.impossibilityNoteTrimmed), findsNothing);
    await tester.tap(find.text(AppStrings.commonCancel));
    await tester.pumpAndSettle();

    await pumpHost(tester, noteTrimmed: true);

    expect(find.text(AppStrings.impossibilityNoteTrimmed), findsOneWidget);
  });
}
