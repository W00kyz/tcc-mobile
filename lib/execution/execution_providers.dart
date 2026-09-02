import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/api/api_client.dart';
import 'package:route_monitor/api/env.dart';
import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/execution/execution_api.dart';
import 'package:route_monitor/execution/execution_repository.dart';
import 'package:route_monitor/local/app_database.dart';
import 'package:route_monitor/local/local_write_store.dart';

/// The on-device SQLite connection, as a true singleton — never construct a
/// second [AppDatabase] for the same file (Task 16 review). Every provider
/// that needs storage watches this one instead of building its own.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final localWriteStoreProvider = Provider<LocalWriteStore>(
  (ref) => DriftLocalWriteStore(ref.watch(appDatabaseProvider)),
);

final executionApiProvider = Provider<ExecutionApi>((ref) {
  final session = ref.watch(sessionProvider);
  final dio = buildDio(
    baseUrl: apiBaseUrlFromEnvironment(),
    accessToken: session?.accessToken,
  );
  return DioExecutionApi(dio);
});

final executionRepositoryProvider = Provider<ExecutionRepository>(
  (ref) => ExecutionRepository(
    ref.watch(executionApiProvider),
    ref.watch(localWriteStoreProvider),
  ),
);
