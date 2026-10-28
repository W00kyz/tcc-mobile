import 'package:flutter/material.dart';
import 'package:route_monitor/ui/app_theme.dart';

/// A small white chip floating over the map, under the top bar (redesign
/// §6.2). The chip reads 32dp tall; its touch target is 48dp.
///
///     MapChip(icon: Icons.location_on, label: '…', onTap: explain)
class MapChip extends StatelessWidget {
  const MapChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.alert = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Brick icon: something is wrong (silence), not just informative.
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: _body(p),
          ),
        ),
      ),
    );
  }

  Widget _body(FieldPalette p) {
    return Container(
      height: 32,
      padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
      decoration: BoxDecoration(
        color: p.white,
        border: Border.all(color: p.rule),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: alert ? p.brick : p.moss),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: p.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The explanation a chip opens: a title and its paragraphs in a modal
/// sheet.
///
///     showChipExplanation(context, title: t, paragraphs: [body]);
Future<void> showChipExplanation(
  BuildContext context, {
  required String title,
  required List<String> paragraphs,
}) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(sheetContext).textTheme.titleLarge),
            for (final paragraph in paragraphs) ...[
              const SizedBox(height: 12),
              Text(paragraph),
            ],
          ],
        ),
      ),
    ),
  );
}
