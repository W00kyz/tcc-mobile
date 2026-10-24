import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/batch_allocation.dart';

/// The "Iniciar rota" button, alone on a day with no route yet or under the
/// "Seus pontos foram liberados" notice of a paused route (where it resumes
/// the route with a new batch). The outcome of a refused start is shown as a
/// snackbar; a successful one reloads the day, which replaces this panel.
///
///     StartRoutePanel(paused: true, releaseReason: route.latestReleaseReason)
class StartRoutePanel extends ConsumerStatefulWidget {
  const StartRoutePanel({super.key, this.paused = false, this.releaseReason});

  /// True on a `PAUSED` route: explains why before offering to resume.
  final bool paused;

  /// The `release_reason` code behind the pause, when known.
  final String? releaseReason;

  @override
  ConsumerState<StartRoutePanel> createState() => _StartRoutePanelState();
}

class _StartRoutePanelState extends ConsumerState<StartRoutePanel> {
  bool _starting = false;

  @override
  Widget build(BuildContext context) {
    final reason = widget.releaseReason;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.paused) ...[
              Text(
                AppStrings.routePausedTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (reason != null)
                Text(
                  AppStrings.routePausedReason(
                    AppStrings.releaseReasonLabel(reason),
                  ),
                ),
              const SizedBox(height: 16),
            ],
            FilledButton(
              // Disabled while a request is out; the server would hand the
              // same batch back to a double tap anyway.
              onPressed: _starting ? null : _start,
              child: const Text(AppStrings.routeStartButton),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _start() async {
    // Taken before the await: a successful start reloads the day and this
    // panel may be gone by the time the answer arrives.
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _starting = true);
    final outcome = await ref.read(batchAllocationProvider.notifier).start();
    if (mounted) setState(() => _starting = false);
    final message = _startOutcomeMessage(outcome);
    if (message == null) return;
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

String? _startOutcomeMessage(AllocationOutcome outcome) => switch (outcome) {
  AllocationOutcome.allocated => null,
  AllocationOutcome.poolEmpty => AppStrings.routeNoMorePoints,
  AllocationOutcome.notAServiceDay => AppStrings.routeNotServiceDay,
  AllocationOutcome.workdayOver => AppStrings.routeWorkdayOver,
  AllocationOutcome.outsideCampus => AppStrings.routeOutsideCampus,
  AllocationOutcome.offline => AppStrings.routeStartOffline,
  AllocationOutcome.locationUnavailable => AppStrings.routeLocationUnavailable,
  AllocationOutcome.failed => AppStrings.routeStartFailed,
};
