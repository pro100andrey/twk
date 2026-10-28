// The fake clock: timers and microtasks of its zone run only as it moves.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  test('a timer fires once elapse reaches its time, not before', () async {
    final clock = FakeClock();
    final fired = <Duration>[];
    clock.run(
      () => Timer(
        const Duration(milliseconds: 30),
        () => fired.add(clock.elapsed),
      ),
    );
    await clock.elapse(const Duration(milliseconds: 29));
    expect(fired, isEmpty);
    await clock.elapse(const Duration(milliseconds: 1));
    expect(fired, [const Duration(milliseconds: 30)]);
    expect(clock.pendingTimers, 0);
  });

  test('timers fire in the order of their times, those due together in the '
      'order they were started, with the microtasks after each', () async {
    final clock = FakeClock();
    final seen = <String>[];
    clock.run(() {
      Timer(const Duration(milliseconds: 20), () => seen.add('b'));
      Timer(const Duration(milliseconds: 10), () {
        seen.add('a');
        scheduleMicrotask(() => seen.add('a microtask'));
      });
      Timer(const Duration(milliseconds: 20), () => seen.add('c'));
      Timer.run(() => seen.add('now'));
    });
    expect(seen, isEmpty, reason: 'even a zero timer waits for elapse');
    await clock.elapse(const Duration(seconds: 1));
    expect(seen, ['now', 'a', 'a microtask', 'b', 'c']);
    expect(clock.elapsed, const Duration(seconds: 1));
  });

  test('a timer started by a timer fires in the same elapse when it is due '
      'by its end', () async {
    final clock = FakeClock();
    final fired = <Duration>[];
    clock.run(
      () => Timer(const Duration(milliseconds: 10), () {
        fired.add(clock.elapsed);
        Timer(
          const Duration(milliseconds: 10),
          () => fired.add(clock.elapsed),
        );
      }),
    );
    await clock.elapse(const Duration(milliseconds: 20));
    expect(fired, [
      const Duration(milliseconds: 10),
      const Duration(milliseconds: 20),
    ]);
  });

  test('a periodic timer fires each period, its tick counting, until it is '
      'cancelled', () async {
    final clock = FakeClock();
    final ticks = <int>[];
    final timer = clock.run(
      () => Timer.periodic(
        const Duration(milliseconds: 10),
        (t) => ticks.add(t.tick),
      ),
    );
    await clock.elapse(const Duration(milliseconds: 35));
    expect(ticks, [1, 2, 3]);
    expect(timer.isActive, isTrue);
    timer.cancel();
    expect(timer.isActive, isFalse);
    await clock.elapse(const Duration(seconds: 1));
    expect(ticks, [1, 2, 3]);
  });

  test('a cancelled timer does not fire', () async {
    final clock = FakeClock();
    var fired = false;
    clock
        .run(() => Timer(const Duration(milliseconds: 1), () => fired = true))
        .cancel();
    await clock.elapse(const Duration(seconds: 1));
    expect(fired, isFalse);
  });

  test('microtasks of the zone wait for a flush: futures complete then, '
      'also those resumed by a future completed outside the zone', () async {
    final clock = FakeClock();
    final seen = <String>[];
    // ignore: close_sinks, its listener cancels
    final controller = StreamController<int>();
    clock.run(() {
      unawaited(Future<void>.value().then((_) => seen.add('value')));
      final subscription = controller.stream.listen(null);
      unawaited(() async {
        // completed in the root zone: resumed by a real microtask
        await subscription.cancel();
        await null;
        seen.add('cancelled');
      }());
    });
    expect(seen, isEmpty);
    await clock.flushMicrotasks();
    expect(seen, ['value', 'cancelled']);
  });

  test('Future.delayed completes when the clock reaches it', () async {
    final clock = FakeClock();
    var done = false;
    clock.run(
      () => unawaited(
        Future<void>.delayed(
          const Duration(seconds: 5),
        ).then((_) => done = true),
      ),
    );
    await clock.elapse(const Duration(seconds: 4));
    expect(done, isFalse);
    await clock.elapse(const Duration(seconds: 1));
    expect(done, isTrue);
  });

  test('an error in a timer goes to the zone it was started in', () async {
    final clock = FakeClock();
    final errors = <Object>[];
    clock.run(
      () => runZonedGuarded(
        () => Timer(Duration.zero, () => throw StateError('boom')),
        (e, _) => errors.add(e),
      ),
    );
    await clock.elapse(Duration.zero);
    expect(errors, [isA<StateError>()]);
  });

  test('the stopwatch reads the clock; stopped, it counts no more', () async {
    final clock = FakeClock();
    final watch = clock.stopwatch;
    expect(watch.isRunning, isTrue);
    await clock.elapse(const Duration(milliseconds: 1500));
    expect(watch.elapsedMicroseconds, 1500000);
    expect(watch.elapsedMilliseconds, 1500);
    expect(watch.elapsed, const Duration(milliseconds: 1500));
    expect(watch.elapsedTicks, 1500000);
    expect(watch.frequency, 1000000);
    watch.stop();
    await clock.elapse(const Duration(seconds: 1));
    expect(watch.elapsedMicroseconds, 1500000);
    watch
      ..start()
      ..reset();
    await clock.elapse(const Duration(milliseconds: 2));
    expect(watch.elapsedMicroseconds, 2000);
  });

  test('elapse is not re-entrant, nor negative', () async {
    final clock = FakeClock();
    final moving = clock.elapse(const Duration(seconds: 1));
    await expectLater(clock.elapse(Duration.zero), throwsStateError);
    await moving;
    await expectLater(
      clock.elapse(const Duration(microseconds: -1)),
      throwsArgumentError,
    );
  });

  test('nextTimerDue is the time the next timer fires at; null while none '
      'waits', () async {
    final clock = FakeClock();
    expect(clock.nextTimerDue, isNull);
    clock.run(() {
      Timer(const Duration(milliseconds: 30), () {});
      Timer.periodic(const Duration(milliseconds: 20), (_) {});
    });
    expect(clock.nextTimerDue, const Duration(milliseconds: 20));
    await clock.elapse(const Duration(milliseconds: 25));
    expect(clock.nextTimerDue, const Duration(milliseconds: 30));
    await clock.elapse(const Duration(milliseconds: 10));
    expect(clock.nextTimerDue, const Duration(milliseconds: 40));
  });

  test('outside its zone time is real', () async {
    final clock = FakeClock();
    var fired = false;
    Timer(Duration.zero, () => fired = true);
    await waitUntil(() => fired, 'the timer started outside the zone');
    expect(clock.pendingTimers, 0);
    expect(clock.elapsed, Duration.zero);
  });

  group('elapseUntil', () {
    test('moves the clock a step at a time until the future completed, '
        'and returns it', () async {
      final clock = FakeClock();
      final answer = clock.run(
        () => Future<int>.delayed(const Duration(milliseconds: 25), () => 42),
      );
      expect(await clock.elapseUntil(answer), 42);
      // three steps of 10 ms, the last one firing the timer at 25 ms
      expect(clock.elapsed, const Duration(milliseconds: 30));
    });

    test('leaves the clock where it is for a future its microtasks '
        'complete', () async {
      final clock = FakeClock();
      final answer = clock.run(() => Future<int>.microtask(() => 1));
      expect(await clock.elapseUntil(answer), 1);
      expect(clock.elapsed, Duration.zero);
    });

    test('moves the clock by step, the last step whole', () async {
      final clock = FakeClock();
      final done = clock.run(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await clock.elapseUntil(done, step: const Duration(milliseconds: 50));
      expect(clock.elapsed, const Duration(milliseconds: 100));
    });

    test('the error the future completes with is thrown', () async {
      final clock = FakeClock();
      final failed = clock.run(
        () => Future<void>.delayed(
          const Duration(milliseconds: 20),
          () => throw StateError('boom'),
        ),
      );
      await expectLater(clock.elapseUntil(failed), throwsStateError);
      expect(clock.elapsed, const Duration(milliseconds: 20));
    });

    test('fails once the clock moved on by within, saying how many timers '
        'wait', () async {
      final clock = FakeClock()
        ..run(() => Timer(const Duration(hours: 1), () {}));
      final never = Completer<void>().future;
      await expectLater(
        clock.elapseUntil(never, within: const Duration(milliseconds: 95)),
        throwsA(
          isA<TestFailure>().having(
            (e) => e.message,
            'message',
            'elapseUntil: the future has not completed 0.095 s on the '
                'clock, and 1 timer waits',
          ),
        ),
      );
      expect(clock.elapsed, const Duration(milliseconds: 95));
    });

    test('an app run by hand on the clock ends once quit, its frames on '
        'the clock', () async {
      final clock = FakeClock();
      final term = clock.run(() => HeadlessTerminal(width: 20, height: 2));
      final done = clock.run(
        () => AppBinding(term, clock: clock.stopwatch).run(const Text('hi')),
      );
      await clock.elapse(const Duration(milliseconds: 30));
      expect(term.frames, isNotEmpty);
      expect(term.closed, isFalse);
      term.type('\x03');
      await clock.elapseUntil(done);
      expect(term.closed, isTrue);
    });

    test('a step that is not positive is refused', () {
      final clock = FakeClock();
      expect(
        () => clock.elapseUntil(Future<void>.value(), step: Duration.zero),
        throwsArgumentError,
      );
    });
  });
}
