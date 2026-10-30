# twk reference: `style`

[The reference](README.md) · `lib/src/style/`, `test/style/`

## `Style`

`Style` (colors with alpha, attributes on and off, underline color, link;
`merge`, and `pen` / `penIn` for the core's pens), `Span`, and the
`StringStyles` extension: `'x'.bold.fg(…)`, with `bold`, `dim`, `italic`,
`underline` (`doubleUnderline`, `curlyUnderline`, `dottedUnderline`,
`dashedUnderline`: each kind replaces the one before), `reverse`, `strike`,
`overline`, `fg`, `bg` and `link`, and `gradient`: `Span.gradient(text,
gradient, [style])` (`'x'.gradient(g)`) colors its text along a `Gradient`,
grapheme by grapheme, the first at its start and the last at its end, across
the lines it is broken into (a line break takes no step, a tab does), its
background and attributes kept and its lines broken as without it;

## `ThemeData`

`ThemeData`, the styles of an app by what they are for (`background`,
`surface` and `selection` set a background; `text`, `muted`, `primary`,
`accent`, `border`, `error`, `warning`, `success` and `info` a text color)
and its `Brightness`, with `copyWith`, and the tokens the gallery design
derives from those unless given: `chrome` (the background of a header, a
sidebar, the key hints), `well` (a field sunk into it), `faint` (rules that
only separate), `dim` (the least important text), `selectionIdle` (the
selection of a list without the focus), `hover` (what the mouse is over),
`onPrimary` (text on a `primary` fill), `shade` and `shadeAlpha` (a
barrier's dimming: black at half on a dark theme, at 28 % on a light one);
on a theme of palette colors each of the others is the slot it starts from;
`theme.fill(color)` a fill of a color with text that reads on it
(`onPrimary` on `primary`, else black or white by contrast), which a badge,
a focused button, a lit tab and a cursor are in rather than reverse video;

## `ThemeData.lerp`

`ThemeData.lerp(a, b, t)` blends two themes, slot by slot and token by token
(`ThemeDataTween`), and `AnimatedTheme(data:, child:, duration: 280 ms,
curve: Curves.easeInOut)` cross-fades the widgets below it to a new theme;
the presets `ThemeData.dark`, `light`, `nord`, `catppuccinMocha` and
`catppuccinLatte` (held to contrast targets, a test computing them: muted
text 4.5 to 1 on the background, 3.5 on the surface and 1.5 apart from the
text, `dim` 3, text on the selection 4.5, the selection apart from the
background and the surface, the idle one from the background and the
selection, the status colors 3 as text; Nord and Catppuccin in colors of
their own palettes, a palette color at an opacity over the background where
the guide has one, their best where none meets a target), and
`ThemeData.terminal(brightness)`, the terminal's default colors and palette
(`surface`, `selectionIdle`, `hover`, `selection`, `border` and `muted` a
ladder of greys of the 256 colors from the background, which no color scheme
changes: 234, 235, 236, 237, 240 and 245 on a dark terminal, 255, 254, 253,
252, 250 and 243 on a light one, so that a toast or a dialog stands out of
the page; `selection` a background, as every theme's is and a `Theme`
asserts), `ThemeData.terminalOn(background, foreground:, palette:)` the same
with those greys mixed from the default colors the terminal told (the
palette kept as its `palette`, by which `fill` picks black or white text on
a palette color as the terminal draws it, not as xterm does), a step from
its background whatever it is, and each of its colors the palette's bright
entry where the normal one reads under 4.5 on the background and the bright
one, of its hue, reads better (xterm's blue on black), and
`ThemeData.terminalOf(context)` whichever of the two the terminal allows
(`TerminalBrightness.backgroundOf` / `foregroundOf` / `paletteOf`, which the
binding keeps from OSC 11, 10 and 4 and their later reports; a terminal that
tells no background gets the fixed greys of the side its `COLORFGBG`
declares, `brightnessFor`, dark where nothing says, and never twk's themes
on that guess), so its color scheme shows through;

## `Theme`

`Theme` with its `data`, `Theme.adaptive` with a `dark` and a `light` theme
picked by the brightness of the terminal, or `Theme.terminal` with
`ThemeData.terminal` of that brightness;

## `Theme.of`

`Theme.of(context)`, without a `Theme` `ThemeData.dark` or `ThemeData.light`
by the brightness of the terminal, as under a `Theme.adaptive` of the
defaults, and `ThemeData.terminal` where the terminal did not say it
(`TerminalBrightness.isKnown`);

## `TerminalBrightness`

`TerminalBrightness`, dark without one. A theme or a brightness that changes
rebuilds only what reads it. The widgets of this package that read the theme
take from it the styles they are not given, each as its doc says: the log
console (`debug`), `Calendar`, `Table`, `TreeView`, `TreeTable`, `TaskList`,
`DirectoryTree`, `DescriptionList`, `Heatmap`, `ProgressList`, `TextField`,
`TextArea`, `Autocomplete`, `Dialog`, the toasts, `Tooltip`, the menus,
`CommandPalette`, `SingleChildScrollView`, `ListView`, `LogView`,
`Scrollbar`, `SplitView`, `SelectionArea`, `TabBar`, `KeyHintsBar`,
`StatusBar`, `Scaffold`, `StatusMessage`, `Badge`, `Link`, `ListTile`,
`Button`, `Checkbox`, `Switch`, `RadioGroup`, `SelectionList`, `Select`,
`MultiSelect`, `ConfirmInput`, `FormField` (its error), `Slider`,
`NumberInput`, `DatePicker`, `FilePicker`, `WindowLayer`, `DockArea`,
`Callout`, `SegmentedButton`, `ExpansionTile`, `Breadcrumbs`, `Pagination`,
`Stepper`, `Skeleton`, `Skeletonize`, `Spinner` and `ProgressBar`; the
binding's debug panels are in `ThemeData.terminal`'s colors.

## `Gradient`

`Gradient(colors, stops:, direction: Axis.horizontal, phase:)` changes color
cell by cell along the columns (or down the rows), the first cell at the
first stop and the last at the last, the stops spread evenly where none are
given, the colors between mixed as the core blends a translucent background,
so palette and default colors mix as the terminal shows them; in truecolor,
the nearest color on a terminal of 256 or 16. With a `phase` the colors are
a loop, the first again after the last, turned `phase` of the way along the
axis (only its fraction counts; evenly spread, 0.5 turns `[a, b, c, d]` into
`[c, d, a, b, c]`), each cell between two colors mixed as between two stops:
a phase that grows a little each frame makes the colors flow towards the
last cell, a palette color turning as smoothly as an RGB one.

## `GradientBackground`

`GradientBackground(gradient:, child:)` fills the backgrounds of its cells
along it under the child (a `Box` with no style over it takes it as its
own), as big as the constraints allow without a child;

## `GradientForeground`

`GradientForeground(gradient:, child:)` draws the child's text in it, each
glyph in the color of its column (or row), a two-column one in that of its
first, the backgrounds and attributes kept, and what a repaint boundary in
its child repaints on its own colored again
