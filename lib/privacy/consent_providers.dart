import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/api/api_client.dart';
import 'package:route_monitor/api/env.dart';
import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/privacy/consent_repository.dart';

final consentRepositoryProvider = Provider<ConsentRepository>((ref) {
  final session = ref.watch(sessionProvider);
  final dio = buildDio(
    baseUrl: apiBaseUrlFromEnvironment(),
    accessToken: session?.accessToken,
  );
  return DioConsentRepository(dio);
});

/// The notice source for the consent gate. `session.consentRequired` from the
/// login response is the primary guard signal; this future carries the text.
final consentStatusProvider = FutureProvider<ConsentStatus>((ref) {
  return ref.watch(consentRepositoryProvider).status();
});
