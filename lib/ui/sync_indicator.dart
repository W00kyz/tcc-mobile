import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/sync/sync_detail_sheet.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/sync/sync_status.dart';
import 'package:route_monitor/ui/app_theme.dart';

/// The top bar's sync mark (redesign §6.7), read by shape and not by colour:
/// a cloud with a moss check (all sent), a cloud with the pending count, or a
/// brick cloud struck through (blocked). Nothing until a status exists.
///
///     SyncIndicator(status: status, onTap: openDetail)
class SyncIndicator extends StatelessWidget {
  const SyncIndicator({required this.status, required this.onTap, super.key});

  final RouteSyncStatus? status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final current = status;
    if (current == null) return const SizedBox.shrink();
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    final blocked =
        current.state == RouteSyncState.blocked || current.blocked > 0;
    final (label, mark) = blocked
        ? (AppStrings.routeSyncBlockedBanner, _blockedMark(p))
        : current.pending > 0
        ? (
            AppStrings.routePendingSync(current.pending),
            _pendingMark(current, p),
          )
        : (AppStrings.routeAllSynced, _sentMark(p));
    return Semantics(
      label: label,
      button: true,
      excludeSemantics: true,
      onTap: onTap,
      child: IconButton(
        tooltip: label,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: onTap,
        icon: mark,
      ),
    );
  }

  Widget _sentMark(FieldPalette p) =>
      Icon(Icons.cloud_done_outlined, color: p.moss);

  Widget _blockedMark(FieldPalette p) =>
      Icon(Icons.cloud_off_outlined, color: p.brick);

  Widget _pendingMark(RouteSyncStatus current, FieldPalette p) {
    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.cloud_outlined, size: 28, color: p.ink),
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              '${current.pending}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: p.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// [SyncIndicator] wired to a route's status stream; a tap opens the detail
/// sheet.
///
///     RouteSyncIndicator(routeId: route.id)
class RouteSyncIndicator extends ConsumerWidget {
  const RouteSyncIndicator({required this.routeId, super.key});

  final String routeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(routeSyncStatusProvider(routeId)).asData?.value;
    return SyncIndicator(
      status: status,
      onTap: () => showSyncDetailSheet(context, routeId),
    );
  }
}
