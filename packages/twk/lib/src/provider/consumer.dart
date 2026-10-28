/// Widgets that build with what providers above provide: [Consumer] and
/// [Consumer2] with the whole values, [Selector] with a part of one.
library;

import '../../twk.dart';

import 'inherited_provider.dart';
import 'single_child.dart';

// Examples can assume:
// final class Cart extends ChangeNotifier {
//   final items = <String>[];
//   void add(String item) {
//     items.add(item);
//     notifyListeners();
//   }
// }
// final class Settings {
//   const Settings({this.dark = false, this.user = ''});
//   final bool dark;
//   final String user;
// }
// final class Api {
//   Api(this.settings);
//   final Settings settings;
// }
// final class Database {
//   void close() {}
// }
// late Widget app;
// late ValueNotifier<int> unread;
// late Stream<String> statusLines;
// Future<Settings> loadSettings() async => const Settings();

/// Shows what [builder] returns for the [T] of the provider above, built
/// again each time it changes; the widgets around it are not rebuilt.
/// `child`, built once by the parent, is handed to [builder], for what
/// does not depend on the value.
///
/// Only the count is built again when the cart changes, not the title
/// handed in as `child`:
///
/// ```dart
/// Consumer<Cart>(
///   builder: (context, cart, child) =>
///       Row(children: [child!, Text(' ${cart.items.length}')]),
///   child: const Text('Items:'),
/// )
/// ```
final class Consumer<T> extends SingleChildStatelessWidget {
  /// Shows what [builder] returns for the [T] above.
  const Consumer({required this.builder, super.key, super.child});

  /// Builds what this widget shows from the value and the child.
  // called with the value, whose T is this widget's own
  // ignore: unsafe_variance
  final Widget Function(BuildContext context, T value, Widget? child) builder;

  @override
  Widget buildWithChild(BuildContext context, Widget? child) =>
      builder(context, Provider.of<T>(context), child);
}

/// Shows what [builder] returns for the [A] and the [B] of the providers
/// above, as [Consumer] does for one.
///
/// ```dart
/// Consumer2<Settings, Cart>(
///   builder: (context, settings, cart, _) =>
///       Text('${settings.user}: ${cart.items.length} items'),
/// )
/// ```
final class Consumer2<A, B> extends SingleChildStatelessWidget {
  /// Shows what [builder] returns for the [A] and the [B] above.
  const Consumer2({required this.builder, super.key, super.child});

  /// Builds what this widget shows from the values and the child.
  // called with the values, whose types are this widget's own
  // ignore: unsafe_variance
  final Widget Function(BuildContext context, A value, B value2, Widget? child)
  builder;

  @override
  Widget buildWithChild(BuildContext context, Widget? child) => builder(
    context,
    Provider.of<A>(context),
    Provider.of<B>(context),
    child,
  );
}

/// Whether a [Selector] builds again now that what it selects went from
/// [previous] to [next].
typedef ShouldRebuild<T> = bool Function(T previous, T next);

/// Shows what [builder] returns for what [selector] picks with the
/// context, built again only when it picks something else: not `==`,
/// lists, sets, maps and other iterables compared element by element (or
/// as [shouldRebuild] says), or when this widget is replaced. `child` is
/// handed to [builder], as a [Consumer]'s is.
///
/// ```dart
/// Selector0<int>(
///   selector: (context) => context.watch<Cart>().items.length,
///   builder: (context, count, _) => Text('$count items'),
/// )
/// ```
class Selector0<S> extends SingleChildStatefulWidget {
  /// Shows what [builder] returns for what [selector] picks.
  const Selector0({
    required this.builder,
    required this.selector,
    super.key,
    this.shouldRebuild,
    super.child,
  });

  /// Builds what this widget shows from what [selector] picked.
  // called with what the selector picks, whose S is this widget's own
  // ignore: unsafe_variance
  final ValueWidgetBuilder<S> builder;

  /// Picks what [builder] builds with, the providers it finds through the
  /// context watched.
  final S Function(BuildContext context) selector;

  /// Whether to build again for what [selector] picked, given what it
  /// picked before; null builds when the two differ.
  // called with what the selector picks, whose S is this widget's own
  // ignore: unsafe_variance
  final ShouldRebuild<S>? shouldRebuild;

  @override
  State<Selector0<S>> createState() => _SelectorState<S>();
}

final class _SelectorState<S> extends SingleChildState<Selector0<S>> {
  late S _selected;
  Widget? _built;
  // the widget and the child _built was built for
  Selector0<S>? _builtFor;
  Widget? _builtWith;

  @override
  Widget buildWithChild(BuildContext context, Widget? child) {
    final selected = widget.selector(context);
    final built = _built;
    if (built != null &&
        identical(_builtFor, widget) &&
        identical(_builtWith, child) &&
        !(widget.shouldRebuild?.call(_selected, selected) ??
            !deepEquals(_selected, selected))) {
      return built;
    }
    _selected = selected;
    _builtFor = widget;
    _builtWith = child;
    final builder = widget.builder;
    return _built = SingleChildBuilder(
      builder: (context, child) => builder(context, selected, child),
      child: child,
    );
  }
}

/// Shows what [builder] returns for what [selector] picks from the [A] of
/// the provider above, built again only when it picks something else, as
/// [Selector0] is. The selector runs each time the value changes; the
/// builder only then.
///
/// The first item of the cart, built again only when it changes:
///
/// ```dart
/// Selector<Cart, String?>(
///   selector: (context, cart) => cart.items.firstOrNull,
///   builder: (context, first, _) => Text(first ?? 'Empty'),
/// )
/// ```
class Selector<A, S> extends Selector0<S> {
  /// Shows what [builder] returns for what [selector] picks of the [A]
  /// above.
  Selector({
    required super.builder,
    required S Function(BuildContext context, A value) selector,
    super.key,
    super.shouldRebuild,
    super.child,
  }) : super(selector: (context) => selector(context, Provider.of<A>(context)));
}

/// Shows what [builder] returns for what [selector] picks from the [A] and
/// the [B] of the providers above, as [Selector] does for one.
///
/// ```dart
/// Selector2<Settings, Cart, bool>(
///   selector: (context, settings, cart) =>
///       settings.user.isNotEmpty && cart.items.isNotEmpty,
///   builder: (context, canBuy, _) => Text(canBuy ? 'Buy' : '—'),
/// )
/// ```
class Selector2<A, B, S> extends Selector0<S> {
  /// Shows what [builder] returns for what [selector] picks of the [A]
  /// and the [B] above.
  Selector2({
    required super.builder,
    required S Function(BuildContext context, A value, B value2) selector,
    super.key,
    super.shouldRebuild,
    super.child,
  }) : super(
         selector: (context) => selector(
           context,
           Provider.of<A>(context),
           Provider.of<B>(context),
         ),
       );
}
