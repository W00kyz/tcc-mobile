import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/batch_allocation.dart';
import 'package:route_monitor/routing/blocked_sync_screen.dart';
import 'package:route_monitor/routing/day_state_panels.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/sync/sync_snackbar_queue.dart';
import 'package:route_monitor/sync/sync_status.dart';
import 'package:route_monitor/ui/snackbar_lane.dart';

/// Reports the sync with snackbars while the app is open (redesign §6.7): at
/// most one at a time, floating above the map sheet so "Escanear QR" is
/// never covered.
///
///     SyncSnackbars(routeId: route.id, lane: lane, child: body)
class SyncSnackbars extends ConsumerStatefulWidget {
  const SyncSnackbars({
    required this.lane,
    required this.child,
    this.routeId,
    super.key,
  });

  /// Today's route, when there is one; no sync status to report without it.
  final String? routeId;

  /// The home's snackbar line: it lifts them over the map sheet.
  final SnackbarLane lane;
  final Widget child;

  @override
  ConsumerState<SyncSnackbars> createState() => _SyncSnackbarsState();
}

class _SyncSnackbarsState extends ConsumerState<SyncSnackbars> {
  final SyncSnackbarQueue _queue = SyncSnackbarQueue();
  static const RouteSyncStatus _quiet = RouteSyncStatus(
    routeId: '',
    state: RouteSyncState.idle,
    pending: 0,
    blocked: 0,
  );
  RouteSyncStatus _last = _quiet;

  @override
  void didUpdateWidget(SyncSnackbars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routeId != widget.routeId) _last = _quiet;
  }

  @override
  Widget build(BuildContext context) {
    final routeId = widget.routeId;
    if (routeId != null) {
      ref.listen<AsyncValue<RouteSyncStatus>>(
        routeSyncStatusProvider(routeId),
        (_, next) => unawaited(_onStatus(next.asData?.value)),
      );
    }
    ref.listen<NextBatchState>(batchAllocationProvider, (previous, next) {
      if (next == NextBatchState.waitingForNetwork &&
          previous != NextBatchState.waitingForNetwork) {
        _show(const NeedsNetworkForBatch());
      }
    });
    return widget.child;
  }

  Future<void> _onStatus(RouteSyncStatus? status) async {
    if (status == null) return;
    final online = await ref.read(connectivityProvider).isOnline;
    if (!mounted) return;
    final notice = _queue.next(_last, status, online: online);
    _last = status;
    if (notice != null) _show(notice);
  }

  void _show(SyncNotice notice) {
    final (text, label, onPressed) = _content(notice);
    widget.lane.show(
      SnackKind.sync,
      (margin) => SnackBar(
        content: Text(text),
        margin: margin,
        action: label == null
            ? null
            : SnackBarAction(label: label, onPressed: onPressed!),
      ),
    );
  }

  (String, String?, VoidCallback?) _content(SyncNotice notice) =>
      switch (notice) {
        Sending(:final n) => (AppStrings.syncSending(n), null, null),
        AllSent() => (AppStrings.routeAllSynced, null, null),
        Waiting(:final n) => (
          AppStrings.syncWaiting(n),
          AppStrings.syncSendAction,
          _sendNow,
        ),
        Blocked(:final n) => (
          AppStrings.syncBlockedNotice(n),
          AppStrings.syncSeeAction,
          _openBlocked,
        ),
        NeedsNetworkForBatch() => (
          AppStrings.routeNextBatchOffline,
          AppStrings.retryButton,
          _sendNow,
        ),
      };

  void _sendNow() => unawaited(sendAllAndPull(ref));

  void _openBlocked() {
    final routeId = widget.routeId;
    if (routeId == null) return;
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BlockedSyncScreen(routeId: routeId),
        ),
      ),
    );
  }
}
