/// [FocusBuilder]: what follows the focus into and out of a part of the
/// app, as a border lit while the focus is in a box.
library;

import '../foundation/listenable_builder.dart';
import '../framework/framework.dart';
import 'focus_tree.dart';

// Examples can assume:
// late ThemeData theme;

/// Shows what [builder] returns for whether the focus is in this widget's
/// subtree, built again when the focus enters or leaves it; the widgets
/// around it are not.
///
/// It takes no focus itself: Tab does not stop at it, nor does a press
/// focus it, as `Focus(canRequestFocus: false, skipTraversal: true)`
/// around a `Builder` that reads `Focus.of(context).hasFocus` does in
/// Flutter, made one widget:
///
/// ```dart
/// FocusBuilder(
///   builder: (context, hasFocus, child) => Box(
///     border: Border.all(
///       type: .rounded,
///       style: hasFocus ? theme.primary : theme.border,
///     ),
///     child: child,
///   ),
///   child: const TextField(),
/// )
/// ```
///
/// [child] is handed to [builder] each time, as a [ListenableBuilder]'s
/// is: built once by the parent, it is not rebuilt as the focus moves.
final class FocusBuilder extends StatelessWidget {
  /// Shows what [builder] returns for whether the focus is in it.
  const FocusBuilder({
    required this.builder,
    this.child,
    this.debugLabel,
    super.key,
  });

  /// Builds the subtree from whether the primary focus is in it.
  final ValueWidgetBuilder<bool> builder;

  /// Handed to [builder].
  final Widget? child;

  /// Names the node this widget puts in the focus tree.
  final String? debugLabel;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    debugLabel: debugLabel,
    child: _Built(builder, child),
  );
}

/// What the [FocusBuilder] shows, built again when the focus of the node
/// above it changes.
final class _Built extends StatelessWidget {
  const _Built(this.builder, this.child);

  final ValueWidgetBuilder<bool> builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) =>
      builder(context, Focus.of(context).hasFocus, child);
}
