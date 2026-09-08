import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/monitoring/monitoring_api.dart';
import 'package:route_monitor/monitoring/monitoring_providers.dart';
import 'package:route_monitor/monitoring/notifications_screen.dart';

/// Records `markRead` calls and serves a fixed list — the seam the screen
/// exercises instead of the real Dio client.
class _FakeMonitoringApi implements MonitoringApi {
  _FakeMonitoringApi(this.notifications);

  final List<AppNotification> notifications;
  final List<String> markReadCalls = [];
  int fetchCount = 0;

  @override
  Future<List<AppNotification>> fetchNotifications({int limit = 30}) async {
    fetchCount++;
    return notifications;
  }

  @override
  Future<int> unreadCount() async =>
      notifications.where((n) => n.isUnread).length;

  @override
  Future<void> markRead(String id) async => markReadCalls.add(id);

  @override
  Future<void> reportPosition({
    required String routeId,
    required double latitude,
    required double longitude,
    required DateTime reportedAt,
    double? accuracyM,
  }) async => throw UnimplementedError();
}

AppNotification _note({required String id, required bool unread}) =>
    AppNotification(
      id: id,
      kind: 'ROUTE_ASSIGNED',
      title: 'Título $id',
      body: 'Corpo $id',
      createdAt: DateTime.utc(2026, 9, 7, 9),
      readAt: unread ? null : DateTime.utc(2026, 9, 7, 10),
    );

Widget _screen(MonitoringApi api) => ProviderScope(
  overrides: [monitoringApiProvider.overrideWithValue(api)],
  child: const MaterialApp(home: NotificationsScreen()),
);

void main() {
  testWidgets('renders each notification, the unread one in bold', (
    tester,
  ) async {
    final api = _FakeMonitoringApi([
      _note(id: 'n1', unread: true),
      _note(id: 'n2', unread: false),
    ]);
    await tester.pumpWidget(_screen(api));
    await tester.pumpAndSettle();

    expect(find.text('Título n1'), findsOneWidget);
    expect(find.text('Título n2'), findsOneWidget);

    final unreadTitle = tester.widget<Text>(find.text('Título n1'));
    final readTitle = tester.widget<Text>(find.text('Título n2'));
    expect(unreadTitle.style?.fontWeight, FontWeight.bold);
    expect(readTitle.style?.fontWeight, FontWeight.normal);
  });

  testWidgets('shows a pt-BR kind label', (tester) async {
    final api = _FakeMonitoringApi([_note(id: 'n1', unread: true)]);
    await tester.pumpWidget(_screen(api));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(AppStrings.notificationKindRouteAssigned),
      findsOneWidget,
    );
  });

  testWidgets('tapping an unread notification marks it read and refetches', (
    tester,
  ) async {
    final api = _FakeMonitoringApi([_note(id: 'n1', unread: true)]);
    await tester.pumpWidget(_screen(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Título n1'));
    await tester.pumpAndSettle();

    expect(api.markReadCalls, ['n1']);
    // The initial load plus the post-markRead invalidation.
    expect(api.fetchCount, 2);
  });

  testWidgets('tapping an already-read notification does not call markRead', (
    tester,
  ) async {
    final api = _FakeMonitoringApi([_note(id: 'n2', unread: false)]);
    await tester.pumpWidget(_screen(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Título n2'));
    await tester.pumpAndSettle();

    expect(api.markReadCalls, isEmpty);
  });

  testWidgets('shows the empty state when there are no notifications', (
    tester,
  ) async {
    await tester.pumpWidget(_screen(_FakeMonitoringApi([])));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.notificationsEmpty), findsOneWidget);
  });
}
