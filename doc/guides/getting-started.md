---
title: "Getting started"
about: "Install twk, write a first app, run it full screen or inline, and debug it."
order: 1
---
# Getting started

twk is Flutter's widget model on a terminal: `StatelessWidget`,
`StatefulWidget`, `setState`, layout by constraints, focus and keys, all
measured in cells. Under it, [twk_core](https://pub.dev/packages/twk_core)
keeps the screen as a buffer of cells and writes only the ones that
changed.

## Set up

twk needs Dart 3.13.5 or later: the code uses Dart's dot shorthands
(`.inline`, `.all(type: .rounded)`). In a new or existing package:

```sh
dart create -t console my_app
cd my_app
dart pub add twk
dart pub add dev:twk_test
```

## A first app

A counter: Up counts, q quits. Put it in `bin/main.dart`:

<!-- file: packages/twk/example/counter.dart -->
```dart
import 'package:twk/twk.dart';

Future<void> main(List<String> args) => runApp(
  const Counter(),
  mode: args.contains('--inline') ? .inline : .fullscreen,
);

final class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

final class _CounterState extends State<Counter> {
  var _n = 0;

  @override
  Widget build(BuildContext context) => KeyBindings(
    {
      'up': () => setState(() => _n++),
      'q': () => AppBinding.of(context).quit(),
    },
    child: Box(
      border: const .all(type: .rounded),
      titles: const [
        BorderTitle(' up: count  q: quit ', alignment: .bottomRight),
      ],
      padding: const .all(1),
      child: Text.rich(['Count: '.dim, '$_n'.bold.fg(.green)]),
    ),
  );
}
```

- `runApp` runs a widget as an app until it quits: by default full
  screen, on the terminal's alternate screen, which gives back what the
  terminal showed when the app ends.
- `KeyBindings` binds keys by name (`'up'`, `'ctrl+s'`, `'g g'`) for the
  widgets below it.
- `Box` draws a border, titles on it and padding around its child.
- `'Count: '.dim` and `'$_n'.bold.fg(.green)` are spans of styled text,
  which `Text.rich` puts in a row.

## Run it

```sh
dart run bin/main.dart            # full screen
dart run bin/main.dart --inline   # in rows below the prompt
```

Inline, the app takes as many rows below the shell's prompt as it asks
for and leaves them in the terminal's history when it ends:
[Screen modes](screen-modes.md) says more. Ctrl+C that no widget takes
quits.

A frame builds only what `setState` marked, at most 60 a second, and
writes only the cells that changed: an app that changes nothing writes
nothing.

## Debug it

`print` and `log()` inside the app go to its log, not to the screen; the
warnings and errors are printed once the app has ended.

```sh
TWK_DEBUG=overlay,console dart run bin/main.dart
```

turns the debug aids on from the start: `overlay` shows each frame's
times and bytes, `console` the log, `rainbow` tints what repaints. With
any of them on, Ctrl+G and then `o`, `c` or `r` turns each on or off
while the app runs.

A build that throws shows the error in a red box in its place and goes on;
an error in a key binding or a mouse callback ends the app with the path
of the widget it came from.

Hot reload, an inspector of the widget tree and a recorder of sessions
are the `twk` command of
[twk_dev](https://github.com/pro100andrey/twk/tree/main/packages/twk_dev),
not on pub.dev yet.

## Next

- [Layout](layout.md): rows, columns, boxes and the room each child gets.
- [Input and focus](input-and-focus.md): keys, the focus and the mouse.
- [Theming](theming.md): colors and styles from a theme.
- [Screen modes](screen-modes.md): full screen, inline and a fixed
  viewport.
- [State](state.md): `setState`, controllers, hooks and Provider.
- [Testing](testing.md): an app tested on a terminal in memory.
- [The widget catalog](../widgets/README.md): every widget, with
  pictures and the Dart that builds it.
