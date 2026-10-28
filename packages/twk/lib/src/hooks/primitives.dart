/// The hooks of a build's own state: [useState], [useEffect],
/// [useMemoized], [useRef], [useCallback] and [useValueChanged].
library;

import '../../twk.dart';

import 'hook.dart';

// Examples can assume:
// late Stream<String> lines;
// late String path;
// List<String> readLines(String path) => [];
// late int selected;

/// A notifier of [initialData], made by the first build and disposed with
/// the element, whose changes rebuild it: `count.value++` in a callback
/// shows the new count. Later builds' [initialData] is ignored.
///
/// ```dart
/// HookBuilder(
///   builder: (context) {
///     final count = useState(0);
///     return KeyBindings({
///       'up': () => count.value++,
///     }, child: Text('Count: ${count.value}'));
///   },
/// )
/// ```
ValueNotifier<T> useState<T>(T initialData) => use(_StateHook(initialData));

final class _StateHook<T> extends Hook<ValueNotifier<T>> {
  const _StateHook(this.initialData);

  final T initialData;

  @override
  String get debugLabel => 'useState<$T>';

  @override
  _StateHookState<T> createState() => _StateHookState<T>();
}

final class _StateHookState<T>
    extends HookState<ValueNotifier<T>, _StateHook<T>> {
  late final ValueNotifier<T> _notifier;

  @override
  void initHook() {
    super.initHook();
    _notifier = ValueNotifier(hook.initialData)..addListener(_changed);
  }

  void _changed() => setState(() {});

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

/// Runs [effect] in the first build, and the function it returns, if any,
/// when the element is unmounted. With [keys], in a later build whose keys
/// differ from the last one's, the function the last run returned runs
/// first, then [effect] again; without, that happens in every build.
///
/// The effect runs within the build, before it goes on: a change it makes
/// to the state of the widget building does not rebuild it again.
///
/// A subscription made when the widget first builds and cancelled when it
/// goes, made anew for another stream:
///
/// ```dart
/// HookBuilder(
///   builder: (context) {
///     final last = useRef<String?>(null);
///     useEffect(() {
///       final subscription = lines.listen((line) => last.value = line);
///       return subscription.cancel;
///     }, [lines]);
///     return const Text('Listening');
///   },
/// )
/// ```
void useEffect(VoidCallback? Function() effect, [List<Object?>? keys]) =>
    use(_EffectHook(effect, keys));

final class _EffectHook extends Hook<void> {
  const _EffectHook(this.effect, List<Object?>? keys) : super(keys: keys);

  final VoidCallback? Function() effect;

  @override
  String get debugLabel => 'useEffect';

  @override
  _EffectHookState createState() => _EffectHookState();
}

final class _EffectHookState extends HookState<void, _EffectHook> {
  VoidCallback? _cleanup;

  @override
  void initHook() {
    super.initHook();
    _cleanup = hook.effect();
  }

  @override
  void didUpdateHook(_EffectHook oldHook) {
    super.didUpdateHook(oldHook);
    if (hook.keys == null) {
      _cleanUp();
      _cleanup = hook.effect();
    }
  }

  @override
  void build(BuildContext context) {}

  @override
  void dispose() {
    _cleanUp();
    super.dispose();
  }

  void _cleanUp() {
    final cleanup = _cleanup;
    _cleanup = null;
    cleanup?.call();
  }
}

/// What [valueBuilder] returns in the first build, kept until a build whose
/// [keys] differ from the last one's calls it again.
///
/// The lines of a file read once per path, not once per build:
///
/// ```dart
/// HookBuilder(
///   builder: (context) {
///     final lines = useMemoized(() => readLines(path), [path]);
///     return Text('${lines.length} lines');
///   },
/// )
/// ```
T useMemoized<T>(T Function() valueBuilder, [List<Object?> keys = const []]) =>
    use(_MemoizedHook(valueBuilder, keys, 'useMemoized<$T>'));

/// A box of [initialValue], the same one in every build: what is put in it
/// stays without rebuilding anything.
///
/// How many times the widget was built, which no build shows:
///
/// ```dart
/// HookBuilder(
///   builder: (context) {
///     final builds = useRef(0);
///     builds.value++;
///     return const Text('Ready');
///   },
/// )
/// ```
ObjectRef<T> useRef<T>(T initialValue) => use(
  _MemoizedHook(() => ObjectRef(initialValue), const [], 'useRef<$T>'),
);

/// [callback] as the first build gave it, until a build whose [keys]
/// differ from the last one's: a function that stays identical for the
/// widgets it is given to.
///
/// ```dart
/// HookBuilder(
///   builder: (context) {
///     final count = useState(0);
///     final increment = useCallback(() => count.value++);
///     return Button('Add', onPressed: increment);
///   },
/// )
/// ```
T useCallback<T extends Function>(
  T callback, [
  List<Object?> keys = const [],
]) => use(_MemoizedHook(() => callback, keys, 'useCallback<$T>'));

/// A box whose [value] can be read and replaced: what [useRef] keeps.
final class ObjectRef<T> {
  /// A box holding [value].
  ObjectRef(this.value);

  /// What the box holds.
  T value;

  @override
  String toString() => 'ObjectRef($value)';
}

final class _MemoizedHook<T> extends Hook<T> {
  const _MemoizedHook(this.valueBuilder, List<Object?> keys, this.debugLabel)
    : super(keys: keys);

  final T Function() valueBuilder;

  @override
  final String debugLabel;

  @override
  _MemoizedHookState<T> createState() => _MemoizedHookState<T>();
}

final class _MemoizedHookState<T> extends HookState<T, _MemoizedHook<T>> {
  late final T _value;

  @override
  void initHook() {
    super.initHook();
    _value = hook.valueBuilder();
  }

  @override
  T build(BuildContext context) => _value;
}

/// What [valueChange] returned the last time [value] changed: null in the
/// first build, then, in each build whose [value] is not equal to the last
/// one's, [valueChange] of the last value and of what it returned before.
///
/// Which way the selection moved last:
///
/// ```dart
/// HookBuilder(
///   builder: (context) {
///     final direction = useValueChanged<int, String>(
///       selected,
///       (old, _) => selected > old ? 'down' : 'up',
///     );
///     return Text('moved ${direction ?? 'nowhere'}');
///   },
/// )
/// ```
R? useValueChanged<T, R>(
  T value,
  R? Function(T oldValue, R? oldResult) valueChange,
) => use(_ValueChangedHook(value, valueChange));

final class _ValueChangedHook<T, R> extends Hook<R?> {
  const _ValueChangedHook(this.value, this.valueChange);

  final T value;

  // called by the state, whose T and R are the hook's own
  // ignore: unsafe_variance
  final R? Function(T oldValue, R? oldResult) valueChange;

  @override
  String get debugLabel => 'useValueChanged<$T, $R>';

  @override
  _ValueChangedHookState<T, R> createState() => _ValueChangedHookState<T, R>();
}

final class _ValueChangedHookState<T, R>
    extends HookState<R?, _ValueChangedHook<T, R>> {
  R? _result;

  @override
  void didUpdateHook(_ValueChangedHook<T, R> oldHook) {
    super.didUpdateHook(oldHook);
    if (hook.value != oldHook.value) {
      _result = hook.valueChange(oldHook.value, _result);
    }
  }

  @override
  R? build(BuildContext context) => _result;
}
