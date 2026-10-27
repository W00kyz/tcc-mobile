import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/monitoring/notification_models.dart';

void main() {
  test('fromJson parses a full unread notification', () {
    final note = AppNotification.fromJson({
      'id': 'n1',
      'kind': 'IMPEDIMENT_REPORTED',
      'title': 'Rota alterada',
      'body': 'Um ponto foi adicionado à sua rota.',
      'created_at': '2026-09-07T09:00:00Z',
      'read_at': null,
    });

    expect(note.id, 'n1');
    expect(note.kind, 'IMPEDIMENT_REPORTED');
    expect(note.title, 'Rota alterada');
    expect(note.body, 'Um ponto foi adicionado à sua rota.');
    expect(note.createdAt, DateTime.utc(2026, 9, 7, 9));
    expect(note.readAt, isNull);
    expect(note.isUnread, isTrue);
  });

  test('fromJson parses a non-null read_at as a read notification', () {
    final note = AppNotification.fromJson({
      'id': 'n2',
      'kind': 'ALERT',
      'title': 'Alerta',
      'body': 'Profissional parado há 20 min.',
      'created_at': '2026-09-07T09:00:00Z',
      'read_at': '2026-09-07T09:30:00Z',
    });

    expect(note.readAt, DateTime.utc(2026, 9, 7, 9, 30));
    expect(note.isUnread, isFalse);
  });
}
