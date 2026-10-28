/// Values provided to a subtree, found by their type: [InheritedProvider]
/// and [Provider] provide them, `context.read`, `context.watch` and
/// `context.select` ([ReadContext], [WatchContext], [SelectContext]) find
/// them, as package:provider does on Flutter's widgets.
///
/// A provider is an inherited widget of twk whose element keeps the value:
/// it creates it when it is first read (unless not lazy), tells the
/// widgets that depend on it when it changes, and disposes of it when it
/// leaves the tree. Each dependent is told of all changes, or only of
/// those that change what its last build selected.
library;

import 'package:meta/meta.dart';

import '../../twk.dart';

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

/// Makes a provider's value: called with the provider's context, in which
/// it may read other providers (`context.read`) but not depend on them.
typedef Create<T> = T Function(BuildContext context);

/// Disposes of a value a provider created, when the provider leaves the
/// tree.
typedef Dispose<T> = void Function(BuildContext context, T value);

/// Whether the widgets that depend on a provider are told that its value
/// went from [previous] to [current].
typedef UpdateShouldNotify<T> = bool Function(T previous, T current);

/// Starts listening to [value], which [element] provides, for the changes
/// to tell the dependents of ([InheritedContext.markNeedsNotifyDependents]);
/// returns what stops it.
typedef StartListening<T> = VoidCallback Function(
  InheritedContext<T?> element,
  T value,
);

/// Starts listening to [controller] for the values [element] provides,
/// each handed to [setState], the first before it returns; [value] is the
/// last one, null before the first. Returns what stops it.
typedef DeferredStartListening<T, R> = VoidCallback Function(
  InheritedContext<R?> element,
  void Function(R value) setState,
  T controller,
  R? value,
);

/// The element of a provider, as its `startListening` gets it.
abstract interface class InheritedContext<T> implements BuildContext {
  /// The value, created when it is first read.
  T get value;

  /// Whether the value was created.
  bool get hasValue;

  /// Tells the widgets that depend on the provider, in the next build, that
  /// its value changed.
  void markNeedsNotifyDependents();
}

/// Provides a [T] to the widgets below it, which find it by its type:
/// `context.read<T>()`, `context.watch<T>()`, `context.select`,
/// [Provider.of], a `Consumer`. What the other providers of this package
/// are made of.
///
/// The value is the one `create` makes, the first time it is read unless
/// [lazy] is false, then handed to `dispose` when this widget leaves the
/// tree; `update` makes it anew, from the one before, each time this widget
/// is replaced or a provider `update` depends on changes
/// (`Provider.of(context)`), the dependents told when the new one is not
/// `==` the old (or as `updateShouldNotify` says), and the old one
/// disposed. With [InheritedProvider.value] it is one made elsewhere,
/// neither created nor disposed: a new widget with a value that is not
/// `==` (or as `updateShouldNotify` says) tells the dependents.
///
/// `startListening` is called with the value once it is read, for a value
/// whose changes are to rebuild the dependents (a listenable, a stream),
/// and what it returns when the value is replaced or the provider leaves
/// the tree.
///
/// With [builder], the child is what it returns for `child`, built below
/// this provider: the context it gets finds the value. Outside a
/// [MultiProvider], one of `child` and [builder] is given.
///
/// A provider of a value that tells its dependents when a key changes it,
/// as the other providers of this package are made:
///
/// ```dart
/// InheritedProvider<ValueNotifier<int>>(
///   create: (context) => ValueNotifier(0),
///   startListening: (element, notifier) {
///     notifier.addListener(element.markNeedsNotifyDependents);
///     return () => notifier.removeListener(element.markNeedsNotifyDependents);
///   },
///   dispose: (context, notifier) => notifier.dispose(),
///   child: app,
/// )
/// ```
class InheritedProvider<T> extends SingleChildStatelessWidget {
  /// Provides the value `create` makes, or `update` makes anew; one of
  /// them is given.
  InheritedProvider({
    super.key,
    Create<T>? create,
    T Function(BuildContext context, T? value)? update,
    UpdateShouldNotify<T>? updateShouldNotify,
    void Function(T value)? debugCheckInvalidValueType,
    StartListening<T>? startListening,
    Dispose<T>? dispose,
    this.builder,
    bool? lazy,
    super.child,
  }) : assert(
         create != null || update != null,
         'an InheritedProvider needs a create or an update',
       ),
       lazy = lazy ?? true,
       _delegate = _CreateDelegate(
         create: create,
         update: update,
         updateShouldNotify: updateShouldNotify,
         debugCheckInvalidValueType: debugCheckInvalidValueType,
         startListening: startListening,
         dispose: dispose,
       );

  /// Provides `value`, made and disposed of elsewhere.
  InheritedProvider.value({
    required T value,
    super.key,
    UpdateShouldNotify<T>? updateShouldNotify,
    StartListening<T>? startListening,
    bool? lazy,
    this.builder,
    super.child,
  }) : lazy = lazy ?? true,
       _delegate = _ValueDelegate(
         value: value,
         updateShouldNotify: updateShouldNotify,
         startListening: startListening,
       );

  const InheritedProvider._({
    required this._delegate,
    required this.lazy,
    super.key,
    this.builder,
    super.child,
  });

  final _Delegate<T> _delegate;

  /// Whether the value is made only when it is first read; else when this
  /// widget is placed in the tree.
  final bool lazy;

  /// Builds the child below this provider, from the one given.
  final TransitionBuilder? builder;

  @override
  Widget buildWithChild(BuildContext context, Widget? child) {
    final builder = this.builder;
    return _Scope<T?>(
      owner: this,
      child: builder != null
          ? SingleChildBuilder(builder: builder, child: child)
          : child ??
                (throw StateError(
                  '$runtimeType outside a MultiProvider without a child or '
                  'a builder',
                )),
    );
  }
}

/// Provides a [T] whose values a controller [C] gives over time, as a
/// future or a stream gives them: `FutureProvider` and `StreamProvider`
/// are made of it.
///
/// The controller is the one `create` makes, the first time the value is
/// read unless [lazy] is false, and handed to `dispose` when this widget
/// leaves the tree; or with [DeferredInheritedProvider.value] one made
/// elsewhere, which a new widget may replace by another. `startListening`
/// is called with it when the value is first read and hands its values to
/// `setState`, the first before it returns; each value after it that is
/// not `==` the one before (or as `updateShouldNotify` says) tells the
/// dependents.
///
/// The latest of a stream's lines, `''` before the first, as a
/// `StreamProvider` provides them:
///
/// ```dart
/// DeferredInheritedProvider<Stream<String>, String>(
///   create: (context) => statusLines,
///   startListening: (element, setState, stream, value) {
///     setState(value ?? '');
///     return stream.listen(setState).cancel;
///   },
///   child: app,
/// )
/// ```
class DeferredInheritedProvider<C, T> extends InheritedProvider<T> {
  /// Provides the values of the controller `create` makes.
  DeferredInheritedProvider({
    required Create<C> create,
    required DeferredStartListening<C, T> startListening,
    super.key,
    Dispose<C>? dispose,
    UpdateShouldNotify<T>? updateShouldNotify,
    bool? lazy,
    super.builder,
    super.child,
  }) : super._(
         lazy: lazy ?? true,
         delegate: _CreateDeferredDelegate(
           create: create,
           dispose: dispose,
           updateShouldNotify: updateShouldNotify,
           startListening: startListening,
         ),
       );

  /// Provides the values of `value`, a controller made elsewhere.
  DeferredInheritedProvider.value({
    required C value,
    required DeferredStartListening<C, T> startListening,
    super.key,
    UpdateShouldNotify<T>? updateShouldNotify,
    bool? lazy,
    super.builder,
    super.child,
  }) : super._(
         lazy: lazy ?? true,
         delegate: _ValueDeferredDelegate(
           value: value,
           updateShouldNotify: updateShouldNotify,
           startListening: startListening,
         ),
       );
}

/// Provides a [T] to the widgets below it, which find it by its type:
/// `context.read<T>()`, `context.watch<T>()`, `context.select`, [of], a
/// `Consumer`.
///
/// The value is the one `create` makes, the first time it is read unless
/// `lazy` is false, then handed to `dispose` when this widget leaves the
/// tree; with [Provider.value] one made elsewhere, which it does not
/// dispose of, and which a new widget may replace by another: the widgets
/// that watch it are rebuilt when it is not `==` the one before (or as
/// `updateShouldNotify` says).
///
/// A value whose changes are to rebuild the widgets below is provided by a
/// `ChangeNotifierProvider`, a `ListenableProvider` or a `StreamProvider`:
/// a [Provider] of a [Listenable] or a [Stream] is an error while asserts
/// are on ([debugCheckInvalidValueType]).
///
/// Settings made once for the app, which a widget below shows:
///
/// ```dart
/// Provider(
///   create: (context) => const Settings(user: 'ada'),
///   child: Builder(
///     builder: (context) =>
///         Text('Signed in as ${context.watch<Settings>().user}'),
///   ),
/// )
/// ```
///
/// See also:
///
///  * [MultiProvider], for several without nesting them.
///  * `ChangeNotifierProvider`, for a value whose changes rebuild the widgets
///    below.
class Provider<T> extends InheritedProvider<T> {
  /// Provides the value `create` makes, handed to `dispose`, if given,
  /// when this widget leaves the tree.
  Provider({
    required Create<T> super.create,
    super.key,
    super.dispose,
    super.lazy,
    super.builder,
    super.child,
  }) : super(debugCheckInvalidValueType: _checkValue<T>);

  /// Provides `value`, made and disposed of elsewhere.
  Provider.value({
    required super.value,
    super.key,
    super.updateShouldNotify,
    super.builder,
    super.child,
  }) : assert(_checkValue<T>(value), 'checked by debugCheckInvalidValueType'),
       super.value();

  /// Checks the value of each [Provider], while asserts are on: by default
  /// a [Listenable] or a [Stream] is a [StateError], since its changes would
  /// rebuild nothing. Null checks none.
  static void Function<V>(V value)? debugCheckInvalidValueType = <V>(value) {
    if (value is Listenable || value is Stream<Object?>) {
      throw StateError(
        'Tried to use Provider with a subtype of Listenable/Stream ($V), '
        'which rebuilds nothing when it changes: provide it with a '
        'ListenableProvider, a ChangeNotifierProvider or a '
        'StreamProvider, or set Provider.debugCheckInvalidValueType to '
        'null',
      );
    }
  };

  static bool _checkValue<T>(T value) {
    debugCheckInvalidValueType?.call<T>(value);
    return true;
  }

  /// The value of the nearest provider of a [T] above [context]; [context]
  /// depends on it when [listen]: rebuilt each time it changes. A
  /// [ProviderNotFoundException] when there is none, unless [T] is nullable:
  /// then null.
  static T of<T>(BuildContext context, {bool listen = true}) {
    final scope = _scopeOf<T>(context);
    if (listen && scope != null) {
      context.dependOnInheritedElement(scope);
      scope._dependOnAll(context);
    }
    final value = scope?.value;
    if (value is! T) {
      throw ProviderNullException(T, context.widget.runtimeType);
    }
    return value;
  }
}

/// No provider of the type a context looked for was found above it.
final class ProviderNotFoundException implements Exception {
  /// No provider of [valueType] above a [widgetType].
  ProviderNotFoundException(this.valueType, this.widgetType);

  /// The type looked for.
  final Type valueType;

  /// The type of the widget whose context looked for it.
  final Type widgetType;

  @override
  String toString() =>
      '''
Error: Could not find the correct Provider<$valueType> above this $widgetType Widget

The context used is not below a provider of $valueType: one the widget
builds itself is not above its own context (use the provider's builder),
and one in another route is not above this one.''';
}

/// A provider of a nullable type gave null where a non-nullable one was
/// asked for: `Provider<int?>` read as an `int`.
final class ProviderNullException implements Exception {
  /// A [widgetType] asked for a [valueType] and got null.
  ProviderNullException(this.valueType, this.widgetType);

  /// The type asked for.
  final Type valueType;

  /// The type of the widget whose context asked for it.
  final Type widgetType;

  @override
  String toString() =>
      'Error: The widget $widgetType tried to read Provider<$valueType> but '
      'the matching provider returned null: make it Provider<$valueType?>';
}

/// Finds what a provider above provides.
///
/// ```dart
/// Builder(
///   builder: (context) =>
///       Button('Buy', onPressed: () => context.read<Cart>().add('tea')),
/// )
/// ```
extension ReadContext on BuildContext {
  /// The [T] of the nearest provider of one above this context, without
  /// depending on it: for callbacks, as `context.read<Counter>().increment()`
  /// on a key, and for [State.initState]. A [ProviderNotFoundException] if
  /// there is none, unless [T] is nullable: then null.
  ///
  /// As with package:provider, a build had better [WatchContext.watch]:
  /// what it read is not rebuilt when it changes.
  T read<T>() => Provider.of<T>(this, listen: false);
}

/// Finds what a provider above provides, and depends on it.
///
/// ```dart
/// Builder(
///   builder: (context) => Text('${context.watch<Cart>().items.length} items'),
/// )
/// ```
extension WatchContext on BuildContext {
  /// The [T] of the nearest provider of one above this context, which is
  /// rebuilt each time it changes, as long as its builds watch it. A
  /// [ProviderNotFoundException] if there is none, unless [T] is nullable:
  /// then null.
  T watch<T>() => Provider.of<T>(this);
}

/// Depends on a part of what a provider above provides.
///
/// A widget built again when the theme changes, not when the user does:
///
/// ```dart
/// Builder(
///   builder: (context) {
///     final dark = context.select((Settings s) => s.dark);
///     return Text(dark ? 'Dark' : 'Light');
///   },
/// )
/// ```
extension SelectContext on BuildContext {
  /// What [selector] picks from the [T] of the nearest provider of one
  /// above this context, which is rebuilt only when a change of the value
  /// makes [selector] pick something else: not `==`, lists, sets, maps and
  /// other iterables compared element by element. A build may select any
  /// number of parts, of one value or of several; each build selects anew.
  /// A [ProviderNotFoundException] if there is none, unless [T] is
  /// nullable.
  ///
  /// [selector] picks with the value alone: reading, watching or selecting
  /// another provider in it is an error while asserts are on.
  R select<T, R>(R Function(T value) selector) {
    final scope = _scopeOf<T>(this);
    final type = widget.runtimeType;
    final value = scope?.value;
    if (value is! T) {
      throw ProviderNullException(T, type);
    }
    final selected = _selecting(() => selector(value));
    if (scope != null) {
      dependOnInheritedElement(scope);
      scope._dependOnPart(this, (current) {
        if (current is! T) {
          throw ProviderNullException(T, type);
        }
        return !deepEquals(selector(current), selected);
      });
    }
    return selected;
  }
}

// a selector of SelectContext.select runs
var _inSelector = false;

R _selecting<R>(R Function() selector) {
  final outer = _inSelector;
  _inSelector = true;
  try {
    return selector();
  } finally {
    _inSelector = outer;
  }
}

/// The element of the nearest provider of a [T] above [context] (or of a
/// `T?`, or of the `T` of a `T?`); a [ProviderNotFoundException] if there
/// is none, unless [T] is nullable.
_ScopeElement<T?>? _scopeOf<T>(BuildContext context) {
  assert(
    !_inSelector,
    'Cannot call context.read/watch/select inside the callback of a '
    'context.select',
  );
  assert(
    T != dynamic,
    'Tried to call Provider.of<dynamic>, which is likely a mistake: a '
    'variable that can be anything is an Object',
  );
  final element =
      context.getElementForInheritedWidgetOfExactType<_Scope<T?>>()
          as _ScopeElement<T?>?;
  if (element == null && null is! T) {
    throw ProviderNotFoundException(T, context.widget.runtimeType);
  }
  return element;
}

/// Whether [a] and [b] are equal, lists, sets, maps and other iterables
/// element by element, as package:collection's DeepCollectionEquality has
/// them: how what is selected is compared.
@internal
bool deepEquals(Object? a, Object? b) {
  if (identical(a, b)) {
    return true;
  }
  return switch ((a, b)) {
    (final Set<Object?> a, final Set<Object?> b) =>
      a.length == b.length && a.every((x) => b.any((y) => deepEquals(x, y))),
    (final Map<Object?, Object?> a, final Map<Object?, Object?> b) =>
      a.length == b.length &&
          a.keys.every(
            (k) => b.containsKey(k) && deepEquals(a[k], b[k]),
          ),
    (final Iterable<Object?> a, final Iterable<Object?> b) =>
      a.length == b.length && _allEqual(a.iterator, b.iterator),
    _ => a == b,
  };
}

bool _allEqual(Iterator<Object?> a, Iterator<Object?> b) {
  while (a.moveNext() && b.moveNext()) {
    if (!deepEquals(a.current, b.current)) {
      return false;
    }
  }
  return true;
}

/// The inherited widget an [InheritedProvider] builds, found by the type
/// it provides (`_Scope<T?>` for a `T`), whose element keeps the value.
final class _Scope<T> extends InheritedWidget {
  const _Scope({required this.owner, required super.child});

  final InheritedProvider<T> owner;

  // the element tells the dependents itself
  @override
  bool updateShouldNotify(_Scope<T> oldWidget) => false;

  @override
  _ScopeElement<T> createElement() => _ScopeElement<T>(this);
}

/// What a dependent of a provider depends on: the whole value, or the
/// parts its last build selected.
final class _Dependency<T> {
  _Dependency(this.build);

  /// It watched the whole value once, and stays told of every change, as
  /// with package:provider.
  var all = false;

  /// The rebuild count of the build that selected [parts].
  int build;

  /// Each says whether the value changed what it selected.
  final parts = <bool Function(T value)>[];
}

/// The element of a provider: it keeps the value, tells the widgets that
/// depend on it of its changes, and disposes of it when it leaves the tree.
///
/// twk's inherited elements keep no data per dependent (Flutter's
/// `InheritedModel` aspects), so this one keeps it: for each dependent,
/// whether it watched the whole value, else the parts it selected, which
/// [notifyDependent] checks against the value before it rebuilds it. A
/// dependent's parts are those of its last build, told apart by the
/// owner's rebuild count, which each build of an element moves on.
///
/// Its own lookups start at its parent, so that `create` and `update`,
/// which get this element as their context, find the providers above,
/// one of the type it provides too. A dependency `update` made stays
/// through the builds of this element that do not call it, as in Flutter,
/// where twk would drop it.
final class _ScopeElement<T> extends InheritedElement
    implements InheritedContext<T> {
  _ScopeElement(_Scope<T> super.widget);

  late final _DelegateState<T, _Delegate<T>> _state =
      widget.owner._delegate.createState()..element = this;

  final _dependencies = Expando<_Dependency<T>>();

  // the inherited elements update depended on, kept across builds
  final _kept = <InheritedElement>{};

  // the next build tells the dependents
  var _shouldNotify = false;

  // false while startListening runs: markNeedsNotifyDependents does nothing
  var _notifying = true;

  // the new widget tells the dependents
  var _updatedShouldNotify = false;

  // this build is for a new widget or a changed dependency: update runs
  var _external = false;

  // create runs: depending is refused
  var _locked = false;

  @override
  _Scope<T> get widget => super.widget as _Scope<T>;

  @override
  T get value => _state.value;

  @override
  bool get hasValue => _state.hasValue;

  @override
  void markNeedsNotifyDependents() {
    if (!_notifying) {
      return;
    }
    markNeedsBuild();
    _shouldNotify = true;
  }

  /// Runs [create] with depending refused.
  R _create<R>(R Function() create) {
    final outer = _locked;
    _locked = true;
    try {
      return create();
    } finally {
      _locked = outer;
    }
  }

  /// Runs [listen] with [markNeedsNotifyDependents] doing nothing.
  R _quietly<R>(R Function() listen) {
    _notifying = false;
    try {
      return listen();
    } finally {
      _notifying = true;
    }
  }

  void _dependOnAll(BuildContext dependent) {
    (_dependencies[dependent] ??= _Dependency(_buildOf(dependent))).all = true;
  }

  void _dependOnPart(BuildContext dependent, bool Function(T value) changed) {
    final build = _buildOf(dependent);
    final dependency = _dependencies[dependent] ??= _Dependency(build);
    if (dependency.build != build) {
      dependency
        ..build = build
        ..parts.clear();
    }
    dependency.parts.add(changed);
  }

  static int _buildOf(BuildContext dependent) => dependent.owner?.rebuilds ?? 0;

  @override
  void notifyDependent(_Scope<T> oldWidget, Element dependent) {
    final dependency = _dependencies[dependent];
    if (dependency != null && !dependency.all) {
      // it is to be rebuilt anyway, and selects anew then
      if (dependent.dirty) {
        return;
      }
      final current = value;
      if (!_selecting(
        () => dependency.parts.any((changed) => changed(current)),
      )) {
        return;
      }
    }
    dependent.didChangeDependencies();
  }

  @override
  InheritedElement?
  getElementForInheritedWidgetOfExactType<W extends InheritedWidget>() {
    InheritedElement? found;
    visitAncestorElements((parent) {
      found = parent.widget.runtimeType == W
          ? parent as InheritedElement
          : parent.getElementForInheritedWidgetOfExactType<W>();
      return false;
    });
    return found;
  }

  @override
  W? getInheritedWidgetOfExactType<W extends InheritedWidget>() =>
      getElementForInheritedWidgetOfExactType<W>()?.widget as W?;

  @override
  W? dependOnInheritedWidgetOfExactType<W extends InheritedWidget>() {
    final ancestor = getElementForInheritedWidgetOfExactType<W>();
    return ancestor == null ? null : dependOnInheritedElement(ancestor) as W;
  }

  @override
  InheritedWidget dependOnInheritedElement(InheritedElement ancestor) {
    assert(
      !_locked,
      'Tried to listen to an InheritedWidget in a life-cycle that will never '
      'be called again: the create of ${widget.owner.runtimeType} depends on '
      '${ancestor.widget.runtimeType}. Read it with listen: false '
      '(context.read), or provide with a ProxyProvider, whose update runs '
      'again when what it depends on changes',
    );
    _kept.add(ancestor);
    return super.dependOnInheritedElement(ancestor);
  }

  @override
  void update(_Scope<T> newWidget) {
    assert(() {
      if (widget.owner._delegate.runtimeType !=
          newWidget.owner._delegate.runtimeType) {
        throw StateError(
          'Rebuilt ${widget.owner.runtimeType} using a different '
          'constructor, which is unsupported: give each constructor a key '
          'of its own',
        );
      }
      return true;
    }(), 'the constructor of a provider stays');
    _external = true;
    _updatedShouldNotify = _state.willUpdateDelegate(newWidget.owner._delegate);
    super.update(newWidget);
    _updatedShouldNotify = false;
  }

  @override
  void updated(_Scope<T> oldWidget) {
    super.updated(oldWidget);
    if (_updatedShouldNotify) {
      notifyClients(oldWidget);
    }
  }

  @override
  void didChangeDependencies() {
    _external = true;
    super.didChangeDependencies();
  }

  @override
  Widget build() {
    for (final ancestor in _kept) {
      super.dependOnInheritedElement(ancestor);
    }
    if (!widget.owner.lazy) {
      _state.value;
    }
    _state.build(external: _external);
    _external = false;
    if (_shouldNotify) {
      _shouldNotify = false;
      notifyClients(widget);
    }
    return super.build();
  }

  @override
  void deactivate() {
    _kept.clear();
    super.deactivate();
  }

  @override
  void unmount() {
    _state.dispose();
    super.unmount();
  }
}

/// How a provider makes its value: what the widget holds, a new one each
/// time it is replaced.
@immutable
abstract class _Delegate<T> {
  const _Delegate();

  _DelegateState<T, _Delegate<T>> createState();
}

/// The value of a provider, kept by its element across the delegates of
/// the widgets that replace one another.
abstract class _DelegateState<T, D extends _Delegate<T>> {
  _ScopeElement<T?>? element;

  T get value;

  bool get hasValue;

  D get delegate => element!.widget.owner._delegate as D;

  /// Whether the dependents are to be told now that [newDelegate] replaces
  /// [delegate].
  bool willUpdateDelegate(D newDelegate) => false;

  void dispose() {}

  /// Called by each build of the element; [external] when the widget was
  /// replaced or a dependency changed.
  void build({required bool external}) {}
}

final class _CreateDelegate<T> extends _Delegate<T> {
  const _CreateDelegate({
    required this.create,
    required this.update,
    required this.updateShouldNotify,
    required this.debugCheckInvalidValueType,
    required this.startListening,
    required this.dispose,
  });

  final Create<T>? create;

  // called by the state, whose T is this delegate's own
  // ignore: unsafe_variance
  final T Function(BuildContext context, T? value)? update;

  // ignore: unsafe_variance, called by the state, whose T is this one's
  final UpdateShouldNotify<T>? updateShouldNotify;

  // ignore: unsafe_variance, called by the state, whose T is this one's
  final void Function(T value)? debugCheckInvalidValueType;

  // ignore: unsafe_variance, called by the state, whose T is this one's
  final StartListening<T>? startListening;

  // ignore: unsafe_variance, called by the state, whose T is this one's
  final Dispose<T>? dispose;

  @override
  _CreateState<T> createState() => _CreateState<T>();
}

final class _CreateState<T> extends _DelegateState<T, _CreateDelegate<T>> {
  VoidCallback? _stopListening;
  var _created = false;
  T? _value;
  Object? _error;
  _CreateDelegate<T>? _previous;

  @override
  bool get hasValue => _created;

  @override
  T get value {
    final element = this.element!;
    if (_created && _error != null) {
      throw StateError(
        'Tried to read a provider that threw during the creation of its '
        'value, a $T: $_error',
      );
    }
    if (!_created) {
      _created = true;
      final create = delegate.create;
      if (create != null) {
        try {
          _value = element._create(() => create(element));
        } on Object catch (error) {
          _error = error;
          rethrow;
        }
        _check(_value as T);
      }
      final update = delegate.update;
      if (update != null) {
        _value = update(element, _value);
        _check(_value as T);
      }
    }
    final value = _value as T;
    final startListening = delegate.startListening;
    if (startListening != null) {
      _stopListening ??= element._quietly(
        () => startListening(element, value),
      );
    }
    return value;
  }

  void _check(T value) {
    assert(() {
      delegate.debugCheckInvalidValueType?.call(value);
      return true;
    }(), 'the value is checked');
  }

  @override
  void build({required bool external}) {
    final update = delegate.update;
    if (external && _created && update != null) {
      final previous = _value as T;
      final value = _value = update(element!, previous);
      final shouldNotify =
          delegate.updateShouldNotify?.call(previous, value) ??
          value != previous;
      if (shouldNotify) {
        _check(value);
        _stopListening?.call();
        _stopListening = null;
        _previous?.dispose?.call(element!, previous);
        element!._shouldNotify = true;
      }
    }
    _previous = delegate;
  }

  @override
  void dispose() {
    _stopListening?.call();
    if (_created && _error == null) {
      delegate.dispose?.call(element!, _value as T);
    }
  }
}

final class _ValueDelegate<T> extends _Delegate<T> {
  const _ValueDelegate({
    required this.value,
    required this.updateShouldNotify,
    required this.startListening,
  });

  final T value;

  // ignore: unsafe_variance, called by the state, whose T is this one's
  final UpdateShouldNotify<T>? updateShouldNotify;

  // ignore: unsafe_variance, called by the state, whose T is this one's
  final StartListening<T>? startListening;

  @override
  _ValueState<T> createState() => _ValueState<T>();
}

final class _ValueState<T> extends _DelegateState<T, _ValueDelegate<T>> {
  VoidCallback? _stopListening;

  @override
  bool get hasValue => true;

  @override
  T get value {
    final element = this.element!;
    final value = delegate.value;
    final startListening = delegate.startListening;
    if (startListening != null) {
      _stopListening ??= element._quietly(
        () => startListening(element, value),
      );
    }
    return value;
  }

  @override
  bool willUpdateDelegate(_ValueDelegate<T> newDelegate) {
    final old = delegate.value;
    final shouldNotify =
        delegate.updateShouldNotify?.call(old, newDelegate.value) ??
        newDelegate.value != old;
    if (shouldNotify) {
      _stopListening?.call();
      _stopListening = null;
    }
    return shouldNotify;
  }

  @override
  void dispose() => _stopListening?.call();
}

abstract class _DeferredDelegate<C, T> extends _Delegate<T> {
  const _DeferredDelegate({
    required this.updateShouldNotify,
    required this.startListening,
  });

  // ignore: unsafe_variance, called by the state, whose T is this one's
  final UpdateShouldNotify<T>? updateShouldNotify;

  // ignore: unsafe_variance, called by the state, whose T is this one's
  final DeferredStartListening<C, T> startListening;
}

abstract class _DeferredState<C, T, D extends _DeferredDelegate<C, T>>
    extends _DelegateState<T, D> {
  VoidCallback? _stopListening;
  var _hasValue = false;
  T? _value;

  C get controller;

  @override
  bool get hasValue => _hasValue;

  @override
  T get value {
    final element = this.element!;
    _stopListening ??= element._quietly(
      () => delegate.startListening(element, setState, controller, _value),
    );
    assert(
      _hasValue,
      'the startListening of ${element.widget.owner.runtimeType} did not '
      'call setState before it returned',
    );
    return _value as T;
  }

  void setState(T value) {
    if (_hasValue) {
      final previous = _value as T;
      final shouldNotify =
          delegate.updateShouldNotify?.call(previous, value) ??
          previous != value;
      if (shouldNotify) {
        element!.markNeedsNotifyDependents();
      }
    }
    _hasValue = true;
    _value = value;
  }

  @override
  void dispose() => _stopListening?.call();
}

final class _CreateDeferredDelegate<C, T> extends _DeferredDelegate<C, T> {
  const _CreateDeferredDelegate({
    required this.create,
    required this.dispose,
    required super.updateShouldNotify,
    required super.startListening,
  });

  final Create<C> create;

  // ignore: unsafe_variance, called by the state, whose C is this one's
  final Dispose<C>? dispose;

  @override
  _CreateDeferredState<C, T> createState() => _CreateDeferredState<C, T>();
}

final class _CreateDeferredState<C, T>
    extends _DeferredState<C, T, _CreateDeferredDelegate<C, T>> {
  var _created = false;
  C? _controller;

  @override
  C get controller {
    if (!_created) {
      final element = this.element!;
      _controller = element._create(() => delegate.create(element));
      _created = true;
    }
    return _controller as C;
  }

  @override
  void dispose() {
    super.dispose();
    if (_created) {
      delegate.dispose?.call(element!, _controller as C);
    }
  }
}

final class _ValueDeferredDelegate<C, T> extends _DeferredDelegate<C, T> {
  const _ValueDeferredDelegate({
    required this.value,
    required super.updateShouldNotify,
    required super.startListening,
  });

  final C value;

  @override
  _ValueDeferredState<C, T> createState() => _ValueDeferredState<C, T>();
}

final class _ValueDeferredState<C, T>
    extends _DeferredState<C, T, _ValueDeferredDelegate<C, T>> {
  @override
  C get controller => delegate.value;

  @override
  bool willUpdateDelegate(_ValueDeferredDelegate<C, T> newDelegate) {
    if (newDelegate.value == delegate.value) {
      return false;
    }
    _stopListening?.call();
    _stopListening = null;
    return true;
  }
}
