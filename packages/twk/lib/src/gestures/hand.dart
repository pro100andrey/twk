/// The pointer over what a click presses, by one rule for every tap target:
/// [HandOver].
library;

import 'package:twk_core/twk_core.dart' show HitTestBehavior, PointerShape;

import '../framework/framework.dart';
import '../style/theme.dart';
import 'mouse.dart';

/// The hand (`PointerShape.pointer`) over what a click presses, by the one
/// rule of [ThemeData.handPointer], or [shape] in its place. A
/// `GestureDetector` shows it from its taps: this is for what presses
/// otherwise, a menu's press, drag and release.
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
    this.shape,
    this.behavior = HitTestBehavior.deferToChild,
  });

  /// Whether [child] is pressed by a click; false for none.
  final bool active;

  /// Whether the cell at `x`, `y` of [child] is pressed by a click; null
  /// for all of it.
  final bool Function(int x, int y)? where;

  /// The shape in place of the hand, whatever the theme says;
  /// `PointerShape.arrow` asks for no motion, another does. Null for the
  /// hand.
  final PointerShape? shape;

  /// Where the mouse is in it.
  final HitTestBehavior behavior;

  /// What is pressed.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final own = shape;
    final mode = own == null && active ? Theme.of(context).handPointer : null;
    final shown = active && mode != HandPointer.off
        ? own ?? PointerShape.pointer
        : null;
    final where = this.where;
    return MouseRegion(
      cursor: where == null ? shown : null,
      cursorAt: shown != null && where != null
          ? (x, y) => where(x, y) ? shown : null
          : null,
      cursorAsksMotion: own == null
          ? mode == HandPointer.on
          : own != PointerShape.arrow,
      behavior: behavior,
      child: child,
    );
  }
}
