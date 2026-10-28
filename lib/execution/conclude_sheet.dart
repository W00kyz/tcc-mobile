import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show NotifierProviderFamily;

import 'package:route_monitor/execution/evidence_list.dart';
import 'package:route_monitor/execution/evidence_photo_count.dart';
import 'package:route_monitor/execution/evidence_requirement.dart';
import 'package:route_monitor/execution/evidence_thumbnail.dart';
import 'package:route_monitor/execution/execution_providers.dart';
import 'package:route_monitor/execution/photo_sequence_screen.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/routing/route_repository.dart';
import 'package:route_monitor/ui/app_theme.dart';

// The conclusion sheet (redesign §6.6): the photos taken, ONE optional
// observation for every stop, and "Escanear QR de saída". It writes nothing:
// the observation is a draft until the exit QR is read and the check-out
// carries it as `complaints_suggestions`.

/// What the backend takes in `complaints_suggestions` (and what the old
/// note dialog allowed).
const int maxObservationLength = 2000;

/// Truncates the text to [maxCodePoints] Unicode code points.
///
/// The field's own `maxLength` counts grapheme clusters, but the backend
/// (pydantic) counts code points: a family emoji is one cluster and seven code
/// points, so emoji-heavy text could pass the field and be refused with a 422
/// that blocks the queued check-out.
class _CodePointLimiter extends TextInputFormatter {
  const _CodePointLimiter(this.maxCodePoints);

  final int maxCodePoints;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.runes.length <= maxCodePoints) return newValue;
    final kept = String.fromCharCodes(newValue.text.runes.take(maxCodePoints));
    return TextEditingValue(
      text: kept,
      selection: TextSelection.collapsed(offset: kept.length),
    );
  }
}

/// Whether [stop] may conclude now: an evidence stop needs its photos, read
/// from the device outbox first ([stopPhotoCountProvider]); with no open
/// execution there is no photo to count, so only a stop without the flag
/// passes. [watch] false reads once (a flow), true rebuilds on change (a
/// widget).
///
///     if (!stopMayConclude(ref, routeId, stop, executionId)) return;
bool stopMayConclude(
  WidgetRef ref,
  String routeId,
  RouteStopSummary stop,
  String? executionId, {
  bool watch = false,
}) {
  final provider = executionId == null
      ? null
      : stopPhotoCountProvider((routeId, executionId));
  final photoCount = provider == null
      ? null
      : (watch ? ref.watch(provider) : ref.read(provider));
  return canConcludeWithEvidence(
    requiresEvidence: stop.requiresEvidence,
    photoCount: photoCount,
  );
}

/// The thumbnails the sheet's summary shows at most.
const int _summaryThumbnails = 3;

/// The observation typed for one stop, kept outside the sheet so cancelling
/// the exit QR and reopening "Concluir" shows it again (Review Focus 3).
/// Memory only, on purpose: nothing about it is a user action until the
/// check-out, which is what writes it to SQLite (RNF06).
///
///     ref.read(observationDraftProvider(stopId).notifier).write('pia');
final NotifierProviderFamily<ObservationDraft, String, String>
observationDraftProvider =
    NotifierProvider.family<ObservationDraft, String, String>(
      ObservationDraft.new,
    );

class ObservationDraft extends Notifier<String> {
  ObservationDraft(this.routeStopId);

  final String routeStopId;

  @override
  String build() => '';

  // A method, not a setter: reads as the action it is at the call site.
  // ignore: use_setters_to_change_properties
  void write(String text) => state = text;

  void clear() => state = '';
}

/// The draft as the check-out sends it: trimmed, or null when blank so the
/// payload carries no `complaints_suggestions` key at all.
///
///     observationToSend('  pia  '); // 'pia'
String? observationToSend(String draft) {
  final trimmed = draft.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Opens the sheet for [stop]; true when the worker chose "Escanear QR de
/// saída", false on "Cancelar" or a dismiss. [executionId] is null in the
/// Ruling 17 cold-start gap: the photo summary is left out then.
///
///     final go = await showConcludeSheet(
///       context, routeId: r, stop: s, executionId: e);
Future<bool> showConcludeSheet(
  BuildContext context, {
  required String routeId,
  required RouteStopSummary stop,
  required String? executionId,
}) async {
  final scanExit = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ConcludeSheet(
      routeId: routeId,
      stop: stop,
      executionId: executionId,
    ),
  );
  return scanExit ?? false;
}

class ConcludeSheet extends ConsumerStatefulWidget {
  const ConcludeSheet({
    required this.routeId,
    required this.stop,
    required this.executionId,
    super.key,
  });

  final String routeId;
  final RouteStopSummary stop;
  final String? executionId;

  @override
  ConsumerState<ConcludeSheet> createState() => _ConcludeSheetState();
}

class _ConcludeSheetState extends ConsumerState<ConcludeSheet> {
  late final TextEditingController _observation = TextEditingController(
    text: ref.read(observationDraftProvider(widget.stop.id)),
  );

  @override
  void dispose() {
    _observation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _sections(context),
        ),
      ),
    );
  }

  List<Widget> _sections(BuildContext context) {
    final stop = widget.stop;
    return [
      Text(
        AppStrings.concludeSheetTitle(stop.buildingName, stop.floorLabel),
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 16),
      if (widget.executionId case final executionId?)
        _PhotoSummary(
          routeId: widget.routeId,
          executionId: executionId,
          stop: stop,
        ),
      const SizedBox(height: 16),
      _observationField(),
      const SizedBox(height: 16),
      _actions(context),
    ];
  }

  Widget _observationField() {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    return TextField(
      controller: _observation,
      maxLength: maxObservationLength,
      inputFormatters: const [_CodePointLimiter(maxObservationLength)],
      // Counts code points too, so the counter matches what is enforced.
      buildCounter:
          (
            context, {
            required currentLength,
            required isFocused,
            required maxLength,
          }) => Text('${_observation.text.runes.length}/$maxLength'),
      minLines: 3,
      maxLines: 5,
      textCapitalization: TextCapitalization.sentences,
      onChanged: ref
          .read(observationDraftProvider(widget.stop.id).notifier)
          .write,
      decoration: InputDecoration(
        labelText: AppStrings.concludeObservationLabel,
        helperText: AppStrings.concludeObservationHelper,
        filled: true,
        fillColor: p.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _actions(BuildContext context) {
    final navigator = Navigator.of(context);
    // "Tirar mais" can delete photos too: the gate is read again here, not
    // only on the block's "Concluir" that opened the sheet.
    final allowed = stopMayConclude(
      ref,
      widget.routeId,
      widget.stop,
      widget.executionId,
      watch: true,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const ValueKey('conclude-scan-exit'),
          onPressed: allowed ? () => navigator.pop(true) : null,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text(AppStrings.concludeScanExitButton),
        ),
        ..._missingLine(allowed),
        const SizedBox(height: 8),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () => navigator.pop(false),
          child: const Text(AppStrings.commonCancel),
        ),
      ],
    );
  }

  /// "Falta {n} foto(s)" under a closed primary button.
  List<Widget> _missingLine(bool allowed) {
    final executionId = widget.executionId;
    if (allowed || executionId == null) return const [];
    final count =
        ref.watch(stopPhotoCountProvider((widget.routeId, executionId))) ?? 0;
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    return [
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          AppStrings.missingPhotos(missingEvidencePhotos(count)),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: p.muted),
        ),
      ),
    ];
  }
}

/// The photos of the stop's open execution: up to three thumbnails, the
/// count and "Tirar mais".
class _PhotoSummary extends ConsumerWidget {
  const _PhotoSummary({
    required this.routeId,
    required this.executionId,
    required this.stop,
  });

  final String routeId;
  final String executionId;
  final RouteStopSummary stop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = Theme.of(context).extension<FieldPalette>() ?? FieldPalette.light;
    final query = (routeId, executionId);
    final count = ref.watch(stopPhotoCountProvider(query)) ?? 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          ..._thumbnails(ref.watch(stopEvidenceProvider(query)).value),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              AppStrings.photoSequenceCounter(count),
              style: TextStyle(fontWeight: FontWeight.w700, color: p.ink),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => _takeMore(context),
            child: const Text(AppStrings.concludeTakeMore),
          ),
        ],
      ),
    );
  }

  List<Widget> _thumbnails(List<EvidenceListEntry>? items) => [
    for (final item in photosOf(items).take(_summaryThumbnails))
      Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: EvidenceThumbnail(item, size: 48),
        ),
      ),
  ];

  Future<void> _takeMore(BuildContext context) => openPhotoSequence(
    context,
    routeId: routeId,
    executionId: executionId,
    buildingName: stop.buildingName,
    floorLabel: stop.floorLabel,
    minimum: stop.requiresEvidence ? minEvidencePhotos : null,
  );
}

/// The photo entries of a stop's evidence list (none while it loads).
///
///     photosOf(ref.watch(stopEvidenceProvider(query)).value)
List<EvidenceListEntry> photosOf(List<EvidenceListEntry>? items) => [
  for (final item in items ?? const <EvidenceListEntry>[])
    if (item.kind == 'PHOTO') item,
];
