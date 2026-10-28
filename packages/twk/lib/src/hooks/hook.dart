/// Hooks over the framework's elements: a [Hook] a build [use]s, the
/// [HookState] its element keeps for it, and the widgets whose builds call
/// hooks: [HookWidget], [StatefulHookWidget] and [HookBuilder].
///
/// The element keeps the states in the order its build used their hooks:
/// the n-th hook of a build gets the state of the n-th hook of the last
/// one. So a build calls the same hooks in the same order every time, none
/// in a condition or a loop whose course changes, and calls them itself.
/// In debug, a build that calls another hook where its last build called
/// one, or more or fewer hooks than it, fails with an error naming the
/// hooks and the widget, and so does a hook called by another hook; a hook
/// called outside a build is a [StateError] in release too.
///
/// @docImport 'primitives.dart';
library;

import 'package:meta/meta.dart';

import '../../twk.dart';

/// What a build uses a [HookState] by: the description, made anew by each
/// build, that the state its first use created is updated with, as a
/// widget updates its element.
///
/// A hook of one's own: the time since the first build, which a later
/// build reads anew.
///
/// ```dart
/// Duration useElapsed() => use(const _ElapsedHook());
///
/// final class _ElapsedHook extends Hook<Duration> {
///   const _ElapsedHook();
///
///   @override
///   _ElapsedState createState() => _ElapsedState();
/// }
///
/// final class _ElapsedState extends HookState<Duration, _ElapsedHook> {
///   final _stopwatch = Stopwatch()..start();
///
///   @override
///   Duration build(BuildContext context) => _stopwatch.elapsed;
/// }
/// ```
///
/// A hook made of other hooks is a function that calls them, as
/// `useElapsed` above calls [use].
@immutable
abstract class Hook<R> {
  /// A hook whose state is kept while [keys] stay equal; null, the
  /// default, keeps it for good.
  const Hook({this.keys});

  /// The state is created anew, the old one disposed first, when these
  /// differ from those of the last build's hook ([keysEqual]); null keeps
  /// it.
  final List<Object?>? keys;

  /// Names the hook in errors and descriptions: its type by default.
  String get debugLabel => '$runtimeType';

  /// The state of a first use of this hook.
  @protected
  HookState<R, Hook<R>> createState();

  /// Whether [a] and [b] are both null, or as long and their items equal
  /// (or identical, as a NaN is to itself) one by one.
  static bool keysEqual(List<Object?>? a, List<Object?>? b) {
    if (identical(a, b)) {
      return true;
    }
    if (a == null || b == null || a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i]) && a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

/// What the element of a build that uses a [Hook] keeps for it between
/// builds, and the value [use] gives the build ([build]).
///
/// The first use calls [initHook], then [build]; each later build calls
/// [didUpdateHook] with the hook of the build before, unless the build
/// gave the very same hook, then [build]. [deactivate] and [activate] are
/// called with the element's, [dispose] when the element is unmounted or
/// when the hook's [Hook.keys] change.
abstract class HookState<R, T extends Hook<R>> {
  HookElement? _element;
  late T _hook;

  /// The element of the widget whose build uses the hook, from the first
  /// use until [dispose] returns.
  BuildContext get context {
    assert(_element != null, 'the context of $this used after dispose()');
    return _element!;
  }

  /// The hook of the current build; already the new one in
  /// [didUpdateHook].
  T get hook => _hook;

  /// Whether the state has an element: false once [dispose] has run.
  bool get mounted => _element != null;

  /// Called once, at the first use of the hook, before [build]; inherited
  /// widgets are depended on in [build], which every build calls. When it
  /// throws, the state is not kept, nor disposed: the next build creates
  /// another.
  @protected
  @mustCallSuper
  void initHook() {}

  /// Called when a build used a new hook in the place of [oldHook], keys
  /// equal; [hook] is already the new one.
  @protected
  @mustCallSuper
  void didUpdateHook(covariant T oldHook) {}

  /// The value [use] gives the build, asked for on every build.
  @protected
  R build(BuildContext context);

  /// Called when the element is removed from the tree; [activate] follows
  /// if a [GlobalKey] puts it back elsewhere in the same frame, [dispose]
  /// if not.
  @protected
  @mustCallSuper
  void deactivate() {}

  /// Called when a [GlobalKey] put the element back in the tree elsewhere.
  @protected
  @mustCallSuper
  void activate() {}

  /// Called once, when the element is unmounted, or before a state is
  /// created in its place for a hook whose keys changed: release what the
  /// state holds.
  @protected
  @mustCallSuper
  void dispose() {}

  /// Adds what describes this state to its element's description
  /// ([Element.describe]), after its widget's.
  @protected
  @mustCallSuper
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {}

  /// Runs [fn], which changes this state, and rebuilds the element in the
  /// owner's next build scope.
  @protected
  void setState(void Function() fn) {
    assert(_element != null, 'setState() called after dispose(): $this');
    fn();
    _element!.markNeedsBuild();
  }

  void _unmount() {
    try {
      dispose();
    } finally {
      _element = null;
    }
  }

  @override
  String toString() => 'the state of ${_hook.debugLabel}';
}

/// The value of [hook] for the build running: the value of its state,
/// which the first build to use a hook in this place creates; see
/// [HookState]. Called by the build of a [HookWidget], of the state of a
/// [StatefulHookWidget] or of a [HookBuilder], directly or by the
/// functions it calls, such as `useState`.
///
/// ```dart
/// Duration useElapsed() => use(const _ElapsedHook());
///
/// final class _ElapsedHook extends Hook<Duration> {
///   const _ElapsedHook();
///
///   @override
///   _ElapsedState createState() => _ElapsedState();
/// }
///
/// final class _ElapsedState extends HookState<Duration, _ElapsedHook> {
///   final _stopwatch = Stopwatch()..start();
///
///   @override
///   Duration build(BuildContext context) => _stopwatch.elapsed;
/// }
/// ```
R use<R>(Hook<R> hook) {
  final element = HookElement._current;
  if (element == null) {
    throw StateError(_outside(hook.debugLabel));
  }
  return element._use(hook);
}

/// The context of the build running, in which a function that uses hooks
/// can look up what is above it.
///
/// A hook of one's own that gives a function quitting the app:
///
/// ```dart
/// VoidCallback useQuit() {
///   final context = useContext();
///   return () => AppBinding.of(context).quit();
/// }
/// ```
BuildContext useContext() =>
    HookElement._current ?? (throw StateError(_outside('useContext')));

String _outside(String label) =>
    '$label called outside a build: hooks are called by the build of a '
    "HookWidget, a StatefulHookWidget's state or a HookBuilder";

/// Makes a [ComponentElement] keep the states of the hooks its build
/// [use]s: the element of a [HookWidget] and of a [StatefulHookWidget],
/// and of other widgets whose builds call hooks.
mixin HookElement on ComponentElement {
  // the element whose build runs
  static HookElement? _current;

  // the states in the order of their hooks; null for one to create, whose
  // creation threw
  final _hooks = <HookState<Object?, Hook<Object?>>?>[];
  var _index = 0;

  // a build used its hooks to the end
  var _built = false;

  // the hook whose state runs a method in use
  Hook<Object?>? _running;

  @override
  Widget build() {
    final outer = _current;
    _current = this;
    _index = 0;
    try {
      final built = super.build();
      if (_index < _hooks.length) {
        assert(
          !_built,
          '$this stopped calling hooks before its hook ${_index + 1}, '
          '${_hooks[_index]?.hook.debugLabel}, which its last build called: '
          '$_rule',
        );
        _disposeFrom(_index);
      }
      _built = true;
      return built;
    } finally {
      _current = outer;
    }
  }

  R _use<R>(Hook<R> hook) {
    assert(
      _running == null,
      '${hook.debugLabel} called by ${_running?.debugLabel}: hooks are '
      'called by builds, not by other hooks',
    );
    final i = _index++;
    _running = hook;
    try {
      var state = i < _hooks.length ? _hooks[i] : null;
      if (i == _hooks.length) {
        assert(
          !_built,
          '$this called ${hook.debugLabel} as its hook ${i + 1}, which its '
          'last build did not call: $_rule',
        );
        _hooks.add(null);
      } else if (state != null) {
        final old = state.hook;
        if (old.runtimeType != hook.runtimeType) {
          assert(
            false,
            '$this called ${hook.debugLabel} as its hook ${i + 1}, where its '
            'last build called ${old.debugLabel}: $_rule',
          );
          _disposeFrom(i);
          _hooks.add(null);
          state = null;
        } else if (!identical(old, hook)) {
          if (Hook.keysEqual(old.keys, hook.keys)) {
            state
              .._hook = hook
              ..didUpdateHook(old);
          } else {
            _hooks[i] = null;
            state._unmount();
            state = null;
          }
        }
      }
      if (state == null) {
        final created = hook.createState()
          .._element = this
          .._hook = hook
          ..initHook();
        _hooks[i] = state = created;
      }
      return state.build(this) as R;
    } finally {
      _running = null;
    }
  }

  static const _rule =
      'a build calls the same hooks in the same order every time, none in '
      'a condition or a loop whose course changes';

  /// Disposes the states from [start] on, the last first, and lets go of
  /// them.
  void _disposeFrom(int start) {
    final states = _hooks.sublist(start);
    _hooks.length = start;
    for (final state in states.reversed) {
      state?._unmount();
    }
  }

  /// Deactivates the states, the last first.
  @override
  void deactivate() {
    for (final state in _hooks.reversed) {
      state?.deactivate();
    }
    super.deactivate();
  }

  /// Activates the states, the first first.
  @override
  void activate() {
    super.activate();
    for (final state in _hooks) {
      state?.activate();
    }
  }

  /// Disposes the states, the last first, all of them also when one
  /// throws; the first error is thrown once the element is unmounted.
  @override
  void unmount() {
    final states = List.of(_hooks.reversed);
    _hooks.clear();
    Object? error;
    StackTrace? stack;
    for (final state in states) {
      try {
        state?._unmount();
      } on Object catch (e, s) {
        error ??= e;
        stack ??= s;
      }
    }
    super.unmount();
    if (error != null) {
      Error.throwWithStackTrace(error, stack!);
    }
  }

  /// Adds the properties of the states, in order, after those of the
  /// widget (and of the state of a stateful one).
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    for (final state in _hooks) {
      state?.debugFillProperties(properties);
    }
  }
}

/// A [StatelessWidget] whose [build] calls hooks.
///
/// A counter whose count is the state of a [useState]:
///
/// ```dart
/// final class Counter extends HookWidget {
///   const Counter({super.key});
///
///   @override
///   Widget build(BuildContext context) {
///     final count = useState(0);
///     return KeyBindings({
///       'up': () => count.value++,
///     }, child: Text('Count: ${count.value}'));
///   }
/// }
/// ```
///
/// See also:
///
///  * [HookBuilder], the same written in place.
///  * [StatefulHookWidget], for a [State] whose build calls hooks.
abstract class HookWidget extends StatelessWidget {
  /// Lets a subclass be constant.
  const HookWidget({super.key});

  @override
  StatelessElement createElement() => _StatelessHookElement(this);
}

final class _StatelessHookElement extends StatelessElement with HookElement {
  _StatelessHookElement(HookWidget super.widget);
}

/// A [StatefulWidget] whose state's build calls hooks, besides keeping
/// what a [State] keeps. Its hooks are deactivated before the state and
/// disposed before it, activated after it.
///
/// A state that keeps a field of its own and calls a hook in its build:
///
/// ```dart
/// final class Search extends StatefulHookWidget {
///   const Search({super.key});
///
///   @override
///   State<Search> createState() => _SearchState();
/// }
///
/// final class _SearchState extends State<Search> {
///   var _searches = 0;
///
///   @override
///   Widget build(BuildContext context) {
///     final controller = useTextEditingController();
///     return TextField(
///       controller: controller,
///       onSubmitted: (_) => setState(() => _searches++),
///     );
///   }
/// }
/// ```
abstract class StatefulHookWidget extends StatefulWidget {
  /// Lets a subclass be constant.
  const StatefulHookWidget({super.key});

  @override
  StatefulElement createElement() => _StatefulHookElement(this);
}

final class _StatefulHookElement extends StatefulElement with HookElement {
  _StatefulHookElement(StatefulHookWidget super.widget);
}

/// Shows what [builder] returns, which calls hooks: a [HookWidget] written
/// in place.
///
/// A toggle that keeps its state in place, inside another widget's build:
///
/// ```dart
/// HookBuilder(
///   builder: (context) {
///     final on = useState(false);
///     return KeyBindings({
///       'space': () => on.value = !on.value,
///     }, child: Text(on.value ? '[x] Wrap' : '[ ] Wrap'));
///   },
/// )
/// ```
final class HookBuilder extends HookWidget {
  /// Shows what [builder] returns.
  const HookBuilder({required this.builder, super.key});

  /// Builds what this widget shows, calling hooks; called by every build.
  final Widget Function(BuildContext context) builder;

  @override
  Widget build(BuildContext context) => builder(context);
}
