/// What the indicators step by: [Steps] of the app's clock.
///
/// @docImport 'progress_bar.dart';
/// @docImport 'spinner.dart';
/// @docImport 'ticker.dart';
library;

import '../binding/app_binding.dart';

/// Steps of [interval] on the clock of [binding]'s app, counted from its
/// start: the one a frame is in ([current]), and, while started, [onStep]
/// called at the first frame of each, a frame callback for the time it
/// starts at ([AppBinding.scheduleFrameCallback]). All that step by the
/// same interval step in the same frames, which one timer asks for.
/// Without a binding it stays at the first step.
///
/// A [TickerMode] that is off mutes it ([muted]).
///
/// A [Spinner] steps its frames, and a [ProgressBar] its sweep, with one.
final class Steps {
  /// Steps of [_interval] for the app of [binding], not started; an
  /// interval not longer than zero is an [ArgumentError].
  Steps(this._interval, this.onStep, {this.binding}) {
    _check(_interval);
  }

  /// Throws where [interval] is not longer than zero: [current] divides by
  /// it.
  static void _check(Duration interval) {
    if (interval <= Duration.zero) {
      throw ArgumentError.value(interval, 'interval', 'a step takes no time');
    }
  }

  /// What it calls at the first frame of each step while started.
  final void Function() onStep;

  /// The app whose clock it steps by; null for none, where it stays at the
  /// first step and calls [onStep] never.
  final AppBinding? binding;

  Duration _interval;

  /// How long a step is; set, a started one goes on at the next step of
  /// the new interval. One not longer than zero is an [ArgumentError].
  Duration get interval => _interval;
  set interval(Duration i) {
    _check(i);
    if (i != _interval) {
      // the steps muted for are counted in the old interval: counted anew
      // in the new one, the step it is in stays the one it is in
      final keep = !_muted && _shifted ? current : null;
      _interval = i;
      if (keep != null) {
        _skipped = _live - keep;
      }
      if (_callback != null) {
        _cancel();
        start();
      }
    }
  }

  int? _callback;

  var _wanted = false;
  var _muted = false;
  var _frozen = 0;
  var _shifted = false;
  var _skipped = 0;
  var _resume = false;

  /// Whether it is muted: no frame asked for and [current] kept at the
  /// step it was in, for a [TickerMode] that is off. Unmuted, a started one
  /// goes on from that step.
  bool get muted => _muted;
  set muted(bool on) {
    if (on == _muted) {
      return;
    }
    if (on) {
      _frozen = current;
      _shifted = true;
      _resume = false;
      _muted = true;
      _cancel();
    } else {
      // the time it was muted for is taken off when the step is next read,
      // in a frame, whose time is the one that counts
      _resume = true;
      _muted = false;
      if (_wanted) {
        start();
      }
    }
  }

  late final FrameCallback _stepCallback = _step;

  /// The step the frame running is in, or the last one between frames.
  int get current {
    if (_muted) {
      return _frozen;
    }
    if (_resume) {
      _resume = false;
      // the steps skipped, as many as the clock has gone on past the step
      // it stood at: counted anew, not added to those of the mutes before
      _skipped = _live - _frozen;
    }
    return _live - _skipped;
  }

  int get _live {
    final b = binding;
    return b == null
        ? 0
        : b.frameTime.inMicroseconds ~/ _interval.inMicroseconds;
  }

  /// Calls [onStep] from the next step on.
  void start() {
    _wanted = true;
    final b = binding;
    if (b != null && !_muted && _callback == null) {
      _callback = b.scheduleFrameCallback(
        _stepCallback,
        at: _interval * (_live + 1),
      );
    }
  }

  /// Calls [onStep] no more until started again.
  void stop() {
    _wanted = false;
    _cancel();
  }

  void _cancel() {
    final callback = _callback;
    if (callback != null) {
      _callback = null;
      binding?.cancelFrameCallback(callback);
    }
  }

  void _step(Duration time) {
    _callback = null;
    onStep();
    start();
  }
}
