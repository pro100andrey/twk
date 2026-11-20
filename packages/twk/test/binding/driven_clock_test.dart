// DrivenClock: the app's time that moves when told to: timers by due time
// and creation order, periodic ones, the cap on one move, timers due now,
// and an app whose frames it spaces.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const _ms = Duration(milliseconds: 1);

void main() {
  group('timers fire', () {
    late DrivenClock clock;
    late List<String> fired;
    setUp(() {
      // what is due now waits for a move: nothing wakes by itself
      clock = DrivenClock(wakesItself: false);
      fired = [];
    });

    test('by due time, those due together in the order they were started', () {
      clock
        ..timer(_ms * 30, () => fired.add('c30'))
        ..timer(_ms * 10, () => fired.add('a10'))
        ..timer(_ms * 20, () => fired.add('b20'))
        ..timer(_ms * 10, () => fired.add('a10 again'))
        ..timer(_ms * 20, () => fired.add('b20 again'))
        ..advance(_ms * 100);
      expect(fired, ['a10', 'a10 again', 'b20', 'b20 again', 'c30']);
      expect(clock.elapsedMicroseconds, 100000);
      expect(clock.pendingTimers, 0);
    });

    test("with the clock at the timer's time, and not before the end of "
        'the move', () {
      final seen = <int>[];
      clock
        ..timer(_ms * 10, () => seen.add(clock.elapsedMicroseconds))
        ..timer(_ms * 25, () => seen.add(clock.elapsedMicroseconds))
        ..advance(_ms * 20);
      expect(seen, [10000]);
      expect(clock.elapsed, _ms * 20);
      clock.advance(_ms * 5);
      expect(seen, [10000, 25000]);
    });

    test('a timer started by a timer fires in the same move when it is due '
        'by its end, after those due together before it', () {
      clock
        ..timer(_ms * 10, () {
          fired.add('first');
          clock
            ..timer(_ms * 5, () => fired.add('nested'))
            ..timer(Duration.zero, () => fired.add('nested now'));
        })
        ..timer(_ms * 10, () => fired.add('second'))
        ..timer(_ms * 20, () => fired.add('late'))
        ..advance(_ms * 16);
      expect(fired, ['first', 'second', 'nested now', 'nested']);
      expect(clock.pendingTimers, 1);
    });

    test('not once cancelled, and a timer cancelled by another one due '
        'before it', () {
      final a = clock.timer(_ms * 10, () => fired.add('a'));
      clock
        ..timer(_ms * 5, a.cancel)
        ..timer(_ms * 7, () => fired.add('b'));
      expect(a.isActive, isTrue);
      clock.advance(_ms * 20);
      expect(fired, ['b']);
      expect(a.isActive, isFalse);
    });

    test('a timer fires once and is no longer active; its tick counts', () {
      final timer = clock.timer(_ms * 3, () => fired.add('x'));
      expect(timer.tick, 0);
      clock.advance(_ms * 3);
      expect(timer.tick, 1);
      expect(timer.isActive, isFalse);
      clock.advance(_ms * 30);
      expect(fired, ['x']);
    });
  });

  group('periodic timers', () {
    late DrivenClock clock;
    setUp(() => clock = DrivenClock(wakesItself: false));

    test('fire every period, and order with the others by their time and '
        'then by when each was last started', () {
      final fired = <String>[];
      clock
        ..periodic(_ms * 10, (t) => fired.add('p${t.tick}'))
        ..timer(_ms * 20, () => fired.add('once 20'))
        ..advance(_ms * 30);
      // due together at 20, the one-shot timer was started before the
      // periodic one was set again by its first firing: it goes first
      expect(fired, ['p1', 'once 20', 'p2', 'p3']);
    });

    test('stop when cancelled, from their own callback too', () {
      var ticks = 0;
      clock
        ..periodic(_ms * 10, (t) {
          if (++ticks == 3) {
            t.cancel();
          }
        })
        ..advance(_ms * 100);
      expect(ticks, 3);
      expect(clock.pendingTimers, 0);
    });

    test('of no period fire once a microsecond: a million times in a '
        'second, and that is what they are measured by', () {
      var ticks = 0;
      clock
        ..periodic(Duration.zero, (_) => ticks++)
        ..advance(const Duration(milliseconds: 5));
      expect(ticks, 5000);
    });
  });

  group('the cap on timers one move fires', () {
    test('ends a move that never would, naming the timers that wait', () {
      final clock = DrivenClock(wakesItself: false, maxFired: 100)
        ..periodic(const Duration(microseconds: 1), (_) {});
      expect(
        () => clock.advance(const Duration(seconds: 1)),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('fired 100 timers'), contains('a periodic timer')),
          ),
        ),
      );
      // the move ended where it was stopped, and the clock is usable
      expect(clock.elapsedMicroseconds, lessThan(1000000));
      clock.advance(const Duration(microseconds: 1));
    });

    test('ends a chain of timers that start one another with no wait', () {
      final clock = DrivenClock(wakesItself: false, maxFired: 50);
      void again() => clock.timer(Duration.zero, again);
      again();
      expect(clock.advanceToNext, throwsStateError);
      expect(clock.elapsedMicroseconds, 0);
    });

    test('allows as many as it says, one move after another', () {
      final clock = DrivenClock(wakesItself: false, maxFired: 10);
      var ticks = 0;
      clock
        ..periodic(const Duration(microseconds: 1), (_) => ticks++)
        ..advance(const Duration(microseconds: 10))
        ..advance(const Duration(microseconds: 10));
      expect(ticks, 20);
    });
  });

  group('timers due now', () {
    test('run by themselves, from the root zone, with the time where it '
        'is', () async {
      final clock = DrivenClock();
      final fired = <String>[];
      clock
        ..timer(Duration.zero, () => fired.add('a'))
        ..timer(const Duration(microseconds: -5), () => fired.add('b'))
        ..timer(_ms, () => fired.add('later'));
      expect(fired, isEmpty);
      await waitUntil(() => fired.length == 2, 'the timers due now');
      expect(fired, ['a', 'b']);
      expect(clock.elapsedMicroseconds, 0);
      expect(clock.pendingTimers, 1);
      // the one that is not due waits for the clock
      await pumpEventQueue();
      expect(fired, hasLength(2));
      clock.advance(_ms);
      expect(fired, ['a', 'b', 'later']);
    });

    test('those started by a timer due now run too, the time standing '
        'still', () async {
      final clock = DrivenClock();
      final times = <int>[];
      clock
        ..timer(const Duration(milliseconds: 5), () {})
        ..advance(_ms * 5)
        ..timer(Duration.zero, () {
          times.add(clock.elapsedMicroseconds);
          clock.timer(
            Duration.zero,
            () => times.add(clock.elapsedMicroseconds),
          );
        });
      await waitUntil(() => times.length == 2, 'the chain');
      expect(times, [5000, 5000]);
    });

    test('wait for a move where the clock does not wake itself', () async {
      final clock = DrivenClock(wakesItself: false);
      var fired = false;
      clock.timer(Duration.zero, () => fired = true);
      await pumpEventQueue();
      expect(fired, isFalse);
      clock.advance(Duration.zero);
      expect(fired, isTrue);
    });

    test('run in the move that is under way when one is, not twice', () {
      final clock = DrivenClock();
      final fired = <String>[];
      clock.timer(_ms, () {
        fired.add('a');
        clock.timer(Duration.zero, () => fired.add('b'));
      });
      clock.advance(_ms);
      expect(fired, ['a', 'b']);
    });
  });

  group('moves', () {
    late DrivenClock clock;
    setUp(() => clock = DrivenClock(wakesItself: false));

    test("advanceTo moves to a time; one before the clock's, or a "
        'negative step, is an error', () {
      clock.advanceTo(7000);
      expect(clock.elapsedMicroseconds, 7000);
      expect(() => clock.advanceTo(6999), throwsArgumentError);
      expect(
        () => clock.advance(const Duration(microseconds: -1)),
        throwsArgumentError,
      );
      clock.advanceTo(7000);
      expect(clock.elapsedMicroseconds, 7000);
    });

    test('advanceToNext moves to the next due time and fires every timer '
        'due then; false while none waits', () {
      expect(clock.advanceToNext(), isFalse);
      final fired = <String>[];
      clock
        ..timer(_ms * 4, () => fired.add('x'))
        ..timer(_ms * 4, () => fired.add('y'))
        ..timer(_ms * 9, () => fired.add('z'));
      expect(clock.nextDue, 4000);
      expect(clock.advanceToNext(), isTrue);
      expect(fired, ['x', 'y']);
      expect(clock.elapsedMicroseconds, 4000);
      expect(clock.nextDue, 9000);
      expect(clock.advanceToNext(), isTrue);
      expect(fired, ['x', 'y', 'z']);
      expect(clock.nextDue, isNull);
    });

    test('a move is not re-entrant', () {
      Object? error;
      clock.timer(_ms, () {
        try {
          clock.advance(_ms);
        } on Object catch (e) {
          error = e;
        }
      });
      clock.advance(_ms * 2);
      expect(error, isA<StateError>());
      expect(clock.elapsedMicroseconds, 2000);
    });

    test('beforeMove is called while the clock still has the old time, '
        'once for each time it changes', () {
      final seen = <int>[];
      clock
        ..beforeMove = (() => seen.add(clock.elapsedMicroseconds))
        ..timer(_ms * 3, () {})
        ..timer(_ms * 3, () {})
        ..advance(_ms * 5);
      clock.advance(Duration.zero);
      expect(seen, [0, 3000]);
    });
  });

  group('describeTimers', () {
    test('says when each is due, whether it is periodic and where it was '
        'started; and that none waits', () {
      final clock = DrivenClock(wakesItself: false, recordStacks: true);
      expect(clock.describeTimers(), 'no timer waits');
      clock
        ..periodic(_ms * 500, (_) {})
        ..timer(const Duration(seconds: 2), () {})
        ..advance(_ms * 100);
      final text = clock.describeTimers();
      final lines = text.split('\n');
      // the periodic one is due first, then the one-shot
      expect(
        lines.first,
        'a periodic timer, every 0.500 s, due in 0.400 s, started at',
      );
      expect(text, contains('a timer due in 1.900 s, started at'));
      expect(text, contains('driven_clock_test.dart'));
      expect(text, isNot(contains('driven_clock.dart')));
    });
  });

  group('recordStacks', () {
    test('off by default: a timer names when it is due, not where it was '
        'started', () {
      final clock = DrivenClock(wakesItself: false)
        ..periodic(_ms * 500, (_) {})
        ..timer(const Duration(seconds: 2), () {});
      expect(
        clock.describeTimers(),
        'a periodic timer, every 0.500 s, due in 0.500 s\n'
        'a timer due in 2.000 s',
      );
      expect(clock.waiting.map((t) => t.created), [null, null]);
    });

    test('a stack goes when its timer fires or is cancelled, and is no longer '
        'listed', () {
      final clock = DrivenClock(wakesItself: false, recordStacks: true);
      final once = clock.timer(_ms, () {});
      final cancelled = clock.timer(_ms * 5, () {});
      final each = clock.periodic(_ms * 2, (_) {});
      expect(clock.recordedStacks, 3);
      clock.advance(_ms);
      expect(clock.recordedStacks, 2);
      expect(once.isActive, isFalse);
      cancelled.cancel();
      expect(clock.recordedStacks, 1);
      expect(clock.waiting, hasLength(1));
      clock.advance(_ms * 10);
      // a periodic timer keeps its stack for as long as it waits
      expect(clock.recordedStacks, 1);
      each.cancel();
      expect(clock.recordedStacks, 0);
      expect(clock.describeTimers(), 'no timer waits');
    });

    test('off: none is held', () {
      final clock = DrivenClock(wakesItself: false)..timer(_ms, () {});
      expect(clock.recordedStacks, 0);
    });

    test('on: the first line outside the clocks is where it was started', () {
      final clock = DrivenClock(wakesItself: false, recordStacks: true)
        ..timer(_ms, () {});
      expect(clock.waiting.single.created, contains('driven_clock_test.dart'));
    });
  });

  group('an app spaced by it', () {
    test('runs its first frame without a move, the next when the clock '
        'reaches the gap of maxFps, and no sooner', () async {
      final clock = DrivenClock();
      final term = HeadlessTerminal(width: 10, height: 2);
      final binding = AppBinding(
        term,
        maxFps: 10,
        clock: clock,
        environment: const {},
      );
      final app = binding.twkApp;
      final done = binding.run(const Text('hi'));
      await waitUntil(() => app.framesRun == 1, 'the first frame');
      expect(clock.elapsedMicroseconds, 0);

      app.requestFrame();
      // a frame at 10 a second is due a gap, 100 ms, after the first
      expect(app.frameDue, 100000);
      expect(clock.nextDue, 100000);
      await pumpEventQueue();
      expect(app.framesRun, 1);
      clock.advance(const Duration(milliseconds: 99));
      await pumpEventQueue();
      expect(app.framesRun, 1);
      clock.advance(_ms);
      await waitUntil(() => app.framesRun == 2, 'the second frame');
      expect(app.frameDue, isNull);

      binding.quit();
      await waitFor(done, 'the app to end');
    });

    test("a timer the app starts is the clock's: it fires when the clock "
        "moves, in the app's zone", () async {
      final clock = DrivenClock();
      final term = HeadlessTerminal(width: 10, height: 2);
      final binding = AppBinding(term, clock: clock, environment: const {});
      final done = binding.run(const Text('hi'));
      await waitUntil(() => binding.twkApp.framesRun == 1, 'a frame');
      Zone? zone;
      var ticks = 0;
      binding.startPeriodic(const Duration(seconds: 1), (_) {
        ticks++;
        zone = Zone.current;
      });
      clock.advance(const Duration(seconds: 3));
      expect(ticks, 3);
      expect(zone, isNotNull);
      binding.quit();
      await waitFor(done, 'the app to end');
    });
  });
}
