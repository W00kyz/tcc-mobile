import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/monitoring/monitoring_providers.dart';

/// The in-app silence warning (spec 2026-10-20-alocacao-automatica §7.3):
/// "Sem enviar sua localização há X min…" while the app is open and the
/// watchdog says the worker is silent. Silence grows with no event to react
/// to, so the banner re-reads the watchdog every [refreshInterval]. Renders
/// nothing otherwise, so callers can mount it unconditionally.
///
///     Column(children: [const SilenceBanner(), Expanded(child: list)])
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

    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: scheme.errorContainer,
      child: Row(
        children: [
          Icon(Icons.location_off, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppStrings.silenceWarning(
                warning.silentMinutes,
                warning.minutesUntilRelease,
              ),
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
