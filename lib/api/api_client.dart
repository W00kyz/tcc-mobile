import 'package:dio/dio.dart';

/// One seam for base URL and bearer token — every screen builds its Dio
/// through here instead of constructing one inline (docs/CLAUDE.base.md —
/// Dependencies).
Dio buildDio({required String baseUrl, String? accessToken}) {
  return Dio(
    BaseOptions(
      baseUrl: baseUrl,
      headers: accessToken != null
          ? {'Authorization': 'Bearer $accessToken'}
          : const {},
    ),
  );
}
