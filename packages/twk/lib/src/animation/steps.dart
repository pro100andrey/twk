/// What the indicators step by: [Steps] of the app's clock.
///
/// @docImport 'progress_bar.dart';
/// @docImport 'spinner.dart';
/// @docImport 'ticker.dart';
library;

import '../binding/app_binding.dart' show AppBinding, FrameCallback;
import 'frame_clock.dart';
import 'mute.dart';
import 'step_count.dart';

/// Steps of [interval] on the clock of [binding], counted from its start:
/// the one a frame is in ([current]), and, while started, [onStep] called
/// at the first frame of each, a frame callback for the time it starts at
/// ([FrameClock.scheduleFrameCallback]). All that step by the same
/// interval step in the same frames, which one timer asks for. Without a
/// binding it stays at the first step.
///
/// A [TickerMode] that is off mutes it ([muted]).
///
/// A [Spinner] steps its frames, and a [ProgressBar] its sweep, with one.
final class Steps implements Muteable {
  /// Steps of [interval] on the clock of [binding], not started; an
  /// interval not longer than zero is an [ArgumentError].
  Steps(Duration interval, this.onStep, {this.binding})
    : _count = StepCount(interval);

  /// What it calls at the first frame of each step while started.
  final void Function() onStep;

  /// The clock it steps by (an app's [AppBinding]); null for none, where it
  /// stays at the first step and calls [onStep] never.
  final FrameClock? binding;

  final StepCount _count;

  Duration get _now => binding?.frameTime ?? Duration.zero;

  /// How long a step is; set, a started one goes on at the next step of
  /// the new interval. One not longer than zero is an [ArgumentError].
  Duration get interval => _count.interval;
  set interval(Duration i) {
    if (_count.setInterval(i, _now) && _callback != null) {
      _cancel();
      start();
    }
  }

  int? _callback;

  var _wanted = false;

  /// Whether it is muted: no frame asked for and [current] kept at the
  /// step it was in, for a [TickerMode] that is off. Unmuted, a started one
  /// goes on from that step.
  @override
  bool get muted => _count.muted;
  @override
  set muted(bool on) {
    if (on == _count.muted) {
      return;
    }
    if (on) {
      _count.mute(_now);
      _cancel();
    } else {
      _count.unmute();
      if (_wanted) {
        start();
      }
    }
  }

  late final FrameCallback _stepCallback = _step;

  /// The step the frame running is in, or the last one between frames.
  int get current => _count.current(_now);

  /// Calls [onStep] from the next step on.
  void start() {
    _wanted = true;
    final b = binding;
    if (b != null && !_count.muted && _callback == null) {
      _callback = b.scheduleFrameCallback(
        _stepCallback,
        at: _count.nextAt(_now),
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
    // an onStep that stopped it leaves it stopped
    if (_wanted) {
      start();
    }
  }
}
