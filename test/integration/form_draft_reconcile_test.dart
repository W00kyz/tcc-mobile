import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/execution/evidence_api.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/execution/execution_repository.dart';
import 'package:route_monitor/forms/form_draft_store.dart';
import 'package:route_monitor/forms/form_providers.dart';
import 'package:route_monitor/forms/form_reconciliation.dart';
import 'package:route_monitor/forms/form_schema.dart';
import 'package:route_monitor/forms/form_screen.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/routing/location_service.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/routing/route_screen.dart';
import 'package:route_monitor/sync/connectivity.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/sync/sync_triggers.dart';
import 'package:route_monitor/sync/sync_worker.dart';

import '../support/in_memory_database.dart';

/// DELIVERABLE PROOF for Etapa 7 (RF39/RF40): a stop's dynamic form is
/// answered, the form version changes under it while `IN_PROGRESS`, the
/// on-device draft reconciles the diff, and the final answers ride the real
/// outbox to a (fake) backend. Spec §6 — this wires the REAL `FormDraftStore`
/// / `FormScreen` / `FormReconciliationTrigger` / `SyncWorker` /
/// `ExecutionRepository` on an in-memory database, exactly like Etapa 6's
/// `offline_route_test.dart`, and fakes only the outermost seams
/// (`Connectivity`, the two APIs, `RouteRepository`, GPS).
///
/// Same LiveTestWidgetsFlutterBinding rationale as `offline_route_test.dart`:
/// this drives the real SyncWorker/outbox/FormDraftStore, whose futures ride
/// the real event loop — plain `await` + `tester.pump()` is enough, no
/// `runAsync`.
void main() {
  LiveTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a form draft survives a version change offline, reconciles, and syncs '
    'the final answers on check-out',
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // ---- Check in stop 1 BEFORE mounting: real ExecutionRepository.
      // checkIn, then the same form-draft snapshot RouteScreen._checkIn
      // performs right after a successful check-in (the FormSchema lives on
      // the route's stop list, not on the repository). Done pre-mount, same
      // convention as `route_screen_test.dart`'s form-gating tests (they
      // pre-seed `StopProgressStore`/`FormDraftStore` rather than drive a
      // live check-in transition mid-test) — the family providers this
      // screen watches (`stopProgressForProvider`,
      // `formDraftCompleteProvider`) are plain `FutureProvider`s with no
      // dependency wiring back to `myRoutesProvider`, so nothing here
      // relies on invalidating them mid-run.
      final executionId = await fixture.repo.checkIn(
        routeId: _routeId,
        routeStopId: _stop1,
        qrPayload: _qr,
        latitude: -7.23,
        longitude: -35.88,
      );
      await fixture.formDraftStore.snapshotFrom(
        executionId,
        _stop1,
        _formV1,
      );

      // ---- Warm + mount, route starts already IN_PROGRESS with stop 1 -----
      await fixture.container.read(myRoutesProvider.future);
      await tester.pumpWidget(fixture.app());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // ---- Open FormScreen for real, answer all 3 v1 questions through
      // real widget interaction (tap/enter text), same patterns as
      // test/forms/form_screen_test.dart ----------------------------------
      await tester.tap(find.text(AppStrings.routeFillFormButton));
      await tester.pumpAndSettle();
      expect(find.byType(FormScreen), findsOneWidget);

      await tester.tap(find.byType(SwitchListTile)); // q1 BOOLEAN -> true
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField),
        'Chão limpo, sem infiltração.',
      ); // q2 TEXT
      await tester.pumpAndSettle();
      await tester.tap(find.text('médio')); // q3 SINGLE_CHOICE
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.commonBack));
      await tester.pumpAndSettle();
      expect(find.byType(FormScreen), findsNothing);

      // ---- "Concluir" is enabled: all 3 required v1 questions answered --
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_concluirButton(tester).onPressed, isNotNull);

      // ---- The stop's service now publishes a new form version: q1's hash
      // is unchanged, q2's prompt (and hash) changed, q3 unchanged, q4 is a
      // brand-new required TEXT question -----------------------------------
      fixture.routeApi.form = _formV2;
      fixture.container.invalidate(myRoutesProvider);
      // Gives `FormReconciliationTrigger`'s `unawaited` loop (mounted in
      // fixture.app()) real wall-clock time to re-fetch, diff and write the
      // reconciled draft — matching offline_route_test.dart's cadence for a
      // background async operation that isn't explicitly awaited.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      final reconciled = await fixture.formDraftStore.itemsFor(executionId);
      expect(reconciled, hasLength(4));
      final byKey = {for (final i in reconciled) i.stableKey: i};

      expect(byKey['q1']!.value, true);
      expect(byKey['q1']!.needsReanswer, isFalse);

      expect(byKey['q2']!.value, 'Chão limpo, sem infiltração.');
      expect(byKey['q2']!.needsReanswer, isTrue);

      expect(byKey['q3']!.value, 'médio');
      expect(byKey['q3']!.needsReanswer, isFalse);

      expect(byKey['q4'], isNotNull);
      expect(byKey['q4']!.value, isNull);

      expect(
        await fixture.formDraftStore.isComplete(executionId),
        isFalse,
      );

      // ---- "Concluir" flips to disabled now — proof that the reconcile
      // invalidated formDraftCompleteProvider(executionId) rather than
      // leaving RouteScreen's gate on its earlier (complete) cached value --
      expect(_concluirButton(tester).onPressed, isNull);

      // ---- Re-open the form: answer q2 again (clears needsReanswer) and
      // q4, the newly-added required question -----------------------------
      await tester.tap(find.text(AppStrings.routeFillFormButton));
      await tester.pumpAndSettle();

      // Two TEXT fields are now on screen (q2 + q4); enterText by index.
      final textFields = find.byType(TextFormField);
      expect(textFields, findsNWidgets(2));
      await tester.enterText(textFields.at(0), 'Chão limpo e seco.');
      await tester.pumpAndSettle();
      await tester.enterText(textFields.at(1), 'Sem pendências extras.');
      await tester.pumpAndSettle();

      expect(
        find.text(AppStrings.formQuestionChanged),
        findsNothing,
      );

      await tester.tap(find.text(AppStrings.commonBack));
      await tester.pumpAndSettle();

      expect(await fixture.formDraftStore.isComplete(executionId), isTrue);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_concluirButton(tester).onPressed, isNotNull);

      // ---- Check out: real ExecutionRepository.checkOut, still offline —
      // the outbox row must carry the v2 form_version_id and all 4 answers
      final finalItems = await fixture.formDraftStore.itemsFor(executionId);
      await fixture.repo.checkOut(
        routeId: _routeId,
        routeStopId: _stop1,
        qrPayload: _qr,
        latitude: -7.23,
        longitude: -35.88,
        checkoutIdempotencyKey: 'checkout-1',
      );

      final rows = await fixture.store.unsyncedForRoute(_routeId);
      final checkOutRow = rows.singleWhere(
        (r) => r.kind == PendingOpKind.checkOut,
      );
      expect(checkOutRow.payload['form_version_id'], 'form-v2');
      final answers = (checkOutRow.payload['answers'] as List)
          .cast<Map<String, Object?>>();
      expect(answers, hasLength(4));
      for (final item in finalItems) {
        final answer = answers.singleWhere(
          (a) => a['stable_key'] == item.stableKey,
        );
        expect(answer['value'], item.value);
      }

      // The draft's job is done: cleared immediately by checkOut, not only
      // once the row syncs (ExecutionRepository's own contract).
      expect(await fixture.formDraftStore.itemsFor(executionId), isEmpty);

      // ---- Go online and drain: the fake ExecutionApi.checkOut must have
      // received the same form_version_id/answers ---------------------------
      fixture.connectivity.goOnline();
      await fixture.worker.syncAll();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(fixture.executionApi.checkOutFormVersionIds, ['form-v2']);
      final syncedAnswers = fixture.executionApi.checkOutAnswers.single!;
      expect(syncedAnswers, hasLength(4));
      for (final item in finalItems) {
        final answer = syncedAnswers.singleWhere(
          (a) => a['stable_key'] == item.stableKey,
        );
        expect(answer['value'], item.value);
      }
      expect(await fixture.formDraftStore.itemsFor(executionId), isEmpty);
    },
  );
}

const _routeId = 'r1';
const _stop1 = 's1';
const _qr = 'v1.floor.1.sig';

FormQuestion _q({
  required String stableKey,
  required int orderIndex,
  required QuestionType type,
  required String prompt,
  required bool required,
  required String contentHash,
  List<String> options = const [],
}) => FormQuestion(
  stableKey: stableKey,
  orderIndex: orderIndex,
  prompt: prompt,
  type: type,
  required: required,
  options: options,
  contentHash: contentHash,
);

/// v1: q1 BOOLEAN, q2 TEXT, q3 SINGLE_CHOICE — all required.
final _formV1 = FormSchema(
  formVersionId: 'form-v1',
  questions: [
    _q(
      stableKey: 'q1',
      orderIndex: 0,
      type: QuestionType.boolean,
      prompt: 'Área limpa?',
      required: true,
      // A real content_hash is sha256-of-canonical-json (backend
      // app/domain/forms/hashing.py); the mobile side never recomputes it —
      // it only compares the token it's given (Ruling 2) — so an opaque
      // stand-in string is all a test needs here.
      contentHash: 'hash-q1-v1',
    ),
    _q(
      stableKey: 'q2',
      orderIndex: 1,
      type: QuestionType.text,
      prompt: 'Observações',
      required: true,
      contentHash: 'hash-q2-v1',
    ),
    _q(
      stableKey: 'q3',
      orderIndex: 2,
      type: QuestionType.singleChoice,
      prompt: 'Nível de sujeira',
      required: true,
      options: const ['baixo', 'médio', 'alto'],
      contentHash: 'hash-q3-v1',
    ),
  ],
);

/// v2: q1 unchanged (same hash), q2's prompt (and hash) changed, q3
/// unchanged, q4 TEXT required — brand new.
final _formV2 = FormSchema(
  formVersionId: 'form-v2',
  questions: [
    _q(
      stableKey: 'q1',
      orderIndex: 0,
      type: QuestionType.boolean,
      prompt: 'Área limpa?',
      required: true,
      contentHash: 'hash-q1-v1', // same content -> no re-answer
    ),
    _q(
      stableKey: 'q2',
      orderIndex: 1,
      type: QuestionType.text,
      prompt: 'Observações sobre a limpeza do piso', // changed prompt
      required: true,
      contentHash: 'hash-q2-v2', // different hash -> flagged
    ),
    _q(
      stableKey: 'q3',
      orderIndex: 2,
      type: QuestionType.singleChoice,
      prompt: 'Nível de sujeira',
      required: true,
      options: const ['baixo', 'médio', 'alto'],
      contentHash: 'hash-q3-v1', // same content -> no re-answer
    ),
    _q(
      stableKey: 'q4',
      orderIndex: 3,
      type: QuestionType.text,
      prompt: 'Pendências adicionais',
      required: true,
      contentHash: 'hash-q4-v2',
    ),
  ],
);

/// Finds the "Concluir" `TextButton` on the mounted `RouteScreen` stop tile.
TextButton _concluirButton(WidgetTester tester) => tester.widget<TextButton>(
  find.ancestor(
    of: find.text(AppStrings.routeConcludeButton),
    matching: find.byType(TextButton),
  ),
);

/// Everything the test drives: a real [ProviderContainer] with a real
/// in-memory database, the real [SyncWorker]/[ExecutionRepository]/
/// [FormDraftStore]/[FormReconciliationTrigger], and recording fakes for the
/// outermost seams only.
class _Fixture {
  _Fixture(
    this.container,
    this.executionApi,
    this.evidenceApi,
    this.routeApi,
    this.connectivity,
  );

  final ProviderContainer container;
  final _RecordingExecutionApi executionApi;
  final _RecordingEvidenceApi evidenceApi;
  final _MutableFormRouteRepository routeApi;
  final _FakeConnectivity connectivity;

  static Future<_Fixture> create() async {
    final executionApi = _RecordingExecutionApi();
    final evidenceApi = _RecordingEvidenceApi();
    final routeApi = _MutableFormRouteRepository();
    final connectivity = _FakeConnectivity();
    final db = inMemoryDatabase();

    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        connectivityProvider.overrideWithValue(connectivity),
        executionApiProvider.overrideWithValue(executionApi),
        evidenceApiProvider.overrideWithValue(evidenceApi),
        routeRepositoryProvider.overrideWithValue(routeApi),
        locationServiceProvider.overrideWithValue(_FakeLocationService()),
        apiBaseUrlProvider.overrideWithValue('http://test-base'),
      ],
    );
    return _Fixture(
      container,
      executionApi,
      evidenceApi,
      routeApi,
      connectivity,
    );
  }

  ExecutionRepository get repo => container.read(executionRepositoryProvider);
  SyncWorker get worker => container.read(syncWorkerProvider);
  FormDraftStore get formDraftStore => container.read(formDraftStoreProvider);
  LocalWriteStore get store => container.read(localWriteStoreProvider);
  AppDatabase get _db => container.read(appDatabaseProvider);

  Widget app() => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      builder: (context, child) => SyncTriggers(
        child: FormReconciliationTrigger(
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      home: const RouteScreen(),
    ),
  );

  Future<void> dispose() async {
    await _db.close();
    container.dispose();
    await connectivity.dispose();
  }
}

class _FakeLocationService implements LocationService {
  @override
  Future<Coordinates> getCurrentPosition({
    required LocationPurpose purpose,
  }) async => const Coordinates(latitude: -7.23, longitude: -35.88);
}

class _FakeConnectivity implements Connectivity {
  bool _online = false;
  final _controller = StreamController<bool>.broadcast();

  @override
  Future<bool> get isOnline async => _online;

  @override
  Stream<bool> get onOnlineChanged => _controller.stream;

  void goOnline() {
    _online = true;
    _controller.add(true);
  }

  Future<void> dispose() => _controller.close();
}

/// A [RouteRepository] with one route, one stop, and a mutable [form] —
/// tests flip it mid-run to simulate a new PUBLISHED form version landing on
/// the stop's service type, then re-fetch via `myRoutesProvider`.
class _MutableFormRouteRepository implements RouteRepository {
  FormSchema? form = _formV1;

  @override
  Future<List<RouteSummary>> fetchMyRoutes({DateTime? date}) async => [
    RouteSummary(
      id: _routeId,
      fieldWorkerName: 'João',
      routeDate: DateTime(2026, 9, 3),
      routeType: 'REGULAR',
      status: 'IN_PROGRESS',
      startedAt: DateTime.utc(2026, 9, 3, 8),
      stops: [
        RouteStopSummary(
          id: _stop1,
          orderIndex: 1,
          status: 'PENDING',
          servicePointName: 'Sala 101',
          latitude: -7.23,
          longitude: -35.88,
          serviceTypeId: 'svc-cleaning',
          serviceTypeName: 'Limpeza',
          form: form,
        ),
      ],
    ),
  ];

  @override
  Future<RouteSummary> startRoute({
    required String routeId,
    required double latitude,
    required double longitude,
    required DateTime startedAt,
  }) async => (await fetchMyRoutes()).first;
}

/// Records every `checkOut` call's `formVersionId`/`answers` args — the
/// deliverable proof that the sync worker actually forwards what
/// `ExecutionRepository.checkOut` put in the outbox payload.
class _RecordingExecutionApi implements ExecutionApi {
  final List<String?> checkOutFormVersionIds = [];
  final List<List<Map<String, Object?>>?> checkOutAnswers = [];

  @override
  Future<({CheckInResult result, DateTime? serverDate})> checkIn({
    required String executionId,
    required String qrPayload,
    required DateTime scannedAt,
    required String idempotencyKey,
    double? latitude,
    double? longitude,
    String? routeStopId,
    double? clientClockOffsetSeconds,
  }) async => (
    result: CheckInResult(
      routeStopId: routeStopId!,
      executionId: executionId,
      geoValidation: 'INSIDE',
      flags: const [],
    ),
    serverDate: null,
  );

  @override
  Future<({CheckOutResult result, DateTime? serverDate})> checkOut({
    required String executionId,
    required String qrPayload,
    required DateTime scannedAt,
    required String checkoutIdempotencyKey,
    double? latitude,
    double? longitude,
    String? routeStopId,
    double? clientClockOffsetSeconds,
    String? formVersionId,
    List<Map<String, Object?>>? answers,
  }) async {
    checkOutFormVersionIds.add(formVersionId);
    checkOutAnswers.add(answers);
    return (
      result: CheckOutResult(
        routeStopId: routeStopId!,
        executionId: executionId,
        checkedOutAt: DateTime.utc(2026),
        flags: const [],
      ),
      serverDate: null,
    );
  }

  @override
  Future<void> reportImpediment({
    required String routeId,
    required String? routeStopId,
    required String scope,
    required String reason,
    required DateTime reportedAt,
    String? note,
  }) async => throw UnimplementedError();
}

class _RecordingEvidenceApi implements EvidenceApi {
  @override
  Future<DateTime?> uploadPhoto({
    required String executionId,
    required Uint8List bytes,
    required String sha256,
    required DateTime capturedAt,
    required String idempotencyKey,
  }) async => null;

  @override
  Future<DateTime?> uploadNote({
    required String executionId,
    required String textBody,
    required DateTime capturedAt,
    required String idempotencyKey,
  }) async => null;

  @override
  Future<List<EvidenceItem>> listEvidence(String executionId) async => const [];
}
