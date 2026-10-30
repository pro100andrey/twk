# twk_bloc — Bloc for twk widgets

[Bloc](https://bloclibrary.dev) for widgets of [twk](../twk/README.md), as
flutter_bloc is for Flutter's: blocs and cubits provided to a subtree and
found by their type, and widgets that build and act on the states they
emit. It takes package:bloc (`^9.2.1`, pure Dart) as a dependency, twk
as a path one, and
[twk_test](../twk_test/README.md), whose tester (`testTwk`) runs its
tests, as a path dev dependency.

It builds on twk's provider library, `package:twk/provider.dart`
([twk's reference](../twk/doc/reference/provider.md)), as
flutter_bloc does on provider: its providers are that library's
(`BlocProvider` an `InheritedProvider` that tells its dependents of each
state, `RepositoryProvider` one of any object), what it nests are its
`SingleChildWidget`s, and blocs are found with its `context.read`,
`context.watch` and `context.select`. A file may import both libraries:
their providers mix in either's Multi widgets, and there is one `read`
and one `watch`.

`lib/twk_bloc.dart` exports package:bloc with the widgets, and of
`package:twk/provider.dart` `ReadContext`, `WatchContext`, `SelectContext`,
`SingleChildWidget` and `ProviderNotFoundException`, so an app imports
nothing else.

## A counter

```dart
import 'package:twk/twk.dart';
import 'package:twk_bloc/twk_bloc.dart';

Future<void> main() => runApp(
  BlocProvider(create: (_) => CounterCubit(), child: const Counter()),
);

final class CounterCubit extends Cubit<int> {
  CounterCubit() : super(0);

  void increment() => emit(state + 1);
}

final class Counter extends StatelessWidget {
  const Counter({super.key});

  @override
  Widget build(BuildContext context) => KeyBindings(
    {
      'up': () => context.read<CounterCubit>().increment(),
      'q': () => AppBinding.of(context).quit(),
    },
    child: BlocBuilder<CounterCubit, int>(
      builder: (context, n) => Text('Count: $n'),
    ),
  );
}
```

`dart run example/counter.dart` (or with `--inline`) runs it in a rounded
box; `test/example/counter_test.dart` tests it.

## Providing

- `BlocProvider(create: (context) => …, lazy: true, child:)` creates the
  bloc the first time it is read (when it is placed in the tree unless
  `lazy`) and closes it when it leaves the tree; `BlocProvider.value(value:,
  child:)` provides one made elsewhere, which it does not close, and a new
  widget may provide another: what follows the bloc follows the new one.
  `BlocProvider.of<B>(context, listen:)`.
- `RepositoryProvider(create:, dispose:, lazy:, child:)` and
  `RepositoryProvider.value` do the same for any other object, such as the
  repositories blocs take: `dispose` is handed what it created.
- `MultiBlocProvider(providers: […], child:)`, `MultiRepositoryProvider`
  and `MultiBlocListener(listeners: […], child:)` nest the widgets they are
  given without a child (`SingleChildWidget`s), the first outermost: each
  is `package:twk/provider.dart`'s `MultiProvider`, whose list may hold
  that library's providers too, as a `MultiProvider`'s may hold these.
- `context.read<T>()` finds the nearest provided `T` without depending on
  it: for callbacks and `initState`. `context.watch<T>()` depends on it:
  the widget is rebuilt by each state a bloc emits, as long as its builds
  watch it, and when the provider provides another.
  `context.select<B, R>((bloc) => …)` is rebuilt only when a state makes
  the selector pick something else. Each is a
  `ProviderNotFoundException` naming the type and the widget when there
  is none; `BlocProvider.of` and `RepositoryProvider.of`, and the widgets
  below that look for their bloc, a `StateError` naming the bloc's
  providers. A provider is found by the exact type it provides: a
  `BlocProvider<CounterCubit>` by `read<CounterCubit>()`.

## Following states

Each takes a `bloc:`, else follows the `B` provided above (anew when the
provider provides another), from its first build until it leaves the
tree; a condition takes the state the bloc emitted before and the one it
emits now.

| widget | does |
|--------|------|
| `BlocBuilder<B, S>(builder:, buildWhen:)` | Shows what `builder` returns for the state, built again for each state `buildWhen` takes; one that it does not take leaves the widget as it was. The widgets around it are not rebuilt |
| `BlocSelector<B, S, T>(selector:, builder:)` | Built again only when a state picks another value (`!=`) |
| `BlocListener<B, S>(listener:, listenWhen:, child:)` | Calls `listener` once for each state `listenWhen` takes, without rebuilding `child`: for what is done once, as a notification |
| `BlocConsumer<B, S>(listener:, builder:, listenWhen:, buildWhen:)` | Both: the listener first, then the rebuild, each as its condition says |

A widget that looks for its bloc depends on its provider only for which
bloc it provides (`context.select` of its identity): the provider's
states rebuild it through its own subscription, as its condition says.

## Checks

From this directory: `dart pub get`, `dart analyze`, `dart test`, and
`dart format --output=none --set-exit-if-changed lib test example`.

## License

MIT, copyright 2026 Andrii Ivanov: [LICENSE](LICENSE).
