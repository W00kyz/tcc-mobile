import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/api/api_client.dart';
import 'package:route_monitor/api/env.dart';
import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/checkin/checkin_repository.dart';
import 'package:route_monitor/checkin/qr_verifier.dart';

final qrVerifierProvider = Provider<QrVerifier>(
  (ref) => QrVerifier(qrPublicKeyHexFromEnvironment()),
);

final checkInRepositoryProvider = Provider<CheckInRepository>((ref) {
  final session = ref.watch(sessionProvider);
  final dio = buildDio(
    baseUrl: apiBaseUrlFromEnvironment(),
    accessToken: session?.accessToken,
  );
  return DioCheckInRepository(dio);
});
