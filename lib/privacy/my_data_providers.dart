import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/api/api_client.dart';
import 'package:route_monitor/api/env.dart';
import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/privacy/my_data_api.dart';

final myDataApiProvider = Provider<MyDataApi>((ref) {
  final session = ref.watch(sessionProvider);
  final dio = buildDio(
    baseUrl: apiBaseUrlFromEnvironment(),
    accessToken: session?.accessToken,
  );
  return DioMyDataApi(dio);
});

/// The aggregate behind the "Meus dados" transparency screen (LGPD, RNF10).
final myDataProvider = FutureProvider<PersonalData>(
  (ref) => ref.watch(myDataApiProvider).fetch(),
);
