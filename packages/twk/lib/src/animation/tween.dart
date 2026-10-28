/// A value for each point of an animation: [Animatable], the [Tween]s
/// between two values ([IntTween], [ColorTween]), and their chains.
///
/// @docImport 'curves.dart';
/// @docImport 'implicit.dart';
library;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart' show Color;

import '../foundation/change_notifier.dart';

// Examples can assume:
// late AnimationController controller;
// var failed = false;

/// Maps t, how far an animation is (0 to 1, as an `AnimationController`'s
/// value by default), to a [T].
///
/// [Tween] and the curves ([Curve]) are animatables; another is a class
/// with a [transform] of its own.
@immutable
abstract class Animatable<T> {
  /// An animatable; a subclass's constructor can be const.
  const Animatable();

  /// The value at [t].
  T transform(double t);

  /// The value at [animation]'s value: an `AnimationController`'s, say.
  T evaluate(ValueListenable<double> animation) => transform(animation.value);

  /// This at what [parent] maps t to: a tween chained to a curve runs
  /// along it, `Tween(begin: 0.0, end: 10.0).chain(Curves.easeOut)`.
  Animatable<T> chain(Animatable<double> parent) => _Chained(parent, this);
}

/// [begin] at 0, [end] at 1, and [lerp]'s value between them: for
/// doubles, as far from begin to end as t says, and on beyond them where
/// t is (a curve that overshoots). Other types extend it with a [lerp] of
/// their own, as [IntTween] and [ColorTween] do.
///
/// The width of a bar, 10 to 40 cells as `controller` runs from 0 to 1,
/// eased out:
///
/// ```dart
/// AnimatedBuilder(
///   animation: controller,
///   builder: (context, child) {
///     final width = Tween(begin: 10.0, end: 40.0)
///         .chain(Curves.easeOut)
///         .evaluate(controller);
///     return SizedBox(width: width.round(), height: 1, child: child);
///   },
///   child: const ColoredBox(color: Color.blue),
/// )
/// ```
class Tween<T> extends Animatable<T> {
  /// A tween from [begin], at 0, to [end], at 1.
  const Tween({required this.begin, required this.end});

  /// The value at 0.
  final T begin;

  /// The value at 1.
  final T end;

  /// The value at [t]: for doubles `begin + (end - begin) * t`; an
  /// [UnsupportedError] for another type, which overrides it.
  @protected
  T lerp(double t) {
    if ((begin, end) case (final double a, final double b)) {
      return a + (b - a) * t as T;
    }
    throw UnsupportedError('Tween<$T> has no lerp: extend it with one');
  }

  /// [begin] at 0, [end] at 1, [lerp]'s value elsewhere.
  @override
  T transform(double t) => t == 0 ? begin : (t == 1 ? end : lerp(t));

  @override
  String toString() => 'Tween($begin → $end)';
}

/// The whole number nearest to as far from [begin] to [end] as t says.
class IntTween extends Tween<int> {
  /// A tween of whole numbers from [begin] to [end].
  const IntTween({required super.begin, required super.end});

  @override
  int lerp(double t) => (begin + (end - begin) * t).round();
}

/// Between two colors as `Color.lerp` has it: between two RGB colors,
/// each channel as far from [begin] to [end] as t says; between colors of
/// which either is not RGB (the default, the palette's), [begin] until
/// halfway and [end] from there.
///
/// A dot that turns from green to red as a check fails, in 300 ms:
///
/// ```dart
/// TweenAnimationBuilder<Color>(
///   value: failed
///       ? const Color.rgb(220, 50, 50)
///       : const Color.rgb(50, 200, 80),
///   tween: ColorTween.new,
///   duration: const Duration(milliseconds: 300),
///   builder: (context, color, child) =>
///       Text('●', style: Style(fg: color)),
/// )
/// ```
///
/// See also:
///
///  * [StyleTween], which runs the colors of a whole style, and their
///    alpha, the same way.
class ColorTween extends Tween<Color> {
  /// A tween of colors from [begin] to [end].
  const ColorTween({required super.begin, required super.end});

  @override
  Color lerp(double t) => Color.lerp(begin, end, t);
}

/// [child] at what [parent] maps t to.
final class _Chained<T> extends Animatable<T> {
  const _Chained(this.parent, this.child);

  final Animatable<double> parent;
  final Animatable<T> child;

  @override
  T transform(double t) => child.transform(parent.transform(t));

  @override
  String toString() => '$child.chain($parent)';
}
