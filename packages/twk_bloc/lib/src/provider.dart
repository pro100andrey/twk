/// Objects provided to a subtree: blocs and cubits by [BlocProvider], other
/// objects, such as the repositories blocs take, by [RepositoryProvider];
/// the widgets below find them by their type with the `context.read`,
/// `context.watch` and `context.select` of `package:twk/provider.dart`, as
/// flutter_bloc's are found with provider's.
library;

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:twk/provider.dart';
import 'package:twk/twk.dart';

// Examples can assume:
// import 'package:twk/twk.dart';
// final class CounterCubit extends Cubit<int> {
//   CounterCubit() : super(0);
//   void increment() => emit(state + 1);
// }
// final class ThemeCubit extends Cubit<bool> {
//   ThemeCubit() : super(false);
// }
// final class Todos {
//   void close() {}
// }
// final class Settings {}
// late CounterCubit counter;
// late Widget app;

/// Provides the bloc or cubit [B] to the widgets below it, which find it by
/// its type: [BlocProvider.of], `context.read<B>()`, `context.watch<B>()`.
///
/// The bloc is the one `create` makes, the first time it is read unless
/// not [lazy], which this widget closes when it leaves the tree; or with
/// [BlocProvider.value] one made elsewhere, which it does not close, and
/// which a new widget may replace by another. `child` may be left out only
/// in a [MultiBlocProvider] or a `MultiProvider`. It is made of
/// twk's [InheritedProvider] (`package:twk/provider.dart`): the widgets that watch it are
/// rebuilt by each state the bloc emits and when a new widget provides
/// another bloc.
///
/// A cubit made for the app and closed with it, read by a key below:
///
/// ```dart
/// BlocProvider(
///   create: (context) => CounterCubit(),
///   child: Builder(
///     builder: (context) => KeyBindings({
///       'up': () => context.read<CounterCubit>().increment(),
///     }, child: Text('Count: ${context.watch<CounterCubit>().state}')),
///   ),
/// )
/// ```
///
/// A cubit made elsewhere, which the provider leaves open:
///
/// ```dart
/// BlocProvider.value(value: counter, child: app)
/// ```
///
/// See also:
///
///  * [MultiBlocProvider], for several without nesting them.
///  * [RepositoryProvider], for objects that are not blocs.
final class BlocProvider<B extends StateStreamableSource<Object?>>
    extends SingleChildStatelessWidget {
  /// Provides the bloc `create` makes, and closes it when this widget
  /// leaves the tree.
  const BlocProvider({
    required Create<B> this._create,
    super.key,
    super.child,
    this.lazy = true,
  }) : _value = null;

  /// Provides `value`, a bloc made and closed elsewhere.
  const BlocProvider.value({required B this._value, super.key, super.child})
    : _create = null,
      lazy = true;

  /// Whether the bloc is created only when it is first read; else when this
  /// widget is placed in the tree.
  final bool lazy;

  final Create<B>? _create;
  final B? _value;

  /// The bloc of the nearest [BlocProvider] of a [B] above [context],
  /// [context] rebuilt by each state the bloc emits when [listen]; a
  /// [StateError] if there is none.
  static B of<B extends StateStreamableSource<Object?>>(
    BuildContext context, {
    bool listen = false,
  }) => findProvided<B>(context, listen: listen);

  @override
  Widget buildWithChild(BuildContext context, Widget? child) {
    final inner =
        child ??
        (throw StateError(
          '$runtimeType without a child outside a MultiBlocProvider, '
          'MultiRepositoryProvider or MultiProvider',
        ));
    final value = _value;
    return value != null
        ? InheritedProvider<B>.value(
            value: value,
            startListening: _startListening,
            lazy: lazy,
            child: inner,
          )
        : InheritedProvider<B>(
            create: _create,
            dispose: (_, bloc) {
              if (bloc.close() case final Future<void> closing) {
                unawaited(closing);
              }
            },
            startListening: _startListening,
            lazy: lazy,
            child: inner,
          );
  }

  // the dependents are told of each state the bloc emits
  static VoidCallback _startListening(
    InheritedContext<Object?> element,
    StateStreamableSource<Object?> bloc,
  ) {
    final subscription = bloc.stream.listen(
      (_) => element.markNeedsNotifyDependents(),
    );
    return () => unawaited(subscription.cancel());
  }
}

/// Provides [T], an object other than a bloc, to the widgets below it,
/// which find it by its type: [RepositoryProvider.of], `context.read<T>()`.
///
/// The object is the one `create` makes, the first time it is read unless
/// not `lazy`, which this widget hands to `dispose` when it leaves the
/// tree; or with [RepositoryProvider.value] one made elsewhere. `child` may
/// be left out only in a [MultiRepositoryProvider] or a `MultiProvider`.
/// It is twk's [InheritedProvider] (`package:twk/provider.dart`), the
/// widgets that watch it rebuilt when a new widget provides another (not `==`).
///
/// A repository made for the app, closed when it leaves the tree, which a
/// bloc below takes:
///
/// ```dart
/// RepositoryProvider(
///   create: (context) => Todos(),
///   dispose: (todos) => todos.close(),
///   child: app,
/// )
/// ```
final class RepositoryProvider<T extends Object> extends InheritedProvider<T> {
  /// Provides the object `create` makes, handed to `dispose`, if given,
  /// when this widget leaves the tree.
  RepositoryProvider({
    required Create<T> super.create,
    void Function(T value)? dispose,
    super.key,
    super.child,
    super.lazy,
  }) : super(dispose: dispose == null ? null : (_, value) => dispose(value));

  /// Provides `value`, an object made and disposed of elsewhere.
  RepositoryProvider.value({
    required super.value,
    super.key,
    super.child,
  }) : super.value();

  /// The object of the nearest [RepositoryProvider] of a [T] above
  /// [context], [context] rebuilt when it provides another when [listen];
  /// a [StateError] if there is none.
  static T of<T extends Object>(BuildContext context, {bool listen = false}) =>
      findProvided<T>(context, listen: listen);
}

/// The [providers] one inside another, the first outermost, around
/// [child]: `MultiBlocProvider(providers: [BlocProvider(create: …), …],
/// child: …)` for as many nested [BlocProvider]s. It is a `MultiProvider`
/// of `package:twk/provider.dart`, whose providers may be in the list too.
///
/// ```dart
/// MultiBlocProvider(
///   providers: [
///     BlocProvider(create: (context) => CounterCubit()),
///     BlocProvider(create: (context) => ThemeCubit()),
///   ],
///   child: app,
/// )
/// ```
final class MultiBlocProvider extends SingleChildStatelessWidget {
  /// Nests [providers] around [child].
  const MultiBlocProvider({
    required this.providers,
    required this.child,
    super.key,
  }) : super(child: child);

  /// Each without a child.
  final List<SingleChildWidget> providers;

  /// The widget inside the innermost provider.
  final Widget child;

  @override
  Widget buildWithChild(BuildContext context, Widget? child) =>
      MultiProvider(providers: providers, child: child);
}

/// The [providers] one inside another, the first outermost, around
/// [child], as [MultiBlocProvider] nests [BlocProvider]s.
///
/// ```dart
/// MultiRepositoryProvider(
///   providers: [
///     RepositoryProvider(create: (context) => Todos()),
///     RepositoryProvider(create: (context) => Settings()),
///   ],
///   child: app,
/// )
/// ```
final class MultiRepositoryProvider extends SingleChildStatelessWidget {
  /// Nests [providers] around [child].
  const MultiRepositoryProvider({
    required this.providers,
    required this.child,
    super.key,
  }) : super(child: child);

  /// Each without a child.
  final List<SingleChildWidget> providers;

  /// The widget inside the innermost provider.
  final Widget child;

  @override
  Widget buildWithChild(BuildContext context, Widget? child) =>
      MultiProvider(providers: providers, child: child);
}

/// The [T] of the nearest provider of one above [context], [context]
/// depending on it when [listen]: `Provider.of`, but a [StateError] naming
/// the bloc's providers when there is none. What [BlocProvider.of],
/// [RepositoryProvider.of] and the widgets of this package that follow
/// the bloc above them find it with.
T findProvided<T>(BuildContext context, {required bool listen}) {
  try {
    return Provider.of<T>(context, listen: listen);
  } on ProviderNotFoundException catch (e) {
    if (e.valueType != T) {
      rethrow;
    }
    throw StateError(
      'no BlocProvider<$T> or RepositoryProvider<$T> above '
      '${context.widget.runtimeType}',
    );
  }
}
