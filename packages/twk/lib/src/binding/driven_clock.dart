/// [DrivenClock]: an app's time that moves only when told to.
library;

import 'dart:async';

import 'package:twk_core/twk_core.dart';

/// A [Clock] that stands still until [advance], [advanceTo] or
/// [advanceToNext] moves it, firing each timer as it reaches the timer's
/// time.
///
/// Timers fire by their due time, those due together in the order they
/// were started. A timer due at or before the clock's time, started with no
/// wait, runs without the clock moving: the clock wakes itself with a
/// zero-delay timer of the root zone. Time does not move, so this costs no
/// determinism; it is what lets a first frame, due at once, run without
/// whoever drives the clock. Pass `wakesItself: false` where the caller
/// runs what is due, as a test's fake clock does between its microtasks.
///
/// It queues no microtasks: the code it calls runs them as it normally
/// does.
///
/// ```dart
/// final clock = DrivenClock(wakesItself: false);
/// final order = <String>[];
/// clock.timer(const Duration(seconds: 2), () => order.add('b'));
/// clock.timer(const Duration(seconds: 1), () => order.add('a'));
/// clock.advance(const Duration(seconds: 3));
/// assert(order.join() == 'ab');
/// assert(clock.elapsed == const Duration(seconds: 3));
/// ```
final class DrivenClock implements Clock {
  /// A clock at zero with no timers. [maxFired] bounds how many timers one
  /// move may fire, a guard against a periodic timer of a tiny period or
  /// one that starts another with no wait, which would never let it end.
  DrivenClock({this.maxFired = 10000000, this.wakesItself = true});

  /// The most timers one [advance], [advanceTo] or [advanceToNext] fires
  /// before it throws a [StateError] that names the timers waiting.
  final int maxFired;

  /// Whether a timer due now runs by itself, from a zero timer of the root
  /// zone, or waits for the next move.
  final bool wakesItself;

  var _now = 0;
  var _created = 0;
  var _moving = false;
  Timer? _wake;
  final _timers = <_DrivenTimer>[];

  @override
  int get elapsedMicroseconds => _now;

  /// Called before the clock's time changes, when something was done at
  /// the time it still has.
  void Function()? beforeMove;

  /// Called when the timers that wait change from outside a move: one is
  /// started or cancelled, or the clock woke itself and ran what was due.
  /// Not while the clock moves ([advance] and its kin), whose caller sees
  /// the result. While null, a timer pays one test of it.
  void Function()? onChange;

  /// How many timers wait, periodic ones included.
  int get pendingTimers => _timers.length;

  /// When the next timer is due, in microseconds of the clock; null while
  /// none waits.
  int? get nextDue {
    int? due;
    for (final t in _timers) {
      if (due == null || t._due < due) {
        due = t._due;
      }
    }
    return due;
  }

  @override
  Timer timer(Duration after, void Function() callback) =>
      _add(_DrivenTimer(this, after.inMicroseconds, callback, null));

  @override
  Timer periodic(Duration every, void Function(Timer) callback) => _add(
    // one that fires at once would keep the clock in place
    _DrivenTimer(
      this,
      every.inMicroseconds < 1 ? 1 : every.inMicroseconds,
      null,
      callback,
    ),
  );

  Timer _add(_DrivenTimer timer) {
    _timers.add(timer);
    if (wakesItself && !_moving && timer._due <= _now && _wake == null) {
      _wake = Zone.root.createTimer(Duration.zero, _wakeUp);
    }
    _changed();
    return timer;
  }

  void _wakeUp() {
    _wake = null;
    if (!_moving) {
      _run(() => _fireUntil(_now));
      _changed();
    }
  }

  void _changed() {
    if (!_moving) {
      onChange?.call();
    }
  }

  /// Moves the clock on by [by], firing each timer as it reaches the
  /// timer's time, at or before the end.
  void advance(Duration by) {
    if (by.isNegative) {
      throw ArgumentError.value(by, 'by', 'is negative');
    }
    advanceTo(_now + by.inMicroseconds);
  }

  /// Moves the clock to [time], in microseconds, firing each timer as it
  /// reaches the timer's time. A time before the clock's is an error.
  void advanceTo(int time) {
    if (time < _now) {
      throw ArgumentError.value(time, 'time', "is before the clock's");
    }
    _run(() {
      _fireUntil(time);
      moveTo(time);
    });
  }

  /// Moves the clock to the time the next timer is due, firing every timer
  /// due then; false, the clock where it was, while none waits.
  bool advanceToNext() {
    final due = nextDue;
    if (due == null) {
      return false;
    }
    advanceTo(due > _now ? due : _now);
    return true;
  }

  void _run(void Function() body) {
    if (_moving) {
      throw StateError('the clock is already moving: it is not re-entrant');
    }
    _moving = true;
    try {
      body();
    } finally {
      _moving = false;
    }
  }

  void _fireUntil(int end) {
    for (var fired = 0; fireNext(end); fired++) {
      if (fired >= maxFired) {
        throw StateError(
          'the clock fired $maxFired timers in one move: a timer that '
          'starts itself again with no wait?\n${describeTimers()}',
        );
      }
    }
  }

  /// Fires the next timer if it is due by [end], the clock moved to its
  /// time first; false when there is none. For a caller that does
  /// something between timers, which [advance] does not; it fires without
  /// the cap [maxFired] puts on a move.
  bool fireNext(int end) {
    _DrivenTimer? next;
    for (final t in _timers) {
      if (t._due <= end &&
          (next == null ||
              t._due < next._due ||
              (t._due == next._due && t._order < next._order))) {
        next = t;
      }
    }
    if (next == null) {
      return false;
    }
    moveTo(next._due);
    next._fire();
    return true;
  }

  /// Moves the clock to [time] if that is after its time, [beforeMove]
  /// called first. For a caller of [fireNext] that ends its move.
  void moveTo(int time) {
    if (time > _now) {
      beforeMove?.call();
      _now = time;
    }
  }

  /// The timers that wait, the next due first: when each is due in
  /// microseconds of the clock, whether it is periodic, and the line of
  /// the code that started it (the first outside the SDK and the clocks),
  /// null where none is known.
  List<({int due, bool periodic, String? created})> get waiting {
    int byDue(_DrivenTimer a, _DrivenTimer b) =>
        a._due != b._due ? a._due - b._due : a._order - b._order;
    return [
      for (final t in [..._timers]..sort(byDue))
        (
          due: t._due,
          periodic: t._each != null,
          created: _callers(
            t._started,
          ).where((l) => !l.startsWith('AppBinding.start')).firstOrNull,
        ),
    ];
  }

  /// The timers that wait, one a line, the next due first: when each is
  /// due, its period where it is periodic, and where it was started, the
  /// first lines of its stack outside the SDK and the clocks; `no timer
  /// waits` while none does.
  ///
  /// ```dart
  /// final clock = DrivenClock(wakesItself: false);
  /// clock.timer(const Duration(seconds: 2), () {});
  /// assert(clock.describeTimers().startsWith('a timer due in 2.000 s'));
  /// ```
  String describeTimers() {
    if (_timers.isEmpty) {
      return 'no timer waits';
    }
    int byDue(_DrivenTimer a, _DrivenTimer b) =>
        a._due != b._due ? a._due - b._due : a._order - b._order;
    String kind(_DrivenTimer t) => t._each == null
        ? 'a timer'
        : 'a periodic timer, every ${_seconds(t._period)},';
    String head(_DrivenTimer t) =>
        '${kind(t)} due in ${_seconds(t._due - _now)}, started at';
    return [
      for (final t in [..._timers]..sort(byDue)) ...[
        head(t),
        for (final frame in _callers(t._started)) '  $frame',
      ],
    ].join('\n');
  }

  static String _seconds(int micros) =>
      '${(micros / 1e6).toStringAsFixed(3)} s';

  /// The first [count] frames of [stack] that are neither the SDK's nor
  /// a clock's: where the code that started a timer is.
  static List<String> _callers(StackTrace stack, {int count = 3}) => [
    for (final line in '$stack'.split('\n'))
      if (line.trim().isNotEmpty &&
          !line.contains('(dart:') &&
          !line.contains('driven_clock.dart') &&
          !line.contains('fake_clock.dart'))
        line.replaceFirst(RegExp(r'^#\d+\s+'), ''),
  ].take(count).toList();
}

final class _DrivenTimer implements Timer {
  _DrivenTimer(this._clock, int micros, this._once, this._each)
    : _period = micros < 0 ? 0 : micros,
      _order = _clock._created++,
      _started = StackTrace.current {
    _due = _clock._now + _period;
  }

  final DrivenClock _clock;
  final int _period;

  /// Where it was started, which a failure that waited on it names.
  final StackTrace _started;

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
  void cancel() {
    if (_clock._timers.remove(this)) {
      _clock._changed();
    }
  }

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
