// test/ui/no_raw_colors_test.dart
//
// Guard (spec 6.13): screens read colour from the theme only. A raw
// `Colors.*` or `Color(0x...)` outside `lib/ui/app_theme.dart` is an offender;
// a colour with no token becomes a named constant there.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no raw colours outside lib/ui/app_theme.dart', () {
    final offenders = <String>[];
    final re = RegExp(r'Colors\.\w+|Color\(0x');
    final entries = Directory('lib').listSync(recursive: true);
    for (final f in entries.whereType<File>()) {
      final path = f.path.replaceAll(r'\', '/');
      if (!path.endsWith('.dart') || path.endsWith('.g.dart')) continue;
      if (path.endsWith('lib/ui/app_theme.dart')) continue;
      for (final m in re.allMatches(f.readAsStringSync())) {
        offenders.add('$path: ${m.group(0)}');
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
