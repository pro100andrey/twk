// A hosted program's timers (the reaper that waits for its end, the grace
// before it is killed after a hang-up) run on real time: a `TerminalView`
// makes its `Pty` in the app's zone, which a driver of the app
// (TWK_DRIVEN) gives a clock that moves only when it says, and a shell
// whose end waited for that clock would never be seen to end.
@Tags(['process'])
@TestOn('linux || mac-os')
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk_term/twk_term.dart';
import 'package:twk_test/twk_test.dart' show waitFor;

void main() {
  test('the reaper and the hang-up grace are made in the root zone, not in '
      'the zone that starts and closes the Pty', () async {
    final made = <Duration>[];
    final zone = Zone.current.fork(
      specification: ZoneSpecification(
        createTimer: (self, parent, zone, after, callback) {
          made.add(after);
          return parent.createTimer(zone, after, callback);
        },
        createPeriodicTimer: (self, parent, zone, every, callback) {
          made.add(every);
          return parent.createPeriodicTimer(zone, every, callback);
        },
      ),
    );
    final pty = zone.run(() => Pty.start('sleep', ['30']));
    addTearDown(pty.close);
    final reading = pty.output.listen((_) {});
    addTearDown(reading.cancel);
    zone.run(() {
      pty
        ..kill(ProcessSignal.sigkill)
        ..close();
    });
    await waitFor(pty.exitCode, 'the program to end');
    await pumpEventQueue();
    expect(made, isEmpty);
  });
}
