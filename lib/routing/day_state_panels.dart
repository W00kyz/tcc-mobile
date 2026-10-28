import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/monitoring/location_mode.dart';
import 'package:route_monitor/monitoring/location_mode_device.dart';
import 'package:route_monitor/monitoring/monitoring_providers.dart';
import 'package:route_monitor/routing/batch_allocation.dart';
import 'package:route_monitor/routing/home_notices.dart';
import 'package:route_monitor/routing/route_providers.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/ui/app_theme.dart';

// What the home sheet shows outside a batch in progress (redesign §6.10):
// no service, no route yet, paused, done, load error, and a finished batch
// waiting for the network.

/// "Hoje não tem serviço para você": no card, no start.
class NoServicePanel extends StatelessWidget {
  const NoServicePanel({super.key});

  @override
  Widget build(BuildContext context) =>
      const _Panel(title: AppStrings.dayNoService);
}

/// No route yet: "Iniciar rota" asks for the first batch.
class StartDayPanel extends StatelessWidget {
  const StartDayPanel({super.key});

  @override
  Widget build(BuildContext context) => const _Panel(
    action: StartDayButton(label: AppStrings.routeStartButton),
  );
}

/// "Rota pausada" + why + "Retomar", which resumes the route with a new
/// batch.
class PausedPanel extends StatelessWidget {
  const PausedPanel({this.releaseReason, super.key});

  /// The `release_reason` code behind the pause, when known.
  final String? releaseReason;

  @override
  Widget build(BuildContext context) {
    final reason = releaseReason;
    return _Panel(
      title: AppStrings.routePausedTitle,
      lines: [
        if (reason != null)
          AppStrings.routePausedReason(AppStrings.releaseReasonLabel(reason)),
      ],
      action: const StartDayButton(label: AppStrings.dayResumeButton),
    );
  }
}

/// "Dia concluído" + the day's count + "Verificar de novo". Not final before
/// the workday ends: points released later go back to the pool, and
/// "Verificar de novo" asks for them (spec §1).
class DonePanel extends StatelessWidget {
  const DonePanel({required this.doneToday, super.key});

  final int doneToday;

  @override
  Widget build(BuildContext context) => _Panel(
    title: AppStrings.dayDoneTitle,
    lines: [AppStrings.dayDoneSummary(doneToday)],
    action: const StartDayButton(label: AppStrings.routeCheckAgainButton),
  );
}

/// The day could not be read: the message and "Tentar de novo"; the map
/// stays visible behind.
class LoadErrorPanel extends ConsumerWidget {
  const LoadErrorPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Panel(
    title: AppStrings.routeLoadError,
    action: FilledButton(
      onPressed: () => ref.invalidate(myDayProvider),
      child: const Text(AppStrings.retryButton),
    ),
  );
}

/// "Conecte-se para receber mais pontos": the batch is finished on this
/// device but the next one could not be pulled; it is retried as soon as the
/// connection comes back (spec §6.4), or now with "Tentar de novo".
class NextBatchOfflinePanel extends ConsumerWidget {
  const NextBatchOfflinePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Panel(
    title: AppStrings.routeNextBatchOffline,
    action: OutlinedButton(
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      onPressed: () => sendAllAndPull(ref),
      child: const Text(AppStrings.retryButton),
    ),
  );
}

/// Drains every route, then re-runs the next-batch pull: the outbox was
/// what the pull was waiting for.
///
///     onPressed: () => sendAllAndPull(ref)
Future<void> sendAllAndPull(WidgetRef ref) async {
  final allocation = ref.read(batchAllocationProvider.notifier);
  await ref.read(syncWorkerProvider).syncAll();
  await allocation.retry();
}

/// A title, muted lines under it, then one action.
class _Panel extends StatelessWidget {
  const _Panel({this.title, this.lines = const [], this.action});

  final String? title;
  final List<String> lines;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    final heading = title;
    final button = action;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (heading != null)
            Text(heading, style: Theme.of(context).textTheme.titleLarge),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(line, style: TextStyle(color: p.muted)),
            ),
          if (button != null) ...[const SizedBox(height: 16), button],
        ],
      ),
    );
  }
}

/// The "Iniciar rota" / "Retomar" / "Verificar de novo" button: on a day
/// with no route yet, under a paused route (where it resumes the route with
/// a new batch) or on a route the pool ran out for, where points released
/// since (a colleague went silent, say) reopen it (spec §1). The outcome of
/// a refused start is shown as a snackbar; a successful one reloads the day,
/// which replaces the panel.
///
///     const StartDayButton(label: AppStrings.dayResumeButton)
class StartDayButton extends ConsumerStatefulWidget {
  const StartDayButton({required this.label, super.key});

  final String label;

  @override
  ConsumerState<StartDayButton> createState() => _StartDayButtonState();
}

class _StartDayButtonState extends ConsumerState<StartDayButton> {
  bool _starting = false;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      // Disabled while a request is out; the server would hand the
      // same batch back to a double tap anyway.
      onPressed: _starting ? null : _start,
      child: Text(widget.label),
    );
  }

  Future<void> _start() async {
    // Taken before the await: a successful start reloads the day and this
    // panel may be gone by the time the answer arrives.
    final notify = homeNotifier(ref, context);
    setState(() => _starting = true);
    final AllocationOutcome outcome;
    try {
      await _settleLocationMode();
      outcome = await ref.read(batchAllocationProvider.notifier).start();
    } finally {
      if (mounted) setState(() => _starting = false);
    }
    final message = _startOutcomeMessage(outcome);
    if (message == null) return;
    notify(message);
  }

  /// Before the first batch: "while in use", then — once per device — the
  /// explained "always" request (spec §7.3). The reporter picks the mode up
  /// from `locationModeProvider` when the route turns `IN_PROGRESS`.
  Future<void> _settleLocationMode() async {
    try {
      await resolveLocationMode(
        ref.read(permissionPortProvider),
        prompts: DialogLocationModePrompts(context),
        asked: ref.read(backgroundAskStoreProvider),
      );
    } on PlatformException {
      // permission_handler refused to ask (e.g. a request already running):
      // start anyway — the start's own GPS read decides, and the mode below
      // reflects whatever is granted.
    }
    ref.invalidate(locationModeProvider);
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
