import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/privacy/my_data_api.dart';

final myDataApiProvider = Provider<MyDataApi>((ref) {
  final dio = buildSessionDio(ref);
  return DioMyDataApi(dio);
});

/// The aggregate behind the "Meus dados" transparency screen (LGPD, RNF10).
final myDataProvider = FutureProvider<PersonalData>(
  (ref) => ref.watch(myDataApiProvider).fetch(),
);
