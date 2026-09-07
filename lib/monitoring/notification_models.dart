/// The wire shape of one row from `GET /notifications/me` (backend
/// `app/schemas/notification.py` `NotificationOut`) — an in-app notification
/// surfaced to the field worker (RF49: a route was assigned or modified).
///
///     final note = AppNotification.fromJson(json);
///     if (note.isUnread) markInBold(note);
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.readAt,
  });

  /// Parses the JSON object for a single notification. `read_at` is null for
  /// an unread row and an ISO-8601 timestamp once the worker has opened it.
  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        kind: json['kind'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        readAt: json['read_at'] == null
            ? null
            : DateTime.parse(json['read_at'] as String),
      );

  final String id;

  /// One of `ALERT`, `ROUTE_ASSIGNED`, `ROUTE_MODIFIED`, `STOP_REASSIGNED` —
  /// rendered as a pt-BR chip by `NotificationsScreen`.
  final String kind;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;
}
