/// The app's time: [Clock], and [SystemClock], the real one.
library;

import 'dart:async';

/// The time an app runs on: a monotonic reading, and the timers that fire
/// when it reaches their time.
///
/// `TwkApp` spaces its frames on one, and a binding starts its timers,
/// animations and periodic work on it. The real one is [SystemClock]; a
/// test, or a program that drives the app, gives a clock that moves only
/// when it says so.
///
/// The reading is an `int` of microseconds, not a [Duration]: the frame
/// path reads it twice a frame, and a [Duration] there is an allocation
/// that [elapsed] (an extension) makes only where it is wanted.
///
/// ```dart
/// final clock = SystemClock();
/// final timer = clock.timer(const Duration(seconds: 1), () {});
/// assert(clock.elapsedMicroseconds >= 0);
/// timer.cancel();
/// ```
abstract interface class Clock {
  /// Microseconds since the clock began; never goes back.
  int get elapsedMicroseconds;

  /// A timer that calls [callback] once, [after] on this clock.
  ///
  /// The callback runs in the zone of whoever moves the clock, the
  /// system's in the zone the timer was started in: bind it to the zone
  /// it is to run in (`Zone.bindCallbackGuarded`) when that is another.
  Timer timer(Duration after, void Function() callback);

  /// A timer that calls [callback] every [every] on this clock, with the
  /// timer itself.
  Timer periodic(Duration every, void Function(Timer) callback);
}

/// [Clock]'s reading as a [Duration].
extension ClockElapsed on Clock {
  /// How long the clock has been running.
  Duration get elapsed => Duration(microseconds: elapsedMicroseconds);
}

/// Real time: a [Stopwatch] started with the clock, and the zone's timers.
final class SystemClock implements Clock {
  /// A clock at zero, running.
  SystemClock() : _watch = Stopwatch()..start();

  final Stopwatch _watch;

  @override
  int get elapsedMicroseconds => _watch.elapsedMicroseconds;

  @override
  Timer timer(Duration after, void Function() callback) =>
      Timer(after, callback);

  @override
  Timer periodic(Duration every, void Function(Timer) callback) =>
      Timer.periodic(every, callback);
}
