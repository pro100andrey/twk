/// Widgets that use providers: [ConsumerWidget], [ConsumerStatefulWidget]
/// with its [ConsumerState], and [Consumer], each with a [WidgetRef].
library;

import 'package:meta/meta.dart' show protected, useResult;
import 'package:riverpod/experimental/mutation.dart' show MutationTarget;
import 'package:riverpod/misc.dart'
    show ProviderBase, ProviderListenable, ProviderOrFamily, Refreshable;
import 'package:riverpod/riverpod.dart';
import 'package:twk/twk.dart';

import 'provider_scope.dart';

// Examples can assume:
// import 'package:twk/twk.dart';
// final class Count extends Notifier<int> {
//   @override
//   int build() => 0;
//   void increment() => state++;
// }
// final countProvider = NotifierProvider<Count, int>(Count.new);
// final messagesProvider = Provider<List<String>>((ref) => []);
// late WidgetRef ref;

/// What a widget uses providers through, in the container of the nearest
/// [ProviderScope] above it: the element of a [ConsumerStatefulWidget].
///
/// A build watches a provider, a key reads it to change it:
///
/// ```dart
/// KeyBindings({
///   'up': () => ref.read(countProvider.notifier).increment(),
/// }, child: Text('Count: ${ref.watch(countProvider)}'))
/// ```
sealed class WidgetRef implements MutationTarget {
  /// The context of the widget, as its build gets it.
  BuildContext get context;

  /// The container of the nearest scope above the widget.
  @override
  ProviderContainer get container;

  /// The value of [provider], the widget rebuilt in the next build scope
  /// whenever it changes; widgets that did not watch it are not. What a
  /// build watches is watched until a later build does not watch it again,
  /// or until the widget leaves the tree. Meant for the build.
  T watch<T>(ProviderListenable<T> provider);

  /// The value of [provider] now, without watching it: for callbacks, such
  /// as `ref.read(counterProvider.notifier).increment()` on a key.
  T read<T>(ProviderListenable<T> provider);

  /// Calls [listener] with the value before and the value after whenever
  /// [provider] changes, and [onError] when it fails, from the build that
  /// calls this until the next one: each build listens anew. Only in the
  /// build; [listenManual] elsewhere.
  void listen<T>(
    ProviderListenable<T> provider,
    void Function(T? previous, T next) listener, {
    void Function(Object error, StackTrace stackTrace)? onError,
    bool weak = false,
  });

  /// Listens as [listen] does, but from anywhere, as in
  /// [State.initState], until the subscription is closed or the widget
  /// leaves the tree; [fireImmediately] calls [listener] with the value now
  /// first.
  ProviderSubscription<T> listenManual<T>(
    ProviderListenable<T> provider,
    void Function(T? previous, T next) listener, {
    void Function(Object error, StackTrace stackTrace)? onError,
    bool fireImmediately = false,
    bool weak = false,
  });

  /// Whether [provider] has a state in the container yet.
  bool exists(ProviderBase<Object?> provider);

  /// Builds [provider] again now and returns its new value.
  @useResult
  T refresh<T>(Refreshable<T> provider);

  /// Makes [provider] (or each provider of a family) build again before it
  /// is next read, its state dropped meanwhile unless [asReload].
  void invalidate(ProviderOrFamily provider, {bool asReload = false});
}

/// A [StatelessWidget] whose build gets a [WidgetRef] too.
///
/// ```dart
/// final class Counter extends ConsumerWidget {
///   const Counter({super.key});
///
///   @override
///   Widget build(BuildContext context, WidgetRef ref) => KeyBindings({
///     'up': () => ref.read(countProvider.notifier).increment(),
///   }, child: Text('Count: ${ref.watch(countProvider)}'));
/// }
/// ```
///
/// See also:
///
///  * [Consumer], the same written in place.
///  * [ConsumerStatefulWidget], for a state of its own besides.
abstract class ConsumerWidget extends ConsumerStatefulWidget {
  /// Lets a subclass be constant.
  const ConsumerWidget({super.key});

  /// Describes this part of the interface; [WidgetRef.watch] makes it built
  /// again when a provider changes.
  @protected
  Widget build(BuildContext context, WidgetRef ref);

  @override
  ConsumerState<ConsumerWidget> createState() => _ConsumerWidgetState();
}

final class _ConsumerWidgetState extends ConsumerState<ConsumerWidget> {
  @override
  Widget build(BuildContext context) => widget.build(context, ref);
}

/// A [StatefulWidget] whose [ConsumerState] has a [WidgetRef].
///
/// A state that listens to a provider from [State.initState] on:
///
/// ```dart
/// final class Log extends ConsumerStatefulWidget {
///   const Log({super.key});
///
///   @override
///   ConsumerState<Log> createState() => _LogState();
/// }
///
/// final class _LogState extends ConsumerState<Log> {
///   var _changes = 0;
///
///   @override
///   void initState() {
///     super.initState();
///     ref.listenManual(countProvider, (_, _) => setState(() => _changes++));
///   }
///
///   @override
///   Widget build(BuildContext context) => Text('$_changes changes');
/// }
/// ```
abstract class ConsumerStatefulWidget extends StatefulWidget {
  /// Lets a subclass be constant.
  const ConsumerStatefulWidget({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState();

  @override
  ConsumerStatefulElement createElement() => ConsumerStatefulElement(this);
}

/// The state of a [ConsumerStatefulWidget]: its [ref] is there from
/// [initState] on (for [WidgetRef.read] and [WidgetRef.listenManual]; its
/// build watches).
abstract class ConsumerState<T extends ConsumerStatefulWidget>
    extends State<T> {
  /// The element of this state, as a [WidgetRef].
  late final ref = context as WidgetRef;
}

/// Shows what [builder] returns, built again when a provider it watches
/// changes; the widgets around it are not. [child] is handed to [builder]
/// each time: the part of the subtree built by the parent.
///
/// Only the count is built again when it changes, not the title beside it:
///
/// ```dart
/// Column(
///   children: [
///     const Text('Messages'),
///     Consumer(
///       builder: (context, ref, child) =>
///           Text('${ref.watch(messagesProvider).length} new'),
///     ),
///   ],
/// )
/// ```
final class Consumer extends ConsumerWidget {
  /// Shows what [builder] returns, which is handed [child].
  const Consumer({required this.builder, super.key, this.child});

  /// Builds what this widget shows, watching providers through its ref;
  /// called again when one of them changes.
  final Widget Function(BuildContext context, WidgetRef ref, Widget? child)
  builder;

  /// Handed to [builder]; see [Consumer].
  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      builder(context, ref, child);
}

typedef _Subscriptions =
    Map<ProviderListenable<Object?>, ProviderSubscription<Object?>>;

/// The element of a [ConsumerStatefulWidget], and its [WidgetRef]: it
/// keeps a subscription to each provider its last build watched and those
/// [WidgetRef.listenManual] opened, closed when it leaves the tree.
final class ConsumerStatefulElement extends StatefulElement
    implements WidgetRef {
  /// The element of [widget].
  ConsumerStatefulElement(ConsumerStatefulWidget super.widget);

  // the container the subscriptions of watch and listen are in
  ProviderContainer? _container;

  // what the build running or the last one watched, and what the one
  // before did that it has not watched yet
  _Subscriptions _watched = {};
  _Subscriptions? _unwatched;

  // what the last build listened to
  final _listened = <ProviderSubscription<Object?>>[];

  // what listenManual listens to
  final _manual = <ProviderSubscription<Object?>>[];

  var _building = false;

  @override
  BuildContext get context => this;

  @override
  ProviderContainer get container {
    _checkMounted();
    return ProviderScope.containerOf(this, listen: false);
  }

  void _checkMounted() {
    if (!mounted) {
      throw StateError(
        'a ref used after its widget left the tree: keep what dispose() '
        'needs in a field of the state',
      );
    }
  }

  /// Watches the scope too, so that a new container rebuilds it: then what
  /// it watched in the old one is let go.
  @override
  Widget build() {
    final scoped = ProviderScope.containerOf(this);
    if (!identical(scoped, _container)) {
      _closeAll(_watched.values);
      _watched.clear();
      _container = scoped;
    }
    _closeAll(_listened);
    _listened.clear();
    _unwatched = _watched;
    _watched = {};
    _building = true;
    try {
      return super.build();
    } finally {
      _building = false;
      _closeAll(_unwatched!.values);
      _unwatched = null;
    }
  }

  static void _closeAll(Iterable<ProviderSubscription<Object?>> subs) {
    for (final sub in subs) {
      sub.close();
    }
  }

  @override
  T watch<T>(ProviderListenable<T> provider) {
    _checkMounted();
    final container = _container ??= this.container;
    final sub = _watched.putIfAbsent(
      provider,
      () =>
          _unwatched?.remove(provider) ??
          container.listen<T>(provider, (_, _) => markNeedsBuild()),
    );
    return sub.read() as T;
  }

  @override
  T read<T>(ProviderListenable<T> provider) => container.read(provider);

  @override
  void listen<T>(
    ProviderListenable<T> provider,
    void Function(T? previous, T next) listener, {
    void Function(Object error, StackTrace stackTrace)? onError,
    bool weak = false,
  }) {
    _checkMounted();
    assert(
      _building,
      'ref.listen() outside the build of ${widget.runtimeType}: '
      'ref.listenManual() listens from elsewhere',
    );
    _listened.add(
      (_container ??= container).listen<T>(
        provider,
        listener,
        onError: onError,
        weak: weak,
      ),
    );
  }

  @override
  ProviderSubscription<T> listenManual<T>(
    ProviderListenable<T> provider,
    void Function(T? previous, T next) listener, {
    void Function(Object error, StackTrace stackTrace)? onError,
    bool fireImmediately = false,
    bool weak = false,
  }) {
    final sub = container.listen<T>(
      provider,
      listener,
      onError: onError,
      fireImmediately: fireImmediately,
      weak: weak,
    );
    _manual
      ..removeWhere((s) => s.closed)
      ..add(sub);
    return sub;
  }

  @override
  bool exists(ProviderBase<Object?> provider) => container.exists(provider);

  @override
  T refresh<T>(Refreshable<T> provider) => container.refresh(provider);

  @override
  void invalidate(ProviderOrFamily provider, {bool asReload = false}) =>
      container.invalidate(provider, asReload: asReload);

  /// Closes the subscriptions of watch and listen before the state is
  /// disposed, those of listenManual after.
  @override
  void unmount() {
    _closeAll(_watched.values);
    _watched.clear();
    _closeAll(_listened);
    _listened.clear();
    try {
      super.unmount();
    } finally {
      _closeAll(_manual);
      _manual.clear();
    }
  }
}
