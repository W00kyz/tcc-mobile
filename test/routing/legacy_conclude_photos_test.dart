import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/local/local_write_store.dart';

import '../support/fake_route_repository.dart';
import 'map_home_harness.dart';

// LEGACY: the in-progress block's "Concluir" has no stamp step, so
// `concludeStop` itself must let the stop's held photos leave (they are taken
// `held`, see ExecutionRepository.addPhoto).

void main() {
  testWidgets('concluding a stop releases its held photo and leaves the '
      'photos of other stops held', (tester) async {
    final store = InMemoryLocalWriteStore();
    for (final (id, execution) in [('p1', 'exec-1'), ('p2', 'exec-2')]) {
      await store.enqueue(
        id: id,
        kind: PendingOpKind.evidencePhoto,
        payload: {'execution_id': execution},
        routeId: 'r1',
        initialState: PendingOpState.held,
      );
    }
    final route = routeWith(
      stops: [stopIn(id: 's1', status: 'IN_PROGRESS')],
    );
    await pumpHome(
      tester,
      homeWith(
        repositoryWith(route),
        localWriteStore: store,
        stopProgressStore: FakeStopProgressStore({'s1': 'exec-1'}),
      ),
    );

    await concludeWith(tester, 'v1.floor.1.sig');

    final states = {
      for (final row in await store.unsyncedForRoute('r1'))
        if (row.kind == PendingOpKind.evidencePhoto) row.id: row.state,
    };
    expect(states, {'p1': PendingOpState.pending, 'p2': PendingOpState.held});
  });
}
