import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/monitoring/monitoring_providers.dart';
import 'package:route_monitor/ui/map_chip.dart';

/// The in-app silence warning (spec 2026-10-20-alocacao-automatica §7.3), as
/// a chip over the map (redesign §6.2): "Sem localização há X min" while the
/// app is open and the watchdog says the worker is silent; a tap opens the
/// whole warning ("Sem enviar sua localização há X min…"). Silence grows
/// with no event to react to, so the banner re-reads the watchdog every
/// [refreshInterval]. Renders nothing otherwise, so callers can mount it
/// unconditionally.
///
///     Column(children: [const CollectionBanner(), const SilenceBanner()])
class SilenceBanner extends ConsumerStatefulWidget {
  const SilenceBanner({super.key});

  static const Duration refreshInterval = Duration(seconds: 30);

  @override
  ConsumerState<SilenceBanner> createState() => _SilenceBannerState();
}

class _SilenceBannerState extends ConsumerState<SilenceBanner> {
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(
      SilenceBanner.refreshInterval,
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final warning = ref.watch(silenceWatchdogProvider)?.currentWarning();
    if (warning == null) return const SizedBox.shrink();

    return MapChip(
      icon: Icons.location_off,
      label: AppStrings.silenceChip(warning.silentMinutes),
      alert: true,
      onTap: () => showChipExplanation(
        context,
        title: AppStrings.silenceChip(warning.silentMinutes),
        paragraphs: [
          AppStrings.silenceWarning(
            warning.silentMinutes,
            warning.minutesUntilRelease,
          ),
        ],
      ),
    );
  }
}
