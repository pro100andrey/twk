# twk_riverpod — Riverpod for twk widgets

[Riverpod](https://riverpod.dev) for widgets of [twk](../twk/README.md),
as flutter_riverpod is for Flutter's: a `ProviderScope` keeps the state of
providers, and widgets watch them through a `WidgetRef`, rebuilt when what
they watch changes and only then. It takes package:riverpod (`^3.4.3`,
pure Dart) as a dependency and twk as a path one, and
[twk_test](../twk_test/README.md), whose tester (`testTwk`) runs its
tests, as a path dev dependency.

`lib/twk_riverpod.dart` exports package:riverpod's own library with the
widgets, so an app imports nothing else; `misc.dart` exports riverpod's
library of that name (`ProviderListenable`, `Override`).

## A counter

```dart
import 'package:twk/twk.dart';
import 'package:twk_riverpod/twk_riverpod.dart';

Future<void> main() => runApp(const ProviderScope(child: Counter()));

final class Count extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state++;
}

final countProvider = NotifierProvider<Count, int>(Count.new);

final class Counter extends ConsumerWidget {
  const Counter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => KeyBindings(
    {
      'up': () => ref.read(countProvider.notifier).increment(),
      'q': () => AppBinding.of(context).quit(),
    },
    child: Text('Count: ${ref.watch(countProvider)}'),
  );
}
```

`dart run example/counter.dart` (or with `--inline`) runs it in a rounded
box; `test/example/counter_test.dart` tests it.

## The widgets

| widget | does |
|--------|------|
| `ProviderScope(overrides:, observers:, retry:, child:)` | Creates a `ProviderContainer` when it is placed in the tree and disposes it when it leaves. One below another creates a child container of the one above: its `overrides` change providers for its subtree only, the others are shared. A new widget may change the values of its overrides (`updateOverrides`), not which providers they override. `ProviderScope.containerOf(context, listen:)` finds the nearest container, a `StateError` naming the widget if there is none |
| `UncontrolledProviderScope(container:, child:)` | Gives the subtree a container made elsewhere, which it neither creates nor disposes; given another, the widgets below watch their providers in it instead |
| `ConsumerWidget` | A `StatelessWidget` whose `build(context, ref)` gets a `WidgetRef` |
| `ConsumerStatefulWidget`, `ConsumerState` | A `StatefulWidget` whose state has a `ref`, from `initState` on |
| `Consumer(builder: (context, ref, child) => …, child:)` | Rebuilds only what its builder returns; `child` is built by the parent |

A `WidgetRef` (the element of a `ConsumerStatefulWidget`, `ConsumerStatefulElement`):

- `watch(provider)` returns the value and rebuilds the widget in the next
  build scope when it changes (through `select`, when what it selects
  does); widgets that did not watch it are not rebuilt. What a build
  watches is watched until a later build does not watch it again, or until
  the widget leaves the tree: then an `autoDispose` provider nobody else
  listens to is disposed.
- `read(provider)` the value now, without watching: for callbacks.
- `listen(provider, (previous, next) => …, onError:)` in the build: the
  listener is called on each change, not on rebuilds, until the next build
  listens anew. `listenManual` listens from anywhere (`initState`), with
  `fireImmediately`, until its subscription is closed or the widget leaves
  the tree, after `dispose`.
- `exists`, `refresh`, `invalidate`, and `container`, which makes it a
  `MutationTarget` for riverpod's mutations.

A ref used after its widget left the tree is a `StateError`; `listen`
outside the build fails an assert.

Unlike flutter_riverpod, no ticker mode pauses the subscriptions, and the
container's scheduler keeps its own timing: a provider that watches
another is built again in a timer of zero duration, before the frame that
rebuilds its widgets.

## Checks

From this directory: `dart pub get`, `dart analyze`, `dart test`, and
`dart format --output=none --set-exit-if-changed lib test example`.

## License

MIT, copyright 2026 Andrii Ivanov: [LICENSE](LICENSE).
