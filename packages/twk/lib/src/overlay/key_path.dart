/// What the keys reach from the focused node of an app: the context they
/// start at ([keyTarget]) and the keys bound there ([activeKeysAt],
/// [firstKeys]), which the menus and the command palette show and do what
/// they do from.
library;

import '../focus/focus.dart';
import '../framework/framework.dart';

/// The context of the node the keys go to first in the app [context] is
/// in ([FocusManager.keyPath]); [context] while none has one in the tree.
BuildContext keyTarget(BuildContext context) {
  final manager = Focus.maybeOf(context, createDependency: false)?.manager;
  final first = manager?.keyPath.first.context;
  return first != null && first.mounted ? first : context;
}

/// The keys [FocusManagerKeys.activeKeys] lists now in the app [context]
/// is in.
List<ActiveKey> activeKeysAt(BuildContext context) =>
    Focus.maybeOf(context, createDependency: false)?.manager?.activeKeys ??
    const [];

/// Of [keys], the first bound to each callback and intent.
Map<Object, ActiveKey> firstKeys(Iterable<ActiveKey> keys) {
  final first = <Object, ActiveKey>{};
  for (final key in keys) {
    first.putIfAbsent(key.binding, () => key);
  }
  return first;
}
