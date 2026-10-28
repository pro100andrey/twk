/// Widgets that rebuild when a listenable notifies: [ListenableBuilder] and
/// [ValueListenableBuilder].
library;

import '../framework/framework.dart';
import 'change_notifier.dart';

// Examples can assume:
// abstract class Cart extends ChangeNotifier { List<String> get items; }
// late Cart cart;
// late ValueNotifier<int> count;

/// Builds a widget around [child], the part of it built by the caller.
typedef TransitionBuilder = Widget Function(
  BuildContext context,
  Widget? child,
);

/// Builds a widget from [value], around [child], the part of it built by
/// the caller.
typedef ValueWidgetBuilder<T> = Widget Function(
  BuildContext context,
  T value,
  Widget? child,
);

/// Shows what [builder] returns, built again in the next build scope
/// whenever [listenable] notifies; the widgets around this one are not.
///
/// [child] is handed to [builder] each time: the part of the subtree that
/// does not depend on [listenable], built once by the parent, and not
/// rebuilt with the rest. A new [listenable] from the parent is listened
/// to in place of the old one.
///
/// The items of a cart, a [ChangeNotifier] the app keeps:
///
/// ```dart
/// ListenableBuilder(
///   listenable: cart,
///   builder: (context, child) => Text('${cart.items.length} items'),
/// )
/// ```
///
/// See also:
///
///  * [ValueListenableBuilder], which hands [builder] the value of a
///    [ValueListenable].
///  * `AnimatedBuilder`, the same under Flutter's name for an animation.
class ListenableBuilder extends StatefulWidget {
  /// Shows what [builder] returns, built again when [listenable]
  /// notifies.
  const ListenableBuilder({
    required this.listenable,
    required this.builder,
    super.key,
    this.child,
  });

  /// What this widget listens to while its element is in the tree.
  final Listenable listenable;

  /// Builds what this widget shows, from what [listenable] holds; it is
  /// handed [child].
  final TransitionBuilder builder;

  /// Handed to [builder]; see [ListenableBuilder].
  final Widget? child;

  @override
  State<ListenableBuilder> createState() => _ListenableBuilderState();
}

final class _ListenableBuilderState extends _ListeningState<ListenableBuilder> {
  @override
  Listenable _listenableOf(ListenableBuilder widget) => widget.listenable;

  @override
  Widget build(BuildContext context) => widget.builder(context, widget.child);
}

/// Shows what [builder] returns for the value of [valueListenable], built
/// again in the next build scope whenever it notifies; [child] is as a
/// [ListenableBuilder]'s.
///
/// ```dart
/// ValueListenableBuilder<int>(
///   valueListenable: count,
///   builder: (context, value, child) => Text('Count: $value'),
/// )
/// ```
///
/// See also:
///
///  * [ListenableBuilder], for any [Listenable].
final class ValueListenableBuilder<T> extends StatefulWidget {
  /// Shows what [builder] returns for [valueListenable]'s value, built
  /// again when it notifies.
  const ValueListenableBuilder({
    required this.valueListenable,
    required this.builder,
    super.key,
    this.child,
  });

  /// What this widget listens to while its element is in the tree.
  final ValueListenable<T> valueListenable;

  /// Builds what this widget shows from the value; it is handed [child].
  // called by the state, whose T is the widget's own
  // ignore: unsafe_variance
  final ValueWidgetBuilder<T> builder;

  /// Handed to [builder]; see [ListenableBuilder].
  final Widget? child;

  @override
  State<ValueListenableBuilder<T>> createState() =>
      _ValueListenableBuilderState<T>();
}

final class _ValueListenableBuilderState<T>
    extends _ListeningState<ValueListenableBuilder<T>> {
  @override
  Listenable _listenableOf(ValueListenableBuilder<T> widget) =>
      widget.valueListenable;

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.valueListenable.value, widget.child);
}

/// A state that listens to the listenable of its widget, of each new
/// widget's from its update on, until it is disposed, and rebuilds when
/// that notifies.
abstract base class _ListeningState<W extends StatefulWidget> extends State<W> {
  Listenable _listenableOf(W widget);

  @override
  void initState() {
    super.initState();
    _listenableOf(widget).addListener(_changed);
  }

  @override
  void didUpdateWidget(W oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = _listenableOf(oldWidget);
    final current = _listenableOf(widget);
    if (old != current) {
      old.removeListener(_changed);
      current.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _listenableOf(widget).removeListener(_changed);
    super.dispose();
  }

  // what the build reads has changed already
  void _changed() => setState(() {});
}
