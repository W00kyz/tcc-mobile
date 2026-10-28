import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/sync/sync_status.dart';
import 'package:route_monitor/ui/app_theme.dart';
import 'package:route_monitor/ui/sync_indicator.dart';

RouteSyncStatus _status(
  RouteSyncState state, {
  int pending = 0,
  int blocked = 0,
}) => RouteSyncStatus(
  routeId: 'r1',
  state: state,
  pending: pending,
  blocked: blocked,
);

Future<void> _pump(
  WidgetTester tester,
  RouteSyncStatus? status, {
  VoidCallback? onTap,
}) => tester.pumpWidget(
  MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: SyncIndicator(status: status, onTap: onTap ?? () {}),
    ),
  ),
);

void main() {
  testWidgets('idle reads "Tudo enviado" with a moss check', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, _status(RouteSyncState.idle));
    expect(find.bySemanticsLabel(AppStrings.routeAllSynced), findsOneWidget);
    semantics.dispose();
    final icon = tester.widget<Icon>(find.byIcon(Icons.cloud_done_outlined));
    expect(icon.color, FieldPalette.light.moss);
  });

  testWidgets('pending shows its count', (tester) async {
    await _pump(tester, _status(RouteSyncState.idle, pending: 2));
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('blocked is a brick struck cloud', (tester) async {
    await _pump(tester, _status(RouteSyncState.blocked, blocked: 1));
    final icon = tester.widget<Icon>(find.byIcon(Icons.cloud_off_outlined));
    expect(icon.color, FieldPalette.light.brick);
  });

  testWidgets('no status draws nothing; the target is 48dp', (tester) async {
    await _pump(tester, null);
    expect(find.byType(IconButton), findsNothing);
    await _pump(tester, _status(RouteSyncState.idle));
    final size = tester.getSize(find.byType(IconButton));
    expect(size.shortestSide, greaterThanOrEqualTo(48));
  });

  testWidgets('a tap calls onTap', (tester) async {
    var taps = 0;
    await _pump(tester, _status(RouteSyncState.idle), onTap: () => taps++);
    await tester.tap(find.byType(IconButton));
    expect(taps, 1);
  });
}
