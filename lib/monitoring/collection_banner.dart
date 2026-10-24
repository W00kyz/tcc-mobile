import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/route_providers.dart' show myDayProvider;

/// In-app banner mirroring the persistent OS notification: shown at the top of
/// the route screen while today's route is `IN_PROGRESS`, so the field worker
/// sees the location-collection notice inside the app too (LGPD transparency,
/// RNF11). Renders nothing when no route is in progress, so callers can mount
/// it unconditionally.
///
///     Column(children: [const CollectionBanner(), Expanded(child: list)])
class CollectionBanner extends ConsumerWidget {
  const CollectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(myDayProvider).asData?.value.route;
    final collecting = route?.status == 'IN_PROGRESS';
    if (!collecting) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: scheme.secondaryContainer,
      child: Row(
        children: [
          Icon(Icons.location_on, size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppStrings.collectionBannerText,
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}
