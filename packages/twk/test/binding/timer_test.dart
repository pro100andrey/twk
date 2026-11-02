// AppBinding.startTimer and startPeriodic: timers on the app's clock, in the
// app's zone, wherever they are started from: a test's body, outside the
// fake clock's zone, gets timers the clock moves, not real ones.
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  testTwk('a timer started from the body fires when the clock moves, '
      'not when real time passes', (t) async {
    await t.pumpWidget(const Text('x'));
    final binding = t.binding;
    var fired = 0;
    binding.startTimer(const Duration(milliseconds: 20), () => fired++);
    // real time is what is passed here: a real timer would have fired
    // ignore: twk_lints/wall_time_in_tests
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(fired, 0);
    await t.pump(const Duration(milliseconds: 19));
    expect(fired, 0);
    await t.pump(const Duration(milliseconds: 1));
    expect(fired, 1);
  });

  testTwk('a periodic timer started from the body ticks with the clock, '
      'and stops when cancelled', (t) async {
    await t.pumpWidget(const Text('x'));
    var ticks = 0;
    final timer = t.binding.startPeriodic(
      const Duration(milliseconds: 10),
      (_) => ticks++,
    );
    // real time is what is passed here: a real timer would have ticked
    // ignore: twk_lints/wall_time_in_tests
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(ticks, 0);
    await t.pump(const Duration(milliseconds: 35));
    expect(ticks, 3);
    timer.cancel();
    await t.pump(const Duration(milliseconds: 50));
    expect(ticks, 3);
  });

  test('no Timer is made in lib but through the binding', () {
    final made = RegExp(r'\bTimer(\.periodic)?\(');
    final found = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      var n = 0;
      for (final line in entity.readAsLinesSync()) {
        n++;
        if (line.trimLeft().startsWith('//')) {
          continue;
        }
        if (made.hasMatch(line)) {
          found.add('${entity.path}:$n: ${line.trim()}');
        }
      }
    }
    expect(found, isEmpty, reason: 'start it with AppBinding.startTimer');
  });
}
