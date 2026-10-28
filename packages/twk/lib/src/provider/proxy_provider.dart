/// Providers of a value made from those of other providers, made anew when
/// they change: [ProxyProvider0], [ProxyProvider], [ProxyProvider2].
library;

import '../../twk.dart';

import 'inherited_provider.dart';

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

/// Makes a [ProxyProvider]'s value from `value`, that of the provider of a
/// [T] above, and `previous`, the value it made before (or `create` made),
/// null the first time.
typedef ProxyProviderBuilder<T, R> = R Function(
  BuildContext context,
  T value,
  R? previous,
);

/// Makes a [ProxyProvider2]'s value from those of the providers of a [T]
/// and of a [T2] above, as [ProxyProviderBuilder] does.
typedef ProxyProviderBuilder2<T, T2, R> = R Function(
  BuildContext context,
  T value,
  T2 value2,
  R? previous,
);

/// Provides the [R] `update` makes from the one it made before, and makes
/// it anew each time this widget is replaced or a provider `update` depends
/// on (`Provider.of(context)`, `context.watch`) changes: the widgets that
/// watch it are rebuilt when the new value is not `==` the one before (or
/// as `updateShouldNotify` says), which is then handed to `dispose`.
///
/// `create` makes a first value for `update` to start from; the first is
/// made when the value is first read unless `lazy` is false. The last is
/// handed to `dispose` when this widget leaves the tree. A value that is a
/// [Listenable] or a [Stream] fails an assert, as with [Provider].
///
/// ```dart
/// ProxyProvider0<String>(
///   update: (context, previous) => 'Hello, ${context.watch<Settings>().user}',
///   child: app,
/// )
/// ```
class ProxyProvider0<R> extends InheritedProvider<R> {
  /// Provides what `update` makes.
  ProxyProvider0({
    required R Function(BuildContext context, R? value) super.update,
    super.key,
    super.create,
    super.updateShouldNotify,
    super.dispose,
    super.lazy,
    super.builder,
    super.child,
  }) : super(
         debugCheckInvalidValueType: (value) =>
             Provider.debugCheckInvalidValueType?.call<R>(value),
       );
}

/// Provides the [R] `update` makes from the value of the provider of a [T]
/// above and the [R] it made before, made anew each time that value
/// changes, as [ProxyProvider0] provides it.
///
/// An `Api` made from the `Settings` provided above, made anew when they
/// change:
///
/// ```dart
/// MultiProvider(
///   providers: [
///     Provider(create: (context) => const Settings()),
///     ProxyProvider<Settings, Api>(
///       update: (context, settings, _) => Api(settings),
///     ),
///   ],
///   child: app,
/// )
/// ```
class ProxyProvider<T, R> extends ProxyProvider0<R> {
  /// Provides what `update` makes from the [T] above.
  ProxyProvider({
    required ProxyProviderBuilder<T, R> update,
    super.key,
    super.create,
    super.updateShouldNotify,
    super.dispose,
    super.lazy,
    super.builder,
    super.child,
  }) : super(
         update: (context, previous) =>
             update(context, Provider.of<T>(context), previous),
       );
}

/// Provides the [R] `update` makes from the values of the providers of a
/// [T] and of a [T2] above, as [ProxyProvider] provides it.
///
/// ```dart
/// ProxyProvider2<Settings, Cart, String>(
///   update: (context, settings, cart, _) =>
///       '${settings.user}: ${cart.items.length} items',
///   child: app,
/// )
/// ```
class ProxyProvider2<T, T2, R> extends ProxyProvider0<R> {
  /// Provides what `update` makes from the [T] and the [T2] above.
  ProxyProvider2({
    required ProxyProviderBuilder2<T, T2, R> update,
    super.key,
    super.create,
    super.updateShouldNotify,
    super.dispose,
    super.lazy,
    super.builder,
    super.child,
  }) : super(
         update: (context, previous) => update(
           context,
           Provider.of<T>(context),
           Provider.of<T2>(context),
           previous,
         ),
       );
}
