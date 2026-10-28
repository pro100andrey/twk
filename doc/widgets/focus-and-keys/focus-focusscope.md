---
title: "Focus, FocusScope"
group: "Focus and keys"
package: "twk"
about: "Nodes the keys go to: Tab moves the focus from one to the next, a click takes it; in a scope Tab goes round its nodes, and Tab into it focuses the one it had last."
image: "packages/gallery/doc/shots/focus-and-keys/focus-focusscope.dark.svg"
image_light: "packages/gallery/doc/shots/focus-and-keys/focus-focusscope.light.svg"
route: "#/focus-and-keys/focus-focusscope"
---
# Focus, FocusScope

Nodes the keys go to: Tab moves the focus from one to the next, a click takes it; in a scope Tab goes round its nodes, and Tab into it focuses the one it had last.

| Dark | Light |
| --- | --- |
| ![Focus, FocusScope, dark](../../../packages/gallery/doc/shots/focus-and-keys/focus-focusscope.dark.svg) | ![Focus, FocusScope, light](../../../packages/gallery/doc/shots/focus-and-keys/focus-focusscope.light.svg) |

## Code

The Dart that builds it, as the gallery's Code tab shows it with the
options as they start:

```dart
final _nodes = [
  for (final label in ['one', 'two', 'three', 'four'])
    FocusNode(debugLabel: label),
];
final _scope = FocusScopeNode(debugLabel: 'scope');

@override
void dispose() {
  for (final node in _nodes) {
    node.dispose();
  }
  _scope.dispose();
  super.dispose();
}

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  final [one, two, three, four] = _nodes;
  return Column(
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    gap: 1,
    children: [
      Row(
        mainAxisSize: .min,
        gap: 1,
        children: [
          _Focusable(one),
          _Focusable(two),
          ListenableBuilder(
            listenable: _scope,
            builder: (context, _) {
              final inside = _scope.hasFocus;
              return Box(
                border: .all(
                  type: .rounded,
                  style: inside ? theme.primary : theme.border,
                ),
                titles: [
                  BorderTitle(
                    ' FocusScope ',
                    style: inside ? theme.primary : theme.muted,
                  ),
                ],
                child: FocusScope(
                  node: _scope,
                  child: Row(
                    mainAxisSize: .min,
                    children: [_Focusable(three), _Focusable(four)],
                  ),
                ),
              );
            },
          ),
        ],
      ),
      ListenableBuilder(
        listenable: Listenable.merge(_nodes),
        builder: (context, _) {
          final focused = [
            for (final node in _nodes)
              if (node.hasPrimaryFocus) node.debugLabel!,
          ];
          return Text.rich([
            Span('focus: ', theme.muted),
            if (focused.isEmpty)
              Span('none', theme.muted)
            else
              Span(focused.first, theme.primary.merge(bold)),
          ]);
        },
      ),
    ],
  );
}

/// [node] in a box that takes the focus, by Tab or a click.
final class _Focusable extends StatelessWidget {
  const _Focusable(this.node);

  final FocusNode node;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: (_) => node.requestFocus(),
      child: Focus(
        focusNode: node,
        child: ListenableBuilder(
          listenable: node,
          builder: (context, _) => Box(
            border: .all(
              type: node.hasFocus ? .heavy : .rounded,
              style: node.hasFocus ? theme.primary : theme.border,
            ),
            padding: const .x(1),
            child: Text(
              node.debugLabel!,
              style: node.hasFocus ? bold : const Style(),
            ),
          ),
        ),
      ),
    );
  }
}

const bold = Style(attrs: Attr.bold);
```

## Options

What the gallery lets you change, and what each starts at:

| option | values | starts at |
| --- | --- | --- |
| FocusScope | on, off | true |
| node two | focusable, skips Tab, unfocusable | focusable |

## More

- API: [`Focus`](https://pub.dev/documentation/twk/latest/twk/Focus-class.html), [`FocusScope`](https://pub.dev/documentation/twk/latest/twk/FocusScope-class.html).
- Also in Focus and keys: [ExcludeFocus](excludefocus.md), [KeyBindings, LeaderKey](keybindings-leaderkey.md), [Shortcuts, Actions](shortcuts-actions.md).
- Live in the gallery:
  `dart run packages/gallery/bin/gallery.dart --route='#/focus-and-keys/focus-focusscope'`.
- [Focus and keys](../focus-and-keys.md) · [All groups](../README.md)
