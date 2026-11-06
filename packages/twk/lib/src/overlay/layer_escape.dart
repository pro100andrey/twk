/// How a layer of an [Overlay] registers Escape.
library;

import '../focus/shortcuts.dart';
import '../foundation/change_notifier.dart' show VoidCallback;
import '../framework/framework.dart';
import 'layer.dart' show Overlay;

/// The one way a layer (a dialog, a menu, the palette, a popover) binds
/// Escape to closing itself: a `KeyBindings` around [child] with the hint
/// `close`, which a `KeyHintsBar` lists while the layer is open.
///
/// Escape goes along the key path from the focus up, so of the layers that
/// are open the one the focus is in hears it first and closes alone: a
/// popover in a dialog closes before the dialog, a menu over a dialog
/// before it. A layer that does not close by Escape ([onEscape] null)
/// binds nothing, and Escape goes on to the layer under it.
final class LayerEscape extends StatelessWidget {
  /// Binds Escape to [onEscape] around [child].
  const LayerEscape({
    required this.onEscape,
    required this.child,
    required this.debugLabel,
    super.key,
  });

  /// What Escape does; null for a layer that Escape does not close.
  final VoidCallback? onEscape;

  /// The name of the bindings, for the focus tree's dumps.
  final String debugLabel;

  /// What the layer shows.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final close = onEscape;
    return KeyBindings(
      close == null ? const {} : {'escape': close},
      hints: close == null ? const {} : const {'escape': 'close'},
      debugLabel: debugLabel,
      child: child,
    );
  }
}
