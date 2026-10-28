/// [ExcludeFocus]: a part of the app the focus stays out of.
library;

import '../framework/framework.dart';
import 'focus_tree.dart';

/// Shows [child], whose focus nodes cannot have the focus while
/// [excluding].
///
/// Tab and Shift+Tab pass them by, autofocus does not focus them, nor does
/// [FocusNode.requestFocus], and a key with no node focused does not start
/// below it ([FocusManager.keyPath]). The focus in [child]
/// when [excluding] turns on leaves it at the end of that build, to where
/// a node that can no longer take the focus sends it
/// ([FocusManager.flush]): the stop of its scope after the subtree, else
/// the one before it, else the scope. Once [excluding] turns off the nodes
/// can have it again; one that asked for it as it was mounted
/// (autofocus) while excluded does not get it then.
///
/// It takes no focus itself: a [Focus] node above those of [child] that
/// cannot request it, so Tab does not stop at it either, and that keeps
/// it from them ([FocusNode.descendantsAreFocusable]); [Focus.of] below
/// finds it. As Flutter's `ExcludeFocus`.
///
/// A form whose fields Tab passes by while it is being sent:
///
/// ```dart
/// final sending = ValueNotifier(false);
/// final form = ValueListenableBuilder(
///   valueListenable: sending,
///   builder: (context, busy, child) =>
///       ExcludeFocus(excluding: busy, child: child!),
///   child: const Column(children: [TextField(), TextField()]),
/// );
/// ```
final class ExcludeFocus extends StatelessWidget {
  /// Keeps the nodes of [child] from the focus while [excluding], by
  /// default.
  const ExcludeFocus({required this.child, this.excluding = true, super.key});

  /// What it shows, whose nodes it keeps from the focus.
  final Widget child;

  /// Whether the nodes of [child] are kept from the focus.
  final bool excluding;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    descendantsAreFocusable: !excluding,
    debugLabel: 'ExcludeFocus',
    child: child,
  );
}
