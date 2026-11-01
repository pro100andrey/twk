import 'package:twk_core/twk_core.dart' show HitTestBehavior, PointerShape;

import '../framework/framework.dart';
import '../gestures/mouse.dart';
import '../style/theme.dart';

/// The hand (`PointerShape.pointer`) over what a click presses, by the one
/// rule of [ThemeData.handPointer]: every widget with a tap target wraps it
/// in this, and none sets the shape itself.
///
/// Over [child] where [active], else over the cells [where] says yes to
/// (`x` and `y` in [child]'s own coordinates: a tab, not the bar around
/// it); the theme's [HandPointer.off] shows none, [HandPointer.auto] only
/// where the mouse's motion is reported already, [HandPointer.on] always,
/// which asks for the motion. It is a [MouseRegion] in every mode and every
/// state, so that a theme or a state changing does not rebuild [child]
/// from nothing.
final class HandOver extends StatelessWidget {
  /// [child] with the hand over it while [active], or over the cells
  /// [where] gives.
  const HandOver({
    required this.child,
    super.key,
    this.active = true,
    this.where,
    this.behavior = HitTestBehavior.deferToChild,
  });

  /// Whether [child] is pressed by a click; false for none.
  final bool active;

  /// Whether the cell at `x`, `y` of [child] is pressed by a click; null
  /// for all of it.
  final bool Function(int x, int y)? where;

  /// Where the mouse is in it.
  final HitTestBehavior behavior;

  /// What is pressed.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mode = Theme.of(context).handPointer;
    final shows = active && mode != HandPointer.off;
    final where = this.where;
    return MouseRegion(
      cursor: shows && where == null ? PointerShape.pointer : null,
      cursorAt: shows && where != null
          ? (x, y) => where(x, y) ? PointerShape.pointer : null
          : null,
      cursorAsksMotion: mode == HandPointer.on,
      behavior: behavior,
      child: child,
    );
  }

  /// The shape for a [MouseRegion] that has callbacks and so has the
  /// motion reported already: the hand where [active] and the theme asks
  /// for it, else null.
  static PointerShape? shapeFor(BuildContext context, {bool active = true}) =>
      active && Theme.of(context).handPointer != HandPointer.off
      ? PointerShape.pointer
      : null;
}
