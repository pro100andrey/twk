/// The hooks of listenables: [useListenable] and [useValueListenable],
/// which rebuild when one notifies, and [useValueNotifier], which makes
/// one.
library;

import '../../twk.dart';

import 'hook.dart';

// Examples can assume:
// late ValueNotifier<int> unread;
// late ScrollController scroll;

/// [listenable], whose notifications rebuild the element from this build
/// on: the listener goes over to the listenable of a later build, and is
/// removed when the element is unmounted. Null listens to nothing.
///
/// The offset of a scroll controller made elsewhere, shown as it changes:
///
/// ```dart
/// HookBuilder(
///   builder: (context) {
///     final controller = useListenable(scroll);
///     return Text('line ${controller.offset + 1}');
///   },
/// )
/// ```
T useListenable<T extends Listenable?>(T listenable) =>
    use(_ListenableHook<T>(listenable, 'useListenable<$T>'));

/// The value of [valueListenable], whose notifications rebuild the
/// element, as [useListenable] listens.
///
/// ```dart
/// HookBuilder(
///   builder: (context) => Text('${useValueListenable(unread)} unread'),
/// )
/// ```
T useValueListenable<T>(ValueListenable<T> valueListenable) => use(
  _ListenableHook(valueListenable, 'useValueListenable<$T>'),
).value;

final class _ListenableHook<T extends Listenable?> extends Hook<T> {
  const _ListenableHook(this.listenable, this.debugLabel);

  final T listenable;

  @override
  final String debugLabel;

  @override
  _ListenableHookState<T> createState() => _ListenableHookState<T>();
}

final class _ListenableHookState<T extends Listenable?>
    extends HookState<T, _ListenableHook<T>> {
  @override
  void initHook() {
    super.initHook();
    hook.listenable?.addListener(_changed);
  }

  @override
  void didUpdateHook(_ListenableHook<T> oldHook) {
    super.didUpdateHook(oldHook);
    if (oldHook.listenable != hook.listenable) {
      oldHook.listenable?.removeListener(_changed);
      hook.listenable?.addListener(_changed);
    }
  }

  void _changed() => setState(() {});

  @override
  T build(BuildContext context) => hook.listenable;

  @override
  void dispose() {
    hook.listenable?.removeListener(_changed);
    super.dispose();
  }
}

/// A notifier of [initialData], made by the first build, made anew when
/// the [keys] of a build differ from the last one's, and disposed with the
/// element or when replaced. Unlike `useState`'s, its changes rebuild
/// nothing: [useListenable] or a `ValueListenableBuilder` listen to it.
///
/// A notifier that only the widgets listening to it rebuild for:
///
/// ```dart
/// HookBuilder(
///   builder: (context) {
///     final progress = useValueNotifier(0.0);
///     return ValueListenableBuilder(
///       valueListenable: progress,
///       builder: (context, value, _) => Text('${(value * 100).round()} %'),
///     );
///   },
/// )
/// ```
ValueNotifier<T> useValueNotifier<T>(T initialData, [List<Object?>? keys]) =>
    use(_ValueNotifierHook(initialData, keys));

final class _ValueNotifierHook<T> extends Hook<ValueNotifier<T>> {
  const _ValueNotifierHook(this.initialData, List<Object?>? keys)
    : super(keys: keys);

  final T initialData;

  @override
  String get debugLabel => 'useValueNotifier<$T>';

  @override
  _ValueNotifierHookState<T> createState() => _ValueNotifierHookState<T>();
}

final class _ValueNotifierHookState<T>
    extends HookState<ValueNotifier<T>, _ValueNotifierHook<T>> {
  late final ValueNotifier<T> _notifier;

  @override
  void initHook() {
    super.initHook();
    _notifier = ValueNotifier(hook.initialData);
  }

  @override
  ValueNotifier<T> build(BuildContext context) => _notifier;

  @override
  void dispose() {
    _notifier.dispose();
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(hook.debugLabel, _notifier.value);
  }
}
