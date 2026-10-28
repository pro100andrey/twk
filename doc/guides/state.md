---
title: "State"
about: "setState, controllers, hooks in the flutter_hooks style, and Provider's API."
order: 6
---
# State

## setState

A `StatefulWidget`'s `State` keeps what changes, and `setState` marks it
to be built again in the next frame. Several `setState` calls between two
frames make one build. The counter of [Getting started](getting-started.md)
is the whole pattern.

A `State` disposes what it made — controllers (`TextEditingController`,
`ScrollController`, `TabController`), focus nodes, timers, subscriptions
— in its `dispose`.

## Hooks

`package:twk/hooks.dart` is hooks in the flutter_hooks style: a
`HookWidget` keeps its state in `useState`, `useMemoized`,
`useTextEditingController` and `useEffect`, without a `State` class.

<!-- file: packages/twk/example/hooks/counter.dart -->
```dart
import 'package:twk/hooks.dart';
import 'package:twk/twk.dart';

Future<void> main(List<String> args) => runApp(
  const Counter(),
  mode: args.contains('--inline') ? .inline : .fullscreen,
);

final class Counter extends HookWidget {
  const Counter({super.key});

  @override
  Widget build(BuildContext context) {
    final count = useState(0);
    return KeyBindings(
      {
        'up': () => count.value++,
        'q': () => AppBinding.of(context).quit(),
      },
      child: Box(
        border: const .all(type: .rounded),
        titles: const [
          BorderTitle(' up: count  q: quit ', alignment: .bottomRight),
        ],
        padding: const .all(1),
        child: Text.rich(['Count: '.dim, '${count.value}'.bold.fg(.green)]),
      ),
    );
  }
}
```

A hook of your own is a function whose name starts with `use` and that
calls other hooks. The search below makes `useDebounced` of `useState`
and `useEffect`: each new value cancels the timer the last one started
(what the effect returns is its cleanup, run before it runs again and
when the widget goes) and starts its own. Around it, the field's
controller comes from `useTextEditingController`, which disposes it,
the text typed from `useValueListenable`, the packages from one request
(`useFuture` of a `useMemoized` future) and the matches from
`useMemoized`, filtered again only when the settled query or the list
changes.

<!-- file: packages/twk/example/hooks/search.dart -->
```dart
import 'dart:async';

import 'package:twk/hooks.dart';
import 'package:twk/twk.dart';

Future<void> main() => runApp(const Search());

/// A package of the list: its name and what it is for.
typedef Package = ({String name, String about});

/// How long loading the packages takes.
const loadingTime = Duration(milliseconds: 600);

/// How long the typing pauses before the list is filtered.
const pause = Duration(milliseconds: 300);

/// The packages, after [loadingTime], as a request to a server gives them.
Future<List<Package>> loadPackages() => Future.delayed(
  loadingTime,
  () => [
    (name: 'args', about: 'parses command-line arguments'),
    (name: 'async', about: 'utilities for streams and futures'),
    (name: 'collection', about: 'collections and what to do with them'),
    (name: 'crypto', about: 'hashes: SHA-1, SHA-256, MD5'),
    (name: 'http', about: 'makes HTTP requests'),
    (name: 'intl', about: 'messages, dates and numbers by locale'),
    (name: 'json_annotation', about: 'annotations for JSON code'),
    (name: 'logging', about: 'hierarchical loggers'),
    (name: 'markdown', about: 'Markdown to HTML'),
    (name: 'meta', about: 'annotations for static analysis'),
    (name: 'path', about: 'joins and splits paths on any platform'),
    (name: 'shelf', about: 'web servers made of middleware'),
    (name: 'stream_channel', about: 'two-way streams'),
    (name: 'test', about: 'writes and runs tests'),
    (name: 'yaml', about: 'parses YAML'),
  ],
);

/// [value] once it has stayed the same for [delay]: a hook of its own,
/// made of two others. Each new [value] cancels the timer the last one
/// started (the effect's cleanup) and starts its own.
T useDebounced<T>(T value, Duration delay) {
  final settled = useState(value);
  useEffect(() {
    final timer = Timer(delay, () => settled.value = value);
    return timer.cancel;
  }, [value]);
  return settled.value;
}

final class Search extends HookWidget {
  const Search({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // made in the first build, disposed with the widget
    final field = useTextEditingController();
    // rebuilt on each key typed
    final query = useValueListenable(field).text.trim().toLowerCase();
    final settled = useDebounced(query, pause);
    // one request, not one a build
    final packages = useFuture(useMemoized(loadPackages));
    final all = packages.data ?? const <Package>[];
    // filtered again only when the settled query or the list changes
    final matches = useMemoized(
      () => [
        for (final package in all)
          if (package.name.contains(settled) ||
              package.about.toLowerCase().contains(settled))
            package,
      ],
      [settled, all],
    );

    return KeyBindings(
      // not 'q': the field takes the characters typed
      {'escape': field.clear, 'ctrl+q': () => AppBinding.of(context).quit()},
      child: Box(
        style: theme.background.merge(theme.text),
        border: .all(type: .rounded, style: theme.border),
        titles: [
          BorderTitle(' Packages ', style: theme.primary),
          BorderTitle(
            ' esc clear  ctrl+q quit ',
            style: theme.muted,
            alignment: .bottomRight,
          ),
        ],
        padding: const .x(1),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            Row(
              gap: 1,
              children: [
                Text('⌕', style: theme.primary),
                Expanded(
                  child: TextField(
                    controller: field,
                    placeholder: 'search',
                    autofocus: true,
                  ),
                ),
              ],
            ),
            if (packages.hasData)
              Text(
                query != settled
                    ? 'searching…'
                    : '${matches.length} of ${all.length}',
                style: theme.muted,
              )
            else
              Row(
                gap: 1,
                children: [
                  Spinner(style: theme.primary),
                  Text('loading the packages', style: theme.muted),
                ],
              ),
            Expanded(
              child: ListView.builder(
                itemCount: matches.length,
                itemBuilder: (context, i) =>
                    _Match(package: matches[i], query: settled),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [package]'s name, the part of it that is [query] highlighted, and what
/// it is for.
final class _Match extends StatelessWidget {
  const _Match({required this.package, required this.query});

  final Package package;
  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = package.name;
    final at = query.isEmpty ? -1 : name.indexOf(query);
    return Text.rich(
      [
        if (at < 0)
          Span(name).bold
        else ...[
          Span(name.substring(0, at)).bold,
          Span(name.substring(at, at + query.length), theme.primary).bold,
          Span(name.substring(at + query.length)).bold,
        ],
        Span(' ' * (16 - name.length).clamp(1, 16)),
        Span(package.about, theme.muted),
      ],
      wrap: .none,
      overflow: .ellipsis,
    );
  }
}
```

Hooks are called in the same order in every build: not in an `if`, a
loop or a callback.

## Provider

`package:twk/provider.dart` is Provider's API: `Provider`,
`ChangeNotifierProvider`, `MultiProvider`, `context.read<T>()`,
`context.watch<T>()`, `context.select`, `Consumer` and `Selector`. A
widget that selects one value is rebuilt only when that value changes.

<!-- file: packages/twk/example/provider/counter.dart -->
```dart
import 'package:twk/provider.dart';
import 'package:twk/twk.dart';

Future<void> main(List<String> args) => runApp(
  ChangeNotifierProvider(create: (_) => CounterModel(), child: const Counter()),
  mode: args.contains('--inline') ? .inline : .fullscreen,
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
    child: const Box(
      border: .all(type: .rounded),
      titles: [BorderTitle(' up: count  q: quit ', alignment: .bottomRight)],
      padding: .all(1),
      child: _Count(),
    ),
  );
}

// rebuilt alone, by the counts it selects
final class _Count extends StatelessWidget {
  const _Count();

  @override
  Widget build(BuildContext context) {
    final n = context.select<CounterModel, int>((counter) => counter.count);
    return Text.rich(['Count: '.dim, '$n'.bold.fg(.green)]);
  }
}
```

Both are libraries of twk that `package:twk/twk.dart` does not export: an
app imports them besides it, and one that uses neither carries neither.

## Riverpod and Bloc

[twk_riverpod](https://github.com/pro100andrey/twk/tree/main/packages/twk_riverpod)
and [twk_bloc](https://github.com/pro100andrey/twk/tree/main/packages/twk_bloc)
bring Riverpod's `ProviderScope` and Bloc's providers and builders to
twk. They are in the repository, not on pub.dev yet.

## Async

`FutureBuilder` and `StreamBuilder` build from a future or a stream (make
the future once, in `initState`, not in a build); `ListenableBuilder` and
`ValueListenableBuilder` from a `ChangeNotifier` or a `ValueNotifier`.
