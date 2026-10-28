/// A theme that cross-fades to the one it is given: [AnimatedTheme], and
/// the tween between two themes, [ThemeDataTween].
library;

import '../animation/curves.dart';
import '../animation/implicit.dart';
import '../animation/tween.dart';
import '../framework/framework.dart';
import 'theme.dart';

// Examples can assume:
// late bool darkMode;

/// Between two themes, as [ThemeData.lerp] blends them.
class ThemeDataTween extends Tween<ThemeData> {
  /// The themes from [begin] at 0 to [end] at 1.
  const ThemeDataTween({required super.begin, required super.end});

  /// The theme [t] of the way from [begin] to [end] ([ThemeData.lerp]).
  @override
  ThemeData lerp(double t) => ThemeData.lerp(begin, end, t);
}

/// The theme of the widgets below it ([Theme] of [data]), cross-fading to
/// a new one ([ThemeData.lerp]) in [duration] along [curve]: by default in
/// 280 ms, easing in and out, as the design switches themes. The first
/// theme it is given shows at once; [onEnd] is called when a fade ends.
///
/// A theme that follows a setting of the app, faded to when it changes:
///
/// ```dart
/// AnimatedTheme(
///   data: darkMode ? ThemeData.dark : ThemeData.light,
///   child: const Text('Settings'),
/// )
/// ```
///
/// See also:
///
///  * [Theme], which switches at once.
final class AnimatedTheme extends ImplicitlyAnimatedWidget {
  /// Gives the widgets below [data], fading to each new one in [duration]
  /// along [curve].
  const AnimatedTheme({
    required this.data,
    required this.child,
    super.key,
    super.duration = const Duration(milliseconds: 280),
    super.curve = Curves.easeInOut,
    super.onEnd,
  });

  /// The theme the widgets below fade to.
  final ThemeData data;

  /// The widgets the theme is for.
  final Widget child;

  @override
  State<AnimatedTheme> createState() => _AnimatedThemeState();
}

final class _AnimatedThemeState
    extends ImplicitlyAnimatedWidgetState<AnimatedTheme> {
  Tween<ThemeData>? _data;

  @override
  void forEachTween(TweenVisitor visit) =>
      _data = visit(_data, widget.data, ThemeDataTween.new);

  @override
  Widget build(BuildContext context) =>
      Theme(data: _data!.transform(progress), child: widget.child);
}
