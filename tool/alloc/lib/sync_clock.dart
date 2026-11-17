/// Time for an app run in memory to be measured: [SyncClock].
library;

import 'dart:async';
import 'dart:collection';

import 'package:twk/twk.dart' show DrivenClock;
import 'package:twk_core/twk_core.dart' show Clock;

/// A clock that moves only by [elapse], and the zone ([run]) whose timers
/// and microtasks it owns, as twk_test's `FakeClock`, but synchronous:
/// [elapse] runs the microtasks, then each timer due in the order of their
/// times with the microtasks after it, and returns, awaiting nothing.
///
/// The timers are a [DrivenClock]'s, one queue for both, with no stack kept
/// per timer (`recordStacks: false`) and no wake of its own
/// (`wakesItself: false`): what a measure counts as the app's is a stack a
/// timer, which the profiler must not see. What this adds is the zone and
/// the microtask drain.
///
/// `FakeClock` lets the real event loop run after each timer (an awaited
/// `Future.delayed`), for a test whose app waits on what completes
/// outside its zone; that is a real timer, futures and closures a frame,
/// which a measure would count as the app's. An app on a
/// `HeadlessTerminal` waits on nothing outside its zone: its futures
/// complete in microtasks of the zone, which this clock runs. What it
/// allocates itself is what a real event loop does for a timer or a
/// microtask: the callback bound to the zone, and the timer.
final class SyncClock implements Clock {
  /// A clock at zero, with no timers, whose zone is a child of the zone
  /// it is created in.
  SyncClock() {
    _zone = Zone.current.fork(
      specification: ZoneSpecification(
        createTimer: (_, _, zone, duration, callback) =>
            _driven.timer(duration, zone.bindCallbackGuarded(callback)),
        createPeriodicTimer: (_, _, zone, period, callback) =>
            _driven.periodic(period, zone.bindUnaryCallbackGuarded(callback)),
        scheduleMicrotask: (_, _, zone, task) =>
            _microtasks.add(zone.bindCallbackGuarded(task)),
      ),
    );
  }

  late final Zone _zone;
  final _driven = DrivenClock(wakesItself: false);
  final _microtasks = ListQueue<void Function()>(64);

  /// How far the clock has moved since it was created.
  Duration get elapsed => Duration(microseconds: _driven.elapsedMicroseconds);

  /// Runs [body] in the clock's zone and returns what it returns; the
  /// microtasks it schedules run at the next [elapse].
  T run<T>(T Function() body) => _zone.run(body);

  /// Moves the clock on by [duration], firing each timer as the clock
  /// reaches its time — those due together in the order they were started
  /// — with the microtasks run before the first and after each one.
  void elapse(Duration duration) {
    final end = _driven.elapsedMicroseconds + duration.inMicroseconds;
    _runMicrotasks();
    while (_driven.fireNext(end)) {
      _runMicrotasks();
    }
    _driven.moveTo(end);
  }

  void _runMicrotasks() {
    while (_microtasks.isNotEmpty) {
      _microtasks.removeFirst()();
    }
  }

  @override
  int get elapsedMicroseconds => _driven.elapsedMicroseconds;

  @override
  Timer timer(Duration after, void Function() callback) =>
      _driven.timer(after, callback);

  @override
  Timer periodic(Duration every, void Function(Timer) callback) =>
      _driven.periodic(every, callback);
}
