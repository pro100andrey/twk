/// A value that runs from one bound to the other over a duration:
/// [AnimationController], and its [AnimationStatus].
///
/// @docImport 'animated_builder.dart';
/// @docImport 'implicit.dart';
library;

import 'dart:async';

import '../foundation/change_notifier.dart';
import 'curves.dart';
import 'ticker.dart';
import 'tween.dart';

/// Where an [AnimationController] is: stopped at a bound, or running
/// towards one.
enum AnimationStatus {
  /// At the lower bound, or ended a run towards it.
  dismissed,

  /// Running towards the upper bound, or stopped on the way.
  forward,

  /// Running towards the lower bound, or stopped on the way.
  reverse,

  /// At the upper bound, or ended a run towards it.
  completed,
}

/// What [AnimationController.addStatusListener] calls with the new status.
typedef AnimationStatusListener = void Function(AnimationStatus status);

/// A [value] from [lowerBound] to [upperBound] (0 to 1 by default) that
/// runs from where it is to a bound ([forward], [reverse]) or to any value
/// ([animateTo]) in a time, or round and round ([repeat]); the value
/// listeners are called each frame it changes in, the status listeners
/// ([addStatusListener]) when its [status] changes, after them.
///
/// A run takes [duration] from one bound to the other ([reverseDuration]
/// back to the lower one, when given), and that share of it for a part of
/// the way. It moves with a [Ticker] of its `vsync` — a `State` with
/// [TickerProviderStateMixin] — once a frame: at the first frame it is
/// where it started, at the frame whose time is the duration on or past it
/// ends at its target. Then the ticker stops, and so do the frames it had
/// the app run: a controller that does not run asks for none.
///
/// A run that starts stops the one running. A [Tween] (an [Animatable])
/// maps the value to what it animates, `tween.evaluate(controller)`; a
/// `ListenableBuilder` of the controller builds with it each frame.
///
/// A dot that fades in and out, back and forth every 600 ms, its controller
/// made and disposed with the state that runs it:
///
/// ```dart
/// final class Pulse extends StatefulWidget {
///   const Pulse({super.key});
///
///   @override
///   State<Pulse> createState() => _PulseState();
/// }
///
/// final class _PulseState extends State<Pulse> with TickerProviderStateMixin {
///   late final controller = AnimationController(
///     vsync: this,
///     duration: const Duration(milliseconds: 600),
///   )..repeat(reverse: true);
///
///   @override
///   void dispose() {
///     controller.dispose();
///     super.dispose();
///   }
///
///   @override
///   Widget build(BuildContext context) => AnimatedBuilder(
///     animation: controller,
///     builder: (context, child) =>
///         Opacity(opacity: controller.value, child: child),
///     child: const Text('●'),
///   );
/// }
/// ```
///
/// See also:
///
///  * [Tween], which maps its value to what it animates.
///  * [ImplicitlyAnimatedWidget], whose widgets run a controller of their
///    own to the values they are given.
final class AnimationController extends ChangeNotifier
    implements ValueListenable<double> {
  /// A controller at [value], or at [lowerBound] when null, not running,
  /// whose runs tick with a ticker of [vsync].
  ///
  /// Its status is [AnimationStatus.dismissed] at the lower bound,
  /// [AnimationStatus.completed] at the upper one, and
  /// [AnimationStatus.forward] between them. Asserts that [upperBound] is
  /// above [lowerBound].
  AnimationController({
    required TickerProvider vsync,
    double? value,
    this.duration,
    this.reverseDuration,
    this.lowerBound = 0,
    this.upperBound = 1,
  }) : assert(upperBound > lowerBound, 'the bounds are the wrong way') {
    _ticker = vsync.createTicker(_tick);
    _value = _clamp(value ?? lowerBound);
    _status = _statusAt(_value);
  }

  /// How long a run from one bound to the other takes; a run without one
  /// is a [StateError].
  Duration? duration;

  /// How long a run back to the lower bound takes; [duration] when null.
  Duration? reverseDuration;

  /// The least [value], where a run [reverse] ends: 0 by default.
  final double lowerBound;

  /// The greatest [value], where a run [forward] ends: 1 by default.
  final double upperBound;

  late final Ticker _ticker;

  double _value = 0;
  late AnimationStatus _status;
  final _statusListeners = <AnimationStatusListener>[];

  // where the run goes: towards the upper bound
  var _forward = true;

  // the run: from _from to _to in _micros along _curve; or, while _period
  // is set, round after round of _period from _phase on, back and forth
  // when _bounce
  var _from = 0.0;
  var _to = 0.0;
  var _micros = 0;
  Curve _curve = Curves.linear;
  int? _period;
  var _bounce = false;
  var _phase = 0.0;

  /// Where it is, from [lowerBound] to [upperBound]. Set, it stops the run
  /// and is there at once, clamped to the bounds: [AnimationStatus.dismissed]
  /// at the lower one, [AnimationStatus.completed] at the upper one.
  @override
  double get value => _value;

  set value(double newValue) {
    stop();
    _set(_clamp(newValue));
    _setStatus(_statusAt(_value));
  }

  /// Whether it is at a bound or running towards one; its status
  /// listeners are called when it changes.
  AnimationStatus get status => _status;

  /// Whether a run is under way.
  bool get isAnimating => _ticker.isActive;

  /// Runs to the upper bound, from [from] when given.
  void forward({double? from}) {
    if (from != null) {
      value = from;
    }
    _forward = true;
    _runTo(upperBound, duration, Curves.linear);
  }

  /// Runs back to the lower bound, from [from] when given.
  void reverse({double? from}) {
    if (from != null) {
      value = from;
    }
    _forward = false;
    _runTo(lowerBound, reverseDuration ?? duration, Curves.linear);
  }

  /// Runs to [target] along [curve], in [duration] when given, else in the
  /// share of [duration] the way is of the bounds'; its status is
  /// [AnimationStatus.forward] on the way and [AnimationStatus.completed]
  /// at the end, as of a run [forward].
  void animateTo(
    double target, {
    Duration? duration,
    Curve curve = Curves.linear,
  }) {
    _forward = true;
    final to = _clamp(target);
    if (duration != null) {
      _start(to, duration.inMicroseconds, curve);
    } else {
      _runTo(to, this.duration, curve);
    }
  }

  /// Runs from where it is to the upper bound, then from the lower one
  /// again, or with [reverse] back to it, round after round until stopped:
  /// each round takes [period], or [duration] when null.
  void repeat({bool reverse = false, Duration? period}) {
    final each = (period ?? duration ?? (throw _noDuration())).inMicroseconds;
    stop();
    _period = each < 1 ? 1 : each;
    _bounce = reverse;
    _phase = (_value - lowerBound) / (upperBound - lowerBound);
    _forward = true;
    _setStatus(AnimationStatus.forward);
    _ticker.start();
  }

  /// Ends the run where it is; the status stays as it is.
  void stop() {
    _ticker.stop();
    _period = null;
  }

  /// Back at the lower bound at once: [value] set to it.
  void reset() => value = lowerBound;

  /// Calls [listener] whenever the status changes.
  void addStatusListener(AnimationStatusListener listener) =>
      _statusListeners.add(listener);

  /// Stops calling [listener], once for each time it was added.
  void removeStatusListener(AnimationStatusListener listener) =>
      _statusListeners.remove(listener);

  /// Stops it for good, its ticker disposed and its listeners dropped.
  @override
  void dispose() {
    _ticker.dispose();
    _statusListeners.clear();
    super.dispose();
  }

  /// Runs to [target] in the share of [full] the way is of the bounds'.
  void _runTo(double target, Duration? full, Curve curve) {
    final micros = (full ?? (throw _noDuration())).inMicroseconds;
    final share = (target - _value).abs() / (upperBound - lowerBound);
    _start(target, (micros * share).round(), curve);
  }

  void _start(double target, int micros, Curve curve) {
    stop();
    if (micros <= 0 || target == _value) {
      _set(target);
      _setStatus(_ended);
      return;
    }
    _from = _value;
    _to = target;
    _micros = micros;
    _curve = curve;
    _setStatus(
      _forward ? AnimationStatus.forward : AnimationStatus.reverse,
    );
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    final e = elapsed.inMicroseconds;
    final period = _period;
    if (period != null) {
      // how far the rounds are: 0 to 1 on the way up, 1 to 2 back
      final p = (_phase + e / period) % (_bounce ? 2 : 1);
      final back = p > 1;
      _set(lowerBound + (upperBound - lowerBound) * (back ? 2 - p : p));
      _setStatus(back ? AnimationStatus.reverse : AnimationStatus.forward);
      return;
    }
    if (e >= _micros) {
      _ticker.stop();
      _set(_to);
      _setStatus(_ended);
    } else {
      _set(_from + (_to - _from) * _curve.transform(e / _micros));
    }
  }

  /// The status a run ends in.
  AnimationStatus get _ended =>
      _forward ? AnimationStatus.completed : AnimationStatus.dismissed;

  AnimationStatus _statusAt(double value) {
    if (value == lowerBound) {
      return AnimationStatus.dismissed;
    }
    if (value == upperBound) {
      return AnimationStatus.completed;
    }
    return _forward ? AnimationStatus.forward : AnimationStatus.reverse;
  }

  double _clamp(double value) => value < lowerBound
      ? lowerBound
      : (value > upperBound ? upperBound : value);

  void _set(double value) {
    if (value != _value) {
      _value = value;
      notifyListeners();
    }
  }

  void _setStatus(AnimationStatus status) {
    if (status == _status) {
      return;
    }
    _status = status;
    for (final listener in List.of(_statusListeners)) {
      try {
        listener(status);
      } on Object catch (error, stack) {
        Zone.current.handleUncaughtError(error, stack);
      }
    }
  }

  StateError _noDuration() => StateError('$this runs with no duration');

  @override
  String toString() =>
      'AnimationController(${_value.toStringAsFixed(3)}, ${_status.name})';
}
