---
title: "Layout"
about: "Rows, columns, boxes, and how much room each child gets, in cells."
order: 2
---
# Layout

Layout works as in Flutter: a parent gives each child constraints, the
child picks a size within them, and the parent places it. The one
difference is the unit: everything is whole cells, so sizes, paddings and
offsets are columns and rows.

## Rows and columns

<!-- file: packages/twk/example/guides/layout.dart -->
```dart
import 'package:twk/twk.dart';

Future<void> main() => runApp(const Layout());

final class Layout extends StatelessWidget {
  const Layout({super.key});

  @override
  Widget build(BuildContext context) => KeyBindings(
    {'q': () => AppBinding.of(context).quit()},
    child: Column(
      // each child as wide as the column, not centred across it
      crossAxisAlignment: .stretch,
      children: [
        Text.rich([' twk'.bold, ' · layout'.dim]),
        // the rows the title and the hints leave
        const Expanded(
          child: Row(
            crossAxisAlignment: .stretch,
            children: [
              // a fixed width
              SizedBox(
                width: 20,
                child: Box(
                  border: .all(type: .rounded),
                  titles: [BorderTitle(' Files ')],
                  padding: EdgeInsets.x(1),
                  child: Text('lib/\ntest/\npubspec.yaml'),
                ),
              ),
              // the columns the files leave
              Expanded(
                child: Box(
                  border: .all(type: .rounded),
                  titles: [BorderTitle(' Preview ')],
                  padding: EdgeInsets.x(1),
                  child: Text(
                    'Everything is measured in cells. A Row gives its '
                    'fixed children their width first, then shares what '
                    'is left among the Expanded ones.',
                  ),
                ),
              ),
            ],
          ),
        ),
        Text(' q quits', style: Theme.of(context).muted),
      ],
    ),
  );
}
```

```text
 twk · layout
╭ Files ───────────╮╭ Preview ───────────────────╮
│ lib/             ││ Everything is measured in  │
│ test/            ││ cells. A Row gives its     │
│ pubspec.yaml     ││ fixed children their width │
│                  ││ first, then shares what is │
╰──────────────────╯╰────────────────────────────╯
 q quits
```

- `Column` and `Row` lay their children out along their axis. A child
  with a fixed size gets it first; `Expanded` and `Flexible` share the
  rest by their `flex`, and `Spacer` is an empty `Expanded`. `gap:` puts
  cells between the children.
- Across their axis they centre their children unless
  `crossAxisAlignment` says otherwise: `.stretch` makes each as wide (or
  tall) as the row or column, `.start` puts them at its start.
- `SizedBox` gives a fixed size, `Padding` empty cells around a child,
  `Center` and `Align` place a child in the room it is given.
- `Box` is the workhorse: a `border:` (`.all(type: .rounded)`, or
  `.single`, `.double`, `.heavy`, `.ascii`), `titles:` on it, `padding:`
  inside it and a `style:` that fills it.

## Room that has no end

`ListView`, `Table`, `TreeView` and other scrolling widgets take all the
room they get. In a `Column` put them in `Expanded`, or they take the
whole height and push the rest off the screen (a `RenderFlex overflowed`
warning in the log). Inline, where the app's height is what it asks for, a
list asks for none: give it a height with a `SizedBox`. A list or a scroll
view left no rows, and an `Expanded` with something to show left no cells,
say so in the log too, which the debug console (`TWK_DEBUG=console`) shows
and a failing test prints.

What has no end to grow into takes its child's size instead, as in
Flutter: an `Align` or a `Center` in a scroll view, or in a list's row,
whose height has no end, is as tall as its child, so
`Align(alignment: .centerLeft, child: …)` in a row of a `ListView` keeps
the row one line tall.

## More layouts

| | |
| --- | --- |
| ![Row, Column, Flex](../../packages/gallery/doc/shots/layout/row-column-flex.dark.svg)<br>**[Row, Column, Flex](../widgets/layout/row-column-flex.md)** | ![Box](../../packages/gallery/doc/shots/layout/box.dark.svg)<br>**[Box](../widgets/layout/box.md)** |
| ![Grid](../../packages/gallery/doc/shots/layout/grid-gridplacement.dark.svg)<br>**[Grid, GridPlacement](../widgets/layout/grid-gridplacement.md)** | ![SplitView](../../packages/gallery/doc/shots/layout/splitview.dark.svg)<br>**[SplitView](../widgets/layout/splitview.md)** |

`Stack` and `Positioned` layer children, `Wrap` flows them onto the next
row, `Grid` places them in tracks whose borders can merge, and
`SplitView` gives panes a divider the mouse drags. All of them are in the
catalog's [Layout](../widgets/layout.md) group.
