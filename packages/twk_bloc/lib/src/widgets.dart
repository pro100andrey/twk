/// Widgets that follow the states of a bloc: [BlocBuilder], [BlocSelector],
/// [BlocListener], [MultiBlocListener] and [BlocConsumer].
library;

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:twk/provider.dart';
import 'package:twk/twk.dart';

import 'provider.dart';

// Examples can assume:
// import 'package:twk/twk.dart';
// final class CounterCubit extends Cubit<int> {
//   CounterCubit() : super(0);
// }
// typedef Login = ({String? user, String? error});
// final class LoginCubit extends Cubit<Login> {
//   LoginCubit() : super((user: null, error: null));
// }
// final class ThemeCubit extends Cubit<bool> {
//   ThemeCubit() : super(false);
// }
// void showError(BuildContext context, String error) {}
// late Widget app;

/// Builds a widget from [state].
typedef BlocWidgetBuilder<S> = Widget Function(BuildContext context, S state);

/// Does something about [state], once for each state it is called for.
typedef BlocWidgetListener<S> = void Function(BuildContext context, S state);

/// Whether a bloc going from [previous] to [current] is to be acted on.
typedef BlocCondition<S> = bool Function(S previous, S current);

/// Shows what [builder] returns for the state of a bloc, built again in the
/// next build scope for each state the bloc emits that [buildWhen] (by
/// default true) takes from the state before; the widgets around this one
/// are not.
///
/// The bloc is [bloc], else the [B] of the nearest [BlocProvider] above,
/// followed anew when the provider provides another.
///
/// The count of the `CounterCubit` provided above, built again for each
/// even count:
///
/// ```dart
/// BlocBuilder<CounterCubit, int>(
///   buildWhen: (previous, current) => current.isEven,
///   builder: (context, count) => Text('Count: $count'),
/// )
/// ```
///
/// See also:
///
///  * [BlocSelector], built again only when a part of the state changes.
///  * [BlocConsumer], which listens too.
final class BlocBuilder<B extends StateStreamable<S>, S>
    extends StatefulWidget {
  /// Shows what [builder] returns for the state of the bloc.
  const BlocBuilder({
    required this.builder,
    super.key,
    this.bloc,
    this.buildWhen,
  });

  /// The bloc to follow; null for the [B] of the nearest [BlocProvider]
  /// above.
  final B? bloc;

  /// Builds what this widget shows from the state of the bloc.
  // called by the state, whose S is the widget's own
  // ignore: unsafe_variance
  final BlocWidgetBuilder<S> builder;

  /// Takes the state the bloc emitted before and the one it emits now, and
  /// says whether to build again; null builds for every state.
  // ignore: unsafe_variance, as builder
  final BlocCondition<S>? buildWhen;

  @override
  State<BlocBuilder<B, S>> createState() => _BlocBuilderState<B, S>();
}

final class _BlocBuilderState<B extends StateStreamable<S>, S>
    extends State<BlocBuilder<B, S>>
    with _Following<B, S, BlocBuilder<B, S>> {
  late S _state;

  @override
  B? get _given => widget.bloc;

  @override
  void _followed(B bloc) => _state = bloc.state;

  @override
  void _emitted(S previous, S state) {
    if (widget.buildWhen?.call(previous, state) ?? true) {
      setState(() => _state = state);
    }
  }

  @override
  Widget build(BuildContext context) {
    _follow(context);
    return widget.builder(context, _state);
  }
}

/// Shows what [builder] returns for the part of a bloc's state [selector]
/// picks, built again when a state the bloc emits picks another (not
/// equal); the bloc is found as a [BlocBuilder]'s.
///
/// The user of a login state, built again only when the user changes, not
/// when the error does:
///
/// ```dart
/// BlocSelector<LoginCubit, Login, String?>(
///   selector: (state) => state.user,
///   builder: (context, user) => Text(user ?? 'Signed out'),
/// )
/// ```
final class BlocSelector<B extends StateStreamable<S>, S, T>
    extends StatefulWidget {
  /// Shows what [builder] returns for what [selector] picks of the state.
  const BlocSelector({
    required this.selector,
    required this.builder,
    super.key,
    this.bloc,
  });

  /// The bloc to follow; null for the [B] of the nearest [BlocProvider]
  /// above.
  final B? bloc;

  /// Picks what [builder] is given of a state of the bloc.
  // called by the state, whose S is the widget's own
  // ignore: unsafe_variance
  final T Function(S state) selector;

  /// Builds what this widget shows from what [selector] picked.
  // ignore: unsafe_variance, as selector
  final Widget Function(BuildContext context, T selected) builder;

  @override
  State<BlocSelector<B, S, T>> createState() => _BlocSelectorState<B, S, T>();
}

final class _BlocSelectorState<B extends StateStreamable<S>, S, T>
    extends State<BlocSelector<B, S, T>>
    with _Following<B, S, BlocSelector<B, S, T>> {
  late T _selected;

  @override
  B? get _given => widget.bloc;

  @override
  void _followed(B bloc) => _selected = widget.selector(bloc.state);

  @override
  void didUpdateWidget(BlocSelector<B, S, T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_bloc case final bloc? when widget.selector != oldWidget.selector) {
      _selected = widget.selector(bloc.state);
    }
  }

  @override
  void _emitted(S previous, S state) {
    final selected = widget.selector(state);
    if (selected != _selected) {
      setState(() => _selected = selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    _follow(context);
    return widget.builder(context, _selected);
  }
}

/// Calls [listener] for each state a bloc emits that [listenWhen] (by
/// default true) takes from the state before, once a state, and shows
/// `child`, which it does not rebuild; the bloc is found as a
/// [BlocBuilder]'s. For what is done once, as a notification or a route
/// pushed. `child` may be left out only in a [MultiBlocListener] or a
/// `MultiProvider`.
///
/// An error shown once, when the login fails, over an app that does not
/// rebuild for it:
///
/// ```dart
/// BlocListener<LoginCubit, Login>(
///   listenWhen: (previous, current) => current.error != previous.error,
///   listener: (context, state) => showError(context, state.error!),
///   child: app,
/// )
/// ```
final class BlocListener<B extends StateStreamable<S>, S>
    extends SingleChildStatefulWidget {
  /// Calls [listener] for the states of the bloc, and shows `child`.
  const BlocListener({
    required this.listener,
    super.key,
    this.bloc,
    this.listenWhen,
    super.child,
  });

  /// The bloc to follow; null for the [B] of the nearest [BlocProvider]
  /// above.
  final B? bloc;

  /// Does what a state calls for, once for each state it is called for.
  // called by the state, whose S is the widget's own
  // ignore: unsafe_variance
  final BlocWidgetListener<S> listener;

  /// Takes the state the bloc emitted before and the one it emits now, and
  /// says whether to call [listener]; null calls it for every state.
  // ignore: unsafe_variance, as listener
  final BlocCondition<S>? listenWhen;

  @override
  State<BlocListener<B, S>> createState() => _BlocListenerState<B, S>();
}

final class _BlocListenerState<B extends StateStreamable<S>, S>
    extends SingleChildState<BlocListener<B, S>>
    with _Following<B, S, BlocListener<B, S>> {
  @override
  B? get _given => widget.bloc;

  @override
  void _emitted(S previous, S state) {
    if (widget.listenWhen?.call(previous, state) ?? true) {
      widget.listener(context, state);
    }
  }

  @override
  Widget buildWithChild(BuildContext context, Widget? child) {
    _follow(context);
    return child ??
        (throw StateError(
          '${widget.runtimeType} without a child outside a '
          'MultiBlocListener or MultiProvider',
        ));
  }
}

/// The [listeners] one inside another, the first outermost, around
/// [child]: `MultiBlocListener(listeners: [BlocListener(listener: …), …],
/// child: …)` for as many nested [BlocListener]s.
///
/// ```dart
/// MultiBlocListener(
///   listeners: [
///     BlocListener<LoginCubit, Login>(
///       listener: (context, state) => showError(context, '${state.error}'),
///     ),
///     BlocListener<ThemeCubit, bool>(listener: (context, dark) {}),
///   ],
///   child: app,
/// )
/// ```
final class MultiBlocListener extends SingleChildStatelessWidget {
  /// Nests [listeners] around [child].
  const MultiBlocListener({
    required this.listeners,
    required this.child,
    super.key,
  }) : super(child: child);

  /// Each without a child.
  final List<SingleChildWidget> listeners;

  /// The widget inside the innermost listener.
  final Widget child;

  @override
  Widget buildWithChild(BuildContext context, Widget? child) =>
      MultiProvider(providers: listeners, child: child);
}

/// A [BlocListener] and a [BlocBuilder] of one bloc in one widget: for each
/// state the bloc emits, [listener] is called first if [listenWhen] takes
/// it, then the widget built again if [buildWhen] does.
///
/// A login form that shows the user and reports each error once:
///
/// ```dart
/// BlocConsumer<LoginCubit, Login>(
///   listenWhen: (previous, current) => current.error != null,
///   listener: (context, state) => showError(context, state.error!),
///   builder: (context, state) => Text(state.user ?? 'Signed out'),
/// )
/// ```
final class BlocConsumer<B extends StateStreamable<S>, S>
    extends StatefulWidget {
  /// Calls [listener] for the states of the bloc and shows what [builder]
  /// returns for them.
  const BlocConsumer({
    required this.listener,
    required this.builder,
    super.key,
    this.bloc,
    this.listenWhen,
    this.buildWhen,
  });

  /// The bloc to follow; null for the [B] of the nearest [BlocProvider]
  /// above.
  final B? bloc;

  /// Does what a state calls for, once for each state it is called for.
  // called by the state, whose S is the widget's own
  // ignore: unsafe_variance
  final BlocWidgetListener<S> listener;

  /// Builds what this widget shows from the state of the bloc.
  // ignore: unsafe_variance, as listener
  final BlocWidgetBuilder<S> builder;

  /// Whether to call [listener] for a state, given the one before; null
  /// calls it for every state.
  // ignore: unsafe_variance, as listener
  final BlocCondition<S>? listenWhen;

  /// Whether to build again for a state, given the one before; null builds
  /// for every state.
  // ignore: unsafe_variance, as listener
  final BlocCondition<S>? buildWhen;

  @override
  State<BlocConsumer<B, S>> createState() => _BlocConsumerState<B, S>();
}

final class _BlocConsumerState<B extends StateStreamable<S>, S>
    extends State<BlocConsumer<B, S>>
    with _Following<B, S, BlocConsumer<B, S>> {
  late S _state;

  @override
  B? get _given => widget.bloc;

  @override
  void _followed(B bloc) => _state = bloc.state;

  @override
  void _emitted(S previous, S state) {
    if (widget.listenWhen?.call(previous, state) ?? true) {
      widget.listener(context, state);
    }
    if (widget.buildWhen?.call(previous, state) ?? true) {
      setState(() => _state = state);
    }
  }

  @override
  Widget build(BuildContext context) {
    _follow(context);
    return widget.builder(context, _state);
  }
}

/// A state that follows the states of a bloc: the one its widget gives,
/// else the one provided above, which its build depends on; subscribed
/// from the first build, anew when the bloc is another, until it is
/// disposed.
base mixin _Following<B extends StateStreamable<S>, S, W extends StatefulWidget>
    on State<W> {
  B? _bloc;
  StreamSubscription<S>? _subscription;

  // the state the bloc emitted last, or had when it was followed
  late S _previous;

  /// The bloc the widget gives, if it gives one.
  B? get _given;

  /// Called when the bloc followed is [bloc], a new one.
  void _followed(B bloc) {}

  /// Called for each state the bloc emits.
  void _emitted(S previous, S state);

  /// Follows the bloc the widget gives, else the one provided above, which
  /// [context] depends on.
  void _follow(BuildContext context) {
    final bloc = _given ?? _provided(context);
    if (identical(bloc, _bloc)) {
      return;
    }
    _cancel();
    _bloc = bloc;
    _previous = bloc.state;
    _followed(bloc);
    _subscription = bloc.stream.listen((state) {
      if (!mounted) {
        return;
      }
      final previous = _previous;
      _previous = state;
      _emitted(previous, state);
    });
  }

  /// The [B] provided above, which [context] depends on: it is rebuilt
  /// when the provider provides another, not by the states of the bloc.
  B _provided(BuildContext context) {
    final bloc = findProvided<B>(context, listen: false);
    context.select<B, bool>((provided) => identical(provided, bloc));
    return bloc;
  }

  void _cancel() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }
}
