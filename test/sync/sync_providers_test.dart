import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/auth/auth_repository.dart';
import 'package:route_monitor/execution/evidence_api.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/local_write_store.dart';
import 'package:route_monitor/monitoring/monitoring_providers.dart';
import 'package:route_monitor/monitoring/silence_watchdog.dart';
import 'package:route_monitor/sync/sync_providers.dart';

import '../support/fake_connectivity.dart';
import '../support/in_memory_database.dart';

/// The wiring of spec 2026-10-20-alocacao-automatica §7.3 on the real
/// `syncWorkerProvider`: a check-in counts for the silence clock once the
/// sync worker delivers it, at its scan time — even when the session changes
/// while the delivery is in flight (a drain after 15+ minutes offline is
/// exactly when the access token gets refreshed).
void main() {
  final scannedAt = DateTime.utc(2026, 10, 20, 8, 40);
  late DateTime now;
  late SilenceWatchdog watchdog;
  late AppDatabase db;

  setUp(() {
    now = scannedAt.subtract(const Duration(minutes: 40));
    watchdog = SilenceWatchdog(
      clock: () => now,
      scheduler: _NoopScheduler(),
      warningMinutes: 30,
      releaseMinutes: 45,
    )..startWatching();
    db = inMemoryDatabase();
    addTearDown(db.close);
  });

  ProviderContainer build({required Override executionApi}) {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sessionProvider.overrideWith(() => _TestSession(_session(1))),
        apiBaseUrlProvider.overrideWithValue('http://test-base'),
        connectivityProvider.overrideWithValue(
          FakeConnectivity(isOnline: true),
        ),
        executionApi,
        evidenceApiProvider.overrideWithValue(_UnusedEvidenceApi()),
        silenceWatchdogProvider.overrideWithValue(watchdog),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> enqueueCheckIn(ProviderContainer container) => container
      .read(localWriteStoreProvider)
      .enqueue(
        id: 'k1',
        kind: PendingOpKind.checkIn,
        routeId: 'r1',
        payload: {
          'execution_id': 'e1',
          'qr_payload': 'v1.floor.1.sig',
          'scanned_at': scannedAt.toIso8601String(),
          'idempotency_key': 'k1',
          'route_stop_id': 's1',
        },
      );

  void refreshSession(ProviderContainer container, Session next) =>
      (container.read(sessionProvider.notifier) as _TestSession).refreshTo(
        next,
      );

  /// No row left pending, failed or blocked: the check-in reached `synced`.
  Future<bool> allSynced() async =>
      (await DriftLocalWriteStore(db).routeIdsWithWork()).isEmpty;

  test(
    'a check-in delivered by syncWorkerProvider quiets the watchdog',
    () async {
      final container = build(
        executionApi: executionApiProvider.overrideWithValue(
          _AcceptingExecutionApi(),
        ),
      );
      await enqueueCheckIn(container);

      await container.read(syncWorkerProvider).syncRoute('r1');

      now = scannedAt.add(const Duration(minutes: 1));
      expect(watchdog.currentWarning(), isNull);
    },
  );

  test('a token refresh does not rebuild the sync worker', () {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sessionProvider.overrideWith(() => _TestSession(_session(1))),
        apiBaseUrlProvider.overrideWithValue('http://test-base'),
        connectivityProvider.overrideWithValue(FakeConnectivity()),
      ],
    );
    addTearDown(container.dispose);
    final before = container.read(syncWorkerProvider);

    refreshSession(container, _session(2));

    expect(identical(container.read(syncWorkerProvider), before), isTrue);
  });

  test(
    'a token refresh mid-delivery: the row ends synced and the watchdog '
    'gets the activity',
    () async {
      final server = _GatedCheckInServer();
      final container = build(
        // The production client, on a fake transport.
        executionApi: executionApiProvider.overrideWith(
          (ref) => DioExecutionApi(
            buildUserScopedSessionDio(ref, baseUrl: 'http://test-base')
              ..httpClientAdapter = server,
          ),
        ),
      );
      await enqueueCheckIn(container);

      final pass = container.read(syncWorkerProvider).syncRoute('r1');
      await server.requested.future;
      refreshSession(container, _session(2));
      server.respond();
      await pass;

      expect(await allSynced(), isTrue);
      now = scannedAt.add(const Duration(minutes: 1));
      expect(watchdog.currentWarning(), isNull);
    },
  );

  test(
    'a worker rebuilt mid-delivery still leaves the row synced',
    () async {
      final gate = Completer<void>();
      final container = build(
        // Worst case: a client that rebuilds the worker on any session change
        // (as `buildSessionDio` did) — the old pass's callback then runs on
        // a disposed ref and must not touch the row.
        executionApi: executionApiProvider.overrideWith((ref) {
          ref.watch(sessionProvider);
          return _AcceptingExecutionApi(gate: gate);
        }),
      );
      await enqueueCheckIn(container);

      final pass = container.read(syncWorkerProvider).syncRoute('r1');
      await Future<void>.delayed(Duration.zero);
      refreshSession(container, _session(2));
      container.read(syncWorkerProvider);
      gate.complete();
      await pass;

      expect(await allSynced(), isTrue);
    },
  );
}

/// A session whose access token is a readable JWT for the same user, issued
/// at [issuedAt] — what a refresh hands back.
Session _session(int issuedAt) {
  String part(Map<String, Object> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final token =
      '${part({'alg': 'HS256'})}.${part({'sub': 'u1', 'iat': issuedAt})}.sig';
  return Session(accessToken: token, refreshToken: 'r', role: 'FIELD_WORKER');
}

class _TestSession extends SessionNotifier {
  _TestSession(this._initial);

  final Session _initial;

  @override
  Session? build() => _initial;

  // A method, not a setter: it stands for the refresh the real notifier
  // performs.
  // ignore: use_setters_to_change_properties
  void refreshTo(Session next) => state = next;
}

/// `POST /check-ins` held open until [respond], then answered 201.
class _GatedCheckInServer implements HttpClientAdapter {
  final requested = Completer<void>();
  final _answer = Completer<void>();

  void respond() => _answer.complete();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.complete();
    await _answer.future;
    return ResponseBody.fromString(
      jsonEncode({
        'route_stop_id': 's1',
        'execution_id': 'e1',
        'geo_validation': 'INSIDE',
        'validation_flags': <String>[],
      }),
      201,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _AcceptingExecutionApi implements ExecutionApi {
  _AcceptingExecutionApi({this.gate});

  /// When set, the check-in answers only once it completes.
  final Completer<void>? gate;

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
  }) async {
    await gate?.future;
    return (
      result: const CheckInResult(
        routeStopId: 's1',
        executionId: 'e1',
        geoValidation: 'INSIDE',
        flags: [],
      ),
      serverDate: null,
    );
  }

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
  }) => throw UnimplementedError();

  @override
  Future<void> reportImpediment({
    required String routeId,
    required String? routeStopId,
    required String scope,
    required String reason,
    required DateTime reportedAt,
    String? note,
  }) => throw UnimplementedError();
}

/// No evidence row is queued here, so nothing may reach it.
class _UnusedEvidenceApi extends Mock implements EvidenceApi {}

class _NoopScheduler implements LocalScheduler {
  @override
  Future<void> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> cancel(int id) async {}
}
