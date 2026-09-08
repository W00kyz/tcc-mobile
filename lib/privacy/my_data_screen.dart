import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/privacy/my_data_api.dart';
import 'package:route_monitor/privacy/my_data_providers.dart';

/// Read-only "Meus dados" transparency screen (LGPD, RNF10): shows the field
/// worker every category of personal data the system holds about them, grouped
/// into cards. Nothing here is editable — it is a disclosure surface.
class MyDataScreen extends ConsumerWidget {
  const MyDataScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(myDataProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.myDataTitle)),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(AppStrings.myDataError),
          ),
        ),
        data: (data) => _MyDataBody(data: data),
      ),
    );
  }
}

/// Formats a date for display as `d/m/yyyy`, or `—` when absent. Deliberately
/// tiny and locale-agnostic — the app ships pt-BR only and adding `intl` for
/// one date format is not worth the dependency.
String _fmt(DateTime? date) {
  if (date == null) return '—';
  return '${date.day}/${date.month}/${date.year}';
}

class _MyDataBody extends StatelessWidget {
  const _MyDataBody({required this.data});

  final PersonalData data;

  @override
  Widget build(BuildContext context) {
    final profile = data.profile;
    final fieldWorker = data.fieldWorker;
    final executions = data.executionsSummary;
    final positions = data.positionsSummary;
    final evidence = data.evidenceSummary;
    final notifications = data.notificationsSummary;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Section(
          title: AppStrings.myDataSectionProfile,
          rows: [
            _Row(AppStrings.myDataFieldEmail, profile.email),
            _Row(AppStrings.myDataFieldName, profile.name),
            _Row(AppStrings.myDataFieldRole, profile.role),
            _Row(
              AppStrings.myDataFieldActive,
              profile.isActive
                  ? AppStrings.myDataFieldActive
                  : AppStrings.myDataFieldInactive,
            ),
            _Row(AppStrings.myDataFieldCreatedAt, _fmt(profile.createdAt)),
          ],
        ),
        _Section(
          title: AppStrings.myDataSectionFieldWorker,
          empty: fieldWorker == null,
          rows: fieldWorker == null
              ? const []
              : [
                  _Row(AppStrings.myDataFieldFullName, fieldWorker.fullName),
                  _Row(
                    AppStrings.myDataFieldCompany,
                    fieldWorker.contractorCompanyId,
                  ),
                  _Row(
                    AppStrings.myDataFieldServiceTypes,
                    fieldWorker.serviceTypeIds.isEmpty
                        ? AppStrings.myDataEmpty
                        : fieldWorker.serviceTypeIds.join(', '),
                  ),
                ],
        ),
        _Section(
          title: AppStrings.myDataSectionConsent,
          empty: data.consentHistory.isEmpty,
          rows: [
            for (final entry in data.consentHistory)
              _Row(
                AppStrings.myDataConsentVersion(entry.noticeVersion),
                _fmt(entry.acceptedAt),
              ),
          ],
        ),
        _Section(
          title: AppStrings.myDataSectionAuthEvents,
          empty: data.authEvents.isEmpty,
          rows: [
            for (final event in data.authEvents)
              _Row(
                event.event,
                '${_fmt(event.createdAt)} · ${event.ipAddress ?? '—'}',
              ),
          ],
        ),
        _Section(
          title: AppStrings.myDataSectionExecutions,
          rows: [
            _Row(AppStrings.myDataFieldTotal, '${executions.total}'),
            _Row(AppStrings.myDataFieldFirstAt, _fmt(executions.firstAt)),
            _Row(AppStrings.myDataFieldLastAt, _fmt(executions.lastAt)),
          ],
        ),
        _Section(
          title: AppStrings.myDataSectionEvidence,
          rows: [
            _Row(AppStrings.myDataFieldEvidenceItems, '${evidence.totalItems}'),
            _Row(
              AppStrings.myDataFieldEvidenceBytes,
              AppStrings.myDataKilobytes(evidence.totalBytes),
            ),
          ],
        ),
        _Section(
          title: AppStrings.myDataSectionPositions,
          rows: [
            _Row(AppStrings.myDataFieldTotal, '${positions.total}'),
            _Row(AppStrings.myDataFieldFirstAt, _fmt(positions.firstAt)),
            _Row(AppStrings.myDataFieldLastAt, _fmt(positions.lastAt)),
          ],
        ),
        _Section(
          title: AppStrings.myDataSectionNotifications,
          rows: [
            _Row(AppStrings.myDataFieldTotal, '${notifications.total}'),
            _Row(
              AppStrings.myDataFieldNotificationsUnread,
              '${notifications.unread}',
            ),
          ],
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows, this.empty = false});

  final String title;
  final List<_Row> rows;

  /// When true (or [rows] is empty), the card shows [AppStrings.myDataEmpty]
  /// instead of a row list — never a literal `null` or `Instance of`.
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final showEmpty = empty || rows.isEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (showEmpty) const Text(AppStrings.myDataEmpty) else ...rows,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: const TextStyle(color: Colors.black54)),
          ),
          Expanded(flex: 3, child: Text(value)),
        ],
      ),
    );
  }
}
