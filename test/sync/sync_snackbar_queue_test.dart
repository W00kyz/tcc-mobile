import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/sync/sync_snackbar_queue.dart';
import 'package:route_monitor/sync/sync_status.dart';

RouteSyncStatus _s(
  RouteSyncState state, {
  int pending = 0,
  int blocked = 0,
}) => RouteSyncStatus(
  routeId: 'r1',
  state: state,
  pending: pending,
  blocked: blocked,
);

final RouteSyncStatus _idle = _s(RouteSyncState.idle);

void main() {
  late SyncSnackbarQueue queue;
  setUp(() => queue = SyncSnackbarQueue());

  test('idle to syncing with 3 pending is Sending(3)', () {
    final notice = queue.next(
      _s(RouteSyncState.idle, pending: 3),
      _s(RouteSyncState.syncing, pending: 3),
      online: true,
    );
    expect(notice, isA<Sending>().having((n) => n.n, 'n', 3));
  });

  test('syncing to idle with nothing pending after a Sending is AllSent', () {
    queue.next(_idle, _s(RouteSyncState.syncing, pending: 2), online: true);
    final notice = queue.next(
      _s(RouteSyncState.syncing, pending: 2),
      _idle,
      online: true,
    );
    expect(notice, isA<AllSent>());
  });

  test('idle to idle with nothing pending and no Sending is silent', () {
    expect(
      queue.next(
        _s(RouteSyncState.idle, pending: 1),
        _idle,
        online: true,
      ),
      isNull,
    );
  });

  test('two pending while offline is Waiting(2), once', () {
    final after = _s(RouteSyncState.idle, pending: 2);
    final notice = queue.next(_idle, after, online: false);
    expect(notice, isA<Waiting>().having((n) => n.n, 'n', 2));
    expect(queue.next(after, after, online: false), isNull);
  });

  test('blocked 0 to 1 is Blocked(1)', () {
    final notice = queue.next(
      _idle,
      _s(RouteSyncState.blocked, blocked: 1),
      online: true,
    );
    expect(notice, isA<Blocked>().having((n) => n.n, 'n', 1));
  });

  test('an unchanged status twice gives nothing', () {
    final status = _s(RouteSyncState.syncing, pending: 3);
    expect(queue.next(status, status, online: true), isNull);
    expect(queue.next(status, status, online: true), isNull);
  });
}
