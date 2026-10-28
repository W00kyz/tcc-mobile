import 'package:dio/dio.dart';

/// Returns a fresh access token after a 401, or null when none can be had.
typedef AccessTokenRefresher = Future<String?> Function();

/// The access token to send right now, or null for none.
typedef AccessTokenReader = String? Function();

/// Learns why the backend refused a worker (pending, rejected, deactivated).
typedef WorkerNotApprovedHandler = Future<void> Function();

/// Learns the worker owes consent to a privacy notice published since login.
typedef ConsentRequiredHandler = Future<void> Function();

/// The machine code of an API error — `{"detail": {"code": ...}}`, the shape
/// the backend uses for every refusal the app reacts to — or null.
String? apiErrorCode(DioException error) {
  final data = error.response?.data;
  if (data is! Map) return null;
  final detail = data['detail'];
  return detail is Map ? detail['code'] as String? : null;
}

/// Every request is bounded in time: a hung socket must fail (a soft sync
/// error, retried) rather than hold an outbox row's send claim past its lease
/// — `SyncWorker.sendLease` is sized from these.
const Duration apiConnectTimeout = Duration(seconds: 20);
const Duration apiSendTimeout = Duration(seconds: 60);
const Duration apiReceiveTimeout = Duration(seconds: 60);

/// One seam for base URL and bearer token — every screen builds its Dio
/// through here instead of constructing one inline (docs/CLAUDE.base.md —
/// Dependencies).
///
/// With [onUnauthorized], a 401 triggers one token refresh and one retry of
/// the same request with the new token; a second 401 (or a refresh that
/// yields nothing) surfaces to the caller unchanged.
///
/// With [readAccessToken] instead of [accessToken], the token is read at
/// each request, so a client held for hours (the position reporter) keeps
/// working across token refreshes without being rebuilt.
///
/// With [onWorkerNotApproved], a 403 `WORKER_NOT_APPROVED` from any call is
/// reported (and awaited) before the error reaches the caller, so the router
/// can send the worker to the waiting screen.
///
/// With [onConsentRequired], a 403 `CONSENT_REQUIRED` (the location gate of
/// "Iniciar rota", next batch and positions) is reported the same way, so the
/// router can show the new privacy notice to a worker who logged in before it.
///
///     final dio = buildDio(baseUrl: url, accessToken: token,
///                          onUnauthorized: notifier.refreshAccessToken);
Dio buildDio({
  required String baseUrl,
  String? accessToken,
  AccessTokenReader? readAccessToken,
  AccessTokenRefresher? onUnauthorized,
  WorkerNotApprovedHandler? onWorkerNotApproved,
  ConsentRequiredHandler? onConsentRequired,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: apiConnectTimeout,
      sendTimeout: apiSendTimeout,
      receiveTimeout: apiReceiveTimeout,
      headers: accessToken != null
          ? {'Authorization': 'Bearer $accessToken'}
          : const {},
    ),
  );
  if (readAccessToken != null) {
    dio.interceptors.add(_BearerAtRequestTime(readAccessToken));
  }
  if (onUnauthorized != null) {
    dio.interceptors.add(_RefreshOnUnauthorized(dio, onUnauthorized));
  }
  if (onWorkerNotApproved != null) {
    dio.interceptors.add(
      _Report403Code('WORKER_NOT_APPROVED', onWorkerNotApproved),
    );
  }
  if (onConsentRequired != null) {
    dio.interceptors.add(_Report403Code('CONSENT_REQUIRED', onConsentRequired));
  }
  return dio;
}

class _BearerAtRequestTime extends Interceptor {
  _BearerAtRequestTime(this._read);

  final AccessTokenReader _read;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // The 401 retry already carries the token the refresh handed back.
    final retried = options.extra[_RefreshOnUnauthorized._retriedKey] == true;
    final token = _read();
    if (!retried && token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}

/// Reports (and awaits) a 403 carrying [_code] before the error reaches the
/// caller.
class _Report403Code extends Interceptor {
  _Report403Code(this._code, this._report);

  final String _code;
  final Future<void> Function() _report;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 403 && apiErrorCode(err) == _code) {
      await _report();
    }
    handler.next(err);
  }
}

// A plain Interceptor, not QueuedInterceptor: the retry below runs inside
// onError, and a queued interceptor would hold that retry's own error behind
// the one being handled — a deadlock. Concurrent refreshes are already folded
// into one request by SessionNotifier.refreshAccessToken.
class _RefreshOnUnauthorized extends Interceptor {
  _RefreshOnUnauthorized(this._dio, this._refresh);

  final Dio _dio;
  final AccessTokenRefresher _refresh;
  static const _retriedKey = 'auth_retried';

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    if (err.response?.statusCode != 401 || options.extra[_retriedKey] == true) {
      return handler.next(err);
    }
    final token = await _refresh();
    if (token == null) return handler.next(err);
    options
      ..headers['Authorization'] = 'Bearer $token'
      ..extra[_retriedKey] = true;
    // A multipart body (evidence photo) is finalized once sent; resend a copy.
    final body = options.data;
    if (body is FormData) options.data = body.clone();
    try {
      handler.resolve(await _dio.fetch<dynamic>(options));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }
}
