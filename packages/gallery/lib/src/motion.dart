// Time and motion in the gallery: the clock a route can stop ([Clock]),
// and values that glide to where they are asked to go ([Motion])
// (doc/design.md, "Motion").
import 'dart:math' as math;

import 'package:twk/twk.dart';

/// The gallery's time: the app's frame time ([AppBinding.frameTime]), or
/// a time it stands still at ([Clock.frozen]), as a route's `t=` stops
/// it: the shell's motions are at their end at once, toasts stay,
/// and a page that moves with time shows that moment.
final class Clock {
  /// The app's time.
  const Clock.app() : frozenAt = null;

  /// Time standing still at [at].
  const Clock.frozen(Duration at) : frozenAt = at;

  /// The clock of the gallery above [context]; the app's where none is.
  factory Clock.of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ClockScope>()?.clock ??
      const Clock.app();

  /// The time it stands still at; null for the app's time.
  final Duration? frozenAt;

  /// Whether it stands still.
  bool get frozen => frozenAt != null;

  /// The time now, in the app [context] is in.
  Duration now(BuildContext context) =>
      frozenAt ?? AppBinding.maybeOf(context)?.frameTime ?? Duration.zero;
}

/// Gives the widgets below it the gallery's [clock].
final class ClockScope extends InheritedWidget {
  const ClockScope({required this.clock, required super.child, super.key});

  final Clock clock;

  @override
  bool updateShouldNotify(ClockScope oldWidget) => clock != oldWidget.clock;
}

/// The design's ease-out: a cubic, fast at first.
double easeOut(double x) => 1 - math.pow(1 - x, 3).toDouble();

/// The design's ease-in-out: a cubic, slow at both ends.
double easeInOut(double x) =>
    x < 0.5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3).toDouble() / 2;

/// The design's theme fade: a quadratic ease-in-out.
final class ThemeCurve extends Curve {
  const ThemeCurve();

  @override
  double transformInternal(double t) =>
      t < 0.5 ? 2 * t * t : 1 - math.pow(-2 * t + 2, 2).toDouble() / 2;
}

/// A value on its way: from [from] to [to], from [start] for [ms].
final class _Glide {
  _Glide(this.to) : from = to;

  double from;
  double to;
  Duration start = Duration.zero;
  var ms = 0;
  double Function(double) curve = easeOut;

  double at(Duration now) {
    if (ms <= 0) {
      return to;
    }
    final p = (now - start).inMicroseconds / (ms * 1000);
    if (p >= 1) {
      return to;
    }
    if (p <= 0) {
      return from;
    }
    return from + (to - from) * curve(p);
  }
}

/// Values that glide to where they are asked to go, for a [State]: each
/// asks for frames while it moves and rebuilds the state with [onFrame].
/// Under a frozen [Clock] each is where it goes at once.
final class Motion {
  Motion(this.onFrame);

  /// Rebuilds what shows the values.
  final void Function() onFrame;

  final _glides = <String, _Glide>{};
  AppBinding? _binding;
  int? _callback;
  var _clock = const Clock.app();
  Duration _now = Duration.zero;
  var _wantsFrame = false;
  int? _wakeId;
  Duration _wake = Duration.zero;

  /// The time of this build.
  Duration get now => _now;

  /// Whether time stands still.
  bool get frozen => _clock.frozen;

  /// Reads the time for a build in [context]: call it first in build.
  void begin(BuildContext context) {
    _binding = AppBinding.maybeOf(context);
    _clock = Clock.of(context);
    _now = _clock.now(context);
    _wantsFrame = false;
  }

  /// Asks for frames after this build: call it last in build.
  void end() {
    if (_wantsFrame) {
      animate();
    }
  }

  /// The value [key] has on its way to [target], which it takes [ms] to
  /// reach from where it was when [target] changed, along [curve].
  double glide(
    String key,
    double target,
    int ms, {
    double Function(double) curve = easeOut,
  }) {
    final g = _glides[key] ??= _Glide(target);
    if (g.to != target) {
      g
        ..from = g.at(_now)
        ..to = target
        ..start = _now
        ..ms = ms
        ..curve = curve;
    }
    if (_clock.frozen) {
      return target;
    }
    final v = g.at(_now);
    if (v != g.to) {
      _wantsFrame = true;
    }
    return v;
  }

  /// Puts [key] where it goes at once.
  void jump(String key, double target) => _glides[key] = _Glide(target);

  /// The target of [key], or null before it was asked.
  double? targetOf(String key) => _glides[key]?.to;

  /// How far [ms] from [start] the time is, from 0 to 1; 1 when frozen.
  double progress(Duration start, int ms) {
    if (_clock.frozen) {
      return 1;
    }
    final p = (_now - start).inMicroseconds / (ms * 1000);
    if (p < 1) {
      _wantsFrame = true;
    }
    return p <= 0 ? 0 : (p >= 1 ? 1 : p);
  }

  /// Asks for the next frame, and a rebuild in it.
  void animate() {
    final binding = _binding;
    if (binding == null || _callback != null || _clock.frozen) {
      return;
    }
    _callback = binding.scheduleFrameCallback((_) {
      _callback = null;
      onFrame();
    });
  }

  /// Asks for a rebuild at [at] on the app's clock; one asked for
  /// sooner is kept.
  void wakeAt(Duration at) {
    final binding = _binding;
    if (binding == null || _clock.frozen) {
      return;
    }
    final pending = _wakeId;
    if (pending != null) {
      if (_wake <= at) {
        return;
      }
      binding.cancelFrameCallback(pending);
    }
    _wake = at;
    _wakeId = binding.scheduleFrameCallback((_) {
      _wakeId = null;
      onFrame();
    }, at: at);
  }

  void dispose() {
    for (final id in [_callback, _wakeId]) {
      if (id != null) {
        _binding?.cancelFrameCallback(id);
      }
    }
    _callback = null;
    _wakeId = null;
  }
}
