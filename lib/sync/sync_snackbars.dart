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
import 'package:route_monitor/ui/map_sheet.dart';

/// Reports the sync with snackbars while the app is open (redesign §6.7): at
/// most one at a time, floating above the map sheet so "Escanear QR" is
/// never covered.
///
///     SyncSnackbars(routeId: route.id, sheet: controller, child: body)
class SyncSnackbars extends ConsumerStatefulWidget {
  const SyncSnackbars({
    required this.sheet,
    required this.child,
    this.routeId,
    super.key,
  });

  /// Today's route, when there is one; no sync status to report without it.
  final String? routeId;

  /// The map sheet's controller: its height lifts the snackbars.
  final DraggableScrollableController sheet;
  final Widget child;

  @override
  ConsumerState<SyncSnackbars> createState() => _SyncSnackbarsState();
}

class _SyncSnackbarsState extends ConsumerState<SyncSnackbars> {
  final SyncSnackbarQueue _queue = SyncSnackbarQueue();
  RouteSyncStatus _last = const RouteSyncStatus(
    routeId: '',
    state: RouteSyncState.idle,
    pending: 0,
    blocked: 0,
  );

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

  /// The sync snackbar on screen, when it is the one showing.
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _visible;

  /// A sync snackbar is queued or showing: a newer notice waits in [_pending]
  /// and replaces it, but never closes another feature's (the "Recorrer"
  /// offer).
  bool _active = false;
  SyncNotice? _pending;

  void _show(SyncNotice notice) {
    if (!_active) return _display(notice);
    _pending = notice;
    _visible?.close();
  }

  void _display(SyncNotice notice) {
    final (text, label, onPressed) = _content(notice);
    _active = true;
    late final ScaffoldFeatureController<SnackBar, SnackBarClosedReason> shown;
    shown = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        margin: _margin(context),
        onVisible: () => _visible = shown,
        action: label == null
            ? null
            : SnackBarAction(label: label, onPressed: onPressed!),
      ),
    );
    unawaited(shown.closed.then((_) => _onClosed()));
  }

  void _onClosed() {
    _visible = null;
    _active = false;
    final next = _pending;
    _pending = null;
    if (next != null && mounted) _show(next);
  }

  /// Bottom margin equal to the sheet's current height.
  EdgeInsets _margin(BuildContext context) {
    final sheet = widget.sheet;
    final fraction = sheet.isAttached ? sheet.size : kMapSheetInitial;
    final height = MediaQuery.sizeOf(context).height * fraction;
    return EdgeInsets.fromLTRB(16, 0, 16, height + 8);
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
