import 'package:dio/dio.dart';

/// Returns a fresh access token after a 401, or null when none can be had.
typedef AccessTokenRefresher = Future<String?> Function();

/// One seam for base URL and bearer token — every screen builds its Dio
/// through here instead of constructing one inline (docs/CLAUDE.base.md —
/// Dependencies).
///
/// With [onUnauthorized], a 401 triggers one token refresh and one retry of
/// the same request with the new token; a second 401 (or a refresh that
/// yields nothing) surfaces to the caller unchanged.
///
///     final dio = buildDio(baseUrl: url, accessToken: token,
///                          onUnauthorized: notifier.refreshAccessToken);
Dio buildDio({
  required String baseUrl,
  String? accessToken,
  AccessTokenRefresher? onUnauthorized,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      headers: accessToken != null
          ? {'Authorization': 'Bearer $accessToken'}
          : const {},
    ),
  );
  if (onUnauthorized != null) {
    dio.interceptors.add(_RefreshOnUnauthorized(dio, onUnauthorized));
  }
  return dio;
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
