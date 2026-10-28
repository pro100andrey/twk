/// Time for an app run in memory to be measured: [SyncClock].
library;

import 'dart:async';
import 'dart:collection';

/// A clock that moves only by [elapse], and the zone ([run]) whose timers
/// and microtasks it owns, as twk_test's `FakeClock`, but synchronous:
/// [elapse] runs the microtasks, then each timer due in the order of their
/// times with the microtasks after it, and returns, awaiting nothing.
///
/// `FakeClock` lets the real event loop run after each timer (an awaited
/// `Future.delayed`), for a test whose app waits on what completes
/// outside its zone; that is a real timer, futures and closures a frame,
/// which a measure would count as the app's. An app on a
/// `HeadlessTerminal` waits on nothing outside its zone: its futures
/// complete in microtasks of the zone, which this clock runs. What it
/// allocates itself is what a real event loop does for a timer or a
/// microtask: the callback bound to the zone, and the timer.
final class SyncClock {
  /// A clock at zero, with no timers, whose zone is a child of the zone
  /// it is created in.
  SyncClock() {
    _zone = Zone.current.fork(
      specification: ZoneSpecification(
        createTimer: (_, _, zone, duration, callback) =>
            _SyncTimer(this, duration, zone.bindCallbackGuarded(callback)),
        createPeriodicTimer: (_, _, zone, period, callback) =>
            _SyncTimer.periodic(
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
  var _created = 0;
  final _timers = <_SyncTimer>[];
  final _microtasks = ListQueue<void Function()>(64);

  /// How far the clock has moved since it was created.
  Duration get elapsed => Duration(microseconds: _now);

  /// Runs [body] in the clock's zone and returns what it returns; the
  /// microtasks it schedules run at the next [elapse].
  T run<T>(T Function() body) => _zone.run(body);

  /// Moves the clock on by [duration], firing each timer as the clock
  /// reaches its time — those due together in the order they were started
  /// — with the microtasks run before the first and after each one.
  void elapse(Duration duration) {
    final end = _now + duration.inMicroseconds;
    _runMicrotasks();
    for (var next = _next(end); next != null; next = _next(end)) {
      _now = next._due;
      next._fire();
      _runMicrotasks();
    }
    _now = end;
  }

  void _runMicrotasks() {
    while (_microtasks.isNotEmpty) {
      _microtasks.removeFirst()();
    }
  }

  /// The timer to fire next, if one is due by [end].
  _SyncTimer? _next(int end) {
    _SyncTimer? next;
    for (var i = 0; i < _timers.length; i++) {
      final t = _timers[i];
      if (t._due <= end &&
          (next == null ||
              t._due < next._due ||
              (t._due == next._due && t._order < next._order))) {
        next = t;
      }
    }
    return next;
  }

  /// A stopwatch on this clock, running since it was created.
  late final Stopwatch stopwatch = _SyncStopwatch(this);
}

final class _SyncTimer implements Timer {
  _SyncTimer(SyncClock clock, Duration duration, void Function() callback)
    : this._(clock, duration.inMicroseconds, callback, null);

  _SyncTimer.periodic(
    SyncClock clock,
    Duration period,
    void Function(Timer timer) callback,
  ) : this._(
        clock,
        // one that fires at once would keep the clock in place
        period.inMicroseconds < 1 ? 1 : period.inMicroseconds,
        null,
        callback,
      );

  _SyncTimer._(this._clock, int micros, this._once, this._each)
    : _period = micros < 0 ? 0 : micros,
      _order = _clock._created++ {
    _due = _clock._now + _period;
    _clock._timers.add(this);
  }

  final SyncClock _clock;
  final int _period;
  final void Function()? _once;
  final void Function(Timer timer)? _each;
  late int _due;
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

/// A [Stopwatch] whose time is a [SyncClock]'s.
final class _SyncStopwatch implements Stopwatch {
  _SyncStopwatch(this._clock) : _startedAt = _clock._now;

  final SyncClock _clock;
  int? _startedAt;
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
