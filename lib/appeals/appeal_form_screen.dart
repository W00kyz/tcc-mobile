import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/appeals/appeal_api.dart';
import 'package:route_monitor/appeals/appeal_providers.dart';
import 'package:route_monitor/appeals/day_time.dart';
import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/sync/sync_providers.dart';
import 'package:uuid/uuid.dart';

/// The appeal reasons: the backend `AppealReason` wire value, then its pt-BR
/// label (RNF02).
const _reasonOptions = <(String, String)>[
  ('NO_SIGNAL', AppStrings.appealReasonNoSignal),
  ('LEFT_BRIEFLY', AppStrings.appealReasonLeftBriefly),
  ('APP_CLOSED', AppStrings.appealReasonAppClosed),
  ('OTHER', AppStrings.appealReasonOther),
];

/// The appeal is a declaration (spec 2026-10-20-alocacao-automatica §7.5):
/// a reason, an optional note, and what the device knows — the declared time
/// is its local check-in, read from the stop's `ReleasedStopNotice`, never
/// typed by the worker. The offline photos and answers do not go with it:
/// the form warns before sending, and once the appeal is on record deletes
/// everything the device held for the stop. Pops `true` when it is.
///
///     Navigator.of(context).push(MaterialPageRoute<bool>(
///       builder: (_) => AppealFormScreen(routeStopId: id,
///           releaseReason: 'LOCATION_SILENCE')));
class AppealFormScreen extends ConsumerStatefulWidget {
  const AppealFormScreen({
    required this.routeStopId,
    required this.releaseReason,
    this.servicePointName,
    super.key,
  });

  final String routeStopId;

  /// The server's `release_reason` for the stop.
  final String releaseReason;

  /// The point's name when the caller knows it (the snackbar path only has
  /// what the device saw of the day).
  final String? servicePointName;

  @override
  ConsumerState<AppealFormScreen> createState() => _AppealFormScreenState();
}

class _AppealFormScreenState extends ConsumerState<AppealFormScreen> {
  static const _uuid = Uuid();

  /// One per form: a retry after a lost answer files the same appeal.
  final String _idempotencyKey = _uuid.v4();
  final _noteController = TextEditingController();
  String? _reason;
  DateTime? _claimedAt;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_prefillClaimedTime());
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _prefillClaimedTime() async {
    final notice = await ref
        .read(releasedStopStoreProvider)
        .noticeFor(widget.routeStopId);
    final checkInAt = notice?.localCheckInAt;
    if (!mounted || checkInAt == null) return;
    setState(() => _claimedAt = checkInAt);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final name = widget.servicePointName;
    final claimedAt = _claimedAt;
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.appealFormTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (name != null) Text(name, style: textTheme.titleMedium),
          Text(
            AppStrings.appealReleaseReason(
              AppStrings.releaseReasonLabel(widget.releaseReason),
            ),
          ),
          const SizedBox(height: 16),
          Text(AppStrings.appealReasonLabel, style: textTheme.titleSmall),
          _ReasonChoice(
            selected: _reason,
            onChanged: (value) => setState(() => _reason = value),
          ),
          TextField(
            controller: _noteController,
            // The backend `AppealBody.note` cap.
            maxLength: 1000,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: AppStrings.appealNoteHint,
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(AppStrings.appealClaimedTimeLabel),
            subtitle: Text(
              claimedAt == null
                  ? AppStrings.appealClaimedTimeNone
                  : formatDayTime(claimedAt),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _reason == null || _sending ? null : _submit,
            child: const Text(AppStrings.appealSubmit),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null || !await _confirmLocalDataLoss()) return;
    if (!mounted) return;
    setState(() => _sending = true);
    final leavingMessage = await _file(reason);
    if (leavingMessage != null) await _finish(leavingMessage);
  }

  /// Files the appeal. Returns the message to leave with once the appeal is
  /// on record, or null after telling the worker why it is not.
  Future<String?> _file(String reason) async {
    final note = _noteController.text.trim();
    try {
      await ref
          .read(appealApiProvider)
          .file(
            routeStopId: widget.routeStopId,
            reason: reason,
            note: note.isEmpty ? null : note,
            claimedExecutedAt: _claimedAt,
            idempotencyKey: _idempotencyKey,
          );
      return AppStrings.appealSent;
    } on NotAppealableException catch (refusal) {
      final message = AppStrings.appealRefusal(refusal.reasonCode);
      // The stop already has an appeal on record: the parked data is moot.
      if (refusal.reasonCode == 'ALREADY_APPEALED') return message;
      // Any other refusal keeps the data: the worker may discard it from
      // `/recursos` or the blocked list.
      _fail(message);
      return null;
      // Deliberately broad: a network failure, or a refusal body that does
      // not decode (a TypeError from the casts in DioAppealApi) — either way
      // the button must come back for a retry.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      _fail(AppStrings.appealSendError);
      return null;
    }
  }

  /// Spec §7.5: the app warns before sending that the offline photos and
  /// answers are left behind and erased. True when the worker goes ahead.
  Future<bool> _confirmLocalDataLoss() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: const Text(AppStrings.appealLocalDataWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(AppStrings.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(AppStrings.appealWarningConfirm),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// The appeal is on record: clear the stop from the device and go back.
  /// A failed cleanup must not read as a failed appeal: the worker is told
  /// it was filed, and "Enviar recurso" again replays it — idempotent on the
  /// same key — and retries the cleanup.
  Future<void> _finish(String message) async {
    if (!mounted) return;
    try {
      await discardReleasedStop(ref, widget.routeStopId);
      // Deliberately broad: any storage failure means the same thing here.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      _fail(AppStrings.appealSentCleanupFailed);
      return;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(true);
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// The four reasons as radio tiles.
class _ReasonChoice extends StatelessWidget {
  const _ReasonChoice({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return RadioGroup<String>(
      groupValue: selected,
      onChanged: onChanged,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (value, label) in _reasonOptions)
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: value,
              title: Text(label),
            ),
        ],
      ),
    );
  }
}
