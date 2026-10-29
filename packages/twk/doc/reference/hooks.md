# Hooks: `package:twk/hooks.dart`

[The reference](README.md)

Hooks in the style of flutter_hooks: state, effects, memoized values,
listenables, streams, futures, animations and controllers that a build
keeps by calling functions, in place of the fields, `initState`,
`didUpdateWidget` and `dispose` of a `State`. `lib/hooks.dart` is a
library of its own, over `lib/src/hooks/`, which `lib/twk.dart` does not
export: an app that uses hooks imports it besides `package:twk/twk.dart`,
and one that does not carries none of it. It builds on twk's public API
alone.

```dart
import 'package:twk/hooks.dart';
import 'package:twk/twk.dart';

Future<void> main() => runApp(const Counter());

final class Counter extends HookWidget {
  const Counter({super.key});

  @override
  Widget build(BuildContext context) {
    final count = useState(0);
    return KeyBindings({
      'up': () => count.value++,
      'q': () => AppBinding.of(context).quit(),
    }, child: Text('Count: ${count.value}'));
  }
}
```

`dart run example/hooks/counter.dart` runs that counter in a box
(`--inline` below the shell's history).

## Widgets and rules

A `HookWidget` is a `StatelessWidget` whose `build` calls hooks; the
state of a `StatefulHookWidget` calls them in its `build`, besides what a
`State` keeps (its hooks are deactivated and disposed before it,
activated after it); `HookBuilder(builder:)` is a `HookWidget` written
in place. Another widget's element keeps hooks with the `HookElement`
mixin.

The element keeps the states of the hooks in the order its build called
them: the n-th hook of a build gets the state of the n-th hook of the
last one. So a build calls the same hooks in the same order every time,
none in a condition or a loop whose course changes, and calls them
itself, not in callbacks. In debug, a build that calls another hook
where its last build called one, or more or fewer hooks than it, fails
with an error naming the widget and the hooks (`HookBuilder called
useMemoized<int> as its hook 2, where its last build called
useState<int>: …`), shown in place of what it builds, and so does a hook
called by another hook's state; a hook called outside a build (in an
`initState`, a callback) is a `StateError` in release too. A hot reload
that changes the hooks a build calls fails so too, until a hot restart.
A build that threw before its last hooks calls them in the next one as
the first time.

## The hooks

A hook is made by the first build that calls it and disposed when the
element is unmounted, the last one first; one that takes `keys` is made
anew, the old one disposed first, when the keys of a build differ from
the last one's (`Hook.keysEqual`: by `==` item by item, a NaN equal to
itself).

| hook | gives |
|------|-------|
| `useState(initialData)` | a `ValueNotifier` whose changes rebuild the element |
| `useEffect(effect, [keys])` | nothing: runs `effect` in the first build, again where the keys change, in every build without keys, and the function it returned before each run and at unmount; within the build, so a change it makes to the state rebuilds nothing |
| `useMemoized(valueBuilder, [keys])` | what `valueBuilder` returned, until the keys change (without keys for good) |
| `useRef(initialValue)` | an `ObjectRef`, the same box in every build; its `value` changes rebuild nothing |
| `useCallback(callback, [keys])` | the callback of the first build, identical until the keys change |
| `useValueChanged(value, valueChange)` | null, then what `valueChange(oldValue, oldResult)` returned the last time `value` changed |
| `useContext()` | the context of the build, for functions that use hooks |
| `useListenable(listenable)` | the listenable, whose notifications rebuild the element; the listener goes over to the listenable of a later build |
| `useValueListenable(valueListenable)` | its value, rebuilt when it changes |
| `useValueNotifier(initialData, [keys])` | a `ValueNotifier` whose changes rebuild nothing |
| `useStream(stream, initialData:, preserveState: true)` | the latest `AsyncSnapshot` of the stream, as `StreamBuilder` builds from: waiting, active with each event, done; cancelled at unmount |
| `useFuture(future, initialData:, preserveState: true)` | the latest `AsyncSnapshot` of the future, as `FutureBuilder` builds from |
| `useAnimationController(duration:, reverseDuration:, initialValue:, lowerBound:, upperBound:, vsync:, keys:)` | an `AnimationController` ticking in the app's frames (or with `vsync`'s ticker), its durations those of the latest build |
| `useTicker(onTick)` | a `Ticker`, not started, calling the `onTick` of the latest build |
| `useFocusNode(debugLabel:, onKeyEvent:, canRequestFocus:, skipTraversal:, descendantsAreFocusable:)` | a `FocusNode` that each build sets up with these |
| `useFocusScopeNode(…)` | a `FocusScopeNode`, likewise |
| `useTextEditingController(text:, keys:)`, `.fromValue(value, [keys])` | a `TextEditingController`; the text of later builds is ignored |
| `useScrollController(initialOffset:, keys:)` | a `ScrollController` |
| `useListController(initialOffset:, keys:)` | a `ListController` |

When the stream or the future of a build is not the last one's, the hook
goes over to it, the snapshot kept, not connected, with `preserveState`,
or from `initialData` again without; the result of a future left, or of
one the element was unmounted with, is ignored.

A hook of one's own is a function that calls others, or a `Hook` (its
`keys`, its `debugLabel` for errors, `createState`) and its `HookState`,
put to work by `use(hook)`: `initHook` at the first use, `didUpdateHook`
with each later build's hook (not when a build gives the very same),
`build` for the value on every build, `deactivate`, `activate`,
`dispose`, `setState` to rebuild the element, and `debugFillProperties`
for the element's description, where `useState`, `useValueNotifier`,
`useStream`, `useFuture` and `useAnimationController` show their values
(`useState<int>: 3`).

## Its tests

`test/hooks/` runs each hook through `testTwk`, mounted, rebuilt with the
same keys and with others, and unmounted: `hook_test.dart` the states
kept in order, updated, created anew for other keys and disposed the last
first, a `StatefulHookWidget`'s hooks around its state, a widget a
`GlobalKey` moves keeping its hooks' states, a dispose that throws
leaving the others disposed, the descriptions, and each rule broken with
the error that names it; `primitives_test.dart`, `listenables_test.dart`,
`async_test.dart`, `animation_test.dart` (in the app's frames, under a
fake clock) and `controllers_test.dart` (with the `Focus`, `TextField`
and `ListView` each controls) the hooks of each group;
`example/counter_test.dart` the example.
