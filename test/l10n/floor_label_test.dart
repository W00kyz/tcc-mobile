import 'package:flutter_test/flutter_test.dart';
import 'package:route_monitor/l10n/floor_label.dart';

void main() {
  test('a bare number reads "Andar <n>"', () {
    expect(floorDisplayLabel('1'), 'Andar 1');
    expect(floorDisplayLabel('12'), 'Andar 12');
  });

  test('any other label is kept as the backend wrote it', () {
    expect(floorDisplayLabel('Térreo'), 'Térreo');
    expect(floorDisplayLabel('1º andar'), '1º andar');
    expect(floorDisplayLabel('-1'), '-1');
    expect(floorDisplayLabel(''), '');
  });
}
