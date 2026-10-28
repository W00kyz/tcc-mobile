import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/route_providers.dart' show myDayProvider;
import 'package:route_monitor/ui/map_chip.dart';

/// In-app notice mirroring the persistent OS notification, as a chip over
/// the map (redesign §6.2): shown while today's route is `IN_PROGRESS`, so
/// the field worker sees the location-collection notice inside the app too
/// (LGPD transparency, RNF11). A tap explains it. Renders nothing when no
/// route is in progress, so callers can mount it unconditionally.
///
///     Column(children: [const CollectionBanner(), const SilenceBanner()])
class CollectionBanner extends ConsumerWidget {
  const CollectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(myDayProvider).asData?.value.route;
    final collecting = route?.status == 'IN_PROGRESS';
    if (!collecting) return const SizedBox.shrink();

    return MapChip(
      icon: Icons.my_location,
      label: AppStrings.collectionChip,
      onTap: () => showChipExplanation(
        context,
        title: AppStrings.collectionChip,
        paragraphs: const [
          AppStrings.collectionNotificationBody,
          AppStrings.locationPurposeRationale,
        ],
      ),
    );
  }
}
