---
title: "Theming"
about: "Colors and styles from a theme, dark or light as the terminal is."
order: 4
---
# Theming

A `Theme` gives the widgets below it a `ThemeData`: a background, text,
`muted`, `primary`, `accent`, `border`, `selection`, and `success`,
`warning`, `error` and `info`, each a `Style`. Every widget of twk draws
in them, and `Theme.of(context)` gives them to an app's own.

<!-- file: packages/twk/example/guides/theming.dart -->
```dart
import 'package:twk/twk.dart';

Future<void> main() => runApp(
  // Catppuccin's dark flavor on a dark terminal, its light one on a light
  // one, switched when the terminal reports another color scheme; without
  // a Theme, ThemeData.dark and ThemeData.light
  const Theme.adaptive(
    dark: ThemeData.catppuccinMocha,
    light: ThemeData.catppuccinLatte,
    child: Status(),
  ),
);

final class Status extends StatelessWidget {
  const Status({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KeyBindings(
      {'q': () => AppBinding.of(context).quit()},
      child: Box(
        border: .all(type: .rounded, style: theme.border),
        titles: [BorderTitle(' Services ', style: theme.primary)],
        padding: const .all(1),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Text.rich([Span('● ', theme.success), const Span('api      up')]),
            Text.rich([Span('● ', theme.warning), const Span('worker   slow')]),
            Text.rich([Span('● ', theme.error), const Span('mail     down')]),
            Text('q quits', style: theme.muted),
          ],
        ),
      ),
    );
  }
}
```

## Which theme

- `Theme(data: ThemeData.nord, child:)` sets one theme. Built in:
  `ThemeData.dark`, `.light`, `.nord`, `.catppuccinMocha`,
  `.catppuccinLatte`.
- Without a `Theme`, the widgets use twk's own: `ThemeData.dark` on a
  terminal with a dark background, `ThemeData.light` on a light one,
  switched as soon as the terminal reports that its color scheme
  changed. Its colors are RGB, brought down to 256 or 16 where the
  terminal shows no more. A terminal that does not answer for its
  background gets its own colors, as under `Theme.terminal`, their greys
  for the side its `COLORFGBG` names (rxvt, Konsole), dark where it names
  none: a guess, and an inherited variable can be stale (in tmux, after a
  profile changed), so it never picks twk's themes, whose dark theme on a
  light terminal would be light text on white.
- `Theme.adaptive(dark:, light:, child:)` chooses the dark and the light
  theme, as the app above does.
- `Theme.terminal(child:)` uses the terminal's own colors
  (`ThemeData.terminalOf`): the user's palette, `primary` blue, and
  `surface` (toasts, dialogs, menus), `muted`, `border` and the
  selections greys mixed from the background
  and text color the terminal told, a step from its background whatever
  it is, and a color of the palette its bright entry where only that one
  reads on the background; where it told none, greys of the 256 colors,
  which no color scheme changes. For an app that should look like
  the rest of the user's terminal.

## Styles and spans

- `Style(fg:, bg:, attrs:)` is a color for the text, one for the
  background and attributes: `Attr.bold`, `dim`, `italic`, `underline`
  (and curly, dotted, dashed and double), `reverse`, `strike`. A `Color`
  is one of the 16 named ones, an index of the 256, or `Color.rgb`; the
  terminal's own depth decides what is written.
- `Text('Ready', style: theme.success)` styles a whole text;
  `Text.rich([...])` a row of spans, `Span('● ', theme.success)` or the
  short forms on a string: `'q'.bold`, `'down'.fg(.red)`, `'docs'.link(url)`.
- `DefaultTextStyle` sets the style of the text below it, which a `Text`
  merges its own over.

| | |
| --- | --- |
| ![Theme](../../packages/gallery/doc/shots/style/theme.dark.svg)<br>**[Theme](../widgets/style/theme.md)** | ![Theme, light](../../packages/gallery/doc/shots/style/theme.light.svg)<br>**[Theme](../widgets/style/theme.md)**, light |

Gradients across a background or text, and how the brightness is read,
are in the catalog's [Style](../widgets/style.md) group.
