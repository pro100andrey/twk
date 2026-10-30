# Provider: `package:twk/provider.dart`

[The reference](README.md)

[Provider](https://pub.dev/packages/provider)'s API: values provided to a
subtree and found by their type, the widgets that watch them rebuilt
when they change, and only those. `lib/provider.dart` is a library of its
own, over `lib/src/provider/`, which `lib/twk.dart` does not export: an
app that uses providers imports it besides `package:twk/twk.dart`. It is
built on twk's own `InheritedWidget`, `Listenable` and `ChangeNotifier`,
through twk's public API alone.

package:provider itself cannot be a dependency: its pubspec (6.1.5+1)
declares `environment: flutter: ">=1.16.0"` and depends on
`flutter: sdk: flutter`, besides `collection` and `nested`, so it resolves
only in a Flutter app. This library gives the same names and semantics
for twk apps instead.

[twk_bloc](../../../twk_bloc/README.md) builds on it, as flutter_bloc does on
provider: its `BlocProvider` and `RepositoryProvider` are
`InheritedProvider`s, its Multi widgets `MultiProvider`s and its
`BlocListener` a `SingleChildStatefulWidget`, and its blocs are found
with this library's `context.read`, `watch` and `select`, which it
exports. A file imports both without a conflict.

```dart
import 'package:twk/provider.dart';
import 'package:twk/twk.dart';

Future<void> main() => runApp(
  ChangeNotifierProvider(create: (_) => CounterModel(), child: const Counter()),
);

class CounterModel extends ChangeNotifier {
  var _count = 0;

  int get count => _count;

  void increment() {
    _count++;
    notifyListeners();
  }
}

final class Counter extends StatelessWidget {
  const Counter({super.key});

  @override
  Widget build(BuildContext context) => KeyBindings(
    {
      'up': () => context.read<CounterModel>().increment(),
      'q': () => AppBinding.of(context).quit(),
    },
    child: Consumer<CounterModel>(
      builder: (context, counter, _) => Text('Count: ${counter.count}'),
    ),
  );
}
```

`dart run example/provider/counter.dart` (or with `--inline`) runs it in
a rounded box, the count shown by a widget that selects it
(`context.select<CounterModel, int>((c) => c.count)`);
`test/provider/example/counter_test.dart` tests it.

## Providing

Each provider creates its value the first time it is read, unless
`lazy: false` (then when it is placed in the tree), with the provider's
context, in which `create` may read the providers above (`context.read`,
one of its own type too) but not depend on them: that fails an assert.
It disposes of what it created when it leaves the tree, and of nothing
it was given (`.value`). A `.value` provider given a new value that is
not `==` the old one (or as `updateShouldNotify` says) rebuilds the
widgets that watch it. Each takes a `child`, or a `builder:
(context, child) => …` whose context is below the provider; one of the
two outside a `MultiProvider`.

| provider | provides |
|----------|----------|
| `Provider<T>(create:, dispose:, lazy:)`, `Provider.value(value:, updateShouldNotify:)` | A value. One that is a `Listenable` or a `Stream` fails an assert, since its changes would rebuild nothing (`Provider.debugCheckInvalidValueType = null` allows it) |
| `ChangeNotifierProvider<T>(create:)`, `.value(value:)` | A `ChangeNotifier`, whose notifications rebuild the widgets that watch it; disposed when it was created |
| `ListenableProvider<T>(create:, dispose:)`, `.value(value:)` | Any `Listenable`, as above; listened to from its first read until it is replaced or the provider leaves the tree |
| `ValueListenableProvider<T>.value(value:, updateShouldNotify:)` | The value of a `ValueListenable<T>`, found as a `T` |
| `FutureProvider<T>(create:, initialData:, catchError:)`, `.value(value:, …)` | `initialData`, then what the future completes with; an error is what `catchError` returns for it, else logged at `LogLevel.error` while the value stays. `.value` listens at once |
| `StreamProvider<T>(create:, initialData:, catchError:)`, `.value(value:, …)` | `initialData`, then each value of the stream that is not `==` the last; cancelled when the provider leaves the tree |
| `ProxyProvider<T, R>(update: (context, t, previous) => …, create:, dispose:)`, `ProxyProvider2<T, T2, R>`, `ProxyProvider0<R>` | What `update` makes from the providers above and the value it made before (`create`'s, or null, the first time), made anew when they change or the widget is replaced: a value not `==` the one before rebuilds the watchers, and the old one goes to `dispose` |
| `InheritedProvider<T>(create:, update:, startListening:, dispose:)`, `DeferredInheritedProvider<C, T>` | What the others are made of, for providers of one's own |

`MultiProvider(providers: [Provider(create: …), …], child:)` nests the
providers, the first outermost, each given without a child; it takes a
`builder` too, and one MultiProvider may be in the list of another. What
it nests are `SingleChildWidget`s: `SingleChildStatelessWidget`,
`SingleChildStatefulWidget` with its `SingleChildState`, and
`SingleChildBuilder`, as package:nested has them.

## Finding

- `context.read<T>()`: the nearest provided `T` without depending on it,
  for callbacks and `initState`.
- `context.watch<T>()`: the same, and the widget is rebuilt each time it
  changes, as long as its builds watch it.
- `context.select<T, R>((t) => …)`: what the selector picks, and the
  widget is rebuilt only when a change makes it pick something else: not
  `==`, lists, sets, maps and other iterables compared element by element.
  A build may select any number of parts; what earlier builds selected is
  forgotten. Reading, watching or selecting in a selector fails an assert.
- `Provider.of<T>(context, listen:)`: `watch` when `listen`, else `read`.

A provider is found by the type it provides: a `Provider<Counter>` by
`read<Counter>()`, the nearest hiding those above. None found is a
`ProviderNotFoundException` naming the type and the widget, unless the
type is nullable: `read<Counter?>()` is then null. A `Provider<int?>` is
found by `read<int>()` too, its null a `ProviderNullException`.

## Building

| widget | does |
|--------|------|
| `Consumer<T>(builder: (context, t, child) => …, child:)` | Builds with the value, again each time it changes; the widgets around it are not rebuilt, and `child` is built once, by the parent |
| `Consumer2<A, B>` | The same with two values |
| `Selector<A, S>(selector: (context, a) => …, builder: (context, s, child) => …, shouldRebuild:)`, `Selector2`, `Selector0` | The selector runs by each change; the builder only when it picks something else (compared as `select` compares, or as `shouldRebuild` says) or the widget is replaced |

## On twk's framework

A provider is an `InheritedWidget` whose element (a subclass of twk's
`InheritedElement`) keeps the value and calls `notifyClients` in its own
build when the value changes. twk has none of Flutter's `InheritedModel`
aspects (`dependOnInheritedElement` takes no aspect, and an inherited
element keeps no data per dependent), so `select` keeps its own: the
element holds, for each dependent, whether it watched the whole value,
else the selectors its last build registered, and its `notifyDependent`
runs them before it rebuilds the dependent. A dependent's selectors are
those of its last build, told apart by the owner's rebuild count
(`BuildOwner.rebuilds`), which each build of an element moves on; one
that watched once stays told of every change, as with package:provider.

twk drops a dependency that a build does not register again; the element
keeps those `update` registered through the builds that do not call it
(a listenable's notification), as Flutter would. Its own lookups start
at its parent, so that `create` and `update` find the providers above.

## Unlike package:provider

- `watch` and `select` outside a build (from a key handler) are not
  refused: twk has neither `Element.debugDoingBuild` nor
  `BuildOwner.debugBuilding`. The dependency made lasts until the next
  build of the widget. `read` in a build is allowed, as in provider 6.
- Not here: `ChangeNotifierProxyProvider`, `ListenableProxyProvider`,
  `ProxyProvider3` to `6`, `Consumer3` to `6`, `Selector3` to `6`,
  `ReassembleHandler` and the devtools binding.

## Its tests

`test/provider/` runs them through `testTwk`: `provider_test.dart`
`Provider` and `InheritedProvider` (when a value is created and disposed
of, read and watch, a value replaced, a provider not found, the providers
above found from `create`, what is refused) and `MultiProvider`;
`listenable_provider_test.dart` what a notification rebuilds, when a
listenable is listened to and disposed of; `async_provider_test.dart` the
initial data, then what a future or a stream gives and its errors;
`proxy_provider_test.dart` values made from those above, made anew and
disposed of; `select_test.dart` what `context.select`, `Selector`,
`Consumer` and `Consumer2` rebuild, and what a selector may not do;
`example/counter_test.dart` the example.

The checks, from this directory:

```bash
dart pub get
dart analyze
dart test
dart format --output=none --set-exit-if-changed lib test example
```

and from the repository's root `dart run tool/web_check.dart twk`, which
`test/platform/web_check_test.dart` runs too: an app of this package
built with dart2wasm, checked for libraries that import dart:io or
dart:ffi, and run in node.
