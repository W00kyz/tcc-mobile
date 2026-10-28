import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:route_monitor/execution/execution_api.dart'
    show AmbiguousRoomException;

/// How the worker reacts to a failed dispatch (spec Ruling 6).
enum SyncErrorClass {
  /// Transient — retry with exponential backoff, then block after 5 tries.
  soft,

  /// The server already has this write — treat as a success.
  alreadyApplied,

  /// Permanent for this payload — block the row and halt the route's queue.
  hard,

  /// 401 even after the token refresh: the session must be renewed (a new
  /// login). Nothing is wrong with the row — leave it `pending`, untouched,
  /// and halt the pass; the next sync after login replays it. Classifying
  /// this as [hard] blocked every queued write of a route that outlived the
  /// 15-minute access token.
  awaitingAuth,
}

/// Sorts one failed dispatch into a [SyncErrorClass] (spec Ruling 6).
///
///     if (classifySyncError(error) == SyncErrorClass.soft) retryLater();
SyncErrorClass classifySyncError(Object error) {
  // RULING P5: a background drain cannot show a room picker, so an
  // unresolved-room check-in blocks that stop.
  if (error is AmbiguousRoomException) return SyncErrorClass.hard;
  if (error is! DioException) return SyncErrorClass.hard;

  final response = error.response;
  // No HTTP response at all — a pure transport/network failure (timeout,
  // DNS blip, TLS handshake abort wrapped as `type: unknown`, a non-socket
  // IOException mid-request). All recoverable: retry with backoff rather
  // than block the route forever.
  if (response == null) return SyncErrorClass.soft;

  final status = response.statusCode;
  if (status == 401) return SyncErrorClass.awaitingAuth;
  if (status != null && const {500, 502, 503, 504, 429}.contains(status)) {
    return SyncErrorClass.soft;
  }
  if (status == 409 &&
      _syncErrorBodyText(response.data).toLowerCase().contains('already')) {
    return SyncErrorClass.alreadyApplied;
  }
  // 422 / 403 / 404 and every other non-retryable HTTP status: permanent.
  return SyncErrorClass.hard;
}

String _syncErrorBodyText(Object? data) {
  if (data is String) return data;
  if (data is Map || data is List) return jsonEncode(data);
  return data?.toString() ?? '';
}
