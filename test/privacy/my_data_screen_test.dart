import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/privacy/my_data_api.dart';
import 'package:route_monitor/privacy/my_data_providers.dart';
import 'package:route_monitor/privacy/my_data_screen.dart';

PersonalData _populated({
  FieldWorkerInfo? fieldWorker = const FieldWorkerInfo(
    id: 'fw-1',
    fullName: 'Ana da Silva',
    contractorCompanyId: 'co-9',
    serviceTypeIds: ['st-1'],
  ),
  List<ConsentEntry> consent = const [],
  List<AuthEvent> authEvents = const [],
}) => PersonalData(
  profile: Profile(
    id: 'u-1',
    email: 'ana@example.com',
    name: 'Ana Field',
    role: 'FIELD_WORKER',
    isActive: true,
    createdAt: DateTime.utc(2026, 1, 2),
  ),
  fieldWorker: fieldWorker,
  consentHistory: consent,
  authEvents: authEvents,
  executionsSummary: TimeSpan(
    total: 12,
    firstAt: DateTime.utc(2026, 1, 5),
    lastAt: DateTime.utc(2026, 3, 20),
  ),
  evidenceSummary: const EvidenceSummary(totalItems: 40, totalBytes: 2048),
  positionsSummary: const TimeSpan(total: 0, firstAt: null, lastAt: null),
  notificationsSummary: const NotificationsSummary(total: 7, unread: 2),
);

Future<void> _pump(
  WidgetTester tester,
  Future<PersonalData> Function(Ref ref) create, {
  bool settle = true,
}) async {
  // A tall viewport so the whole ListView is laid out at once — the render
  // assertions below check every section without scrolling.
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [myDataProvider.overrideWith(create)],
      child: const MaterialApp(home: MyDataScreen()),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders every section with values from the provider', (
    tester,
  ) async {
    await _pump(
      tester,
      (ref) async => _populated(
        consent: [
          ConsentEntry(noticeVersion: 3, acceptedAt: DateTime.utc(2026, 3, 20)),
        ],
        authEvents: [
          AuthEvent(
            event: 'LOGIN',
            ipAddress: '10.0.0.1',
            createdAt: DateTime.utc(2026, 3, 2),
          ),
        ],
      ),
    );

    expect(find.text(AppStrings.myDataSectionProfile), findsOneWidget);
    expect(find.text('ana@example.com'), findsOneWidget);
    expect(find.text(AppStrings.myDataSectionFieldWorker), findsOneWidget);
    expect(find.text('Ana da Silva'), findsOneWidget);
    expect(find.text(AppStrings.myDataSectionConsent), findsOneWidget);
    expect(find.text(AppStrings.myDataConsentVersion(3)), findsOneWidget);
    expect(find.text(AppStrings.myDataSectionAuthEvents), findsOneWidget);
    expect(find.text('LOGIN'), findsOneWidget);
    expect(find.text(AppStrings.myDataSectionExecutions), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text(AppStrings.myDataSectionNotifications), findsOneWidget);
  });

  testWidgets('shows a spinner while loading', (tester) async {
    await _pump(
      tester,
      (ref) => Completer<PersonalData>().future,
      settle: false,
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows the error string on failure', (tester) async {
    await _pump(
      tester,
      (ref) => Future.error(Exception('boom')),
    );

    expect(find.text(AppStrings.myDataError), findsOneWidget);
  });

  testWidgets('null field_worker and empty lists show the empty string', (
    tester,
  ) async {
    await _pump(
      tester,
      (ref) async => _populated(fieldWorker: null),
    );

    expect(find.text(AppStrings.myDataEmpty), findsWidgets);

    final texts = tester.widgetList<Text>(find.byType(Text));
    for (final text in texts) {
      final value = text.data ?? '';
      expect(value.contains('Instance of'), isFalse);
      expect(value, isNot('null'));
    }
  });
}
