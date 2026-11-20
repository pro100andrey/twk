/// Time that passes only when a test says so: [FakeClock].
///
/// @docImport 'tester.dart';
library;

import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:test/test.dart' show TestFailure;
import 'package:twk/twk.dart' show DrivenClock;

// Examples can assume:
// import 'dart:async';
// import 'package:test/test.dart';
// import 'package:twk/twk.dart';

/// A clock that moves only by [elapse], and the zone ([run]) whose timers
/// and microtasks it owns: a timer started there fires when [elapse]
/// reaches its time, a microtask runs when the clock flushes them
/// ([flushMicrotasks]), which [elapse] does after every timer. Its
/// [clock], a [DrivenClock], is what an app's binding takes as its own
/// time: the timers of the zone and the app's are one queue.
///
/// Code outside the zone keeps real time. In the zone, only the timers and
/// microtasks are fake: `Stopwatch()` and `DateTime.now()` read real time
/// (an app's `AppBinding.now()` is on [clock]).
/// A future completed outside the zone resumes the code of the zone that
/// awaits it in a microtask of the real event loop (the SDK keeps some
/// completed in the root zone, as `StreamSubscription.cancel` returns):
/// flushing lets the real event loop run its microtasks too, until
/// neither queue has any left.
///
/// A timer started in the clock's zone fires once the clock reaches it:
///
/// ```dart
/// final clock = FakeClock();
/// var fired = false;
/// clock.run(() => Timer(const Duration(seconds: 1), () => fired = true));
/// await clock.elapse(const Duration(milliseconds: 999));
/// expect(fired, isFalse);
/// await clock.elapse(const Duration(milliseconds: 1));
/// expect(fired, isTrue);
/// ```
///
/// A periodic timer of no period fires once a microsecond, as one that
/// fired at once would keep the clock where it is: moving the clock on by
/// a second fires it a million times, which a test of such a timer, a
/// loop the app should not have, notices by its time.
///
/// A [TwkTester] runs its app on one ([TwkTester.clock]); an app run by
/// hand runs on one when its binding reads [clock] and is started in
/// the zone ([elapseUntil] has it).
final class FakeClock {
  /// A clock at zero, with no timers, whose zone is a child of the zone
  /// it is created in.
  FakeClock() {
    _zone = Zone.current.fork(
      specification: ZoneSpecification(
        createTimer: (_, _, zone, duration, callback) =>
            _driven.timer(duration, zone.bindCallbackGuarded(callback)),
        createPeriodicTimer: (_, _, zone, period, callback) =>
            _driven.periodic(period, zone.bindUnaryCallbackGuarded(callback)),
        scheduleMicrotask: (_, parent, zone, task) => _letGo
            ? parent.scheduleMicrotask(zone, task)
            : _microtasks.add(zone.bindCallbackGuarded(task)),
      ),
    );
  }

  late final Zone _zone;

  // timers due now wait for the next elapse, as the tests expect: nothing
  // here wakes by itself
  final _driven = DrivenClock(wakesItself: false, recordStacks: true);

  var _elapsing = false;
  final _microtasks = Queue<void Function()>();

  // the microtasks go to the real event loop: the test is over
  var _letGo = false;

  /// Lets the microtasks of the clock's zone run on the real event loop
  /// from now on, those waiting first: a test's tear-down, after its body,
  /// awaits a future of the zone (a stream closed by a callback the app
  /// ran, its `close()`), which nothing would flush. Its timers stay fake.
  /// A [TwkTester]'s test lets its clock go once its body is done.
  @internal
  void letGoOfMicrotasks() {
    if (_letGo) {
      return;
    }
    _letGo = true;
    while (_microtasks.isNotEmpty) {
      scheduleMicrotask(_microtasks.removeFirst());
    }
  }

  /// The clock an app reads: the timers it starts are the zone's, in the
  /// one queue [elapse] moves.
  DrivenClock get clock => _driven;

  /// How far the clock has moved since it was created.
  Duration get elapsed => Duration(microseconds: _driven.elapsedMicroseconds);

  /// Called before the clock moves on: what was done so far was done at
  /// [elapsed].
  @internal
  void Function()? get beforeMove => _driven.beforeMove;

  @internal
  set beforeMove(void Function()? value) => _driven.beforeMove = value;

  /// How many timers wait to fire, periodic ones included.
  int get pendingTimers => _driven.pendingTimers;

  /// The timers that wait, one a line, the next due first: when each is
  /// due, its period where it is periodic, and where it was started, the
  /// first lines of its stack outside the SDK and this clock; `no timer
  /// waits` while none does. A failure that waited on them says so with
  /// it, as [elapseUntil]'s and a tester's `pumpUntilIdle`'s do.
  ///
  /// ```dart
  /// final clock = FakeClock();
  /// clock.run(() => Timer(const Duration(seconds: 2), () {}));
  /// assert(clock.describeTimers().startsWith('a timer due in 2.000 s'));
  /// ```
  String describeTimers() => _driven.describeTimers();

  /// The time on the clock ([elapsed]) the next timer fires at; null while
  /// none waits.
  Duration? get nextTimerDue {
    final due = _driven.nextDue;
    return due == null ? null : Duration(microseconds: due);
  }

  /// Runs [body] in the clock's zone and returns what it returns; the
  /// microtasks it schedules wait for [flushMicrotasks].
  T run<T>(T Function() body) => _zone.run(body);

  /// Runs the microtasks scheduled in the clock's zone, those they
  /// schedule included, in order, and lets the real event loop run its
  /// own, until neither has any left.
  Future<void> flushMicrotasks() async {
    do {
      // a real timer runs after every real microtask pending
      await Future<void>.delayed(Duration.zero);
    } while (_runMicrotasks());
  }

  /// Runs the microtasks of the zone until none is left; returns whether
  /// there were any.
  bool _runMicrotasks() {
    final any = _microtasks.isNotEmpty;
    while (_microtasks.isNotEmpty) {
      _microtasks.removeFirst()();
    }
    return any;
  }

  /// Moves the clock on by [duration], firing each timer as the clock
  /// reaches its time — at or before the end, in the order of their times,
  /// those due together in the order they were started — with the
  /// microtasks flushed before the first and after each one.
  Future<void> elapse(Duration duration) async {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'is negative');
    }
    if (_elapsing) {
      throw StateError('the clock is already moving: elapse is not re-entrant');
    }
    _elapsing = true;
    try {
      final end = _driven.elapsedMicroseconds + duration.inMicroseconds;
      await flushMicrotasks();
      while (_driven.fireNext(end)) {
        await flushMicrotasks();
      }
      _driven.moveTo(end);
    } finally {
      _elapsing = false;
    }
  }

  /// [future], once the clock has moved on until it completed, [step] at a
  /// time as [elapse] moves it: what code run in the clock's zone ends
  /// with — an app's run, an answer to a prompt — once the timers it waits
  /// on have fired, however long the machine takes to run them. A future
  /// that completes without the clock moving is returned with the clock
  /// where it was. A [TestFailure] once the clock has moved on by [within]
  /// and [future] has not completed, saying how many timers wait.
  ///
  /// The future is returned as it completed: awaited, it throws the error
  /// it completed with.
  ///
  /// ```dart
  /// final clock = FakeClock();
  /// final answer = clock.run(
  ///   () => Future<int>.delayed(const Duration(milliseconds: 250), () => 42),
  /// );
  /// expect(await clock.elapseUntil(answer), 42);
  /// expect(clock.elapsed, const Duration(milliseconds: 250));
  /// ```
  ///
  /// An app run by hand, on a terminal that neither `testTwk` nor its
  /// tester makes: the terminal and the binding made in the clock's zone,
  /// the binding reading the clock, its run awaited until it has ended.
  ///
  /// ```dart
  /// final clock = FakeClock();
  /// final term = clock.run(() => HeadlessTerminal(width: 20, height: 2));
  /// final done = clock.run(
  ///   () => AppBinding(term, clock: clock.clock).run(const Text('hi')),
  /// );
  /// await clock.elapse(const Duration(milliseconds: 30));
  /// term.type('\x03');
  /// await clock.elapseUntil(done);
  /// expect(term.closed, isTrue);
  /// ```
  Future<T> elapseUntil<T>(
    Future<T> future, {
    Duration step = const Duration(milliseconds: 10),
    Duration within = const Duration(seconds: 1),
  }) async {
    if (step <= Duration.zero) {
      throw ArgumentError.value(step, 'step', 'is not positive');
    }
    var done = false;
    unawaited(
      future.then<void>((_) => done = true, onError: (Object _) => done = true),
    );
    final end = _driven.elapsedMicroseconds + within.inMicroseconds;
    await flushMicrotasks();
    while (!done) {
      final left = end - _driven.elapsedMicroseconds;
      if (left <= 0) {
        final timers = switch (pendingTimers) {
          0 => 'no timer waits',
          1 => '1 timer waits',
          final n => '$n timers wait',
        };
        throw TestFailure(
          'elapseUntil: the future has not completed '
          '${_seconds(within)} on the clock, and $timers'
          '${pendingTimers == 0 ? '' : ':\n${describeTimers()}'}',
        );
      }
      final micros = step.inMicroseconds;
      await elapse(Duration(microseconds: left < micros ? left : micros));
    }
    return future;
  }

  static String _seconds(Duration d) =>
      '${(d.inMicroseconds / 1e6).toStringAsFixed(3)} s';
}
