import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/execution_providers.dart'
    show appDatabaseExecutorProvider;
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/main.dart';

void main() {
  testWidgets('shows the app title on the initial route', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        // SyncTriggers records the foreground flag on mount; keep that off
        // the on-device SQLite file, whose opening outlives a unit test.
        overrides: [
          appDatabaseExecutorProvider.overrideWithValue(
            NativeDatabase.memory(),
          ),
        ],
        child: const RouteMonitorApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.loginTitle), findsWidgets);
  });
}
