# twk

Flutter's widget model for terminal UIs in Dart. Widgets, elements and
`State` behave as in Flutter: `StatelessWidget`, `StatefulWidget`,
`setState`, `InheritedWidget`, keys, `LayoutBuilder`. Everything is
measured in cells. Under the widgets is
[twk_core](https://pub.dev/packages/twk_core), a rendering core that
writes only the cells that changed.

![The Table page of the twk gallery, dark theme](https://raw.githubusercontent.com/pro100andrey/twk/main/packages/gallery/doc/shots/screens/table-dark.svg)

## Features

- **Layout:** `Row`, `Column`, `Flex` with `Expanded` and `Flexible`,
  `Stack`, `Grid`, `Wrap`, `Padding`, `Align`, `SizedBox`, `Box` with
  borders and titles, and `SplitView`.
- **Text:** `Text` and `Text.rich` with styled spans, wrapping and
  ellipsis, links, and bidirectional text.
- **Input:** a focus tree with Tab traversal, `KeyBindings` and
  `Shortcuts`, and the mouse through a hit test (`Listener`, hover,
  drag, the wheel).
- **Scrolling and data:** `ListView`, `Table` (also over a data source),
  `TreeView`, `Scrollbar`, charts, sparklines and gauges.
- **Editing:** `TextField`, multi-line text areas, and `Form` with
  validated `FormField`s.
- **Overlays:** dialogs, menus, a menu bar, context menus, toasts, a
  command palette and tooltips.
- **Navigation and controls:** `Navigator` with routes, tabs, buttons,
  switches, checkboxes, radio buttons, sliders, progress bars and
  spinners.
- **Animation and theming:** tickers, animation controllers and implicit
  animations; `Theme` with dark and light themes, chosen from the
  terminal's background.
- **Screen modes:** fullscreen, inline below the shell's history (lines
  committed into the scrollback with `Static`), or a fixed viewport.
- **Accessibility and debugging:** semantics and a screen-reader mode;
  a frame overlay, repaint rainbow, log console and tree dumps.
- **State:** hooks in the flutter_hooks style (`package:twk/hooks.dart`)
  and Provider's API (`package:twk/provider.dart`), each a library of its
  own.
- **The web:** an app builds with dart2wasm and runs on xterm.js.

## Getting started

```sh
dart pub add twk
```

A counter: Up counts, q quits
([example/counter.dart](https://github.com/pro100andrey/twk/blob/main/packages/twk/example/counter.dart)):

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

`dart run example/counter.dart` runs it on the alternate screen; with
`--inline` it runs below the shell's prompt and stays in the history
when it quits.

The [examples](https://github.com/pro100andrey/twk/tree/main/packages/twk/example)
include larger apps: a chat with a list, a text field and focus; settings
with menus, tabs, a form, a dialog and toasts; a process monitor with a
sorted table and a tree; an operations dashboard of live figures, a chart, a heatmap and a log; and a file
manager with two panes.

## Testing

Apps are tested with `testTwk` from
[twk_test](https://pub.dev/packages/twk_test)
(`dart pub add dev:twk_test`): the app runs on a terminal in memory under
a fake clock, keys and the mouse go in as the bytes a terminal sends, and
the screen is read back through a strict emulator.

```dart
testTwk('Up counts', (t) async {
  await t.pumpWidget(const Counter(), size: (24, 6));
  await t.press('up up up');
  await t.pump();
  expect(t, containsLine('│ Count: 3             │'));
});
```

## Learn more

- [Guides](https://github.com/pro100andrey/twk/blob/main/doc/README.md):
  getting started, layout, input and focus, theming, screen modes, state
  and testing.
- [Widget catalog](https://github.com/pro100andrey/twk/blob/main/doc/widgets/README.md):
  every widget with its pictures, its code and its options.
- [Reference](https://github.com/pro100andrey/twk/blob/main/packages/twk/doc/reference/README.md):
  every topic, widget and parameter, and how the package is tested.
- [The gallery](https://github.com/pro100andrey/twk/tree/main/packages/gallery):
  every widget live, with its options and the Dart that builds it.
- [SKILL.md](https://github.com/pro100andrey/twk/blob/main/packages/twk/SKILL.md):
  a guide for coding agents that build apps with twk.
- [twk_core](https://pub.dev/packages/twk_core): the rendering core, and
  its platforms and limitations.

## License

MIT. The colors of `ThemeData.nord` are those of
[Nord](https://www.nordtheme.com), Copyright (c) 2016-present Sven Greb,
and those of `ThemeData.catppuccinMocha` and `ThemeData.catppuccinLatte`
those of [Catppuccin](https://catppuccin.com), Copyright (c) 2021
Catppuccin, each under the MIT License.
