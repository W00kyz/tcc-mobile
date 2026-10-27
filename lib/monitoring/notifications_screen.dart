import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:route_monitor/l10n/strings.dart';
import 'package:route_monitor/monitoring/monitoring_providers.dart';
import 'package:route_monitor/monitoring/notification_models.dart';

/// The in-app notification list (RF49). Reached from the bell in the route
/// screen's app bar; tapping an unread row marks it read and refreshes both
/// the list and the badge count.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.notificationsAppBarTitle)),
      body: notificationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => const Center(
          child: Text(AppStrings.notificationsLoadError),
        ),
        data: (notifications) {
          if (notifications.isEmpty) {
            return const Center(child: Text(AppStrings.notificationsEmpty));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(notificationsProvider),
            child: ListView.builder(
              itemCount: notifications.length,
              itemBuilder: (context, index) => _NotificationTile(
                notification: notifications[index],
                onTap: () => _markRead(ref, notifications[index]),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _markRead(WidgetRef ref, AppNotification notification) async {
    if (!notification.isUnread) return;
    await ref.read(monitoringApiProvider).markRead(notification.id);
    ref
      ..invalidate(notificationsProvider)
      ..invalidate(unreadCountProvider);
  }
}

/// A pt-BR label for each `kind` on the wire (backend
/// `NotificationKind`). An unknown kind falls back to the raw value rather
/// than hiding the row.
String _kindLabel(String kind) => switch (kind) {
  'ALERT' => AppStrings.notificationKindAlert,
  'IMPEDIMENT_REPORTED' => AppStrings.notificationKindImpedimentReported,
  'APPEAL_FILED' => AppStrings.notificationKindAppealFiled,
  _ => kind,
};

/// `DD/MM HH:MM`, read straight off the timestamp (no `.toLocal()`) — the
/// system-wide wall-clock-tagged-UTC convention, same as `route_screen`.
String _formatTimestamp(DateTime when) {
  final day = when.day.toString().padLeft(2, '0');
  final month = when.month.toString().padLeft(2, '0');
  final hour = when.hour.toString().padLeft(2, '0');
  final minute = when.minute.toString().padLeft(2, '0');
  return '$day/$month $hour:$minute';
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = notification.isUnread;
    return ListTile(
      onTap: onTap,
      leading: unread
          ? const Icon(Icons.circle, size: 12, color: Colors.blue)
          : const SizedBox(width: 12),
      title: Text(
        notification.title,
        style: TextStyle(
          fontWeight: unread ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(notification.body),
          const SizedBox(height: 4),
          Text(
            AppStrings.notificationMeta(
              _kindLabel(notification.kind),
              _formatTimestamp(notification.createdAt),
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      isThreeLine: true,
    );
  }
}
