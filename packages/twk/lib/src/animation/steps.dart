/// What the indicators step by: [Steps] of the app's clock.
///
/// @docImport 'progress_bar.dart';
/// @docImport 'spinner.dart';
library;

import '../binding/app_binding.dart';

/// Steps of [interval] on the clock of [binding]'s app, counted from its
/// start: the one a frame is in ([current]), and, while started, [onStep]
/// called at the first frame of each, a frame callback for the time it
/// starts at ([AppBinding.scheduleFrameCallback]). All that step by the
/// same interval step in the same frames, which one timer asks for.
/// Without a binding it stays at the first step.
///
/// A [Spinner] steps its frames, and a [ProgressBar] its sweep, with one.
final class Steps {
  /// Steps of [_interval] for the app of [binding], not started; asserts
  /// that the interval is longer than zero.
  Steps(this._interval, this.onStep, {this.binding})
    : assert(_interval > Duration.zero, 'a step takes no time');

  /// What it calls at the first frame of each step while started.
  final void Function() onStep;

  /// The app whose clock it steps by; null for none, where it stays at the
  /// first step and calls [onStep] never.
  final AppBinding? binding;

  Duration _interval;

  /// How long a step is; set, a started one goes on at the next step of
  /// the new interval. Asserts that it is longer than zero.
  Duration get interval => _interval;
  set interval(Duration i) {
    assert(i > Duration.zero, 'a step takes no time');
    if (i != _interval) {
      _interval = i;
      if (_callback != null) {
        stop();
        start();
      }
    }
  }

  int? _callback;

  late final FrameCallback _stepCallback = _step;

  /// The step the frame running is in, or the last one between frames.
  int get current {
    final b = binding;
    return b == null
        ? 0
        : b.frameTime.inMicroseconds ~/ _interval.inMicroseconds;
  }

  /// Calls [onStep] from the next step on.
  void start() {
    final b = binding;
    if (b != null && _callback == null) {
      _callback = b.scheduleFrameCallback(
        _stepCallback,
        at: _interval * (current + 1),
      );
    }
  }

  /// Calls [onStep] no more until started again.
  void stop() {
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
