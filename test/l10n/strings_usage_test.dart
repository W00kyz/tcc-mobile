// test/l10n/strings_usage_test.dart
//
// Guard (RNF02): no user-facing string literal may live in a widget — every
// piece of copy goes through `AppStrings`. The regex is deliberately narrow
// (a `Text('… …')` with an inner space); the acceptance bar is "no offender",
// not a full lint. `package:flutter_test` re-exports `package:test` here so the
// file needs no extra dependency.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no user-facing string literals outside AppStrings', () {
    final offenders = <String>[];
    final re = RegExp(
      r'''(?:Text\(\s*|(?:name|message|tooltip|channelName|channelDescription):\s*)['"][^'"]*\s[^'"]*['"]''',
    );
    final entries = Directory('lib').listSync(recursive: true);
    for (final f in entries.whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('.g.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in re.allMatches(src)) {
        offenders.add('${f.path}: ${m.group(0)}');
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
