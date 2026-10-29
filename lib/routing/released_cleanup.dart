import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/execution/execution_providers.dart'
    show localWriteStoreProvider, stopProgressStoreProvider;
import 'package:route_monitor/execution/observation_draft.dart';
import 'package:route_monitor/routing/route_repository.dart';

/// A released stop is no longer the worker's: its observation draft and the
/// photos held for its stamp go (the backend refuses evidence of a released
/// stop). `invalidate` on a draft never opened is a no-op, and a stop never
/// checked in here has no execution, so no photo.
///
///     forgetReleasedStops(ref, day.route); // on every day reload
void forgetReleasedStops(WidgetRef ref, RouteSummary? route) {
  for (final stop in route?.stops ?? const <RouteStopSummary>[]) {
    if (stop.status != 'RELEASED') continue;
    ref.invalidate(observationDraftProvider(stop.id));
    unawaited(_discardHeldPhotos(ref, stop.id));
  }
}

/// Both stores are read before the first await: the screen may be gone by
/// the time the progress row comes back. A failure is logged, never thrown.
Future<void> _discardHeldPhotos(WidgetRef ref, String stopId) async {
  final progress = ref.read(stopProgressStoreProvider);
  final store = ref.read(localWriteStoreProvider);
  try {
    final entry = await progress.progressFor(stopId);
    if (entry != null) await store.discardHeldPhotos(entry.executionId);
  } on Object catch (error, stack) {
    developer.log(
      jsonEncode({'event': 'held_photos_discard_failed', 'error': '$error'}),
      name: 'routing',
      stackTrace: stack,
    );
  }
}
