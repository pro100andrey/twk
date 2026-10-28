/// Where the state of providers lives in the tree: [ProviderScope] and
/// [UncontrolledProviderScope].
library;

import 'package:riverpod/misc.dart' show Override;
import 'package:riverpod/riverpod.dart';
import 'package:twk/twk.dart';

// Examples can assume:
// import 'package:twk/twk.dart';
// final countProvider = Provider<int>((ref) => 0);
// late Widget app;
// late Widget child;

/// Keeps the state of providers for the widgets below it, in a
/// [ProviderContainer] it creates when it is placed in the tree and
/// disposes when it leaves it: an app has one at its root.
///
/// One below another creates a container whose parent is the one above:
/// [overrides] change providers for its subtree only, the others are
/// shared with the scope above. A new widget may change the values of the
/// [overrides] ([ProviderContainer.updateOverrides]), not which providers
/// they override.
///
/// An app with a scope at its root, and a subtree where a provider has a
/// value of its own:
///
/// ```dart
/// ProviderScope(
///   child: Column(
///     children: [
///       app,
///       ProviderScope(
///         overrides: [countProvider.overrideWithValue(3)],
///         child: child,
///       ),
///     ],
///   ),
/// )
/// ```
final class ProviderScope extends StatefulWidget {
  /// Keeps the state of providers for [child] and the widgets below it.
  const ProviderScope({
    required this.child,
    super.key,
    this.overrides = const [],
    this.observers,
    this.retry,
  });

  /// The widgets the providers are kept for.
  final Widget child;

  /// What the providers of this scope do instead of what they were declared
  /// with: `counterProvider.overrideWithValue(3)`.
  final List<Override> overrides;

  /// Told of what the providers of this scope do, along with the observers
  /// of the scopes above.
  final List<ProviderObserver>? observers;

  /// How long a provider that failed waits before it is built again, null
  /// for not again; by default that of the scope above, else
  /// [ProviderContainer.defaultRetry].
  final Duration? Function(int retryCount, Object error)? retry;

  /// The container of the nearest scope above [context] ([ProviderScope] or
  /// [UncontrolledProviderScope]), [context] depending on it unless
  /// [listen] is false; a [StateError] if there is none.
  static ProviderContainer containerOf(
    BuildContext context, {
    bool listen = true,
  }) {
    final scope = listen
        ? context
              .dependOnInheritedWidgetOfExactType<UncontrolledProviderScope>()
        : context.getInheritedWidgetOfExactType<UncontrolledProviderScope>();
    return scope?.container ??
        (throw StateError(
          'no ProviderScope above ${context.widget.runtimeType}: place one '
          'above it, as around the whole app: ProviderScope(child: …)',
        ));
  }

  @override
  State<ProviderScope> createState() => _ProviderScopeState();
}

final class _ProviderScopeState extends State<ProviderScope> {
  late final ProviderContainer _container;
  ProviderContainer? _parent;
  var _overridesChanged = false;

  ProviderContainer? _parentOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<UncontrolledProviderScope>()
      ?.container;

  @override
  void initState() {
    super.initState();
    _parent = _parentOf(context);
    _container = ProviderContainer(
      parent: _parent,
      overrides: widget.overrides,
      observers: widget.observers,
      retry: widget.retry,
    );
  }

  @override
  void didUpdateWidget(ProviderScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _overridesChanged = true;
  }

  @override
  Widget build(BuildContext context) {
    assert(
      identical(_parentOf(context), _parent),
      'a ProviderScope was moved under another ProviderScope',
    );
    if (_overridesChanged) {
      _overridesChanged = false;
      _container.updateOverrides(widget.overrides);
    }
    return UncontrolledProviderScope(
      container: _container,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _container.dispose();
    super.dispose();
  }
}

/// Gives the widgets below it [container], which it neither creates nor
/// disposes: for a container made elsewhere, as by a test. Those that
/// watched providers watch them again in the new container when it is
/// replaced by another.
///
/// A container a test made and reads, given to the widget under test:
///
/// ```dart
/// final container = ProviderContainer();
/// final widget = UncontrolledProviderScope(container: container, child: app);
/// ```
final class UncontrolledProviderScope extends InheritedWidget {
  /// Gives [child] and the widgets below it [container].
  const UncontrolledProviderScope({
    required this.container,
    required super.child,
    super.key,
  });

  /// The container of the providers the widgets below read and watch.
  final ProviderContainer container;

  @override
  bool updateShouldNotify(UncontrolledProviderScope oldWidget) =>
      !identical(container, oldWidget.container);
}
