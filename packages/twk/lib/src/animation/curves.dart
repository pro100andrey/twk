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

final class _BounceOut extends Curve {
  const _BounceOut();

  @override
  double transformInternal(double t) {
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

  @override
  String toString() => 'Curves.bounceOut';
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
