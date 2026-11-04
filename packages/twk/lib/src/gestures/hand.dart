/// The pointer over what a click presses, by one rule for every tap target:
/// [HandOver].
library;

import 'package:twk_core/twk_core.dart' show HitTestBehavior, PointerShape;

import '../binding/terminal_status.dart';
import '../framework/framework.dart';
import '../style/theme.dart';
import 'mouse.dart';

/// The hand (`PointerShape.pointer`) over what a click presses, by the one
/// rule of [ThemeData.pointerMode], or [shape] in its place. A
/// `GestureDetector` shows it from its taps: this is for what presses
/// otherwise, a menu's press, drag and release.
///
/// Over [child] where [active], else over the cells [where] says yes to
/// (`x` and `y` in [child]'s own coordinates: a tab, not the bar around
/// it); the theme's [PointerMode.off] shows none, and the others ask for the
/// motion as [TerminalStatus.handAsksMotion] says. It is a [MouseRegion] in
/// every mode and every state, so that a theme or a state changing does not
/// rebuild [child] from nothing.
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
    final mode = own == null && active ? Theme.of(context).pointerMode : null;
    final shown = active && mode != PointerMode.off
        ? own ?? PointerShape.pointer
        : null;
    final where = this.where;
    return MouseRegion(
      cursor: where == null ? shown : null,
      cursorAt: shown != null && where != null
          ? (x, y) => where(x, y) ? shown : null
          : null,
      cursorAsksMotion: own == null
          ? mode != null &&
                (TerminalStatus.of(context)?.handAsksMotion(mode) ?? false)
          : own != PointerShape.arrow,
      behavior: behavior,
      child: child,
    );
  }
}
