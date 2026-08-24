import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/main.dart';

void main() {
  testWidgets('renders the application shell title', (tester) async {
    await tester.pumpWidget(const RouteMonitorApp());

    expect(find.text('Monitoramento de Rotas'), findsOneWidget);
  });
}
