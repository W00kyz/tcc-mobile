import 'dart:async';

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
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/routing/start_availability.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:route_monitor/ui/app_theme.dart';

// What the home shows outside a route being worked (redesign §6.10): no
// service, the start bar (no route yet, paused), done, load error, the
// loading skeleton, and a finished batch waiting for the network.

/// "Hoje não tem serviço para você": no card, no start.
class NoServicePanel extends StatelessWidget {
  const NoServicePanel({super.key});

  @override
  Widget build(BuildContext context) =>
      const _Panel(title: AppStrings.dayNoService);
}

/// What the start bar says: its button label, whether it can be pressed (and
/// the countdown on it), and the caption over it — why the route paused, or
/// why the button is off.
typedef StartBarContent = ({
  String label,
  String? caption,
  StartAvailability availability,
});

/// The start bar a day shows instead of a sheet — no route yet on a service
/// day ("Iniciar rota"), or a paused route ("Continuar rota" under its
/// reason) — else null (a sheet shows). The button is disabled out of
/// working hours (spec §2), with the reason as caption.
///
///     final bar = startBarOf(day, deviceNow: DateTime.now());
///     // (label: 'Continuar rota', caption: 'Motivo: …', availability: …)
StartBarContent? startBarOf(MyDay? day, {required DateTime deviceNow}) {
  if (day == null) return null;
  final route = day.route;
  final label = switch (route?.status) {
    null when day.serviceDay => AppStrings.routeStartButton,
    'PAUSED' => AppStrings.dayResumeButton,
    _ => null,
  };
  if (label == null) return null;
  final availability = startAvailability(day, deviceNow: deviceNow);
  return (
    label: label,
    caption: availability.hint ?? pausedCaption(route?.latestReleaseReason),
    availability: availability,
  );
}

/// Before the route starts and while it is paused: no sheet over the map,
/// only the start button anchored at the bottom — a 56dp pill with a 16dp
/// gutter, above the system bar. "Iniciar rota" asks for the first batch,
/// "Continuar rota" resumes a paused route with a new one; both are off (the
/// pill greyed, or counting down to the opening) when the server would
/// refuse. [caption] (why it was paused, or why it is off) reads in a muted
/// chip just above the pill.
///
///     StartDayBar(label: AppStrings.dayResumeButton, caption: 'Motivo: …')
class StartDayBar extends StatelessWidget {
  const StartDayBar({
    required this.label,
    this.caption,
    this.availability = _alwaysOn,
    super.key,
  });

  final String label;
  final String? caption;
  final StartAvailability availability;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _captionAndButton(),
        ),
      ),
    );
  }

  Widget _captionAndButton() {
    final text = caption;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (text != null) _StartBarCaption(text: text),
        StartDayButton(
          label: label,
          enabled: availability.enabled,
          countdown: availability.countdown,
        ),
      ],
    );
  }
}

const StartAvailability _alwaysOn = (
  enabled: true,
  countdown: null,
  hint: null,
);

/// The start bar's caption: over the map, so on a paper chip with a rule
/// hairline rather than bare text on the tiles.
class _StartBarCaption extends StatelessWidget {
  const _StartBarCaption({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    final chip = BoxDecoration(
      color: p.paper,
      border: Border.all(color: p.rule),
      borderRadius: BorderRadius.circular(16),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: chip,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, height: 16 / 12, color: p.muted),
      ),
    );
  }
}

/// Why a paused route stopped, as the start bar's caption: `Motivo: <…>`,
/// or null when the server sent no reason.
///
///     pausedCaption(route.latestReleaseReason) // 'Motivo: Saiu do campus'
String? pausedCaption(String? releaseReason) => releaseReason == null
    ? null
    : AppStrings.routePausedReason(
        AppStrings.releaseReasonLabel(releaseReason),
      );

/// "Dia concluído" + the day's count + a disabled "Rota finalizada": a
/// finished route is not reopened from the app (spec §2).
class DonePanel extends StatelessWidget {
  const DonePanel({required this.doneToday, super.key});

  final int doneToday;

  @override
  Widget build(BuildContext context) => _Panel(
    title: AppStrings.dayDoneTitle,
    lines: [AppStrings.dayDoneSummary(doneToday)],
    action: const StartDayButton(
      label: AppStrings.routeFinishedButton,
      enabled: false,
    ),
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

/// The "Iniciar rota" / "Continuar rota" / "Rota finalizada" button: on a day
/// with no route yet, under a paused route (where it resumes the route with
/// a new batch), or disabled — [enabled] false — out of working hours and on
/// a finished route. With a [countdown] (the last 5 minutes before the
/// opening) it reads "Abre em 04:32", ticking each second, and reloads the
/// day at zero. The outcome of a refused start is shown as a snackbar; a
/// successful one reloads the day, which replaces the panel.
///
///     const StartDayButton(label: AppStrings.dayResumeButton)
///     const StartDayButton(label: 'Iniciar rota', enabled: false,
///         countdown: Duration(minutes: 4, seconds: 32))
class StartDayButton extends ConsumerStatefulWidget {
  const StartDayButton({
    required this.label,
    this.enabled = true,
    this.countdown,
    super.key,
  });

  final String label;
  final bool enabled;
  final Duration? countdown;

  @override
  ConsumerState<StartDayButton> createState() => _StartDayButtonState();
}

class _StartDayButtonState extends ConsumerState<StartDayButton> {
  bool _starting = false;
  Timer? _ticker;

  /// When the countdown ends, on the injected clock: the remaining time is
  /// read from it, so a suspended app does not resume with a stale count.
  late DateTime _deadline;
  Duration? _left;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  /// The parent recomputes [StartDayButton.countdown] from the clock on
  /// every rebuild, so only the null/non-null edges start or stop the
  /// ticker: restarting it per rebuild would keep a 1 s tick from ever
  /// firing under frequent rebuilds.
  @override
  void didUpdateWidget(StartDayButton old) {
    super.didUpdateWidget(old);
    final was = old.countdown;
    final now = widget.countdown;
    if (now == null) {
      if (was != null) _stopCountdown();
    } else if (was == null || !(_ticker?.isActive ?? false)) {
      // Also when the tick already hit zero and the reloaded day still has
      // time left: the ticker is dead, but the countdown is not over.
      _startCountdown();
    } else {
      _followCountdown(now);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _ticker?.cancel();
    final countdown = widget.countdown;
    _left = countdown;
    if (countdown == null) return;
    _deadline = ref.read(startClockProvider)().add(countdown);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  /// A rebuild's fresher countdown (a reloaded day moves the opening)
  /// re-aims the deadline without touching the ticker.
  void _followCountdown(Duration countdown) {
    _left = countdown;
    _deadline = ref.read(startClockProvider)().add(countdown);
  }

  /// The countdown went away on a rebuild: the clock crossed zero (the
  /// opening has come, same as in [_tick]) or the day changed under it.
  /// Only a live ticker reloads, so the tick and a rebuild never both do.
  /// This runs while building, where Riverpod cannot be invalidated: the
  /// reload waits for the end of the frame, on the scope's container so it
  /// still goes out if this button is gone by then.
  void _stopCountdown() {
    final ticking = _ticker?.isActive ?? false;
    _ticker?.cancel();
    final crossed = !ref.read(startClockProvider)().isBefore(_deadline);
    if (!ticking || !crossed) return;
    final container = ProviderScope.containerOf(context);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => container.invalidate(myDayProvider),
    );
  }

  void _tick() {
    final left = _deadline.difference(ref.read(startClockProvider)());
    if (left > Duration.zero) return setState(() => _left = left);
    _ticker?.cancel();
    setState(() => _left = Duration.zero);
    // The opening has come: the day says whether the button may start now.
    ref.invalidate(myDayProvider);
  }

  @override
  Widget build(BuildContext context) {
    final left = _left;
    final countingDown = widget.countdown != null && left != null;
    return FilledButton(
      // Disabled while a request is out; the server would hand the
      // same batch back to a double tap anyway.
      onPressed: widget.enabled && !_starting ? _start : null,
      child: Text(
        countingDown ? AppStrings.routeStartCountdown(left) : widget.label,
      ),
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
  AllocationOutcome.workdayNotStarted => AppStrings.routeStartNotOpenYet,
  AllocationOutcome.outsideCampus => AppStrings.routeOutsideCampus,
  AllocationOutcome.offline => AppStrings.routeStartOffline,
  AllocationOutcome.locationUnavailable => AppStrings.routeLocationUnavailable,
  AllocationOutcome.failed => AppStrings.routeStartFailed,
};

/// While the day loads: the card's shape, empty (spec §6.10).
class CardSkeleton extends StatelessWidget {
  const CardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    return Container(
      height: 160,
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: p.card,
        border: Border.all(color: p.rule),
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}
