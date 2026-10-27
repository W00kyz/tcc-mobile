import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/auth/auth_repository.dart';

void main() {
  group('worker standing', workerStandingTests);
  group('self-registration', registrationTests);

  test('login returns tokens on a 200 response', () async {
    // Access token shaped like a real JWT (header.payload.signature) because
    // DioAuthRepository decodes the `role` claim out of the payload segment —
    // a bare string here would make that decode throw a RangeError.
    const accessToken = 'a.eyJyb2xlIjoiRklFTERfV09SS0VSIn0.c';
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _FakeAdapter(
        statusCode: 200,
        body: {
          'access_token': accessToken,
          'refresh_token': 'r',
          'token_type': 'bearer',
        },
      );
    final repository = DioAuthRepository(dio);

    final session = await repository.login(
      email: 'joao@empresa.com',
      password: 'senha-forte-o-suficiente',
    );

    expect(session.accessToken, accessToken);
    expect(session.refreshToken, 'r');
    expect(session.role, 'FIELD_WORKER');
  });

  test('login reads consent_required off the response', () async {
    const accessToken = 'a.eyJyb2xlIjoiRklFTERfV09SS0VSIn0.c';
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _FakeAdapter(
        statusCode: 200,
        body: {
          'access_token': accessToken,
          'refresh_token': 'r',
          'token_type': 'bearer',
          'consent_required': true,
        },
      );
    final repository = DioAuthRepository(dio);

    final session = await repository.login(
      email: 'joao@empresa.com',
      password: 'senha-forte-o-suficiente',
    );

    expect(session.consentRequired, isTrue);
  });

  test(
    'login defaults consentRequired to false when the key is absent',
    () async {
      const accessToken = 'a.eyJyb2xlIjoiRklFTERfV09SS0VSIn0.c';
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = _FakeAdapter(
          statusCode: 200,
          body: {'access_token': accessToken, 'refresh_token': 'r'},
        );
      final repository = DioAuthRepository(dio);

      final session = await repository.login(
        email: 'joao@empresa.com',
        password: 'senha-forte-o-suficiente',
      );

      expect(session.consentRequired, isFalse);
    },
  );

  test('login throws InvalidCredentialsException on a 401 response', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _FakeAdapter(
        statusCode: 401,
        body: {'detail': 'Invalid'},
      );
    final repository = DioAuthRepository(dio);

    expect(
      () =>
          repository.login(email: 'joao@empresa.com', password: 'senha-errada'),
      throwsA(isA<InvalidCredentialsException>()),
    );
  });
}

const _workerToken = 'a.eyJyb2xlIjoiRklFTERfV09SS0VSIn0.c';

void workerStandingTests() {
  test(
    'login keeps the worker status, rejection reason and active flag',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = _FakeAdapter(
          statusCode: 200,
          body: {
            'access_token': _workerToken,
            'refresh_token': 'r',
            'consent_required': false,
            'worker_status': 'REJECTED',
            'rejection_reason': 'Documento ilegível',
            'worker_active': true,
          },
        );

      final session = await DioAuthRepository(
        dio,
      ).login(email: 'ana@empresa.com', password: 'senha-forte-o-suficiente');

      expect(session.workerStanding.status, WorkerStatus.rejected);
      expect(session.workerStanding.rejectionReason, 'Documento ilegível');
      expect(session.workerStanding.active, isTrue);
    },
  );

  test('refresh brings back the current standing with the token', () async {
    final adapter = _FakeAdapter(
      statusCode: 200,
      body: {
        'access_token': 'new-access',
        'worker_status': 'APPROVED',
        'rejection_reason': null,
        'worker_active': false,
      },
    );
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;

    final refreshed = await DioAuthRepository(dio).refreshAccessToken('r');

    expect(adapter.lastRequest?.path, '/auth/refresh');
    expect(refreshed.accessToken, 'new-access');
    expect(refreshed.workerStanding.status, WorkerStatus.approved);
    expect(refreshed.workerStanding.active, isFalse);
  });

  test('refresh reports whether a new privacy notice is owed', () async {
    // A notice published while the worker was logged in reaches them here.
    Future<bool?> consentAfterRefresh(Map<String, Object?> body) async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = _FakeAdapter(statusCode: 200, body: body);
      final refreshed = await DioAuthRepository(dio).refreshAccessToken('r');
      return refreshed.consentRequired;
    }

    expect(
      await consentAfterRefresh({
        'access_token': 'a',
        'consent_required': true,
      }),
      isTrue,
    );
    expect(
      await consentAfterRefresh({
        'access_token': 'a',
        'consent_required': false,
      }),
      isFalse,
    );
    // An older server says nothing: the session keeps what it had.
    expect(await consentAfterRefresh({'access_token': 'a'}), isNull);
  });

  test('only an approved, active worker may work', () {
    const pending = WorkerStanding(
      status: WorkerStatus.pendingApproval,
      active: true,
    );
    const rejected = WorkerStanding(status: WorkerStatus.rejected);
    const approved = WorkerStanding(
      status: WorkerStatus.approved,
      active: true,
    );
    const deactivated = WorkerStanding(
      status: WorkerStatus.approved,
      active: false,
    );
    // A manager, or a session stored before the backend sent a status.
    const notAWorker = WorkerStanding();

    expect(
      [pending, rejected, approved, deactivated, notAWorker].map(
        (standing) => standing.blocksWork,
      ),
      [true, true, false, true, false],
    );
  });
}

void registrationTests() {
  test('publicCompanies lists the companies a worker can join', () async {
    final adapter = _FakeAdapter(
      statusCode: 200,
      body: [
        {'id': 'c-1', 'name': 'Limpa Tudo'},
        {'id': 'c-2', 'name': 'Verde Vivo'},
      ],
    );
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;

    final companies = await DioAuthRepository(dio).publicCompanies();

    expect(adapter.lastRequest?.path, '/public/contractor-companies');
    expect(
      companies.map((company) => (company.id, company.name)),
      [('c-1', 'Limpa Tudo'), ('c-2', 'Verde Vivo')],
    );
  });

  test('register posts the sign-up with the accepted notice version', () async {
    final adapter = _FakeAdapter(
      statusCode: 201,
      body: {'status': 'PENDING_APPROVAL'},
    );
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;

    await DioAuthRepository(dio).register(
      name: 'Ana Souza',
      email: 'ana@empresa.com',
      password: 'senha-forte-o-suficiente',
      companyId: 'c-1',
      noticeVersion: 4,
    );

    expect(adapter.lastRequest?.method, 'POST');
    expect(adapter.lastRequest?.path, '/auth/register');
    expect(adapter.lastRequest?.data, {
      'name': 'Ana Souza',
      'email': 'ana@empresa.com',
      'password': 'senha-forte-o-suficiente',
      'contractor_company_id': 'c-1',
      'privacy_notice_version': 4,
    });
  });

  Future<void> registerAnswered(int statusCode, Object body) {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = _FakeAdapter(statusCode: statusCode, body: body);
    return DioAuthRepository(dio).register(
      name: 'Ana Souza',
      email: 'ana@empresa.com',
      password: 'senha-forte-o-suficiente',
      companyId: 'c-1',
      noticeVersion: 1,
    );
  }

  test('register maps 409 EMAIL_TAKEN', () async {
    await expectLater(
      registerAnswered(409, {
        'detail': {'code': 'EMAIL_TAKEN', 'detail': 'taken'},
      }),
      throwsA(isA<EmailTakenException>()),
    );
  });

  test('register maps 409 NOTICE_OUTDATED', () async {
    await expectLater(
      registerAnswered(409, {
        'detail': {'code': 'NOTICE_OUTDATED', 'detail': 'outdated'},
      }),
      throwsA(isA<NoticeOutdatedException>()),
    );
  });

  test('register maps the 422 for a company that no longer exists', () async {
    await expectLater(
      registerAnswered(422, {'detail': 'Unknown contractor company.'}),
      throwsA(isA<UnknownCompanyException>()),
    );
  });

  test('register maps a 422 validation error to invalid data', () async {
    await expectLater(
      registerAnswered(422, {
        'detail': [
          {
            'loc': ['body', 'email'],
            'msg': 'value is not a valid email address',
            'type': 'value_error',
          },
        ],
      }),
      throwsA(isA<InvalidRegistrationException>()),
    );
  });

  test('register lets any other failure through', () async {
    await expectLater(
      registerAnswered(500, {'detail': 'Internal Server Error'}),
      throwsA(isA<DioException>()),
    );
  });
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({required this.statusCode, required this.body});

  final int statusCode;
  final Object body;
  RequestOptions? lastRequest;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
