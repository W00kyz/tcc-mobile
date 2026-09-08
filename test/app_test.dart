import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/main.dart';

void main() {
  testWidgets('shows the app title on the initial route', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: RouteMonitorApp()));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.loginTitle), findsWidgets);
  });
}
