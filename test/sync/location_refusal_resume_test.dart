import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/local/stop_progress_store.dart';
import 'package:route_monitor/local/sync_meta_store.dart';
import 'package:route_monitor/sync/background_sync.dart';
import 'package:route_monitor/sync/location_refusal_listener.dart';
import 'package:route_monitor/sync/sync_progress.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/sync/sync_status.dart';
import 'package:route_monitor/sync/sync_triggers.dart';
import 'package:route_monitor/sync/sync_worker.dart';
import 'package:route_monitor/ui/snackbar_lane.dart';

import '../support/fake_connectivity.dart';
import '../support/in_memory_database.dart';
import '../support/location_sync_support.dart';

// The app comes back after a refusal the background drain applied: the card
// reads pending again and the refusal is told once.

const _message =
    'Conclusão recusada em Praça central: você estava a 137 m do local.';

class _QuietWorker implements SyncWorker {
  @override
  Future<void> syncAll() async {}

  @override
  Future<void> syncRoute(String routeId) async {}

  @override
  Stream<RouteSyncStatus> statusFor(String routeId) => const Stream.empty();

  @override
  Future<void> unblock(String operationId) async {}

  @override
  Stream<SyncProgress> get progress => const Stream.empty();

  @override
  Future<void> dispose() async {}
}

class _IgnoringForegroundTracker implements AppForegroundTracker {
  @override
  Future<void> entered() async {}

  @override
  Future<void> left() async {}
}

/// Shows the stop's cached local status, with the refusal listener over it.
class _Home extends ConsumerStatefulWidget {
  const _Home();

  @override
  ConsumerState<_Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<_Home> {
  final DraggableScrollableController _sheet = DraggableScrollableController();
  late final SnackbarLane _lane = SnackbarLane(
    contextOf: () => mounted ? context : null,
    sheet: _sheet,
  );

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(stopProgressForProvider('sA')).value?.status;
    return LocationRefusalListener(
      lane: _lane,
      child: Stack(
        children: [
          Text('status:${status?.name ?? 'none'}'),
          DraggableScrollableSheet(
            controller: _sheet,
            minChildSize: 0.22,
            maxChildSize: 0.9,
            builder: (_, scroll) => ListView(controller: scroll),
          ),
        ],
      ),
    );
  }
}

void main() {
  late AppDatabase db;
  late LocationOutbox outbox;
  late LocationApi api;
  late List<String> log;
  late ProviderContainer container;

  setUp(() {
    db = inMemoryDatabase();
    addTearDown(db.close);
    outbox = LocationOutbox(db);
    log = [];
    api = LocationApi(log);
    api.refusals['sA'] = const LocationRefusedException(
      code: 'OUT_OF_RADIUS',
      distanceM: 137.4,
      radiusM: 50,
    );
  });

  Future<void> pumpApp(WidgetTester tester) async {
    container = ProviderContainer(
      overrides: [
        localWriteStoreProvider.overrideWithValue(DriftLocalWriteStore(db)),
        stopProgressStoreProvider.overrideWithValue(DriftStopProgressStore(db)),
        syncMetaStoreProvider.overrideWithValue(DriftSyncMetaStore(db)),
        connectivityProvider.overrideWithValue(FakeConnectivity()),
        syncWorkerProvider.overrideWithValue(_QuietWorker()),
        appForegroundTrackerProvider.overrideWithValue(
          _IgnoringForegroundTracker(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SyncTriggers(child: _Home()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> resume(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  }

  testWidgets('a refusal applied by the background drain: on resume the '
      'card reads pending and the refusal is told, once', (tester) async {
    await outbox.completion('sA', 'Praça central');
    await pumpApp(tester);
    expect(find.text('status:done'), findsOneWidget);

    // Another isolate rejects it: this one's cache still says done.
    await locationWorker(db, api, log).syncRoute('r1');
    expect(find.text('status:done'), findsOneWidget);

    await resume(tester);

    expect(find.text('status:none'), findsOneWidget);
    expect(find.text(_message), findsOneWidget);

    // The snackbar goes away; the next resume does not tell it again.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    await resume(tester);
    expect(find.text(_message), findsNothing);
  });

  testWidgets('a refusal told when the app starts after the drain', (
    tester,
  ) async {
    await outbox.completion('sA', 'Praça central');
    await locationWorker(db, api, log).syncRoute('r1');

    await pumpApp(tester);

    expect(find.text('status:none'), findsOneWidget);
    expect(find.text(_message), findsOneWidget);
  });

  testWidgets('a refusal the running app already told is not told again on '
      'resume', (tester) async {
    await outbox.completion('sA', 'Praça central');
    await pumpApp(tester);
    final foreground = locationWorker(
      db,
      api,
      log,
      onLocationRefused: container
          .read(locationRefusalAnnouncementsProvider.notifier)
          .announce,
    );

    await foreground.syncRoute('r1');
    await tester.pumpAndSettle();
    expect(find.text(_message), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    await resume(tester);

    expect(find.text(_message), findsNothing);
    expect(find.text('status:none'), findsOneWidget);
  });

  testWidgets('two refusals applied while away are both told on resume', (
    tester,
  ) async {
    await outbox.completion('sA', 'Praça central');
    await outbox.completion('sB', 'Jardim');
    api.refusals['sB'] = api.refusals['sA']!;
    await pumpApp(tester);
    await locationWorker(db, api, log).syncRoute('r1');

    await resume(tester);

    expect(find.text(_message), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Conclusão recusada em Jardim: você estava a 137 m do local.',
      ),
      findsOneWidget,
    );

    // Both were acknowledged: the next resume tells neither again.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    await resume(tester);
    expect(find.text(_message), findsNothing);
    expect(
      find.text(
        'Conclusão recusada em Jardim: você estava a 137 m do local.',
      ),
      findsNothing,
    );
  });
}
