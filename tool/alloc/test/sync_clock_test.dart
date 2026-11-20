// SyncClock: the profiler's clock, a DrivenClock's timers with a zone and
// a microtask drain of its own.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk_alloc/sync_clock.dart';

const _ms = Duration(milliseconds: 1);

// In the clock's zone a Timer is the clock's, not the wall's: the zone is
// what is under test.
// ignore: twk_lints/wall_time_in_tests
Timer _after(Duration d, void Function() f) => Timer(d, f);

// (as above)
// ignore: twk_lints/wall_time_in_tests
Timer _every(Duration d, void Function(Timer) f) => Timer.periodic(d, f);

void main() {
  test('fires timers by due time, those due together in the order they '
      'were started, the microtasks run after each', () {
    final clock = SyncClock();
    final log = <String>[];
    clock.run(() {
      _after(_ms * 2, () => log.add('b'));
      _after(_ms, () {
        log.add('a');
        scheduleMicrotask(() => log.add('a-micro'));
      });
      _after(_ms * 2, () => log.add('c'));
      scheduleMicrotask(() => log.add('first'));
    });
    expect(log, isEmpty);
    clock.elapse(_ms * 3);
    expect(log, ['first', 'a', 'a-micro', 'b', 'c']);
    expect(clock.elapsed, _ms * 3);
    expect(clock.elapsedMicroseconds, 3000);
  });

  test('a periodic timer re-arms, and one of no period is a microsecond', () {
    var ticks = 0;
    var fast = 0;
    SyncClock()
      ..run(() {
        _every(_ms, (_) => ticks++);
        _every(Duration.zero, (_) => fast++);
      })
      ..elapse(_ms * 3);
    expect(ticks, 3);
    expect(fast, 3000);
  });

  test('a cancelled timer does not fire; the clock stops at the end of the '
      'step', () {
    final clock = SyncClock();
    var fired = false;
    late Timer timer;
    clock.run(() => timer = _after(_ms, () => fired = true));
    expect(timer.isActive, isTrue);
    timer.cancel();
    clock.elapse(_ms * 2);
    expect(fired, isFalse);
    expect(timer.isActive, isFalse);
    expect(clock.elapsed, _ms * 2);
  });

  test("the clock's own timers need no zone", () {
    final log = <int>[];
    SyncClock()
      ..timer(_ms, () => log.add(1))
      ..periodic(_ms * 2, (t) => log.add(10 + t.tick))
      ..elapse(_ms * 4);
    expect(log, [1, 11, 12]);
  });
}
