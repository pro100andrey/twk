/// Floating panels: what an overlay shows over the app (menus, popovers,
/// toasts, dialogs, the command palette) stands out of it as a [Panel].
library;

import 'package:twk_core/twk_core.dart' show Brightness, EdgeInsets;

import '../framework/framework.dart';
import '../layout/box.dart';
import '../layout/shadow.dart';
import '../style/style.dart';

/// How a floating panel stands out of what is under it.
enum PanelLook {
  /// The theme's surface with a cell of room around what is in it and no
  /// outline, a shadow lifting it where it casts one ([Panel.shadowOf]).
  raised,

  /// The theme's surface in a border of the theme's border color, the
  /// border where the raised panel has its room.
  bordered,
}

/// [child] on a panel that floats over what is under it: the theme's
/// surface and text (and [style] over them), [padding] around the child
/// and, as [look] says, a cell of room around that ([PanelLook.raised]) or
/// a border in the theme's border color ([PanelLook.bordered]); either way
/// as big. With [shadow] it casts the theme's panel shadow ([shadowOf]) to
/// its right and below it, in cells of its own ([Shadow]).
///
/// A bordered panel of a little room around its text, as a popover's:
///
/// ```dart
/// Panel(
///   look: PanelLook.bordered,
///   padding: const EdgeInsets.x(1),
///   child: Text('3 files changed'),
/// )
/// ```
final class Panel extends StatelessWidget {
  /// [child] on a floating panel, [PanelLook.raised] with a shadow by
  /// default.
  const Panel({
    required this.child,
    super.key,
    this.look = PanelLook.raised,
    this.padding = EdgeInsets.zero,
    this.shadow = true,
    this.style,
  });

  /// What is on the panel.
  final Widget child;

  /// Raised (the default) or bordered.
  final PanelLook look;

  /// The cells between the room or the border and [child].
  final EdgeInsets padding;

  /// Whether it casts [shadowOf] its theme.
  final bool shadow;

  /// Merged over the theme's surface and text.
  final Style? style;

  /// The shadow a panel casts in [theme]: two columns to its right and a
  /// row below it, what is under it taken 55 % of the way to black on a
  /// dark theme, 18 % on a light one, exactly ([BoxShadow.opacity]).
  static BoxShadow shadowOf(ThemeData theme) => BoxShadow(
    opacity: theme.brightness == Brightness.dark ? 0.55 : 0.18,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill = theme.surface.merge(theme.text).merge(style ?? const Style());
    final p = padding;
    final box = switch (look) {
      PanelLook.raised => Box(
        style: fill,
        padding: EdgeInsets.only(
          left: p.left + 1,
          top: p.top + 1,
          right: p.right + 1,
          bottom: p.bottom + 1,
        ),
        child: child,
      ),
      PanelLook.bordered => Box(
        style: fill,
        border: Border.all(style: theme.border),
        padding: p,
        child: child,
      ),
    };
    return shadow ? Shadow(shadow: shadowOf(theme), child: box) : box;
  }
}
