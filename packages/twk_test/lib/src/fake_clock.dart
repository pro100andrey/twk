/// Time that passes only when a test says so: [FakeClock].
///
/// @docImport 'tester.dart';
library;

import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:test/test.dart' show TestFailure;

// Examples can assume:
// import 'dart:async';
// import 'package:test/test.dart';
// import 'package:twk/twk.dart';

/// A clock that moves only by [elapse], and the zone ([run]) whose timers
/// and microtasks it owns: a timer started there fires when [elapse]
/// reaches its time, a microtask runs when the clock flushes them
/// ([flushMicrotasks]), which [elapse] does after every timer. Its
/// [stopwatch] reads it.
///
/// Code outside the zone keeps real time. In the zone, only the timers and
/// microtasks are fake: `Stopwatch()` and `DateTime.now()` read real time.
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
/// hand runs on one when its binding reads [stopwatch] and is started in
/// the zone ([elapseUntil] has it).
final class FakeClock {
  /// A clock at zero, with no timers, whose zone is a child of the zone
  /// it is created in.
  FakeClock() {
    _zone = Zone.current.fork(
      specification: ZoneSpecification(
        createTimer: (_, _, zone, duration, callback) =>
            _FakeTimer(this, duration, zone.bindCallbackGuarded(callback)),
        createPeriodicTimer: (_, _, zone, period, callback) =>
            _FakeTimer.periodic(
              this,
              period,
              zone.bindUnaryCallbackGuarded(callback),
            ),
        scheduleMicrotask: (_, _, zone, task) =>
            _microtasks.add(zone.bindCallbackGuarded(task)),
      ),
    );
  }

  late final Zone _zone;

  var _now = 0;
  var _elapsing = false;
  var _created = 0;
  final _timers = <_FakeTimer>[];
  final _microtasks = Queue<void Function()>();

  /// How far the clock has moved since it was created.
  Duration get elapsed => Duration(microseconds: _now);

  /// Called before the clock moves on: what was done so far was done at
  /// [elapsed].
  @internal
  void Function()? beforeMove;

  /// How many timers wait to fire, periodic ones included.
  int get pendingTimers => _timers.length;

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
  String describeTimers() {
    if (_timers.isEmpty) {
      return 'no timer waits';
    }
    int byDue(_FakeTimer a, _FakeTimer b) =>
        a._due != b._due ? a._due - b._due : a._order - b._order;
    String kind(_FakeTimer t) => t._each == null
        ? 'a timer'
        : 'a periodic timer, every '
              '${_seconds(Duration(microseconds: t._period))},';
    String head(_FakeTimer t) =>
        '${kind(t)} due in '
        '${_seconds(Duration(microseconds: t._due - _now))}, started at';
    return [
      for (final t in [..._timers]..sort(byDue)) ...[
        head(t),
        for (final frame in _callers(t._started)) '  $frame',
      ],
    ].join('\n');
  }

  /// The first [count] frames of [stack] that are neither the SDK's nor
  /// this clock's: where the code that started a timer is.
  static List<String> _callers(StackTrace stack, {int count = 3}) => [
    for (final line in '$stack'.split('\n'))
      if (line.trim().isNotEmpty &&
          !line.contains('(dart:') &&
          !line.contains('fake_clock.dart'))
        line.replaceFirst(RegExp(r'^#\d+\s+'), ''),
  ].take(count).toList();

  /// The time on the clock ([elapsed]) the next timer fires at; null while
  /// none waits.
  Duration? get nextTimerDue {
    int? due;
    for (final t in _timers) {
      if (due == null || t._due < due) {
        due = t._due;
      }
    }
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
      final end = _now + duration.inMicroseconds;
      await flushMicrotasks();
      for (var next = _next(end); next != null; next = _next(end)) {
        _moveTo(next._due);
        next._fire();
        await flushMicrotasks();
      }
      _moveTo(end);
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
  ///   () => AppBinding(term, clock: clock.stopwatch).run(const Text('hi')),
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
    final end = _now + within.inMicroseconds;
    await flushMicrotasks();
    while (!done) {
      final left = end - _now;
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

  void _moveTo(int now) {
    if (now != _now) {
      beforeMove?.call();
      _now = now;
    }
  }

  /// The timer to fire next, if one is due by [end].
  _FakeTimer? _next(int end) {
    _FakeTimer? next;
    for (final t in _timers) {
      if (t._due <= end &&
          (next == null ||
              t._due < next._due ||
              (t._due == next._due && t._order < next._order))) {
        next = t;
      }
    }
    return next;
  }

  /// A stopwatch on this clock, running since it was created: until it is
  /// stopped or reset it reads [elapsed].
  late final Stopwatch stopwatch = _FakeStopwatch(this);
}

final class _FakeTimer implements Timer {
  _FakeTimer(FakeClock clock, Duration duration, void Function() callback)
    : this._(clock, duration.inMicroseconds, callback, null);

  _FakeTimer.periodic(
    FakeClock clock,
    Duration period,
    void Function(Timer timer) callback,
  ) : this._(
        clock,
        // one that fires at once would keep the clock in place
        period.inMicroseconds < 1 ? 1 : period.inMicroseconds,
        null,
        callback,
      );

  _FakeTimer._(this._clock, int micros, this._once, this._each)
    : _period = micros < 0 ? 0 : micros,
      _order = _clock._created++,
      _started = StackTrace.current {
    _due = _clock._now + _period;
    _clock._timers.add(this);
  }

  final FakeClock _clock;
  final int _period;

  /// Where it was started, which a failure that waited on it names.
  final StackTrace _started;

  /// What a timer that fires once calls, and what a periodic one calls.
  final void Function()? _once;
  final void Function(Timer timer)? _each;

  late int _due;

  /// Orders timers due together: the one started, or fired, first first.
  int _order;
  var _tick = 0;

  @override
  int get tick => _tick;

  @override
  bool get isActive => _clock._timers.contains(this);

  @override
  void cancel() => _clock._timers.remove(this);

  void _fire() {
    _tick++;
    final each = _each;
    if (each != null) {
      _due += _period;
      _order = _clock._created++;
      each(this);
    } else {
      _clock._timers.remove(this);
      _once!();
    }
  }
}

/// A [Stopwatch] whose time is a [FakeClock]'s.
final class _FakeStopwatch implements Stopwatch {
  _FakeStopwatch(this._clock) : _startedAt = _clock._now;

  final FakeClock _clock;

  /// When it was started last; null while stopped.
  int? _startedAt;

  /// What it counted before it was stopped last.
  var _counted = 0;

  @override
  int get frequency => 1000000;

  @override
  bool get isRunning => _startedAt != null;

  @override
  void start() => _startedAt ??= _clock._now;

  @override
  void stop() {
    final startedAt = _startedAt;
    if (startedAt != null) {
      _counted += _clock._now - startedAt;
      _startedAt = null;
    }
  }

  @override
  void reset() {
    _counted = 0;
    if (_startedAt != null) {
      _startedAt = _clock._now;
    }
  }

  @override
  int get elapsedTicks => elapsedMicroseconds;

  @override
  int get elapsedMicroseconds {
    final startedAt = _startedAt;
    return _counted + (startedAt == null ? 0 : _clock._now - startedAt);
  }

  @override
  int get elapsedMilliseconds => elapsedMicroseconds ~/ 1000;

  @override
  Duration get elapsed => Duration(microseconds: elapsedMicroseconds);
}
