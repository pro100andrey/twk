/// Widgets built around a child that a [MultiProvider] may give them, as
/// package:nested's are for Flutter's provider.
library;

import 'package:meta/meta.dart';

import '../../twk.dart';

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

/// A widget a [MultiProvider] can nest: one built around a child, which it
/// leaves out there, the next widget of the list being its child.
abstract interface class SingleChildWidget implements Widget {}

/// A [StatelessWidget] built around a child: [buildWithChild] gets the one
/// given to the constructor, or in a [MultiProvider] the next widget of its
/// list (its child, for the last).
///
/// A widget that frames its child, which a [MultiProvider] can nest:
///
/// ```dart
/// final class Framed extends SingleChildStatelessWidget {
///   const Framed({super.key, super.child});
///
///   @override
///   Widget buildWithChild(BuildContext context, Widget? child) =>
///       Box(border: const Border.all(), child: child);
/// }
/// ```
abstract class SingleChildStatelessWidget extends StatelessWidget
    implements SingleChildWidget {
  /// A widget around `child`, or around the one a [MultiProvider] gives
  /// it.
  const SingleChildStatelessWidget({super.key, this._child});

  final Widget? _child;

  /// What this widget shows around [child].
  @protected
  Widget buildWithChild(BuildContext context, Widget? child);

  @override
  Widget build(BuildContext context) =>
      buildWithChild(context, nestedChild(context, this) ?? _child);
}

/// A [StatefulWidget] built around a child, as a
/// [SingleChildStatelessWidget] is: its state is a [SingleChildState].
abstract class SingleChildStatefulWidget extends StatefulWidget
    implements SingleChildWidget {
  /// A widget around `child`, or around the one a [MultiProvider] gives
  /// it.
  const SingleChildStatefulWidget({super.key, this._child});

  final Widget? _child;
}

/// The state of a [SingleChildStatefulWidget]: [buildWithChild] gets the
/// child given to the widget, or the one a [MultiProvider] gives it.
abstract class SingleChildState<W extends SingleChildStatefulWidget>
    extends State<W> {
  /// What the widget shows around [child].
  @protected
  Widget buildWithChild(BuildContext context, Widget? child);

  @override
  Widget build(BuildContext context) =>
      buildWithChild(context, nestedChild(context, widget) ?? widget._child);
}

/// Shows what [builder] returns for `child`: a [SingleChildWidget] made of
/// a function.
///
/// ```dart
/// SingleChildBuilder(
///   builder: (context, child) =>
///       Padding(padding: const .all(1), child: child),
///   child: const Text('Inside'),
/// )
/// ```
final class SingleChildBuilder extends SingleChildStatelessWidget {
  /// Shows what [builder] returns for `child`.
  const SingleChildBuilder({required this.builder, super.key, super.child});

  /// Builds what this widget shows around the child.
  final TransitionBuilder builder;

  @override
  Widget buildWithChild(BuildContext context, Widget? child) =>
      builder(context, child);
}

/// The [providers] one inside another, the first outermost, around
/// [child]: `MultiProvider(providers: [Provider(create: …), …], child: …)`
/// for as many nested providers, each a [SingleChildWidget] without a child
/// of its own. A provider finds those before it in the list
/// (`context.read` in its `create`), and [child] finds them all.
///
/// With [builder], the child is what it returns for [child], built below
/// the providers. A MultiProvider is itself a [SingleChildWidget]: one may
/// be in the list of another.
///
/// ```dart
/// MultiProvider(
///   providers: [
///     Provider(create: (context) => const Settings()),
///     ChangeNotifierProvider(create: (context) => Cart()),
///   ],
///   child: app,
/// )
/// ```
final class MultiProvider extends SingleChildStatelessWidget {
  /// Nests [providers] around `child`, or around what [builder] returns.
  const MultiProvider({
    required this.providers,
    super.key,
    super.child,
    this.builder,
  });

  /// Each without a child.
  final List<SingleChildWidget> providers;

  /// Builds the child below the providers, from the one given.
  final TransitionBuilder? builder;

  @override
  Widget buildWithChild(BuildContext context, Widget? child) {
    final builder = this.builder;
    final inner = builder == null
        ? child ??
              (throw StateError('MultiProvider without a child or a builder'))
        : SingleChildBuilder(builder: builder, child: child);
    return providers.reversed.fold(
      inner,
      (inner, provider) => _Nested(injected: inner, child: provider),
    );
  }
}

/// Gives [child], a widget of a [MultiProvider]'s list, the one it is
/// built around: those that depend on it are rebuilt when it is another.
final class _Nested extends InheritedWidget {
  const _Nested({required this.injected, required super.child});

  final Widget injected;

  @override
  bool updateShouldNotify(_Nested oldWidget) =>
      !identical(injected, oldWidget.injected);
}

/// The child a [MultiProvider] gives [widget], whose element is [context],
/// when it is one of the list's, which depends on it; else null.
@internal
Widget? nestedChild(BuildContext context, Widget widget) {
  final element = context.getElementForInheritedWidgetOfExactType<_Nested>();
  if (element == null || !identical(element.widget.child, widget)) {
    return null;
  }
  return (context.dependOnInheritedElement(element) as _Nested).injected;
}
