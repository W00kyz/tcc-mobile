import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:route_monitor/auth/auth_providers.dart';
import 'package:route_monitor/auth/auth_repository.dart';
import 'package:route_monitor/l10n/strings.dart';

/// Where the router holds a worker who may not work (spec
/// 2026-10-20-alocacao-automatica §9): waiting for approval (with
/// "Atualizar"), rejected (with the manager's reason), or deactivated.
class ApprovalScreen extends ConsumerStatefulWidget {
  const ApprovalScreen({super.key});

  @override
  ConsumerState<ApprovalScreen> createState() => _ApprovalScreenState();
}

class _ApprovalScreenState extends ConsumerState<ApprovalScreen> {
  bool _isRefreshing = false;

  /// A refresh brings the standing as of now; an approval made since the
  /// login moves on to the route.
  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    final notifier = ref.read(sessionProvider.notifier);
    final token = await notifier.refreshAccessToken();
    if (!mounted) return;
    setState(() => _isRefreshing = false);
    // Refresh token refused: the session is gone and the router takes over.
    final standing = ref.read(sessionProvider)?.workerStanding;
    if (standing == null) return;
    if (!standing.blocksWork) {
      context.go('/rota');
      return;
    }
    // Rejected or deactivated meanwhile: the rebuilt screen says so.
    if (standing.status != WorkerStatus.pendingApproval) return;
    final feedback = token == null
        ? AppStrings.approvalNetworkError
        : AppStrings.approvalStillPending;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(feedback)));
  }

  Future<void> _exit() async {
    await ref.read(sessionProvider.notifier).logout();
    if (mounted) context.go('/entrar');
  }

  @override
  Widget build(BuildContext context) {
    final standing =
        ref.watch(sessionProvider)?.workerStanding ?? const WorkerStanding();
    final isPending = standing.status == WorkerStatus.pendingApproval;
    final reason = standing.rejectionReason;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _message(standing),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (standing.status == WorkerStatus.rejected &&
                  reason != null) ...[
                const SizedBox(height: 12),
                Text(
                  AppStrings.approvalRejectionReason(reason),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              if (isPending) ...[
                const _EmptyCard(),
                const SizedBox(height: 24),
              ],
              if (isPending)
                FilledButton(
                  onPressed: _isRefreshing ? null : _refresh,
                  child: const Text(AppStrings.approvalRefreshButton),
                ),
              TextButton(
                onPressed: _isRefreshing ? null : _exit,
                child: const Text(AppStrings.approvalExitButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The batch card the worker will get, still blank: a card-shaped panel
/// with a row of empty slots and the line that says when it arrives.
class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      key: const Key('approval-empty-card'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outline),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [for (var i = 0; i < 4; i++) _EmptySlot(scheme.outline)],
          ),
          const SizedBox(height: 16),
          Text(
            AppStrings.approvalEmptyCard,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot(this.line);

  final Color line;

  @override
  Widget build(BuildContext context) => Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: line, width: 2),
    ),
  );
}

String _message(WorkerStanding standing) => switch (standing.status) {
  WorkerStatus.rejected => AppStrings.approvalRejectedMessage,
  WorkerStatus.approved => AppStrings.approvalDeactivatedMessage,
  WorkerStatus.pendingApproval || null => AppStrings.approvalPendingMessage,
};
