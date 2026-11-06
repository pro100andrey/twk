/// How an animation's progress maps to the progress shown: [Curve], the
/// [Cubic] and [Interval] curves, and the common ones in [Curves].
///
/// @docImport 'animated_builder.dart';
/// @docImport 'implicit.dart';
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'tween.dart';

// Examples can assume:
// late AnimationController controller;

/// Maps the progress of an animation, t from 0 to 1, to the progress
/// shown: 0 at 0 and 1 at 1, and in between what [transformInternal]
/// says. An [Animatable] of doubles: a tween chained to it
/// ([Animatable.chain]) runs along it.
///
/// [Curves] has the common ones; a curve of one's own extends this with a
/// [transformInternal]:
///
/// ```dart
/// final class Steps4 extends Curve {
///   const Steps4();
///
///   @override
///   double transformInternal(double t) => (t * 4).floor() / 4;
/// }
/// ```
@immutable
abstract class Curve extends Animatable<double> {
  /// A curve; a subclass's constructor can be const.
  const Curve();

  /// The progress shown at [t], from 0 to 1: exactly 0 and 1 at the ends.
  @override
  double transform(double t) {
    assert(t >= 0 && t <= 1, 't is $t, not from 0 to 1');
    return t == 0 || t == 1 ? t : transformInternal(t);
  }

  /// The progress shown at [t], between 0 and 1.
  @protected
  double transformInternal(double t);

  /// This curve backwards: what it shows at `1 - t`, upside down.
  Curve get flipped => _Flipped(this);
}

/// The curve of a cubic Bézier from (0, 0) to (1, 1) through the control
/// points ([a], [b]) and ([c], [d]), as CSS's `cubic-bezier(a, b, c, d)`;
/// worked out to within 0.001.
///
/// ```dart
/// AnimatedOpacity(
///   opacity: 1,
///   duration: const Duration(milliseconds: 200),
///   curve: const Cubic(0.2, 0, 0, 1),
///   child: Text('hello'),
/// )
/// ```
final class Cubic extends Curve {
  /// The curve whose control points are ([a], [b]) and ([c], [d]).
  const Cubic(this.a, this.b, this.c, this.d);

  /// The x of the first control point, from 0 to 1.
  final double a;

  /// The y of the first control point.
  final double b;

  /// The x of the second control point, from 0 to 1.
  final double c;

  /// The y of the second control point.
  final double d;

  static double _at(double p1, double p2, double m) =>
      3 * p1 * (1 - m) * (1 - m) * m + 3 * p2 * (1 - m) * m * m + m * m * m;

  @override
  double transformInternal(double t) {
    var start = 0.0;
    var end = 1.0;
    for (;;) {
      final m = (start + end) / 2;
      final x = _at(a, c, m);
      if ((t - x).abs() < 0.001) {
        return _at(b, d, m);
      }
      if (x < t) {
        start = m;
      } else {
        end = m;
      }
    }
  }

  @override
  String toString() => 'Cubic($a, $b, $c, $d)';
}

/// 0 until [begin], 1 from [end], and [curve] stretched over the part in
/// between: of an animation that runs several things, one that runs in
/// part of its time.
///
/// Of one controller's run, a title that fades in over its first half and
/// a line that fades in over its second:
///
/// ```dart
/// AnimatedBuilder(
///   animation: controller,
///   builder: (context, child) => Column(
///     children: [
///       Opacity(
///         opacity: const Interval(0, 0.5).evaluate(controller),
///         child: Text('Title'),
///       ),
///       Opacity(
///         opacity: const Interval(0.5, 1).evaluate(controller),
///         child: Text('and what it is about'),
///       ),
///     ],
///   ),
/// )
/// ```
final class Interval extends Curve {
  /// The curve that runs [curve], linear by default, from [begin] to
  /// [end]; asserts that `0 <= begin <= end <= 1`.
  const Interval(this.begin, this.end, {this.curve = Curves.linear})
    : assert(begin >= 0 && begin <= end && end <= 1, 'not 0 ≤ begin ≤ end ≤ 1');

  /// Where it starts to move from 0, from 0 to 1.
  final double begin;

  /// Where it reaches 1, from [begin] to 1.
  final double end;

  /// What it runs along between [begin] and [end].
  final Curve curve;

  @override
  double transformInternal(double t) {
    if (t <= begin) {
      return 0;
    }
    if (t >= end) {
      return 1;
    }
    return curve.transform((t - begin) / (end - begin));
  }

  @override
  String toString() => 'Interval($begin, $end, $curve)';
}

/// The curves an animation usually runs along.
///
/// ```dart
/// AnimatedAlign(
///   alignment: Alignment.centerRight,
///   duration: const Duration(milliseconds: 600),
///   curve: Curves.bounceOut,
///   child: Text('●'),
/// )
/// ```
abstract final class Curves {
  /// As much progress shown as made.
  static const Curve linear = _Linear();

  /// Starts slowly, speeds up, and ends slowly: CSS's `ease`.
  static const Curve ease = Cubic(0.25, 0.1, 0.25, 1);

  /// Starts slowly and speeds up to the end: what leaves the screen.
  static const Curve easeIn = Cubic(0.42, 0, 1, 1);

  /// Starts fast and slows down to the end: what comes into view.
  static const Curve easeOut = Cubic(0, 0, 0.58, 1);

  /// Starts and ends slowly: what moves from one place to another.
  static const Curve easeInOut = Cubic(0.42, 0, 0.58, 1);

  /// Speeds up quickly and slows down gently: Material's standard curve.
  static const Curve fastOutSlowIn = Cubic(0.4, 0, 0.2, 1);

  /// Starts at full speed and slows down evenly to a stop.
  static const Curve decelerate = _Decelerate();

  /// Falls to the end and bounces off it, ever lower.
  static const Curve bounceOut = _BounceOut();

  /// Overshoots the end and swings around it, ever less, as a spring.
  static const Curve elasticOut = _ElasticOut();

  /// Starts at full speed and slows to a stop very gradually.
  static const fastLinearToSlowEaseIn = Cubic(0.18, 1, 0.04, 1);

  /// Fast at first, then slowing: the curve of iOS's page transition.
  static const Curve fastEaseInToSlowEaseOut = _ThreePointCubic(
    (0.056, 0.024),
    (0.108, 0.3085),
    (0.198, 0.541),
    (0.3655, 1),
    (0.5465, 0.989),
  );

  /// Starts slowly, then goes nearly straight.
  static const easeInToLinear = Cubic(0.67, 0.03, 0.65, 0.09);

  /// Starts nearly straight, then slows to a stop.
  static const linearToEaseOut = Cubic(0.35, 0.91, 0.33, 0.97);

  /// Starts slowly and speeds up, as the sine of a quarter turn.
  static const easeInSine = Cubic(0.47, 0, 0.745, 0.715);

  /// Starts slowly and speeds up, as the square of the progress.
  static const easeInQuad = Cubic(0.55, 0.085, 0.68, 0.53);

  /// Starts slowly and speeds up, as the cube of the progress.
  static const easeInCubic = Cubic(0.55, 0.055, 0.675, 0.19);

  /// Starts slowly and speeds up, as the fourth power of the progress.
  static const easeInQuart = Cubic(0.895, 0.03, 0.685, 0.22);

  /// Starts slowly and speeds up, as the fifth power of the progress.
  static const easeInQuint = Cubic(0.755, 0.05, 0.855, 0.06);

  /// Starts slowly and speeds up, as an exponential.
  static const easeInExpo = Cubic(0.95, 0.05, 0.795, 0.035);

  /// Starts slowly and speeds up, as a circle's arc.
  static const easeInCirc = Cubic(0.6, 0.04, 0.98, 0.335);

  /// Pulls back a little before it speeds up to the end.
  static const easeInBack = Cubic(0.6, -0.28, 0.735, 0.045);

  /// Starts fast and slows down, as the sine of a quarter turn.
  static const easeOutSine = Cubic(0.39, 0.575, 0.565, 1);

  /// Starts fast and slows down, as the square of the time left.
  static const easeOutQuad = Cubic(0.25, 0.46, 0.45, 0.94);

  /// Starts fast and slows down, as the cube of the time left.
  static const easeOutCubic = Cubic(0.215, 0.61, 0.355, 1);

  /// Starts fast and slows down, as the fourth power of the time left.
  static const easeOutQuart = Cubic(0.165, 0.84, 0.44, 1);

  /// Starts fast and slows down, as the fifth power of the time left.
  static const easeOutQuint = Cubic(0.23, 1, 0.32, 1);

  /// Starts fast and slows down, as an exponential.
  static const easeOutExpo = Cubic(0.19, 1, 0.22, 1);

  /// Starts fast and slows down, as a circle's arc.
  static const easeOutCirc = Cubic(0.075, 0.82, 0.165, 1);

  /// Overshoots the end a little and comes back.
  static const easeOutBack = Cubic(0.175, 0.885, 0.32, 1.275);

  /// Starts and ends slowly, as the sine of half a turn.
  static const easeInOutSine = Cubic(0.445, 0.05, 0.55, 0.95);

  /// Starts and ends slowly, as the square of the progress.
  static const easeInOutQuad = Cubic(0.455, 0.03, 0.515, 0.955);

  /// Starts and ends slowly, as the cube of the progress.
  static const easeInOutCubic = Cubic(0.645, 0.045, 0.355, 1);

  /// Starts and ends slowly, with most of the move in its first quarter.
  static const Curve easeInOutCubicEmphasized = _ThreePointCubic(
    (0.05, 0),
    (0.133333, 0.06),
    (0.166666, 0.4),
    (0.208333, 0.82),
    (0.25, 1),
  );

  /// Starts and ends slowly, as the fourth power of the progress.
  static const easeInOutQuart = Cubic(0.77, 0, 0.175, 1);

  /// Starts and ends slowly, as the fifth power of the progress.
  static const easeInOutQuint = Cubic(0.86, 0, 0.07, 1);

  /// Starts and ends slowly, as an exponential.
  static const easeInOutExpo = Cubic(1, 0, 0, 1);

  /// Starts and ends slowly, as a circle's arc.
  static const easeInOutCirc = Cubic(0.785, 0.135, 0.15, 0.86);

  /// Pulls back at the start and overshoots the end a little.
  static const easeInOutBack = Cubic(0.68, -0.55, 0.265, 1.55);

  /// Fast at the start and the end, slow in the middle.
  static const slowMiddle = Cubic(0.15, 0.85, 0.85, 0.15);

  /// Bounces off the start, ever higher, and then rises to the end.
  static const Curve bounceIn = _BounceIn();

  /// Bounces off the start and falls to the end, then bounces off it,
  /// ever lower.
  static const Curve bounceInOut = _BounceInOut();

  /// Swings around the start, ever more, before it goes to the end.
  static const Curve elasticIn = _ElasticIn();

  /// Swings around the start, then around the end, ever less.
  static const Curve elasticInOut = _ElasticInOut();
}

final class _Linear extends Curve {
  const _Linear();

  @override
  double transformInternal(double t) => t;

  @override
  String toString() => 'Curves.linear';
}

final class _Decelerate extends Curve {
  const _Decelerate();

  @override
  double transformInternal(double t) => 1 - (1 - t) * (1 - t);

  @override
  String toString() => 'Curves.decelerate';
}

double _bounce(double t) {
  if (t < 1 / 2.75) {
    return 7.5625 * t * t;
  }
  if (t < 2 / 2.75) {
    final u = t - 1.5 / 2.75;
    return 7.5625 * u * u + 0.75;
  }
  if (t < 2.5 / 2.75) {
    final u = t - 2.25 / 2.75;
    return 7.5625 * u * u + 0.9375;
  }
  final u = t - 2.625 / 2.75;
  return 7.5625 * u * u + 0.984375;
}

final class _BounceOut extends Curve {
  const _BounceOut();

  @override
  double transformInternal(double t) => _bounce(t);

  @override
  String toString() => 'Curves.bounceOut';
}

final class _BounceIn extends Curve {
  const _BounceIn();

  @override
  double transformInternal(double t) => 1 - _bounce(1 - t);

  @override
  String toString() => 'Curves.bounceIn';
}

final class _BounceInOut extends Curve {
  const _BounceInOut();

  @override
  double transformInternal(double t) =>
      t < 0.5 ? (1 - _bounce(1 - t * 2)) * 0.5 : _bounce(t * 2 - 1) * 0.5 + 0.5;

  @override
  String toString() => 'Curves.bounceInOut';
}

final class _ElasticOut extends Curve {
  const _ElasticOut();

  // the time a swing takes
  static const _period = 0.4;

  @override
  double transformInternal(double t) =>
      math.pow(2, -10 * t) *
          math.sin((t - _period / 4) * 2 * math.pi / _period) +
      1;

  @override
  String toString() => 'Curves.elasticOut';
}

final class _ElasticIn extends Curve {
  const _ElasticIn();

  @override
  double transformInternal(double t) {
    const period = _ElasticOut._period;
    final u = t - 1;
    return -math.pow(2, 10 * u) *
        math.sin((u - period / 4) * 2 * math.pi / period);
  }

  @override
  String toString() => 'Curves.elasticIn';
}

final class _ElasticInOut extends Curve {
  const _ElasticInOut();

  @override
  double transformInternal(double t) {
    const period = _ElasticOut._period;
    final u = 2 * t - 1;
    final swing = math.sin((u - period / 4) * 2 * math.pi / period);
    return u < 0
        ? -0.5 * math.pow(2, 10 * u) * swing
        : math.pow(2, -10 * u) * swing * 0.5 + 1;
  }

  @override
  String toString() => 'Curves.elasticInOut';
}

/// Two cubic Béziers joined at [midpoint]: the first from (0, 0) through
/// [a1] and [b1], the second from the midpoint through [a2] and [b2] to
/// (1, 1), as Flutter's `ThreePointCubic`.
final class _ThreePointCubic extends Curve {
  const _ThreePointCubic(this.a1, this.b1, this.midpoint, this.a2, this.b2);

  final (double, double) a1;
  final (double, double) b1;
  final (double, double) midpoint;
  final (double, double) a2;
  final (double, double) b2;

  @override
  double transformInternal(double t) {
    final (mx, my) = midpoint;
    final first = t < mx;
    final scaleX = first ? mx : 1 - mx;
    final scaleY = first ? my : 1 - my;
    final scaledT = (t - (first ? 0 : mx)) / scaleX;
    if (first) {
      return Cubic(
            a1.$1 / scaleX,
            a1.$2 / scaleY,
            b1.$1 / scaleX,
            b1.$2 / scaleY,
          ).transform(scaledT) *
          scaleY;
    }
    return Cubic(
              (a2.$1 - mx) / scaleX,
              (a2.$2 - my) / scaleY,
              (b2.$1 - mx) / scaleX,
              (b2.$2 - my) / scaleY,
            ).transform(scaledT) *
            scaleY +
        my;
  }

  @override
  String toString() => 'ThreePointCubic($a1, $b1, $midpoint, $a2, $b2)';
}

final class _Flipped extends Curve {
  const _Flipped(this.curve);

  final Curve curve;

  @override
  double transformInternal(double t) => 1 - curve.transform(1 - t);

  @override
  Curve get flipped => curve;

  @override
  String toString() => '$curve.flipped';
}
