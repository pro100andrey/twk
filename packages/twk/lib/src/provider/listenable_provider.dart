/// Providers of twk's listenables, whose changes rebuild the widgets that
/// watch them: [ListenableProvider], [ChangeNotifierProvider],
/// [ValueListenableProvider].
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

/// Provides a [Listenable] [T], as [Provider] provides a value, and tells
/// the widgets that depend on it each time it notifies its listeners: it
/// listens from the first time the listenable is read until it is replaced
/// or this widget leaves the tree.
///
/// The listenable is the one `create` makes, the first time it is read
/// unless `lazy` is false, handed to `dispose` when this widget leaves the
/// tree; or with [ListenableProvider.value] one made elsewhere, which a new
/// widget may replace by another.
///
/// ```dart
/// ListenableProvider(
///   create: (context) => ScrollController(),
///   dispose: (context, controller) => controller.dispose(),
///   child: app,
/// )
/// ```
class ListenableProvider<T extends Listenable?> extends InheritedProvider<T> {
  /// Provides the listenable `create` makes, handed to `dispose`, if
  /// given, when this widget leaves the tree.
  ListenableProvider({
    required Create<T> super.create,
    super.key,
    super.dispose,
    super.lazy,
    super.builder,
    super.child,
  }) : super(startListening: _startListening);

  /// Provides `value`, a listenable made and disposed of elsewhere.
  ListenableProvider.value({
    required super.value,
    super.key,
    super.updateShouldNotify,
    super.builder,
    super.child,
  }) : super.value(startListening: _startListening);

  static VoidCallback _startListening(
    InheritedContext<Listenable?> element,
    Listenable? value,
  ) {
    value?.addListener(element.markNeedsNotifyDependents);
    return () => value?.removeListener(element.markNeedsNotifyDependents);
  }
}

/// Provides a [ChangeNotifier] [T], as [ListenableProvider] provides a
/// listenable: the notifier `create` makes is disposed of when this widget
/// leaves the tree; one given to [ChangeNotifierProvider.value] is not.
///
/// A cart the app's widgets add to and show, made with the app and
/// disposed of with it:
///
/// ```dart
/// ChangeNotifierProvider(
///   create: (context) => Cart(),
///   child: Builder(
///     builder: (context) => KeyBindings({
///       'a': () => context.read<Cart>().add('tea'),
///     }, child: Text('${context.watch<Cart>().items.length} items')),
///   ),
/// )
/// ```
class ChangeNotifierProvider<T extends ChangeNotifier?>
    extends ListenableProvider<T> {
  /// Provides the notifier `create` makes, disposed of when this widget
  /// leaves the tree.
  ChangeNotifierProvider({
    required super.create,
    super.key,
    super.lazy,
    super.builder,
    super.child,
  }) : super(dispose: _dispose);

  /// Provides `value`, a notifier made and disposed of elsewhere.
  ChangeNotifierProvider.value({
    required super.value,
    super.key,
    super.builder,
    super.child,
  }) : super.value();

  static void _dispose(BuildContext context, ChangeNotifier? notifier) =>
      notifier?.dispose();
}

/// Provides the value of a [ValueListenable], found by its type [T] (not
/// the listenable's): the widgets that watch it are rebuilt each time the
/// listenable changes it to one that is not `==` (or as
/// [updateShouldNotify] says).
///
/// The count of unread messages, an `int` below, kept by a notifier
/// elsewhere:
///
/// ```dart
/// ValueListenableProvider.value(
///   value: unread,
///   child: Builder(
///     builder: (context) => Text('${context.watch<int>()} unread'),
///   ),
/// )
/// ```
final class ValueListenableProvider<T> extends SingleChildStatelessWidget {
  /// Provides the value of `value`, a listenable made elsewhere.
  const ValueListenableProvider.value({
    required ValueListenable<T> value,
    super.key,
    this.updateShouldNotify,
    super.child,
  }) : listenable = value;

  /// What gives the value.
  final ValueListenable<T> listenable;

  /// Whether the widgets that watch the value are told it went from one
  /// value to the next; null tells them when the two are not `==`.
  // called with the listenable's values, whose T is this widget's own
  // ignore: unsafe_variance
  final UpdateShouldNotify<T>? updateShouldNotify;

  @override
  Widget buildWithChild(BuildContext context, Widget? child) =>
      ValueListenableBuilder<T>(
        valueListenable: listenable,
        builder: (context, value, _) => Provider<T>.value(
          value: value,
          updateShouldNotify: updateShouldNotify,
          child: child,
        ),
      );
}
