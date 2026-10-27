import 'package:flutter/material.dart';

import 'package:route_monitor/l10n/strings.dart';

/// "Tire pelo menos 2 fotos (faltam N)" under an in-progress stop that still
/// lacks photos; nothing once none is [missing].
class EvidenceRequirementHint extends StatelessWidget {
  const EvidenceRequirementHint({required this.missing, super.key});

  final int missing;

  @override
  Widget build(BuildContext context) {
    if (missing <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        AppStrings.evidenceMissingHint(missing),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.error,
        ),
      ),
    );
  }
}
